// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Invariant tests: random sequences of every action, by named wallets, wallets with no name and the owner.
// After every sequence the rules in threat model section C must still hold.
// What this file does NOT cover: BNB forced into the contract (NameCredit.t.sol), a registry that misbehaves
// (NameCredit.registry.t.sol), and wallets that are contracts.

import {Test} from "forge-std/Test.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {HandleRegistry} from "./mocks/HandleRegistry.sol";

contract Handler is Test {
    NameCredit public immutable CREDIT;
    address public immutable OWNER;
    address[] public holders;
    address[] public strangers;
    uint32[] public daysSeen;
    mapping(uint32 => bool) private _daySeen;

    uint256 public toppedUp;
    uint256 public withdrawn;
    uint256 public lent;
    uint256 public repaid;
    uint256 public passCounter;
    bool public repayFailed;
    bool public strangerBorrowed;
    bool public advanceAboveLimit;
    bool public openTermsChanged;

    constructor(NameCredit credit, HandleRegistry registry, address owner, address registryOwner) {
        CREDIT = credit;
        OWNER = owner;
        for (uint256 i; i < 10; ++i) {
            string memory name = string(abi.encodePacked("holder", vm.toString(i)));
            address who = makeAddr(name);
            vm.prank(registryOwner);
            registry.adminRegister(name, who);
            vm.deal(who, 100 ether);
            holders.push(who);
        }
        for (uint256 i; i < 3; ++i) {
            address who = makeAddr(string(abi.encodePacked("stranger", vm.toString(i))));
            vm.deal(who, 100 ether);
            strangers.push(who);
        }
        toppedUp = address(credit).balance;
    }

    function holderCount() external view returns (uint256) {
        return holders.length;
    }

    function strangerCount() external view returns (uint256) {
        return strangers.length;
    }

    function dayCount() external view returns (uint256) {
        return daysSeen.length;
    }

    function _anyone(uint256 seed) private view returns (address who, bool isHolder) {
        uint256 i = seed % (holders.length + strangers.length);
        if (i < holders.length) return (holders[i], true);
        return (strangers[i - holders.length], false);
    }

    function _noteDay() private {
        uint32 day = uint32(block.timestamp / 1 days);
        if (!_daySeen[day]) {
            _daySeen[day] = true;
            daysSeen.push(day);
        }
    }

    function _afterBorrow(address who, bool isHolder, uint256 amount) private {
        lent += amount;
        _noteDay();
        if (!isHolder) strangerBorrowed = true;
        (uint96 first, uint96 cap,,) = CREDIT.settings();
        if (amount > cap || amount < (first < cap ? first : cap)) advanceAboveLimit = true;
        if (CREDIT.standingOf(who).owed != amount) advanceAboveLimit = true;
    }

    function borrow(uint256 seed) external {
        (address who, bool isHolder) = _anyone(seed);
        vm.prank(who);
        try CREDIT.borrow() returns (uint256 amount) {
            _afterBorrow(who, isHolder, amount);
        } catch {}
    }

    function borrowWithPass(uint256 seed) external {
        (address who, bool isHolder) = _anyone(seed);
        bytes32 code = bytes32(++passCounter);
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = keccak256(abi.encode(code));
        vm.prank(OWNER);
        CREDIT.addPasses(hashes, uint40(block.timestamp + 1 days));
        vm.prank(who);
        try CREDIT.borrowWithPass(code) returns (uint256 amount) {
            _afterBorrow(who, isHolder, amount);
        } catch {}
    }

    function repay(uint256 borrowerSeed, uint256 payerSeed, uint256 extra) external {
        address borrower = holders[borrowerSeed % holders.length];
        uint256 owed = CREDIT.standingOf(borrower).owed;
        if (owed == 0) return;
        (address payer,) = _anyone(payerSeed);
        extra = bound(extra, 0, 1 ether);
        uint256 before = payer.balance;
        vm.prank(payer);
        try CREDIT.repay{value: owed + extra}(borrower) {
            repaid += owed;
            if (payer.balance != before - owed) repayFailed = true;
        } catch {
            repayFailed = true;
        }
    }

    function underpay(uint256 borrowerSeed, uint256 short) external {
        address borrower = holders[borrowerSeed % holders.length];
        uint256 owed = CREDIT.standingOf(borrower).owed;
        if (owed == 0) return;
        short = bound(short, 1, owed);
        vm.prank(borrower);
        try CREDIT.repay{value: owed - short}(borrower) {
            repayFailed = true;
        } catch {}
    }

    function markMissed(uint256 seed) external {
        try CREDIT.markMissed(holders[seed % holders.length]) {} catch {}
    }

    function markMissedMany() external {
        CREDIT.markMissedMany(holders);
    }

    function wait(uint256 secs) external {
        skip(bound(secs, 1, 5 days));
    }

    function topUp(uint256 amount) external {
        amount = bound(amount, 1, 0.5 ether);
        vm.deal(OWNER, amount);
        vm.prank(OWNER);
        CREDIT.topUp{value: amount}();
        toppedUp += amount;
    }

    function withdraw(uint256 amount) external {
        uint256 available = address(CREDIT).balance;
        if (available == 0) return;
        amount = bound(amount, 1, available);
        vm.prank(OWNER);
        CREDIT.withdraw(amount);
        withdrawn += amount;
    }

    function setPaused(bool on) external {
        vm.prank(OWNER);
        if (on) {
            try CREDIT.pause() {} catch {}
        } else {
            try CREDIT.unpause() {} catch {}
        }
    }

    function changeSettings(uint96 first, uint96 cap, uint32 term, uint32 pace) external {
        first = uint96(bound(first, 0.00005 ether, 0.002 ether));
        cap = uint96(bound(cap, first, 0.02 ether));
        term = uint32(bound(term, 1 hours, 30 days));
        pace = uint32(bound(pace, 0, 10_000));

        uint256[] memory owedBefore = new uint256[](holders.length);
        uint256[] memory dueBefore = new uint256[](holders.length);
        for (uint256 i; i < holders.length; ++i) {
            NameCredit.Standing memory st = CREDIT.standingOf(holders[i]);
            (owedBefore[i], dueBefore[i]) = (st.owed, st.due);
        }

        vm.prank(OWNER);
        CREDIT.scheduleSettings(NameCredit.Settings({firstAdvance: first, cap: cap, term: term, pacePerDay: pace}));
        skip(12 hours);
        CREDIT.applySettings();

        for (uint256 i; i < holders.length; ++i) {
            NameCredit.Standing memory st = CREDIT.standingOf(holders[i]);
            if (st.owed != owedBefore[i] || st.due != dueBefore[i]) openTermsChanged = true;
        }
    }
}

