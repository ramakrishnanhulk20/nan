// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// SECURITY TEST ONLY. Deployed on BNB testnet to attack this project's own NameCredit deployment there.
// Every attack is a real transaction. The runner tries the attack and records what happened next to what
// the rule under test says must happen: which error, by name. A call that fails for some other reason is
// recorded as not as expected. A few entries are controls, calls that must succeed, so that a refusal next
// to them means something. The runner never reverts on an attack, so the record stays on chain.

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NameCredit} from "../src/NameCredit.sol";

/// @dev A wallet the runner controls. It can hold a name, borrow, repay, and call back into the pool when
///      it is sent BNB. It swallows the failure of that call back and keeps the BNB, so the outer call
///      completes and the reason the call back was refused can be read afterwards.
contract Puppet {
    address private immutable BOSS;
    NameCredit private immutable CREDIT;
    uint8 public mode; // on receiving BNB: 1 borrow again, 2 repay itself, 3 mark itself missed
    address public watch;
    bool public calledBack;
    bool public callBackWentThrough;
    bytes4 public innerReason;
    uint256 public owedSeen;

    event Asked(bool served, bytes4 reason);

    error NotBoss();

    constructor(NameCredit credit) {
        BOSS = msg.sender;
        CREDIT = credit;
        watch = address(this);
    }

    modifier onlyBoss() {
        if (msg.sender != BOSS) revert NotBoss();
        _;
    }

    function setMode(uint8 newMode) external onlyBoss {
        mode = newMode;
        calledBack = false;
        callBackWentThrough = false;
        innerReason = bytes4(0);
        // Not zero: zero has to mean "looked, and nothing was owed", never "did not look".
        owedSeen = type(uint256).max;
    }

    /// Whose debt this wallet looks at from inside a payment: its own by default, the borrower's when it is
    /// paying for someone else.
    function setWatch(address who) external onlyBoss {
        watch = who;
    }

    function borrow() external onlyBoss returns (uint256) {
        return CREDIT.borrow();
    }

    function borrowWithPass(bytes32 code) external onlyBoss returns (uint256) {
        return CREDIT.borrowWithPass(code);
    }

    /// Pays the open advance of `borrower` with everything sent along. Anything above what is owed comes
    /// back to this wallet, which is the moment it calls back.
    function repayFor(address borrower) external payable onlyBoss {
        CREDIT.repay{value: msg.value}(borrower);
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
        if (mode == 0) return;
        owedSeen = CREDIT.standingOf(watch).owed;
        bytes memory data;
        uint256 value;
        if (mode == 1) {
            data = abi.encodeCall(NameCredit.borrow, ());
        } else if (mode == 2) {
            data = abi.encodeCall(NameCredit.repay, (address(this)));
            value = msg.value;
        } else {
            data = abi.encodeCall(NameCredit.markMissed, (address(this)));
        }
        (bool ok, bytes memory ret) = address(CREDIT).call{value: value}(data);
        calledBack = true;
        callBackWentThrough = ok;
        innerReason = ret.length >= 4 ? bytes4(ret) : bytes4(0);
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
    /// @param attack What was tried.
    /// @param rule The rule in docs/security/threat-model.md it tests, or "control" for a call that must succeed.
    /// @param asExpected True when the outcome is the one the rule calls for.
    /// @param refused True when the attempt did not go through.
    /// @param reason The error it was refused with, as four bytes.
    /// @param expected The error the rule says it must be refused with. Zero for a control.
    struct Result {
        string attack;
        string rule;
        bool asExpected;
        bool refused;
        bytes4 reason;
        bytes4 expected;
    }

    bytes4 private constant GUARD = bytes4(keccak256("ReentrancyGuardReentrantCall()"));
    bytes4 private constant NOT_OWNER = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
    bytes4 private constant BOOKS_BALANCE = bytes4(keccak256("BooksBalance()"));
    bytes4 private constant COST_TOO_MUCH = bytes4(keccak256("CostTooMuch()"));
    /// @dev A borrow makes three registry reads of at most 60,000 gas each. A read with no ceiling would
    ///      take nearly all of the 600,000 sent.
    uint256 private constant HOSTILE_GAS_SENT = 600_000;
    uint256 private constant HOSTILE_GAS_BOUND = 250_000;

    NameCredit public immutable CREDIT;
    address public immutable OPERATOR;
    Puppet[] public puppets;
    Result[] private _results;

    event Attacked(string attack, string rule, bool asExpected, bool refused, bytes4 reason, bytes4 expected);

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

    function _push(string memory attack, string memory rule, bool asExpected, bool refused, bytes4 reason, bytes4 expected)
        private
    {
        _results.push(Result(attack, rule, asExpected, refused, reason, expected));
        emit Attacked(attack, rule, asExpected, refused, reason, expected);
    }

    function _reason(bytes memory ret) private pure returns (bytes4) {
        return ret.length >= 4 ? bytes4(ret) : bytes4(0);
    }

    /// An attempt that the rule says must be refused with `expected`.
    function _attack(
        string memory attack,
        string memory rule,
        address target,
        uint256 value,
        bytes memory data,
        bytes4 expected
    ) private {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        bytes4 reason = _reason(ret);
        _push(attack, rule, !ok && reason == expected, !ok, reason, expected);
    }

    /// A call that must succeed. Without it, the refusals around it could have another cause.
    function _control(string memory what, address target, uint256 value, bytes memory data) private {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        _push(what, "control", ok, !ok, _reason(ret), bytes4(0));
    }

    /// A wallet with no name asks for an advance, first plainly and then holding a pass that is valid.
    function noNameBorrows(bytes32 validPass) external onlyOperator {
        _attack(
            "a wallet with no name borrows",
            "C1",
            address(CREDIT),
            0,
            abi.encodeCall(NameCredit.borrow, ()),
            NameCredit.NoAgentId.selector
        );
        _attack(
            "a wallet with no name borrows with a valid pass",
            "C1 C18",
            address(CREDIT),
            0,
            abi.encodeCall(NameCredit.borrowWithPass, (validPass)),
            NameCredit.NoAgentId.selector
        );
    }

    /// One named wallet borrows with the plain call, which must work. A second asks in the same block, when
    /// the pace has nothing left.
    function paceServesOneThenRefuses(uint256 first, uint256 second) external onlyOperator {
        _control("a named wallet borrows with the plain call", address(puppets[first]), 0, abi.encodeCall(Puppet.borrow, ()));
        _attack(
            "one more first advance than the pace allows, in the same block",
            "C8",
            address(puppets[second]),
            0,
            abi.encodeCall(Puppet.borrow, ()),
            NameCredit.PaceExhausted.selector
        );
    }

    /// A wallet with an open advance asks for another. A stranger then tries to spoil that advance.
    function againstAnOpenAdvance(uint256 i) external onlyOperator {
        address borrower = address(puppets[i]);
        uint256 owed = CREDIT.standingOf(borrower).owed;
        if (owed == 0) revert SetupFailed("no open advance to attack");
        _attack(
            "a second advance while one is open", "C3", borrower, 0, abi.encodeCall(Puppet.borrow, ()), NameCredit.AdvanceOpen.selector
        );
        _attack(
            "mark an advance missed before it is overdue",
            "C13",
            address(CREDIT),
            0,
            abi.encodeCall(NameCredit.markMissed, (borrower)),
            NameCredit.NotOverdue.selector
        );
        _attack(
            "repay one wei less than owed",
            "C4 C14",
            address(CREDIT),
            owed - 1,
            abi.encodeCall(NameCredit.repay, (borrower)),
            NameCredit.Underpaid.selector
        );
        if (CREDIT.standingOf(borrower).owed != owed) revert SetupFailed("the open advance changed");
    }

    /// Three named wallets each take an advance and call back into the pool from inside the payout. The
    /// advance goes through; what is recorded is why the call back was refused, and that the debt was
    /// already on the books when the BNB arrived.
    function reenterOnPayout(uint256 first, bytes32[3] calldata passes) external onlyOperator {
        string[3] memory attacks = [
            "borrow again from inside the payout",
            "repay from inside the payout",
            "mark itself missed from inside the payout"
        ];
        // Marking is not behind the guard. It is refused because the advance is not overdue.
        string[3] memory rules = ["C15", "C15", "C13"];
        bytes4[3] memory expected = [GUARD, GUARD, NameCredit.NotOverdue.selector];
        for (uint256 m; m < 3; ++m) {
            Puppet p = puppets[first + m];
            p.setMode(uint8(m + 1));
            try p.borrowWithPass(passes[m]) {}
            catch {
                revert SetupFailed("the advance under attack did not go through");
            }
            bool refused = p.calledBack() && !p.callBackWentThrough();
            // What the wallet saw of its own debt from inside the payout must be the whole advance.
            uint256 owedNow = CREDIT.standingOf(address(p)).owed;
            bool booksFirst = owedNow != 0 && p.owedSeen() == owedNow;
            _push(attacks[m], rules[m], refused && booksFirst && p.innerReason() == expected[m], refused, p.innerReason(), expected[m]);
            p.setMode(0);
        }
    }

    /// One wallet pays another's advance with a wei too much, and calls back from inside the refund.
    function reenterOnRefund(uint256 payer, uint256 borrower) external onlyOperator {
        Puppet p = puppets[payer];
        address b = address(puppets[borrower]);
        uint256 owed = CREDIT.standingOf(b).owed;
        if (owed == 0) revert SetupFailed("no open advance to repay");
        p.setMode(1);
        p.setWatch(b);
        try p.repayFor{value: owed + 1}(b) {}
        catch {
            revert SetupFailed("the repayment under attack did not go through");
        }
        bool refused = p.calledBack() && !p.callBackWentThrough();
        // What the payer saw of the borrower's debt from inside the refund must be nothing: cleared first.
        bool booksFirst = p.owedSeen() == 0;
        _push(
            "borrow from inside the refund of an overpayment",
            "C15",
            refused && booksFirst && p.innerReason() == GUARD,
            refused,
            p.innerReason(),
            GUARD
        );
        p.setWatch(address(p));
        p.setMode(0);
        if (CREDIT.standingOf(b).owed != 0 || CREDIT.standingOf(b).step != 1) revert SetupFailed("an on-time repayment did not add a step");
    }

    /// A borrower whose advance was just repaid asks for the next one before the term has ended, and then
    /// tries to spend a newcomer's pass, which does nothing above the first step.
    function climbInAMinute(uint256 i, bytes32 validPass) external onlyOperator {
        address borrower = address(puppets[i]);
        if (CREDIT.standingOf(borrower).step != 1) revert SetupFailed("the wallet is not at the second step");
        _attack(
            "borrow again before the term has ended", "C6", borrower, 0, abi.encodeCall(Puppet.borrow, ()), NameCredit.TooEarly.selector
        );
        _attack(
            "a repeat borrower spends a newcomer's pass",
            "C18",
            borrower,
            0,
            abi.encodeCall(Puppet.borrowWithPass, (validPass)),
            NameCredit.PassNotNeeded.selector
        );
    }

    /// A pass is used once, then tried again by another named wallet. An unknown code is tried too.
    function reuseAPass(uint256 first, uint256 second, bytes32 pass) external onlyOperator {
        try puppets[first].borrowWithPass(pass) {}
        catch {
            revert SetupFailed("first use of the pass");
        }
        _attack(
            "use the same pass a second time",
            "C18",
            address(puppets[second]),
            0,
            abi.encodeCall(Puppet.borrowWithPass, (pass)),
            NameCredit.BadPass.selector
        );
        _attack(
            "use a code that was never issued",
            "C18",
            address(puppets[second]),
            0,
            abi.encodeCall(Puppet.borrowWithPass, (keccak256("guess"))),
            NameCredit.BadPass.selector
        );
    }

    /// BNB sent straight to the contract, and BNB forced in without a call. Run after real advances, a
    /// repayment and a refund, so that the first check is on books that have been used.
    /// forcedBefore is the BNB already forced into this pool by earlier runs: zero on a fresh deployment.
    function unwantedBnb(uint256 forcedBefore) external onlyOperator {
        _attack("send BNB straight to the contract", "C10", address(CREDIT), 1, "", NameCredit.DirectTransfer.selector);
        _attack(
            "call a function that does not exist, with BNB", "C10", address(CREDIT), 1, abi.encodeWithSignature("deposit()"), bytes4(0)
        );

        bool exact = _balanceAboveBooks() == forcedBefore;
        _push("the balance equals the books to the wei, after real use", "C7", exact, exact, exact ? BOOKS_BALANCE : bytes4(0), BOOKS_BALANCE);
        new ForcedSender{value: 1}(payable(address(CREDIT)));
        bool oneAbove = _balanceAboveBooks() == forcedBefore + 1;
        _push(
            "force BNB in: the books stay put and the balance sits one wei above them",
            "C7",
            oneAbove,
            oneAbove,
            oneAbove ? BOOKS_BALANCE : bytes4(0),
            BOOKS_BALANCE
        );
    }

    function _balanceAboveBooks() private view returns (uint256) {
        NameCredit.Totals memory t = CREDIT.totals();
        return address(CREDIT).balance + t.lent + t.withdrawn - t.toppedUp - t.repaid;
    }

    /// A stranger calls every function that belongs to the owner.
    function ownerFunctions() external onlyOperator {
        address c = address(CREDIT);
        NameCredit.Settings memory s =
            NameCredit.Settings({firstAdvance: 0.002 ether, cap: 0.02 ether, term: 30 days, pacePerDay: 10_000});
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = keccak256(abi.encode(bytes32("mine")));
        _attack("stranger withdraws the pool", "C16", c, 0, abi.encodeCall(NameCredit.withdraw, (c.balance)), NOT_OWNER);
        _attack("stranger tops up", "C16", c, 1, abi.encodeCall(NameCredit.topUp, ()), NOT_OWNER);
        _attack("stranger pauses", "C16", c, 0, abi.encodeCall(NameCredit.pause, ()), NOT_OWNER);
        _attack("stranger unpauses", "C16", c, 0, abi.encodeCall(NameCredit.unpause, ()), NOT_OWNER);
        _attack("stranger schedules settings", "C16", c, 0, abi.encodeCall(NameCredit.scheduleSettings, (s)), NOT_OWNER);
        _attack("stranger cancels settings", "C16", c, 0, abi.encodeCall(NameCredit.cancelSettings, ()), NOT_OWNER);
        _attack("stranger issues a pass", "C16", c, 0, abi.encodeCall(NameCredit.addPasses, (hashes, type(uint40).max)), NOT_OWNER);
        _attack("stranger revokes a pass", "C16", c, 0, abi.encodeCall(NameCredit.revokePass, (hashes[0])), NOT_OWNER);
        _attack("stranger rescues a token", "C16", c, 0, abi.encodeCall(NameCredit.rescueToken, (IERC20(c), 1)), NOT_OWNER);
        _attack("stranger takes ownership", "C16", c, 0, abi.encodeWithSignature("transferOwnership(address)", address(this)), NOT_OWNER);
        _attack("stranger accepts ownership", "C16", c, 0, abi.encodeWithSignature("acceptOwnership()"), NOT_OWNER);
        _attack("stranger renounces ownership", "C16", c, 0, abi.encodeWithSignature("renounceOwnership()"), NOT_OWNER);
    }

    /// More wallets in one marking call than the limit.
    function tooManyAtOnce() external onlyOperator {
        address[] memory list = new address[](CREDIT.MAX_BATCH() + 1);
        _attack(
            "mark more wallets in one call than the limit",
            "C13",
            address(CREDIT),
            0,
            abi.encodeCall(NameCredit.markMissedMany, (list)),
            NameCredit.BatchTooLarge.selector
        );
    }

    /// Anyone tries to bring settings into force: when none are scheduled, and before the delay has passed.
    function rushSettings() external onlyOperator {
        bool none = CREDIT.pendingSettingsAt() == 0;
        _attack(
            none ? "apply settings when none are scheduled" : "apply settings before the delay has passed",
            "C16",
            address(CREDIT),
            0,
            abi.encodeCall(NameCredit.applySettings, ()),
            none ? NameCredit.NothingScheduled.selector : NameCredit.TooSoon.selector
        );
    }

    /// One borrow attempt against a second NameCredit whose registry has been set to misbehave. It must be
    /// refused with `expected`, and must not cost more than three capped reads.
    function againstAHostileRegistry(NameCredit hostile, string calldata what, string calldata rule, bytes4 expected)
        external
        onlyOperator
    {
        uint256 before = gasleft();
        (bool ok, bytes memory ret) = address(hostile).call{gas: HOSTILE_GAS_SENT}(abi.encodeCall(NameCredit.borrow, ()));
        uint256 used = before - gasleft();
        bytes4 reason = used > HOSTILE_GAS_BOUND ? COST_TOO_MUCH : _reason(ret);
        _push(what, rule, !ok && reason == expected, !ok, reason, expected);
    }

    /// The same wallet against the same second pool, with the registry answering honestly. It must be served,
    /// which shows the refusals before it came from the registry's answers and nothing else. The advance is
    /// paid straight back.
    function hostileRegistryControl(NameCredit hostile) external onlyOperator {
        _control("the same wallet, once the registry answers honestly", address(hostile), 0, abi.encodeCall(NameCredit.borrow, ()));
        uint256 owed = hostile.standingOf(address(this)).owed;
        if (owed != 0) hostile.repay{value: owed}(address(this));
    }

    /// Run a day or more later: the advance is past its grace.
    function afterTheGrace(uint256 i, bytes32 validPass) external onlyOperator {
        address borrower = address(puppets[i]);
        uint256 owed = CREDIT.standingOf(borrower).owed;
        if (owed == 0) revert SetupFailed("no open advance");
        CREDIT.markMissed(borrower);
        _attack(
            "mark the same advance missed twice",
            "C13",
            address(CREDIT),
            0,
            abi.encodeCall(NameCredit.markMissed, (borrower)),
            NameCredit.AlreadyMarked.selector
        );
        _attack(
            "borrow again while a missed advance is unpaid",
            "C3 C5",
            borrower,
            0,
            abi.encodeCall(Puppet.borrow, ()),
            NameCredit.AdvanceOpen.selector
        );
        CREDIT.repay{value: owed}(borrower);
        NameCredit.Standing memory st = CREDIT.standingOf(borrower);
        if (st.step != 0 || st.late != 1) revert SetupFailed("a late repayment did not reset the ladder");
        _attack(
            "borrow again during the cooling-off after a late repayment",
            "C5",
            borrower,
            0,
            abi.encodeCall(Puppet.borrow, ()),
            NameCredit.TooEarly.selector
        );
        _attack(
            "use a valid pass to skip the cooling-off",
            "C5 C18",
            borrower,
            0,
            abi.encodeCall(Puppet.borrowWithPass, (validPass)),
            NameCredit.TooEarly.selector
        );
    }

    /// A repeat borrower asks for an advance that would take the pool below the day of first advances held
    /// back for newcomers. The operator has set the pool's balance just under what that needs.
    function intoTheReserve(uint256 i) external onlyOperator {
        address borrower = address(puppets[i]);
        if (CREDIT.standingOf(borrower).step != 1) revert SetupFailed("the wallet is not at the second step");
        _attack(
            "a repeat borrower takes the pool below the newcomers' reserve",
            "C9",
            borrower,
            0,
            abi.encodeCall(Puppet.borrow, ()),
            NameCredit.PoolEmpty.selector
        );
    }

    /// Scheduled settings that double the pace come into force, and two fresh wallets ask in that block.
    /// The store of unused pace must not jump to the new, larger ceiling: one is served, one is not.
    function burstAfterASettingsChange(uint256 first, uint256 second) external onlyOperator {
        CREDIT.applySettings();
        _control("a named wallet borrows right after a faster pace comes into force", address(puppets[first]), 0, abi.encodeCall(Puppet.borrow, ()));
        _attack(
            "a second first advance in the block where a faster pace came into force",
            "C8",
            address(puppets[second]),
            0,
            abi.encodeCall(Puppet.borrow, ()),
            NameCredit.PaceExhausted.selector
        );
    }

    function sweep() external onlyOperator {
        for (uint256 i; i < puppets.length; ++i) {
            puppets[i].sweep();
        }
        (bool ok,) = OPERATOR.call{value: address(this).balance}("");
        ok;
    }
}
