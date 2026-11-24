// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Unit tests for the constructor and every owner function: what the owner can do, and what nobody else can.
// What this file does NOT cover: borrower flows (NameCredit.t.sol), registry misbehaviour
// (NameCredit.registry.t.sol), and whether a stolen owner key could be used off-chain (it could; see the
// threat model's non-goals).

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {Base} from "./Base.t.sol";
import {TestToken, RejectingWallet} from "./mocks/Hostile.sol";

contract NameCreditOwnerTest is Base {
    function _unauthorized(address who) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, who);
    }

    function test_constructor_setsEverything() public view {
        assertEq(address(credit.REGISTRY()), address(registry));
        assertEq(credit.owner(), owner);
        (uint96 first, uint96 cap, uint32 term, uint32 pace) = credit.settings();
        assertEq(first, FIRST);
        assertEq(cap, CAP);
        assertEq(term, TERM);
        assertEq(pace, PACE);
        assertEq(credit.pendingSettingsAt(), 0);
        assertEq(credit.GRACE(), GRACE);
        assertEq(credit.COOLING_OFF(), COOLING_OFF);
        assertEq(credit.SETTINGS_DELAY(), 12 hours);
    }

    function test_constructor_refusesARegistryThatIsNotAContract() public {
        vm.expectRevert(NameCredit.NotAContract.selector);
        new NameCredit(makeAddr("an ordinary wallet"), owner, _defaults());
    }

    function test_constructor_refusesSettingsOutsideTheLimits() public {
        NameCredit.Settings[7] memory bad;
        for (uint256 i; i < 7; ++i) {
            bad[i] = _defaults();
        }
        bad[0].firstAdvance = 0.00005 ether - 1;
        bad[1].firstAdvance = 0.002 ether + 1;
        bad[1].cap = 0.01 ether;
        bad[2].cap = FIRST - 1;
        bad[3].cap = 0.02 ether + 1;
        bad[4].term = 1 hours - 1;
        bad[5].term = 30 days + 1;
        bad[6].pacePerDay = 10_001;
        for (uint256 i; i < 7; ++i) {
            vm.expectRevert(NameCredit.SettingsOutOfBounds.selector);
            new NameCredit(address(registry), owner, bad[i]);
        }
    }

    function test_constructor_acceptsTheLimitsThemselves() public {
        NameCredit.Settings memory low =
            NameCredit.Settings({firstAdvance: 0.00005 ether, cap: 0.00005 ether, term: 1 hours, pacePerDay: 0});
        NameCredit.Settings memory high =
            NameCredit.Settings({firstAdvance: 0.002 ether, cap: 0.02 ether, term: 30 days, pacePerDay: 10_000});
        NameCredit a = new NameCredit(address(registry), owner, low);
        NameCredit b = new NameCredit(address(registry), owner, high);
        assertEq(a.pool().slotsNow, 0, "a pace of zero releases nothing");
        assertEq(a.pool().nextSlotAt, 0);
        assertEq(b.pool().slotsNow, 416, "one hour of 10,000 a day");
    }

    function test_paceOfZero_onlyAPassCanStartAFirstAdvance() public {
        NameCredit.Settings memory s = _defaults();
        s.pacePerDay = 0;
        NameCredit c = new NameCredit(address(registry), owner, s);
        vm.prank(owner);
        c.topUp{value: 1 ether}();
        skip(10 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.PaceExhausted.selector, 0));
        c.borrow();

        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = keccak256(abi.encode(bytes32("code")));
        vm.prank(owner);
        c.addPasses(hashes, uint40(block.timestamp + 1 days));
        vm.prank(alice);
        assertEq(c.borrowWithPass(bytes32("code")), FIRST);
    }

    function test_topUp_ownerOnlyAndCounted() public {
        vm.prank(alice);
        vm.expectRevert(_unauthorized(alice));
        credit.topUp{value: 1 ether}();

        vm.prank(owner);
        vm.expectRevert(NameCredit.ZeroAmount.selector);
        credit.topUp{value: 0}();

        vm.expectEmit(true, false, false, true, address(credit));
        emit NameCredit.ToppedUp(owner, 2 ether);
        vm.prank(owner);
        credit.topUp{value: 2 ether}();
        assertEq(credit.totals().toppedUp, 3 ether);
        assertEq(address(credit).balance, 3 ether);
    }

    function test_withdraw_ownerOnlyAndOnlyWhatIsHere() public {
        vm.prank(alice);
        vm.expectRevert(_unauthorized(alice));
        credit.withdraw(1);

        vm.startPrank(owner);
        vm.expectRevert(NameCredit.ZeroAmount.selector);
        credit.withdraw(0);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.PoolEmpty.selector, 1 ether + 1, 1 ether));
        credit.withdraw(1 ether + 1);

        uint256 before = owner.balance;
        vm.expectEmit(true, false, false, true, address(credit));
        emit NameCredit.Withdrawn(owner, 0.4 ether);
        credit.withdraw(0.4 ether);
        vm.stopPrank();

        assertEq(owner.balance, before + 0.4 ether);
        assertEq(credit.totals().withdrawn, 0.4 ether);
        assertEq(address(credit).balance, 0.6 ether);
    }

    function test_withdraw_cannotReachMoneyThatIsLentOut() public {
        _borrow(alice);
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.PoolEmpty.selector, 1 ether, 1 ether - FIRST));
        credit.withdraw(1 ether);
        credit.withdraw(1 ether - FIRST);
        vm.stopPrank();
        assertEq(_st(alice).owed, FIRST, "the borrower's record is untouched");
        _repay(alice);
        assertEq(address(credit).balance, FIRST);
    }

    function test_pause_ownerOnlyStopsNewAdvancesNotRepayment() public {
        vm.prank(alice);
        vm.expectRevert(_unauthorized(alice));
        credit.pause();

        _borrow(alice);
        vm.prank(owner);
        credit.pause();
        assertTrue(credit.pool().newAdvancesPaused);

        vm.prank(bob);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        credit.borrow();

        _repay(alice);
        skip(TERM + GRACE + 1);

        vm.prank(alice);
        vm.expectRevert(_unauthorized(alice));
        credit.unpause();
        vm.prank(owner);
        credit.unpause();
        _borrow(bob);
    }

    function test_pause_doesNotStopMarkingMissed() public {
        _borrow(alice);
        vm.prank(owner);
        credit.pause();
        skip(TERM + GRACE + 1);
        credit.markMissed(alice);
        assertTrue(_st(alice).missed);
    }

    function _next() internal pure returns (NameCredit.Settings memory) {
        return NameCredit.Settings({firstAdvance: 0.001 ether, cap: 0.01 ether, term: 1 days, pacePerDay: 10});
    }

    function test_settings_scheduleThenApplyAfterTheDelay() public {
        vm.prank(alice);
        vm.expectRevert(_unauthorized(alice));
        credit.scheduleSettings(_next());

        vm.expectRevert(NameCredit.NothingScheduled.selector);
        credit.applySettings();

        vm.expectEmit(false, false, false, true, address(credit));
        emit NameCredit.SettingsScheduled(_next(), START + 12 hours);
        vm.prank(owner);
        credit.scheduleSettings(_next());
        assertEq(credit.pendingSettingsAt(), START + 12 hours);

        skip(12 hours - 1);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.TooSoon.selector, START + 12 hours));
        credit.applySettings();
        assertEq(_borrow(alice), FIRST, "the old settings still rule");

        skip(1);
        vm.expectEmit(false, false, false, true, address(credit));
        emit NameCredit.SettingsApplied(_next());
        vm.prank(nobody);
        credit.applySettings();

        (uint96 first, uint96 cap, uint32 term, uint32 pace) = credit.settings();
        assertEq(first, 0.001 ether);
        assertEq(cap, 0.01 ether);
        assertEq(term, 1 days);
        assertEq(pace, 10);
        assertEq(credit.pendingSettingsAt(), 0);
        assertEq(_borrow(bob), 0.001 ether);
        assertEq(_st(bob).due, block.timestamp + 1 days);
    }

    function test_withdraw_anOwnerThatRefusesBnbFailsCleanly() public {
        RejectingWallet stubborn = new RejectingWallet(credit);
        vm.prank(owner);
        credit.transferOwnership(address(stubborn));
        stubborn.acceptOwnership();
        vm.expectRevert(NameCredit.PayoutFailed.selector);
        stubborn.withdraw(1);
        assertEq(credit.totals().withdrawn, 0);
        assertEq(address(credit).balance, 1 ether);
    }

    function test_settings_lapseAWeekAfterTheDelay() public {
        vm.prank(owner);
        credit.scheduleSettings(_next());
        uint256 effectiveAt = START + 12 hours;

        vm.warp(effectiveAt + 7 days + 1);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.SettingsLapsed.selector, effectiveAt + 7 days));
        credit.applySettings();
        (uint96 first,,,) = credit.settings();
        assertEq(first, FIRST, "the stale change did not arrive");

        vm.prank(owner);
        credit.scheduleSettings(_next());
        vm.warp(block.timestamp + 12 hours + 7 days);
        credit.applySettings();
        (first,,,) = credit.settings();
        assertEq(first, 0.001 ether, "scheduled again, it applies up to the last second of the window");
    }

    function test_settings_anOpenAdvanceKeepsItsTerms() public {
        _borrow(alice);
        vm.prank(owner);
        credit.scheduleSettings(_next());
        skip(12 hours);
        credit.applySettings();

        NameCredit.Standing memory st = _st(alice);
        assertEq(st.owed, FIRST, "amount fixed when it was made");
        assertEq(st.due, START + TERM, "due time fixed when it was made");
        assertEq(st.limit, 0.001 ether, "only the next advance follows the new settings");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.Underpaid.selector, FIRST));
        credit.repay{value: FIRST - 1}(alice);
        _repay(alice);
        assertEq(_st(alice).step, 1);
    }

    function test_settings_outOfBoundsRefusedAndCancelWorks() public {
        NameCredit.Settings memory bad = _next();
        bad.cap = 0.02 ether + 1;
        vm.startPrank(owner);
        vm.expectRevert(NameCredit.SettingsOutOfBounds.selector);
        credit.scheduleSettings(bad);

        vm.expectRevert(NameCredit.NothingScheduled.selector);
        credit.cancelSettings();

        credit.scheduleSettings(_next());
        vm.expectEmit(false, false, false, false, address(credit));
        emit NameCredit.SettingsCancelled();
        credit.cancelSettings();
        vm.stopPrank();

        assertEq(credit.pendingSettingsAt(), 0);
        skip(1 days);
        vm.expectRevert(NameCredit.NothingScheduled.selector);
        credit.applySettings();

        vm.prank(alice);
        vm.expectRevert(_unauthorized(alice));
        credit.cancelSettings();
    }

    function test_settings_aSecondScheduleRestartsTheDelay() public {
        vm.startPrank(owner);
        credit.scheduleSettings(_next());
        skip(11 hours);
        NameCredit.Settings memory other = _next();
        other.pacePerDay = 50;
        credit.scheduleSettings(other);
        vm.stopPrank();
        skip(1 hours);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.TooSoon.selector, START + 23 hours));
        credit.applySettings();
        skip(11 hours);
        credit.applySettings();
        (,,, uint32 pace) = credit.settings();
        assertEq(pace, 50);
    }

    function test_settings_storedPaceIsHeldToTheNewCeiling() public {
        assertEq(credit.pool().slotsNow, 4);
        vm.prank(owner);
        credit.scheduleSettings(_next());
        skip(12 hours);
        credit.applySettings();
        assertEq(credit.pool().slotsNow, 1, "a pace of 10 a day can hold one slot");

        _borrow(alice);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NameCredit.PaceExhausted.selector, block.timestamp + 8640));
        credit.borrow();
    }

    function test_settings_aLowerCapPullsTheLadderDown() public {
        _borrow(alice);
        _repay(alice);
        skip(TERM);
        _borrow(alice);
        _repay(alice);
        assertEq(_st(alice).step, 2);
        assertEq(_st(alice).limit, 4 * FIRST);

        NameCredit.Settings memory s = _defaults();
        s.cap = FIRST;
        vm.prank(owner);
        credit.scheduleSettings(s);
        skip(TERM);
        credit.applySettings();
        assertEq(_st(alice).limit, FIRST);
        assertEq(_borrow(alice), FIRST);
        _repay(alice);
        assertEq(_st(alice).step, 2, "at the cap, an on-time repayment does not add a step");
    }

    function test_addPasses_ownerOnlyWithLimits() public {
        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = keccak256("a");
        hashes[1] = keccak256("b");

        vm.prank(alice);
        vm.expectRevert(_unauthorized(alice));
        credit.addPasses(hashes, uint40(START + 1));

        vm.startPrank(owner);
        vm.expectRevert(NameCredit.BadExpiry.selector);
        credit.addPasses(hashes, uint40(START));
        vm.expectRevert(NameCredit.BatchTooLarge.selector);
        credit.addPasses(new bytes32[](201), uint40(START + 1));

        vm.expectEmit(false, false, false, true, address(credit));
        emit NameCredit.PassesAdded(2, START + 1 days);
        credit.addPasses(hashes, uint40(START + 1 days));
        vm.stopPrank();
        assertEq(credit.passExpiry(hashes[0]), START + 1 days);
        assertEq(credit.passExpiry(hashes[1]), START + 1 days);

        vm.prank(alice);
        vm.expectRevert(_unauthorized(alice));
        credit.revokePass(hashes[0]);
    }

    function test_rescueToken_returnsATokenSentByMistake() public {
        TestToken token = new TestToken();
        token.transfer(address(credit), 5 ether);

        vm.prank(alice);
        vm.expectRevert(_unauthorized(alice));
        credit.rescueToken(IERC20(address(token)), 5 ether);

        vm.startPrank(owner);
        vm.expectRevert(NameCredit.ZeroAmount.selector);
        credit.rescueToken(IERC20(address(token)), 0);
        vm.expectEmit(true, false, false, true, address(credit));
        emit NameCredit.TokenRescued(address(token), 5 ether);
        credit.rescueToken(IERC20(address(token)), 5 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(owner), 5 ether);
    }

    function test_ownership_movesInTwoStepsAndCannotBeRenounced() public {
        vm.prank(owner);
        vm.expectRevert(NameCredit.RenounceDisabled.selector);
        credit.renounceOwnership();

        vm.prank(alice);
        vm.expectRevert(_unauthorized(alice));
        credit.renounceOwnership();

        address next = makeAddr("next owner");
        vm.prank(owner);
        credit.transferOwnership(next);
        assertEq(credit.owner(), owner, "nothing changes until the new owner accepts");
        assertEq(credit.pendingOwner(), next);

        vm.prank(alice);
        vm.expectRevert(_unauthorized(alice));
        credit.acceptOwnership();

        vm.prank(next);
        credit.acceptOwnership();
        assertEq(credit.owner(), next);

        vm.prank(owner);
        vm.expectRevert(_unauthorized(owner));
        credit.pause();
    }

    /// The owner's powers are "exactly these and nothing else". This is the test that can fail on the
    /// "nothing else": the complete list of what the compiled contract answers to. Adding, removing or
    /// renaming any function breaks it until this list and the threat model are changed on purpose.
    ///   Anyone may call: borrow, borrowWithPass, repay, markMissed, markMissedMany, applySettings.
    ///   Owner only: topUp, withdraw, pause, unpause, scheduleSettings, cancelSettings, addPasses,
    ///   revokePass, rescueToken, transferOwnership. Pending owner only: acceptOwnership.
    ///   Everything else on the list is a read, and renounceOwnership always reverts.
    function test_theContractAnswersToExactlyTheseFunctions() public view {
        string[47] memory expected = [
            "COOLING_OFF()",
            "GRACE()",
            "MAX_BATCH()",
            "MAX_CAP()",
            "MAX_FIRST_ADVANCE()",
            "MAX_PACE_PER_DAY()",
            "MAX_PAGE()",
            "MAX_TERM()",
            "MIN_FIRST_ADVANCE()",
            "MIN_TERM()",
            "REGISTRY()",
            "SETTINGS_DELAY()",
            "SETTINGS_WINDOW()",
            "acceptOwnership()",
            "addPasses(bytes32[],uint40)",
            "applySettings()",
            "borrow()",
            "borrowWithPass(bytes32)",
            "borrowerCount()",
            "borrowersPage(uint256,uint256)",
            "cancelSettings()",
            "dayTally(uint32)",
            "holdsAgentId(address)",
            "markMissed(address)",
            "markMissedMany(address[])",
            "owner()",
            "passExpiry(bytes32)",
            "pause()",
            "paused()",
            "pendingOwner()",
            "pendingSettings()",
            "pendingSettingsAt()",
            "pool()",
            "quoteBorrow(address)",
            "renounceOwnership()",
            "repay(address)",
            "rescueToken(address,uint256)",
            "revokePass(bytes32)",
            "scheduleSettings((uint96,uint96,uint32,uint32))",
            "settings()",
            "standingOf(address)",
            "stepTally(uint8)",
            "topUp()",
            "totals()",
            "transferOwnership(address)",
            "unpause()",
            "withdraw(uint256)"
        ];
        string memory artifact = vm.readFile("out/NameCredit.sol/NameCredit.json");
        string[] memory actual = vm.parseJsonKeys(artifact, ".methodIdentifiers");
        assertEq(actual.length, expected.length, "a function was added or removed");
        for (uint256 i; i < expected.length; ++i) {
            bool found = false;
            for (uint256 j; j < actual.length; ++j) {
                if (keccak256(bytes(actual[j])) == keccak256(bytes(expected[i]))) found = true;
            }
            assertTrue(found, expected[i]);
        }
    }

    function test_owner_hasNoWayToEditARecord() public {
        _borrow(alice);
        NameCredit.Standing memory before = _st(alice);
        vm.startPrank(owner);
        credit.pause();
        credit.unpause();
        credit.scheduleSettings(_next());
        credit.withdraw(address(credit).balance);
        credit.topUp{value: 1 ether}();
        vm.stopPrank();
        skip(12 hours);
        credit.applySettings();
        NameCredit.Standing memory afterwards = _st(alice);
        assertEq(afterwards.owed, before.owed);
        assertEq(afterwards.due, before.due);
        assertEq(afterwards.step, before.step);
        assertEq(afterwards.nameHash, before.nameHash);
        assertEq(afterwards.notBefore, before.notBefore);
    }
}