contract NameCreditInvariantTest is Test {
    HandleRegistry internal registry;
    NameCredit internal credit;
    Handler internal handler;
    address internal owner = makeAddr("owner");
    address internal registryOwner = makeAddr("registryOwner");

    function setUp() public {
        vm.warp(1_795_000_000);
        vm.prank(registryOwner);
        registry = new HandleRegistry(makeAddr("signer"), 3, 15, "", "");
        credit = new NameCredit(
            address(registry),
            owner,
            NameCredit.Settings({firstAdvance: 0.0003 ether, cap: 0.0048 ether, term: 3 days, pacePerDay: 100})
        );
        vm.deal(owner, 2 ether);
        vm.prank(owner);
        credit.topUp{value: 2 ether}();
        handler = new Handler(credit, registry, owner, registryOwner);
        targetContract(address(handler));
    }

    /// Guards against a handler that quietly does nothing: a fixed sequence must lend, repay and mark.
    function test_handlerReallyLendsRepaysAndMarks() public {
        for (uint256 i; i < 4; ++i) {
            handler.borrow(i);
        }
        handler.borrow(11);
        handler.borrowWithPass(4);
        assertEq(handler.lent(), 5 * 0.0003 ether, "four paced advances and one with a pass");
        assertFalse(handler.strangerBorrowed());
        handler.repay(0, 12, 5);
        handler.underpay(1, 1);
        handler.wait(5 days);
        handler.markMissedMany();
        handler.changeSettings(0.001 ether, 0.004 ether, 2 days, 500);
        handler.repay(1, 1, 0);
        assertEq(handler.repaid(), 2 * 0.0003 ether);
        assertEq(credit.stepTally(0).missed, 3);
        assertEq(credit.stepTally(0).late, 1);
        assertFalse(handler.repayFailed());
        assertFalse(handler.openTermsChanged());
    }

    /// C7: the balance is exactly top-ups plus repayments, minus advances, minus withdrawals.
    function invariant_theBooksBalance() public view {
        NameCredit.Totals memory t = credit.totals();
        assertEq(t.toppedUp, handler.toppedUp());
        assertEq(t.withdrawn, handler.withdrawn());
        assertEq(t.lent, handler.lent());
        assertEq(t.repaid, handler.repaid());
        assertEq(address(credit).balance, uint256(t.toppedUp) + t.repaid - t.lent - t.withdrawn);
    }

    /// C3 and C4: what is outstanding is the sum of open advances, one per wallet, none above the cap limit.
    function invariant_outstandingIsTheSumOfOpenAdvances() public view {
        uint256 sum;
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            NameCredit.Standing memory st = credit.standingOf(handler.holders(i));
            sum += st.owed;
            assertLe(st.owed, 0.02 ether, "no advance above the hard cap");
            assertLe(st.step, 15);
            if (st.owed != 0) assertGt(st.due, 0);
            if (st.owed == 0) assertFalse(st.missed);
        }
        NameCredit.Totals memory t = credit.totals();
        assertEq(sum, t.outstanding);
        assertEq(uint256(t.lent) - t.repaid, t.outstanding);
        assertFalse(handler.advanceAboveLimit(), "an advance fell outside the settings in force");
    }

    /// C1: a wallet with no name never gets an advance and never gets a record.
    function invariant_noNameNoAdvance() public view {
        assertFalse(handler.strangerBorrowed());
        uint256 n = handler.strangerCount();
        for (uint256 i; i < n; ++i) {
            NameCredit.Standing memory st = credit.standingOf(handler.strangers(i));
            assertEq(st.owed, 0);
            assertEq(st.nameHash, bytes32(0));
            assertEq(uint256(st.onTime) + st.late, 0);
        }
    }

    /// C11 and C12: repayment always goes through, and no settings change touches an open advance.
    function invariant_repaymentNeverFailsAndOpenTermsNeverMove() public view {
        assertFalse(handler.repayFailed(), "a full repayment was refused or cost the wrong amount");
        assertFalse(handler.openTermsChanged(), "a settings change altered an open advance");
    }

    /// Every advance ever made is in exactly one state: repaid on time, repaid late, missed, or open.
    function invariant_everyAdvanceIsCountedOnce() public view {
        Sums memory bySteps = _sumSteps();
        Sums memory byWallets = _sumWallets();
        NameCredit.Totals memory t = credit.totals();

        assertEq(bySteps.advances, bySteps.onTime + bySteps.late + bySteps.missed + byWallets.openNotMissed);
        assertEq(bySteps.missed, byWallets.missed);
        assertEq(bySteps.onTime, byWallets.onTime);
        assertEq(bySteps.late, byWallets.late);
        assertEq(bySteps.lent, t.lent);
        assertEq(bySteps.repaid, t.repaid);
        assertEq(byWallets.people, t.people);
        assertEq(byWallets.people, credit.borrowerCount());

        Sums memory byDays = _sumDays();
        assertEq(byDays.advances, bySteps.advances, "the per-day counts add up to the per-step counts");
        assertEq(byDays.onTime + byDays.late + byDays.missed, bySteps.onTime + bySteps.late + bySteps.missed);
    }

    struct Sums {
        uint256 advances;
        uint256 onTime;
        uint256 late;
        uint256 missed;
        uint256 lent;
        uint256 repaid;
        uint256 openNotMissed;
        uint256 people;
    }

    function _sumSteps() internal view returns (Sums memory sums) {
        for (uint8 step; step <= 15; ++step) {
            NameCredit.StepTally memory s = credit.stepTally(step);
            sums.advances += s.advances;
            sums.onTime += s.onTime;
            sums.late += s.late;
            sums.missed += s.missed;
            sums.lent += s.lent;
            sums.repaid += s.repaid;
        }
    }

    function _sumWallets() internal view returns (Sums memory sums) {
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            NameCredit.Standing memory st = credit.standingOf(handler.holders(i));
            if (st.owed != 0 && st.missed) ++sums.missed;
            if (st.owed != 0 && !st.missed) ++sums.openNotMissed;
            if (st.nameHash != bytes32(0)) ++sums.people;
            sums.onTime += st.onTime;
            sums.late += st.late;
        }
    }

    function _sumDays() internal view returns (Sums memory sums) {
        uint256 n = handler.dayCount();
        for (uint256 i; i < n; ++i) {
            NameCredit.DayTally memory d = credit.dayTally(handler.daysSeen(i));
            sums.advances += d.advances;
            sums.onTime += d.onTime;
            sums.late += d.late;
            sums.missed += d.missed;
        }
    }
}
