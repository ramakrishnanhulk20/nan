// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// A what-if run of the real contract over the 16 days of the hackathon window, with three kinds of borrower:
//   takers   borrow once and never repay
//   climbers repay on the due time, borrow again, and stop repaying once they hold an advance at the cap
//   keepers  always repay on the due time and borrow again
// It prints what happens to the pool. Run with:  forge test --match-contract LadderSim -vv
// Change the mix with SIM_TAKERS, SIM_CLIMBERS, SIM_KEEPERS, the pool with SIM_POOL_WEI and the pace with SIM_PACE.
// What this file does NOT cover: how real people will behave. The mix is an assumption, not a measurement.

import {Test, console} from "forge-std/Test.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {HandleRegistry} from "./mocks/HandleRegistry.sol";

contract LadderSim is Test {
    uint256 internal constant START = 1_795_000_000;
    uint256 internal constant HORIZON = 16 days;
    uint256 internal constant TICK = 1 hours;
    uint96 internal constant FIRST = 0.0003 ether;
    uint96 internal constant CAP = 0.0048 ether;
    uint32 internal constant TERM = 3 days;
    uint256 internal constant NEVER = type(uint256).max;

    HandleRegistry internal registry;
    NameCredit internal credit;
    address internal owner = makeAddr("owner");
    address internal registryOwner = makeAddr("registryOwner");

    address[] internal actors;
    uint8[] internal kind; // 0 taker, 1 climber, 2 keeper
    uint256[] internal inside; // actors that will act again, by index
    mapping(uint256 => uint256) internal nextAct; // when that actor next has something to do
    uint256 internal queueHead;
    uint256[3] internal served;

    function _setUp(uint256 takers, uint256 climbers, uint256 keepers, uint256 poolWei, uint32 pace) internal {
        vm.warp(START);
        vm.prank(registryOwner);
        registry = new HandleRegistry(makeAddr("signer"), 3, 15, "", "");
        credit = new NameCredit(
            address(registry), owner, NameCredit.Settings({firstAdvance: FIRST, cap: CAP, term: TERM, pacePerDay: pace})
        );
        vm.deal(owner, poolWei);
        vm.prank(owner);
        credit.topUp{value: poolWei}();

        // Arrivals are interleaved so that no kind is first in line.
        uint256 total = takers + climbers + keepers;
        uint256[3] memory left = [takers, climbers, keepers];
        for (uint256 i; i < total; ++i) {
            uint8 k = uint8(i % 3);
            for (uint256 tries; tries < 3 && left[k] == 0; ++tries) {
                k = (k + 1) % 3;
            }
            left[k]--;
            string memory name = string(abi.encodePacked("sim", vm.toString(i)));
            address who = makeAddr(name);
            vm.prank(registryOwner);
            registry.adminRegister(name, who);
            actors.push(who);
            kind.push(k);
        }
    }

    /// One returning borrower: repay what is due if they are the repaying kind, then borrow again if allowed.
    function _act(uint256 i) internal {
        address who = actors[i];
        NameCredit.Standing memory st = credit.standingOf(who);
        if (st.owed != 0) {
            bool willRepay = kind[i] == 2 || st.owed < CAP;
            if (!willRepay) {
                nextAct[i] = NEVER;
                return;
            }
            vm.deal(who, st.owed);
            vm.prank(who);
            credit.repay{value: st.owed}(who);
            st = credit.standingOf(who);
        }
        (NameCredit.Refusal refusal,,) = credit.quoteBorrow(who);
        if (refusal != NameCredit.Refusal.None) {
            // Waiting for the term to end or for the pool to refill. Look again in six hours.
            nextAct[i] = block.timestamp + 6 hours;
            return;
        }
        vm.prank(who);
        credit.borrow();
        nextAct[i] = block.timestamp + TERM;
    }

    function _run(uint256 takers, uint256 climbers, uint256 keepers, uint256 poolWei, uint32 pace) internal {
        _setUp(takers, climbers, keepers, poolWei, pace);

        for (uint256 t; t <= HORIZON; t += TICK) {
            vm.warp(START + t);

            uint256 n = inside.length;
            for (uint256 j; j < n; ++j) {
                uint256 i = inside[j];
                if (nextAct[i] <= block.timestamp) _act(i);
            }

            // Newcomers take whatever first advances the pace and the pool allow, in arrival order.
            uint256 slots = credit.pool().slotsNow;
            while (slots != 0 && queueHead < actors.length && address(credit).balance >= FIRST) {
                uint256 i = queueHead;
                vm.prank(actors[i]);
                credit.borrow();
                served[kind[i]]++;
                if (kind[i] != 0) {
                    inside.push(i);
                    nextAct[i] = block.timestamp + TERM;
                }
                ++queueHead;
                --slots;
            }

            if (t % (4 days) == 0) {
                console.log("day", t / 1 days);
                console.log("   pool wei", address(credit).balance, "out wei", credit.totals().outstanding);
                console.log("   people served", credit.totals().people);
            }
        }
        _report(poolWei);
    }

    function _report(uint256 poolWei) internal {
        // Everything overdue at the end is marked, so the tallies are complete.
        for (uint256 i; i < queueHead; i += 200) {
            uint256 end = i + 200 > queueHead ? queueHead : i + 200;
            address[] memory page = new address[](end - i);
            for (uint256 j = i; j < end; ++j) {
                page[j - i] = actors[j];
            }
            credit.markMissedMany(page);
        }

        NameCredit.Totals memory tot = credit.totals();
        console.log("---- after 16 days ----");
        console.log("pool at start wei", poolWei);
        console.log("pool now wei", address(credit).balance);
        console.log("still out wei", tot.outstanding);
        console.log("people served", tot.people);
        console.log("   takers", served[0]);
        console.log("   climbers", served[1]);
        console.log("   keepers", served[2]);
        console.log("still waiting in line", actors.length - queueHead);
        uint256 lostWei;
        for (uint8 step; step <= 4; ++step) {
            NameCredit.StepTally memory s = credit.stepTally(step);
            if (s.advances == 0) continue;
            console.log("step", step);
            console.log("   advances", s.advances, "on time", s.onTime);
            console.log("   missed", s.missed, "open, not yet overdue", s.advances - s.onTime - s.late - s.missed);
            lostWei += uint256(s.missed) * (uint256(FIRST) << step > CAP ? CAP : uint256(FIRST) << step);
        }
        console.log("missed so far wei", lostWei);
        NameCredit.StepTally memory s0 = credit.stepTally(0);
        uint256 settled = uint256(s0.onTime) + s0.late + s0.missed;
        if (settled != 0) console.log("first advance on-time rate, percent", (uint256(s0.onTime) * 100) / settled);

        // The books must balance whatever the mix.
        assertEq(address(credit).balance, poolWei + tot.repaid - tot.lent);
        assertEq(tot.outstanding, uint256(tot.lent) - tot.repaid);
    }

    function test_sim_startingNumbers() public {
        _run(
            vm.envOr("SIM_TAKERS", uint256(900)),
            vm.envOr("SIM_CLIMBERS", uint256(300)),
            vm.envOr("SIM_KEEPERS", uint256(300)),
            vm.envOr("SIM_POOL_WEI", uint256(0.3 ether)),
            uint32(vm.envOr("SIM_PACE", uint256(100)))
        );
    }

    function test_sim_worstCaseNobodyRepays() public {
        _run(1500, 0, 0, 0.3 ether, 100);
        assertEq(credit.totals().repaid, 0);
        assertEq(address(credit).balance + credit.totals().outstanding, 0.3 ether, "the most that can be lost is the pool");
    }
}
