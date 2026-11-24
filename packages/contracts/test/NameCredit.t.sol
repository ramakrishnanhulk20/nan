// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Unit tests: every public function, every revert, every event, on the registry's own source deployed locally.
// What this file does NOT cover: the real registry on BNB Smart Chain (NameCredit.fork.t.sol), a registry that
// misbehaves (NameCredit.registry.t.sol), random sequences of actions (NameCredit.invariant.t.sol), and the
// owner functions (NameCredit.owner.t.sol).

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {Base} from "./Base.t.sol";
import {RejectingWallet, ReenteringWallet, GasBurningWallet} from "./mocks/Hostile.sol";

contract NameCreditTest is Base {
    function test_borrow_sendsTheFirstAdvanceAndRecordsIt() public {
        uint256 before = alice.balance;
        uint256 poolBefore = address(credit).balance;

        vm.expectEmit(true, true, false, true, address(credit));
        emit NameCredit.Borrowed(alice, keccak256("alice"), 0, FIRST, START + TERM, false);
        uint256 amount = _borrow(alice);

        assertEq(amount, FIRST);
        assertEq(alice.balance, before + FIRST);
        assertEq(address(credit).balance, poolBefore - FIRST);

        NameCredit.Standing memory st = _st(alice);
        assertEq(st.nameHash, keccak256("alice"));
        assertEq(st.step, 0);
        assertEq(st.limit, FIRST);
        assertEq(st.owed, FIRST);
        assertEq(st.due, START + TERM);
        assertEq(st.overdueAt, START + TERM + GRACE);
        assertFalse(st.missed);

        NameCredit.Totals memory t = credit.totals();
        assertEq(t.people, 1);
        assertEq(t.lent, FIRST);
        assertEq(t.outstanding, FIRST);
        assertEq(t.repaid, 0);

        NameCredit.StepTally memory s0 = credit.stepTally(0);
        assertEq(s0.advances, 1);
        assertEq(s0.lent, FIRST);
        assertEq(credit.dayTally(uint32(START / 1 days)).advances, 1);
        assertEq(credit.borrowerCount(), 1);
        assertEq(credit.borrowersPage(0, 10)[0], alice);
    }

    function test_borrow_refusesAWalletWithNoName() public {
        vm.prank(nobody);
        vm.expectRevert(NameCredit.NoAgentId.selector);
        credit.borrow();
        assertEq(credit.totals().people, 0);
    }

    function test_borrow_refusesASecondAdvanceWhileOneIsOpen() public {
        _borrow(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.AdvanceOpen.selector, FIRST));
        credit.borrow();
    }

    function test_borrow_refusesWhenThePoolIsShort() public {
        vm.prank(owner);
        credit.withdraw(1 ether - 0.0001 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.PoolEmpty.selector, FIRST, 0.0001 ether));
        credit.borrow();
    }

    function test_borrow_refusesWhilePaused() public {
        vm.prank(owner);
        credit.pause();
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        credit.borrow();
    }

    function test_borrow_failsCleanlyWhenTheBorrowerRefusesBnb() public {
        RejectingWallet w = new RejectingWallet(credit);
        _name("rejector", address(w));
        vm.expectRevert(NameCredit.PayoutFailed.selector);
        w.borrow();
        assertEq(_st(address(w)).owed, 0);
        assertEq(credit.totals().outstanding, 0);
    }

    function test_borrow_aBorrowerThatBurnsGasOnlyFailsItsOwnCall() public {
        GasBurningWallet w = new GasBurningWallet(credit);
        _name("burner", address(w));
        vm.expectRevert();
        w.borrow{gas: 500_000}();
        assertEq(_st(address(w)).owed, 0);
        _borrow(alice);
        assertEq(_st(alice).owed, FIRST);
    }

    function test_borrow_reenteringDuringThePayoutGetsNothingExtra() public {
        bytes4 guard = ReentrancyGuard.ReentrancyGuardReentrantCall.selector;
        // Marking is not behind the guard. It is refused because the advance is not overdue, and it could
        // change nothing but a flag if it were.
        bytes4[4] memory expected = [guard, guard, NameCredit.NotOverdue.selector, guard];
        string[4] memory names = ["reentera", "reenterb", "reenterc", "reenterd"];
        for (uint8 mode = 1; mode <= 4; ++mode) {
            ReenteringWallet w = new ReenteringWallet(credit);
            _name(names[mode - 1], address(w));
            w.setMode(mode);
            assertEq(w.borrow(), FIRST, "the advance itself goes through");
            assertTrue(w.calledBack());
            assertFalse(w.callBackWentThrough(), "the call back was refused");
            assertEq(w.innerReason(), expected[mode - 1]);
            assertEq(w.owedSeen(), FIRST, "the debt was on the books before the BNB left");
            assertEq(w.outstandingSeen(), uint256(FIRST) * mode, "and so were the totals");
            assertEq(_st(address(w)).owed, FIRST);
            assertEq(address(w).balance, FIRST, "one advance and no more");
        }
        assertEq(credit.totals().lent, uint256(FIRST) * 4);
    }

    function test_pace_fifthFirstAdvanceInOneBlockMustWait() public {
        address[5] memory h = [alice, bob, carol, _holder("dave"), _holder("erin")];
        assertEq(credit.pool().slotsNow, 4);
        for (uint256 i; i < 4; ++i) {
            _borrow(h[i]);
        }
        assertEq(credit.pool().slotsNow, 0);
        assertEq(credit.pool().nextSlotAt, START + 720);

        vm.prank(h[4]);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.PaceExhausted.selector, START + 720));
        credit.borrow();

        skip(719);
        vm.prank(h[4]);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.PaceExhausted.selector, START + 720));
        credit.borrow();

        skip(1);
        _borrow(h[4]);
        assertEq(credit.totals().people, 5);
    }

    function test_pace_unusedSlotsStopBuildingAfterOneHour() public {
        skip(30 days);
        assertEq(credit.pool().slotsNow, 4);
        assertEq(credit.pool().nextSlotAt, block.timestamp);
    }

    function test_pace_doesNotApplyAboveTheFirstStep() public {
        _borrow(alice);
        _repay(alice);
        address[4] memory h = [bob, carol, _holder("dave"), _holder("erin")];
        skip(TERM);
        for (uint256 i; i < 4; ++i) {
            _borrow(h[i]);
        }
        assertEq(credit.pool().slotsNow, 0);
        assertEq(_borrow(alice), 2 * FIRST);
    }

    function test_reserve_aRepeatBorrowerLeavesOneDayOfFirstAdvances() public {
        _borrow(alice);
        _repay(alice);
        vm.warp(START + TERM);

        // One day of first advances at 100 a day is 0.03 BNB. Leave the pool one wei short of that plus her advance.
        uint256 reserve = uint256(PACE) * FIRST;
        uint256 needed = 2 * uint256(FIRST) + reserve;
        vm.startPrank(owner);
        credit.withdraw(address(credit).balance - (needed - 1));
        vm.stopPrank();

        (NameCredit.Refusal r,,) = credit.quoteBorrow(alice);
        assertEq(uint8(r), uint8(NameCredit.Refusal.PoolEmpty));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.PoolEmpty.selector, needed, needed - 1));
        credit.borrow();

        assertEq(_borrow(bob), FIRST, "a newcomer is still served from the same pool");

        vm.prank(owner);
        credit.topUp{value: uint256(FIRST) + 1}();
        assertEq(_borrow(alice), 2 * FIRST);
    }

    function test_reserve_isZeroWhenThePaceIsZero() public {
        NameCredit.Settings memory s = _defaults();
        s.pacePerDay = 0;
        _borrow(alice);
        _repay(alice);
        vm.prank(owner);
        credit.scheduleSettings(s);
        vm.warp(START + TERM);
        credit.applySettings();
        vm.startPrank(owner);
        credit.withdraw(address(credit).balance - 2 * uint256(FIRST));
        vm.stopPrank();
        assertEq(_borrow(alice), 2 * FIRST, "with no newcomer flow there is nothing to hold back");
        assertEq(address(credit).balance, 0);
    }

    function _addPass(bytes32 code, uint40 expires) internal {
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = keccak256(abi.encode(code));
        vm.prank(owner);
        credit.addPasses(hashes, expires);
    }

    function _drainPace() internal returns (address fifth) {
        address[4] memory h = [alice, bob, carol, _holder("dave")];
        for (uint256 i; i < 4; ++i) {
            _borrow(h[i]);
        }
        fifth = _holder("erin");
    }

    function test_pass_skipsThePaceOnceAndOnlyOnce() public {
        address erin = _drainPace();
        bytes32 code = keccak256("judge code one");
        _addPass(code, uint40(START + 30 days));
        assertEq(credit.passExpiry(keccak256(abi.encode(code))), START + 30 days);

        vm.expectEmit(true, true, false, true, address(credit));
        emit NameCredit.Borrowed(erin, keccak256("erin"), 0, FIRST, START + TERM, true);
        vm.prank(erin);
        credit.borrowWithPass(code);
        assertEq(_st(erin).owed, FIRST);
        assertEq(credit.passExpiry(keccak256(abi.encode(code))), 0);

        address fred = _holder("fred");
        vm.prank(fred);
        vm.expectRevert(NameCredit.BadPass.selector);
        credit.borrowWithPass(code);
    }

    function test_pass_unknownExpiredOrRevokedIsRefused() public {
        address erin = _drainPace();
        vm.prank(erin);
        vm.expectRevert(NameCredit.BadPass.selector);
        credit.borrowWithPass(keccak256("never registered"));

        bytes32 code = keccak256("short lived");
        _addPass(code, uint40(START + 1 hours));
        vm.warp(START + 1 hours + 1);
        vm.prank(erin);
        vm.expectRevert(NameCredit.BadPass.selector);
        credit.borrowWithPass(code);

        bytes32 code2 = keccak256("revoked");
        _addPass(code2, uint40(block.timestamp + 1 days));
        vm.expectEmit(true, false, false, false, address(credit));
        emit NameCredit.PassRevoked(keccak256(abi.encode(code2)));
        vm.prank(owner);
        credit.revokePass(keccak256(abi.encode(code2)));
        vm.prank(erin);
        vm.expectRevert(NameCredit.BadPass.selector);
        credit.borrowWithPass(code2);
    }

    function test_pass_doesNotWaiveAnyOtherRule() public {
        bytes32 code = keccak256("a pass");
        _addPass(code, uint40(START + 1 days));

        vm.prank(nobody);
        vm.expectRevert(NameCredit.NoAgentId.selector);
        credit.borrowWithPass(code);

        _borrow(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.AdvanceOpen.selector, FIRST));
        credit.borrowWithPass(code);

        vm.prank(owner);
        credit.pause();
        vm.prank(bob);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        credit.borrowWithPass(code);

        assertEq(credit.passExpiry(keccak256(abi.encode(code))), START + 1 days, "a refused call leaves the pass unused");
    }

    function test_pass_doesNotSkipTheCoolingOff() public {
        bytes32 code = keccak256("a pass for later");
        _addPass(code, uint40(START + 60 days));
        _borrow(alice);
        vm.warp(START + TERM + GRACE + 1);
        _repay(alice);
        assertEq(_st(alice).step, 0, "a late repayment puts the wallet back at the first step, where a pass counts");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.TooEarly.selector, block.timestamp + COOLING_OFF));
        credit.borrowWithPass(code);

        vm.warp(block.timestamp + COOLING_OFF);
        vm.prank(alice);
        assertEq(credit.borrowWithPass(code), FIRST, "once the wait is over the same pass works");
    }

    function test_pass_isRefusedAboveTheFirstStepAndStaysUnused() public {
        bytes32 code = keccak256("a newcomer's code");
        _addPass(code, uint40(START + 30 days));
        _borrow(alice);
        _repay(alice);
        vm.warp(START + TERM);
        assertEq(_st(alice).step, 1);

        vm.prank(alice);
        vm.expectRevert(NameCredit.PassNotNeeded.selector);
        credit.borrowWithPass(code);
        assertEq(credit.passExpiry(keccak256(abi.encode(code))), START + 30 days, "the code is still there for a newcomer");
        assertEq(_borrow(alice), 2 * FIRST, "the plain call is the one that works above the first step");

        address erin = _holder("erin");
        vm.prank(erin);
        assertEq(credit.borrowWithPass(code), FIRST);
    }

    function test_repay_onTimeMovesUpOneStepAndWaitsOutTheTerm() public {
        _borrow(alice);
        skip(1 hours);
        vm.expectEmit(true, true, false, true, address(credit));
        emit NameCredit.Repaid(alice, alice, 0, FIRST, true);
        _repay(alice);

        NameCredit.Standing memory st = _st(alice);
        assertEq(st.owed, 0);
        assertEq(st.due, 0);
        assertEq(st.overdueAt, 0);
        assertEq(st.step, 1);
        assertEq(st.limit, 2 * FIRST);
        assertEq(st.onTime, 1);
        assertEq(st.notBefore, START + TERM, "the next advance waits for the original due time");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.TooEarly.selector, START + TERM));
        credit.borrow();

        vm.warp(START + TERM);
        assertEq(_borrow(alice), 2 * FIRST);

        NameCredit.Totals memory t = credit.totals();
        assertEq(t.repaid, FIRST);
        assertEq(t.outstanding, 2 * FIRST);
        assertEq(credit.stepTally(0).onTime, 1);
        assertEq(credit.stepTally(0).repaid, FIRST);
        assertEq(credit.dayTally(uint32(START / 1 days)).onTime, 1);
    }

    function test_repay_extraIsReturnedToThePayer() public {
        _borrow(alice);
        uint256 before = bob.balance;
        vm.expectEmit(true, true, false, true, address(credit));
        emit NameCredit.Repaid(alice, bob, 0, FIRST, true);
        vm.prank(bob);
        credit.repay{value: FIRST + 0.5 ether}(alice);
        assertEq(bob.balance, before - FIRST);
        assertEq(_st(alice).owed, 0);
        assertEq(_st(alice).step, 1);
        assertEq(_st(bob).nameHash, bytes32(0), "paying for someone records nothing about the payer");
    }

    function test_repay_aWalletWithNoNameCanPay() public {
        _borrow(alice);
        vm.prank(nobody);
        credit.repay{value: FIRST}(alice);
        assertEq(_st(alice).owed, 0);
    }

    function test_repay_refusesLessThanOwed() public {
        _borrow(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.Underpaid.selector, FIRST));
        credit.repay{value: FIRST - 1}(alice);
    }

    function test_repay_refusesWhenNothingIsOwed() public {
        vm.prank(alice);
        vm.expectRevert(NameCredit.NothingOwed.selector);
        credit.repay{value: FIRST}(alice);
    }

    function test_repay_lastSecondOfGraceIsOnTime() public {
        _borrow(alice);
        vm.warp(START + TERM + GRACE);
        _repay(alice);
        assertEq(_st(alice).step, 1);
        assertEq(_st(alice).onTime, 1);
        assertEq(_st(alice).notBefore, START + TERM);
        assertEq(_borrow(alice), 2 * FIRST, "paid in grace, the term is already over");
    }

    function test_repay_oneSecondAfterGraceIsLate() public {
        _borrow(alice);
        _repay(alice);
        vm.warp(START + TERM);
        _borrow(alice);
        uint256 madeAt = vm.getBlockTimestamp();
        vm.warp(madeAt + TERM + GRACE + 1);

        vm.expectEmit(true, true, false, true, address(credit));
        emit NameCredit.Repaid(alice, alice, 1, 2 * FIRST, false);
        _repay(alice);

        NameCredit.Standing memory st = _st(alice);
        assertEq(st.step, 0, "back to the first step");
        assertEq(st.late, 1);
        assertEq(st.onTime, 1);
        assertEq(st.notBefore, block.timestamp + COOLING_OFF);
        assertEq(credit.stepTally(1).late, 1);
        assertEq(credit.stepTally(1).missed, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.TooEarly.selector, block.timestamp + COOLING_OFF));
        credit.borrow();

        skip(COOLING_OFF);
        assertEq(_borrow(alice), FIRST);
    }

    function test_repay_worksWhilePaused() public {
        _borrow(alice);
        vm.prank(owner);
        credit.pause();
        _repay(alice);
        assertEq(_st(alice).owed, 0);
    }

    function test_repay_aPayerThatRefusesItsChangeFailsOnlyItsOwnCall() public {
        _borrow(alice);
        RejectingWallet payer = new RejectingWallet(credit);
        vm.expectRevert(NameCredit.PayoutFailed.selector);
        payer.repayFor{value: FIRST + 1}(alice);
        assertEq(_st(alice).owed, FIRST, "nothing changed");

        payer.repayFor{value: FIRST}(alice);
        assertEq(_st(alice).owed, 0, "the exact amount goes through");
    }

    function test_repay_reenteringOnTheRefundFails() public {
        bytes4 guard = ReentrancyGuard.ReentrancyGuardReentrantCall.selector;
        // Marking is not behind the guard. It is refused here because the advance is already settled.
        bytes4[4] memory expected = [guard, guard, NameCredit.NothingOwed.selector, guard];
        address[4] memory borrowers = [alice, bob, carol, _holder("dave")];
        for (uint8 mode = 1; mode <= 4; ++mode) {
            address borrower = borrowers[mode - 1];
            _borrow(borrower);
            ReenteringWallet w = new ReenteringWallet(credit);
            w.setMode(mode);
            w.setWatch(borrower);
            w.repayFor{value: FIRST + 1 ether}(borrower);
            assertTrue(w.calledBack());
            assertFalse(w.callBackWentThrough(), "the call back was refused");
            assertEq(w.innerReason(), expected[mode - 1]);
            assertEq(w.owedSeen(), 0, "the debt was cleared before the extra BNB left");
            assertEq(address(w).balance, 1 ether, "the extra came back and nothing else");
            assertEq(_st(borrower).owed, 0);
            assertEq(_st(borrower).onTime, 1);
        }
        assertEq(credit.totals().outstanding, 0);
    }

    function test_ladder_climbsToTheCapAndStopsThere() public {
        uint256[5] memory expected = [uint256(FIRST), 2 * FIRST, 4 * FIRST, 8 * FIRST, CAP];
        for (uint256 i; i < 5; ++i) {
            assertEq(_borrow(alice), expected[i]);
            skip(TERM);
            _repay(alice);
        }
        assertEq(_st(alice).step, 4);
        assertEq(_borrow(alice), CAP, "the cap holds");
        skip(TERM);
        _repay(alice);
        assertEq(_st(alice).step, 4);
        assertEq(_st(alice).onTime, 6);
    }

    function test_markMissed_onlyAfterGraceAndOnlyOnce() public {
        vm.expectRevert(NameCredit.NothingOwed.selector);
        credit.markMissed(alice);

        _borrow(alice);
        vm.warp(START + TERM + GRACE);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.NotOverdue.selector, START + TERM + GRACE));
        credit.markMissed(alice);

        skip(1);
        vm.expectEmit(true, false, false, true, address(credit));
        emit NameCredit.Missed(alice, 0, FIRST);
        vm.prank(nobody);
        credit.markMissed(alice);

        assertTrue(_st(alice).missed);
        assertEq(credit.stepTally(0).missed, 1);
        assertEq(credit.dayTally(uint32(START / 1 days)).missed, 1);

        vm.expectRevert(NameCredit.AlreadyMarked.selector);
        credit.markMissed(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.AdvanceOpen.selector, FIRST));
        credit.borrow();
    }

    function test_markMissed_aLaterRepaymentTurnsItIntoLate() public {
        _borrow(alice);
        skip(TERM + GRACE + 1);
        credit.markMissed(alice);
        _repay(alice);

        assertFalse(_st(alice).missed);
        assertEq(_st(alice).late, 1);
        assertEq(credit.stepTally(0).missed, 0);
        assertEq(credit.stepTally(0).late, 1);
        assertEq(credit.dayTally(uint32(START / 1 days)).missed, 0);
        assertEq(credit.dayTally(uint32(START / 1 days)).late, 1);
    }

    function test_markMissedMany_marksOnlyTheOverdueOnes() public {
        _borrow(alice);
        skip(1 days);
        _borrow(bob);
        vm.warp(START + TERM + GRACE + 1);

        address[] memory list = new address[](4);
        list[0] = alice;
        list[1] = bob;
        list[2] = carol;
        list[3] = alice;
        assertEq(credit.markMissedMany(list), 1);
        assertTrue(_st(alice).missed);
        assertFalse(_st(bob).missed);

        vm.expectRevert(NameCredit.BatchTooLarge.selector);
        credit.markMissedMany(new address[](201));
    }

    function test_quoteBorrow_namesTheFirstRuleThatStopsAnAdvance() public {
        (NameCredit.Refusal r, uint256 amount, uint256 due) = credit.quoteBorrow(alice);
        assertEq(uint8(r), uint8(NameCredit.Refusal.None));
        assertEq(amount, FIRST);
        assertEq(due, START + TERM);

        (r,,) = credit.quoteBorrow(nobody);
        assertEq(uint8(r), uint8(NameCredit.Refusal.NoAgentId));

        _borrow(alice);
        (r,,) = credit.quoteBorrow(alice);
        assertEq(uint8(r), uint8(NameCredit.Refusal.AdvanceOpen));

        _repay(alice);
        (r, amount,) = credit.quoteBorrow(alice);
        assertEq(uint8(r), uint8(NameCredit.Refusal.TooEarly));
        assertEq(amount, 2 * FIRST);

        _borrow(bob);
        _borrow(carol);
        _borrow(_holder("dave"));
        (r,,) = credit.quoteBorrow(_holder("erin"));
        assertEq(uint8(r), uint8(NameCredit.Refusal.PaceExhausted));

        skip(1 hours);
        address fred = _holder("fred");
        vm.startPrank(owner);
        credit.withdraw(address(credit).balance);
        (r,,) = credit.quoteBorrow(fred);
        assertEq(uint8(r), uint8(NameCredit.Refusal.PoolEmpty));
        credit.pause();
        (r,,) = credit.quoteBorrow(fred);
        assertEq(uint8(r), uint8(NameCredit.Refusal.Paused));
        vm.stopPrank();
    }

    function test_views_holdsAgentIdAndPool() public {
        assertTrue(credit.holdsAgentId(alice));
        assertFalse(credit.holdsAgentId(nobody));
        assertFalse(credit.holdsAgentId(address(0)));

        NameCredit.PoolView memory p = credit.pool();
        assertEq(p.balance, 1 ether);
        assertEq(p.outstanding, 0);
        assertEq(p.slotsNow, 4);
        assertEq(p.nextSlotAt, START);
        assertFalse(p.newAdvancesPaused);

        _borrow(alice);
        p = credit.pool();
        assertEq(p.balance, 1 ether - FIRST);
        assertEq(p.outstanding, FIRST);
        assertEq(p.slotsNow, 3);
    }

    function test_views_borrowersPageStopsAtTheEnd() public {
        _borrow(alice);
        _borrow(bob);
        _borrow(carol);
        assertEq(credit.borrowersPage(0, 2).length, 2);
        assertEq(credit.borrowersPage(1, 600).length, 2);
        assertEq(credit.borrowersPage(1, 600)[1], carol);
        assertEq(credit.borrowersPage(3, 1).length, 0);
        assertEq(credit.borrowersPage(99, 1).length, 0);

        _repay(alice);
        vm.warp(START + TERM);
        _borrow(alice);
        assertEq(credit.borrowerCount(), 3, "a returning borrower is listed once");
        assertEq(credit.totals().people, 3);
    }

    function test_plainTransferIsRefused() public {
        vm.prank(alice);
        (bool ok, bytes memory out) = address(credit).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(bytes4(out), NameCredit.DirectTransfer.selector);

        vm.prank(alice);
        (ok,) = address(credit).call{value: 1 ether}(abi.encodeWithSignature("deposit()"));
        assertFalse(ok);
    }

    function test_forcedBnbChangesNoRecordAndTheOwnerCanTakeIt() public {
        _borrow(alice);
        vm.deal(address(credit), address(credit).balance + 5 ether);
        assertEq(credit.totals().toppedUp, 1 ether);
        assertEq(credit.totals().outstanding, FIRST);
        _repay(alice);
        uint256 before = owner.balance;
        vm.prank(owner);
        credit.withdraw(6 ether);
        assertEq(owner.balance, before + 6 ether);
        assertEq(address(credit).balance, 0);
    }
}
