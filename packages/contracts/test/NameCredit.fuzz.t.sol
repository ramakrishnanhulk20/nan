// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Fuzz tests on the money rules: timing, the ladder, the settings limits and the release pace.
// What this file does NOT cover: sequences of many actions by many wallets (NameCredit.invariant.t.sol) and
// the registry's answers (NameCredit.registry.t.sol).

import {NameCredit} from "../src/NameCredit.sol";
import {Base} from "./Base.t.sol";

contract NameCreditFuzzTest is Base {
    function testFuzz_repaymentTimeDecidesTheOutcome(uint32 delay, uint64 extra) public {
        delay = uint32(bound(delay, 0, 60 days));
        extra = uint64(bound(extra, 0, 0.5 ether));
        _borrow(alice);
        vm.warp(START + delay);

        uint256 before = bob.balance;
        vm.prank(bob);
        credit.repay{value: uint256(FIRST) + extra}(alice);

        assertEq(bob.balance, before - FIRST, "the payer pays exactly what was owed");
        assertEq(address(credit).balance, 1 ether, "the pool is whole again");
        NameCredit.Standing memory st = _st(alice);
        assertEq(st.owed, 0);
        if (delay <= TERM + GRACE) {
            assertEq(st.step, 1);
            assertEq(st.onTime, 1);
            assertEq(st.late, 0);
            assertEq(st.notBefore, START + TERM);
        } else {
            assertEq(st.step, 0);
            assertEq(st.onTime, 0);
            assertEq(st.late, 1);
            assertEq(st.notBefore, START + delay + COOLING_OFF);
        }
    }

    function testFuzz_markingMissedNeedsTheGraceToHavePassed(uint32 delay) public {
        delay = uint32(bound(delay, 0, 60 days));
        _borrow(alice);
        vm.warp(START + delay);
        if (delay <= TERM + GRACE) {
            vm.expectRevert(abi.encodeWithSelector(NameCredit.NotOverdue.selector, START + TERM + GRACE));
            credit.markMissed(alice);
            assertFalse(_st(alice).missed);
        } else {
            credit.markMissed(alice);
            assertTrue(_st(alice).missed);
        }
    }

    function testFuzz_everyAdvanceSitsBetweenTheFirstAdvanceAndTheCap(uint96 first, uint96 cap, uint8 rounds) public {
        first = uint96(bound(first, 0.00005 ether, 0.002 ether));
        cap = uint96(bound(cap, first, 0.02 ether));
        rounds = uint8(bound(rounds, 1, 14));
        NameCredit c = new NameCredit(
            address(registry),
            owner,
            NameCredit.Settings({firstAdvance: first, cap: cap, term: 1 hours, pacePerDay: 100})
        );
        // Enough for the largest advance plus the day of first advances that is held back for newcomers.
        vm.prank(owner);
        c.topUp{value: 1 ether}();

        uint256 previous = 0;
        for (uint256 i; i < rounds; ++i) {
            vm.prank(alice);
            uint256 amount = c.borrow();
            uint256 doubled = uint256(first) << i;
            assertEq(amount, doubled > cap ? cap : doubled, "double each step, never above the cap");
            assertGe(amount, previous, "the ladder never goes down while repaying on time");
            previous = amount;
            skip(1 hours);
            vm.prank(alice);
            c.repay{value: amount}(alice);
        }
        assertLe(c.standingOf(alice).step, 9, "nine steps reach the largest cap from the smallest first advance");
    }

    function testFuzz_settingsAreAcceptedExactlyInsideTheLimits(uint96 first, uint96 cap, uint32 term, uint32 pace)
        public
    {
        bool valid = first >= 0.00005 ether && first <= 0.002 ether && cap >= first && cap <= 0.02 ether
            && term >= 1 hours && term <= 30 days && pace <= 10_000;
        NameCredit.Settings memory s = NameCredit.Settings({firstAdvance: first, cap: cap, term: term, pacePerDay: pace});
        vm.prank(owner);
        if (!valid) vm.expectRevert(NameCredit.SettingsOutOfBounds.selector);
        credit.scheduleSettings(s);
        assertEq(credit.pendingSettingsAt(), valid ? START + 12 hours : 0);
    }

    function testFuzz_settingsNearTheLimits(uint8 pick, bool over) public {
        NameCredit.Settings memory s = _defaults();
        pick = uint8(bound(pick, 0, 6));
        if (pick == 0) s.firstAdvance = over ? 0.00005 ether - 1 : 0.00005 ether;
        if (pick == 1) (s.firstAdvance, s.cap) = (over ? 0.002 ether + 1 : 0.002 ether, 0.01 ether);
        if (pick == 2) s.cap = over ? s.firstAdvance - 1 : s.firstAdvance;
        if (pick == 3) s.cap = over ? 0.02 ether + 1 : 0.02 ether;
        if (pick == 4) s.term = over ? 1 hours - 1 : 1 hours;
        if (pick == 5) s.term = over ? 30 days + 1 : 30 days;
        if (pick == 6) s.pacePerDay = over ? 10_001 : 10_000;
        vm.prank(owner);
        if (over) vm.expectRevert(NameCredit.SettingsOutOfBounds.selector);
        credit.scheduleSettings(s);
    }

    /// However long the pool sits unused, the first advances that can start in one block afterwards are at
    /// most one hour of pace, or one advance where an hour of pace is less than one.
    function testFuzz_aQuietSpellStoresAtMostTheCeiling(uint32 pace, uint32 quiet) public {
        pace = uint32(bound(pace, 1, 10_000));
        quiet = uint32(bound(quiet, 0, 60 days));
        NameCredit c = new NameCredit(
            address(registry), owner, NameCredit.Settings({firstAdvance: FIRST, cap: CAP, term: TERM, pacePerDay: pace})
        );
        vm.prank(owner);
        c.topUp{value: 10 ether}();
        skip(quiet);

        uint256 atMost = uint256(pace) * 1 hours / 1 days;
        if (atMost == 0) atMost = 1;
        assertEq(c.pool().slotsNow, atMost, "the store is full and no fuller");

        if (atMost > 6) return;
        for (uint256 i; i <= atMost; ++i) {
            address who = makeAddr(string(abi.encodePacked("q", vm.toString(i))));
            _name(string(abi.encodePacked("quiet", vm.toString(i))), who);
            vm.prank(who);
            if (i == atMost) vm.expectPartialRevert(NameCredit.PaceExhausted.selector);
            c.borrow();
        }
        assertEq(c.totals().people, atMost);
    }

    /// However callers time their attempts, first advances never exceed the ceiling of the store plus what
    /// has been released since. The ceiling itself is checked by the test above.
    function testFuzz_firstAdvancesNeverBeatThePace(uint32 pace, uint16[24] memory gaps) public {
        pace = uint32(bound(pace, 1, 10_000));
        NameCredit c = new NameCredit(
            address(registry), owner, NameCredit.Settings({firstAdvance: FIRST, cap: CAP, term: TERM, pacePerDay: pace})
        );
        vm.prank(owner);
        c.topUp{value: 10 ether}();

        uint256 burst = uint256(pace) * 1 hours;
        uint256 ceiling = burst > 1 days ? burst : 1 days;
        uint256 served;
        uint256 elapsed;
        for (uint256 i; i < gaps.length; ++i) {
            skip(gaps[i]);
            elapsed += gaps[i];
            for (uint256 j; j < 3; ++j) {
                address who = makeAddr(string(abi.encodePacked("p", vm.toString(i), "-", vm.toString(j))));
                _name(string(abi.encodePacked("p", vm.toString(i), "x", vm.toString(j))), who);
                vm.prank(who);
                try c.borrow() {
                    ++served;
                } catch (bytes memory reason) {
                    assertEq(bytes4(reason), NameCredit.PaceExhausted.selector, "the only reason to be turned away");
                    assertEq(c.pool().slotsNow, 0);
                }
            }
        }
        assertLe(served * 1 days, ceiling + elapsed * pace, "never more than the pace allows");
        assertEq(c.totals().people, served);
    }

    function testFuzz_aStrangerCanOnlySettleNeverSpoil(uint32 delay, uint8 action) public {
        delay = uint32(bound(delay, 0, TERM + GRACE));
        _borrow(alice);
        vm.warp(START + delay);
        NameCredit.Standing memory before = _st(alice);

        vm.startPrank(nobody);
        if (action % 3 == 0) {
            vm.expectRevert(abi.encodeWithSelector(NameCredit.NotOverdue.selector, START + TERM + GRACE));
            credit.markMissed(alice);
        } else if (action % 3 == 1) {
            vm.expectRevert(abi.encodeWithSelector(NameCredit.Underpaid.selector, FIRST));
            credit.repay{value: FIRST - 1}(alice);
        } else {
            address[] memory list = new address[](1);
            list[0] = alice;
            assertEq(credit.markMissedMany(list), 0);
        }
        vm.stopPrank();

        NameCredit.Standing memory afterwards = _st(alice);
        assertEq(afterwards.owed, before.owed);
        assertEq(afterwards.due, before.due);
        assertEq(afterwards.missed, before.missed);
        assertEq(afterwards.step, before.step);
    }
}
