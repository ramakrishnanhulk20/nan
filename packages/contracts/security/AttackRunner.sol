// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// SECURITY TEST ONLY. Deployed on BNB testnet to attack this project's own NameCredit deployment there.
// Every attack is a real transaction. The runner tries the attack, records whether NameCredit refused it and
// with which error, and never reverts itself, so the record stays on chain.

import {NameCredit} from "../src/NameCredit.sol";

/// @dev A wallet the runner controls. It can hold a name, borrow, repay, and misbehave when it is sent BNB.
contract Puppet {
    address private immutable BOSS;
    NameCredit private immutable CREDIT;
    uint8 public mode; // on receiving BNB: 1 borrow again, 2 repay itself, 3 mark itself missed

    event Asked(bool served, bytes4 reason);

    error NotBoss();

    constructor(NameCredit credit) {
        BOSS = msg.sender;
        CREDIT = credit;
    }

    modifier onlyBoss() {
        if (msg.sender != BOSS) revert NotBoss();
        _;
    }

    function setMode(uint8 newMode) external onlyBoss {
        mode = newMode;
    }

    function borrow() external onlyBoss returns (uint256) {
        return CREDIT.borrow();
    }

    function borrowWithPass(bytes32 code) external onlyBoss returns (uint256) {
        return CREDIT.borrowWithPass(code);
    }

    /// Asks for an advance and reports the answer without reverting, so that a refusal is a mined transaction
    /// with its reason in the log.
    function tryBorrow() external onlyBoss returns (bool served, bytes4 reason) {
        try CREDIT.borrow() {
            served = true;
        } catch (bytes memory ret) {
            reason = ret.length >= 4 ? bytes4(ret) : bytes4(0);
        }
        emit Asked(served, reason);
    }

    function sweep() external onlyBoss {
        (bool ok,) = BOSS.call{value: address(this).balance}("");
        ok;
    }

    receive() external payable {
        if (mode == 1) CREDIT.borrow();
        else if (mode == 2) CREDIT.repay{value: msg.value}(address(this));
        else if (mode == 3) CREDIT.markMissed(address(this));
    }
}

/// @dev Created with BNB and destroyed in the same transaction, which pushes that BNB into the target
///      without calling it.
contract ForcedSender {
    constructor(address payable target) payable {
        selfdestruct(target);
    }
}

contract AttackRunner {
    struct Result {
        string attack;
        string rule;
        bool refused;
        bytes4 reason;
    }

    NameCredit public immutable CREDIT;
    address public immutable OPERATOR;
    Puppet[] public puppets;
    Result[] private _results;

    event Attacked(string attack, string rule, bool refused, bytes4 reason);

    error NotOperator();
    error SetupFailed(string step);

    constructor(NameCredit credit, uint256 count) {
        CREDIT = credit;
        OPERATOR = msg.sender;
        for (uint256 i; i < count; ++i) {
            puppets.push(new Puppet(credit));
        }
    }

    modifier onlyOperator() {
        if (msg.sender != OPERATOR) revert NotOperator();
        _;
    }

    receive() external payable {}

    function puppetCount() external view returns (uint256) {
        return puppets.length;
    }

    function results() external view returns (Result[] memory) {
        return _results;
    }

    function _record(string memory attack, string memory rule, bool ok, bytes memory ret) private {
        bytes4 reason = ret.length >= 4 ? bytes4(ret) : bytes4(0);
        _results.push(Result(attack, rule, !ok, reason));
        emit Attacked(attack, rule, !ok, reason);
    }

    function _attack(string memory attack, string memory rule, address target, uint256 value, bytes memory data)
        private
    {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        _record(attack, rule, ok, ret);
    }

    /// A wallet with no name asks for an advance, first plainly and then holding a pass that is valid.
    function noNameBorrows(bytes32 validPass) external onlyOperator {
        _attack("a wallet with no name borrows", "C1", address(CREDIT), 0, abi.encodeCall(NameCredit.borrow, ()));
        _attack(
            "a wallet with no name borrows with a valid pass",
            "C1 C18",
            address(CREDIT),
            0,
            abi.encodeCall(NameCredit.borrowWithPass, (validPass))
        );
    }

    /// A named wallet takes one advance with a pass, then tries for a second.
    function secondAdvance(uint256 i, bytes32 pass) external onlyOperator {
        Puppet p = puppets[i];
        try p.borrowWithPass(pass) {}
        catch {
            revert SetupFailed("first advance");
        }
        _attack("a second advance while one is open", "C3", address(p), 0, abi.encodeCall(Puppet.borrow, ()));
    }

    /// A named wallet re-enters during the payout of its own advance.
    function reenterOnPayout(uint256 i, bytes32 pass) external onlyOperator {
        Puppet p = puppets[i];
        p.setMode(1);
        _attack(
            "borrow again from inside the payout", "C15", address(p), 0, abi.encodeCall(Puppet.borrowWithPass, (pass))
        );
        p.setMode(2);
        _attack(
            "repay from inside the payout", "C15", address(p), 0, abi.encodeCall(Puppet.borrowWithPass, (pass))
        );
        p.setMode(3);
        _attack(
            "mark itself missed from inside the payout",
            "C15",
            address(p),
            0,
            abi.encodeCall(Puppet.borrowWithPass, (pass))
        );
        p.setMode(0);
        if (CREDIT.standingOf(address(p)).owed != 0) revert SetupFailed("the re-entering wallet ended up with an advance");
    }

    /// A stranger tries to spoil an open advance: mark it missed early, pay less than owed.
    function spoilAnOpenAdvance(uint256 i) external onlyOperator {
        address borrower = address(puppets[i]);
        uint256 owed = CREDIT.standingOf(borrower).owed;
        if (owed == 0) revert SetupFailed("no open advance to attack");
        _attack(
            "mark an advance missed before it is overdue",
            "C13",
            address(CREDIT),
            0,
            abi.encodeCall(NameCredit.markMissed, (borrower))
        );
        _attack("repay one wei less than owed", "C4 C14", address(CREDIT), owed - 1, abi.encodeCall(NameCredit.repay, (borrower)));
        if (CREDIT.standingOf(borrower).owed != owed) revert SetupFailed("the open advance changed");
    }

    /// BNB sent straight to the contract, and BNB forced in without a call.
    function unwantedBnb() external onlyOperator {
        _attack("send BNB straight to the contract", "C10", address(CREDIT), 1, "");
        _attack("call a function that does not exist, with BNB", "C10", address(CREDIT), 1, abi.encodeWithSignature("deposit()"));

        NameCredit.Totals memory before = CREDIT.totals();
        new ForcedSender{value: 1}(payable(address(CREDIT)));
        NameCredit.Totals memory afterwards = CREDIT.totals();
        bool unchanged = before.toppedUp == afterwards.toppedUp && before.outstanding == afterwards.outstanding
            && before.lent == afterwards.lent && before.repaid == afterwards.repaid;
        bytes4 marker = bytes4(keccak256("BooksUnchanged()"));
        _results.push(Result("force BNB in to distort the books", "C7", unchanged, marker));
        emit Attacked("force BNB in to distort the books", "C7", unchanged, marker);
    }

    /// A stranger calls every owner function.
    function ownerFunctions() external onlyOperator {
        address c = address(CREDIT);
        NameCredit.Settings memory s =
            NameCredit.Settings({firstAdvance: 0.002 ether, cap: 0.02 ether, term: 30 days, pacePerDay: 10_000});
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = keccak256(abi.encode(bytes32("mine")));
        _attack("stranger withdraws the pool", "C16", c, 0, abi.encodeCall(NameCredit.withdraw, (c.balance)));
        _attack("stranger tops up", "C16", c, 1, abi.encodeCall(NameCredit.topUp, ()));
        _attack("stranger pauses", "C16", c, 0, abi.encodeCall(NameCredit.pause, ()));
        _attack("stranger unpauses", "C16", c, 0, abi.encodeCall(NameCredit.unpause, ()));
        _attack("stranger schedules settings", "C16", c, 0, abi.encodeCall(NameCredit.scheduleSettings, (s)));
        _attack("stranger cancels settings", "C16", c, 0, abi.encodeCall(NameCredit.cancelSettings, ()));
        _attack("stranger issues a pass", "C16", c, 0, abi.encodeCall(NameCredit.addPasses, (hashes, type(uint40).max)));
        _attack("stranger revokes a pass", "C16", c, 0, abi.encodeCall(NameCredit.revokePass, (hashes[0])));
        _attack("stranger takes ownership", "C16", c, 0, abi.encodeWithSignature("transferOwnership(address)", address(this)));
        _attack("stranger accepts ownership", "C16", c, 0, abi.encodeWithSignature("acceptOwnership()"));
        _attack("stranger renounces ownership", "C16", c, 0, abi.encodeWithSignature("renounceOwnership()"));
    }

    /// A pass is used once, then tried again by another named wallet. An unknown code is tried too.
    function reuseAPass(uint256 first, uint256 second, bytes32 pass) external onlyOperator {
        try puppets[first].borrowWithPass(pass) {}
        catch {
            revert SetupFailed("first use of the pass");
        }
        _attack(
            "use the same pass a second time", "C18", address(puppets[second]), 0, abi.encodeCall(Puppet.borrowWithPass, (pass))
        );
        _attack(
            "use a code that was never issued",
            "C18",
            address(puppets[second]),
            0,
            abi.encodeCall(Puppet.borrowWithPass, (keccak256("guess")))
        );
    }

    /// Named wallets ask for first advances in one block until the pace says no.
    function beatThePace(uint256 from, uint256 to) external onlyOperator {
        uint256 served;
        for (uint256 i = from; i < to; ++i) {
            (bool ok, bytes memory ret) = address(puppets[i]).call(abi.encodeCall(Puppet.borrow, ()));
            if (ok) {
                ++served;
                continue;
            }
            _record("one more first advance than the pace allows, in one block", "C8", ok, ret);
            return;
        }
        _results.push(Result("the pace never refused anyone", "C8", false, bytes4(0)));
        emit Attacked("the pace never refused anyone", "C8", false, bytes4(0));
    }

    /// A borrower repays at once and asks for the next advance before the term has ended.
    function climbInAMinute(uint256 i) external onlyOperator {
        address borrower = address(puppets[i]);
        uint256 owed = CREDIT.standingOf(borrower).owed;
        if (owed == 0) revert SetupFailed("no open advance to repay");
        CREDIT.repay{value: owed}(borrower);
        if (CREDIT.standingOf(borrower).step != 1) revert SetupFailed("an on-time repayment did not add a step");
        _attack("borrow again before the term has ended", "C6", borrower, 0, abi.encodeCall(Puppet.borrow, ()));
    }

    /// Anyone tries to bring settings into force: when none are scheduled, and before the delay has passed.
    function rushSettings() external onlyOperator {
        string memory attack = CREDIT.pendingSettingsAt() == 0
            ? "apply settings when none are scheduled"
            : "apply settings before the delay has passed";
        _attack(attack, "C16", address(CREDIT), 0, abi.encodeCall(NameCredit.applySettings, ()));
    }

    /// One borrow attempt against a second NameCredit whose registry has been set to misbehave.
    function againstAHostileRegistry(NameCredit hostile, string calldata what) external onlyOperator {
        (bool ok, bytes memory ret) = address(hostile).call{gas: 600_000}(abi.encodeCall(NameCredit.borrow, ()));
        _record(what, "C1 C2", ok, ret);
    }

    /// Run a day or more later: the advance is past its grace.
    function afterTheGrace(uint256 i) external onlyOperator {
        address borrower = address(puppets[i]);
        uint256 owed = CREDIT.standingOf(borrower).owed;
        if (owed == 0) revert SetupFailed("no open advance");
        CREDIT.markMissed(borrower);
        _attack("mark the same advance missed twice", "C13", address(CREDIT), 0, abi.encodeCall(NameCredit.markMissed, (borrower)));
        _attack("borrow again while a missed advance is unpaid", "C5", borrower, 0, abi.encodeCall(Puppet.borrow, ()));
        CREDIT.repay{value: owed}(borrower);
        NameCredit.Standing memory st = CREDIT.standingOf(borrower);
        if (st.step != 0 || st.late != 1) revert SetupFailed("a late repayment did not reset the ladder");
        _attack("borrow again during the cooling-off after a late repayment", "C5", borrower, 0, abi.encodeCall(Puppet.borrow, ()));
    }

    function sweep() external onlyOperator {
        for (uint256 i; i < puppets.length; ++i) {
            puppets[i].sweep();
        }
        (bool ok,) = OPERATOR.call{value: address(this).balance}("");
        ok;
    }
}
