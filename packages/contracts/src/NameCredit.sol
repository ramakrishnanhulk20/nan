// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IAgentIdRegistry} from "./interfaces/IAgentIdRegistry.sol";

/// @title NameCredit
/// @notice Lends small amounts of BNB, with nothing locked up, to wallets that hold an Agent ID.
///         A wallet has one name for life, so a borrower who does not repay cannot start again as someone new.
///         The pool is funded by the owner alone. This contract never holds anyone else's money.
/// @dev    Owner powers, all of them: add BNB, pause new advances, withdraw BNB held here, schedule a change to
///         the four settings inside the limits below (effective after SETTINGS_DELAY), issue and revoke passes
///         that skip the release pace, recover tokens sent here by mistake, and hand over ownership in two steps.
///         The owner cannot change a borrower's record, alter an open advance, or stop anyone repaying.
contract NameCredit is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @notice The four numbers the owner may tune.
    /// @param firstAdvance Amount in wei of an advance at the first step.
    /// @param cap The most any single advance can be, in wei.
    /// @param term Seconds between an advance and its due time.
    /// @param pacePerDay First-step advances released per day.
    struct Settings {
        uint96 firstAdvance;
        uint96 cap;
        uint32 term;
        uint32 pacePerDay;
    }

    /// @dev Packed into one slot, with the name hash in a second.
    struct Account {
        uint96 owed;
        uint40 due;
        uint40 notBefore;
        uint8 step;
        bool missed;
        uint32 madeDay;
        uint16 onTime;
        uint16 late;
        bytes32 nameHash;
    }

    /// @notice A wallet's record as the outside world reads it.
    /// @param nameHash keccak256 of the name seen at the first advance. Zero if the wallet never borrowed.
    /// @param step Ladder step of the open advance, or of the next one.
    /// @param limit What an advance at that step would be under the current settings, in wei.
    /// @param owed The open advance in wei. Zero when there is none.
    /// @param due When the open advance is due. Zero when there is none.
    /// @param overdueAt After this time the open advance is late and can be marked missed.
    /// @param missed The open advance has been marked missed.
    /// @param notBefore The earliest time a new advance may start.
    /// @param onTime Advances repaid on time.
    /// @param late Advances repaid late.
    struct Standing {
        bytes32 nameHash;
        uint8 step;
        uint256 limit;
        uint256 owed;
        uint256 due;
        uint256 overdueAt;
        bool missed;
        uint256 notBefore;
        uint16 onTime;
        uint16 late;
    }

    /// @notice Outcome counts for one ladder step.
    struct StepTally {
        uint64 advances;
        uint64 onTime;
        uint64 late;
        uint64 missed;
        uint128 lent;
        uint128 repaid;
    }

    /// @notice Outcome counts for the advances made on one UTC day.
    struct DayTally {
        uint64 advances;
        uint64 onTime;
        uint64 late;
        uint64 missed;
    }

    /// @notice Running totals in wei, and the number of distinct borrowers.
    struct Totals {
        uint64 people;
        uint128 lent;
        uint128 repaid;
        uint128 outstanding;
        uint128 toppedUp;
        uint128 withdrawn;
    }

    /// @notice The pool as the site shows it.
    /// @param balance BNB held here now.
    /// @param outstanding BNB lent and not yet repaid.
    /// @param slotsNow First-step advances that could start in this block.
    /// @param nextSlotAt When the next first-step advance can start. Zero when the pace is zero and none is stored.
    /// @param newAdvancesPaused True when the owner has paused new advances.
    struct PoolView {
        uint256 balance;
        uint256 outstanding;
        uint256 slotsNow;
        uint256 nextSlotAt;
        bool newAdvancesPaused;
    }

    /// @notice Why `quoteBorrow` says no.
    enum Refusal {
        None,
        Paused,
        AdvanceOpen,
        TooEarly,
        NoAgentId,
        PaceExhausted,
        PoolEmpty
    }

    /// @notice Days after the due time during which a repayment still counts as on time.
    uint256 public constant GRACE = 1 days;
    /// @notice Wait after a late repayment before the wallet may borrow again, from the first step.
    uint256 public constant COOLING_OFF = 7 days;
    /// @notice Wait between scheduling new settings and their taking effect.
    uint256 public constant SETTINGS_DELAY = 12 hours;

    /// @notice The smallest first advance the owner may set, in wei.
    uint96 public constant MIN_FIRST_ADVANCE = 0.00005 ether;
    /// @notice The largest first advance the owner may set, in wei.
    uint96 public constant MAX_FIRST_ADVANCE = 0.002 ether;
    /// @notice The largest cap the owner may set, in wei. No advance can ever exceed it.
    uint96 public constant MAX_CAP = 0.02 ether;
    /// @notice The shortest term the owner may set, in seconds.
    uint32 public constant MIN_TERM = 1 hours;
    /// @notice The longest term the owner may set, in seconds.
    uint32 public constant MAX_TERM = 30 days;
    /// @notice The fastest release pace the owner may set, in first-step advances per day.
    uint32 public constant MAX_PACE_PER_DAY = 10_000;

    /// @notice The most entries one call to `markMissedMany` or `addPasses` accepts.
    /// @dev 200 marks or passes cost about 4 million gas, a small share of a BNB Smart Chain block.
    uint256 public constant MAX_BATCH = 200;
    /// @notice The most wallets `borrowersPage` returns in one call.
    /// @dev A page of 500 addresses is 16 kilobytes of return data, well inside what public nodes serve.
    uint256 public constant MAX_PAGE = 500;

    /// @dev The registry answers each read in under 15,000 gas. The ceiling stops a misbehaving registry
    ///      from spending the caller's whole gas limit.
    uint256 private constant REGISTRY_GAS = 60_000;
    /// @dev The registry's own ceiling on name length.
    uint256 private constant MAX_NAME_LENGTH = 64;
    /// @dev Doubling from the smallest first advance passes the largest cap in nine steps.
    uint8 private constant MAX_STEP = 15;
    /// @dev Pace credit is counted in advance-seconds: one first-step advance costs one day of credit at a pace of one.
    uint256 private constant SLOT = 1 days;
    /// @dev Unused pace builds up for at most this long, so a quiet night cannot be spent in one block.
    uint256 private constant PACE_BURST = 1 hours;

    /// @notice The Agent ID registry this contract reads. Fixed at deployment.
    IAgentIdRegistry public immutable REGISTRY;

    /// @notice The settings in force.
    Settings public settings;
    /// @notice Settings waiting to take effect, if any.
    Settings public pendingSettings;
    /// @notice When the pending settings may be applied. Zero when nothing is scheduled.
    uint256 public pendingSettingsAt;

    mapping(address => Account) private _accounts;
    mapping(uint8 => StepTally) private _stepTally;
    mapping(uint32 => DayTally) private _dayTally;
    mapping(bytes32 => uint40) private _passExpiry;
    address[] private _borrowers;
    Totals private _totals;
    uint64 private _paceCredit;
    uint40 private _paceUpdated;

    /// @notice An advance was sent to a borrower.
    /// @param borrower The wallet that received it.
    /// @param nameHash keccak256 of the borrower's Agent ID name.
    /// @param step The ladder step it was made at.
    /// @param amount The BNB sent, in wei.
    /// @param due When it falls due.
    /// @param withPass True when a pass was used to skip the release pace.
    event Borrowed(
        address indexed borrower, bytes32 indexed nameHash, uint8 step, uint256 amount, uint256 due, bool withPass
    );

    /// @notice An advance was repaid in full.
    /// @param borrower The wallet whose advance was settled.
    /// @param payer The wallet that paid.
    /// @param step The ladder step the advance was made at.
    /// @param amount The BNB repaid, in wei.
    /// @param onTime True when it arrived by the due time plus `GRACE`.
    event Repaid(address indexed borrower, address indexed payer, uint8 step, uint256 amount, bool onTime);

    /// @notice An open advance went past its due time plus `GRACE` and was recorded as missed.
    /// @param borrower The wallet whose advance is overdue.
    /// @param step The ladder step the advance was made at.
    /// @param amount The BNB still owed, in wei.
    event Missed(address indexed borrower, uint8 step, uint256 amount);

    /// @notice The owner added BNB to the pool.
    /// @param from The owner's wallet.
    /// @param amount The BNB added, in wei.
    event ToppedUp(address indexed from, uint256 amount);

    /// @notice The owner took BNB out of the pool.
    /// @param to The owner's wallet.
    /// @param amount The BNB taken, in wei.
    event Withdrawn(address indexed to, uint256 amount);

    /// @notice New settings were scheduled.
    /// @param settings The settings that will apply.
    /// @param effectiveAt The earliest time they can be applied.
    event SettingsScheduled(Settings settings, uint256 effectiveAt);

    /// @notice Settings came into force.
    /// @param settings The settings now in force.
    event SettingsApplied(Settings settings);

    /// @notice The scheduled settings were dropped.
    event SettingsCancelled();

    /// @notice The owner registered passes.
    /// @param count How many were registered.
    /// @param expires When they stop working.
    event PassesAdded(uint256 count, uint256 expires);

    /// @notice The owner cancelled a pass.
    /// @param passHash The hash of the cancelled pass.
    event PassRevoked(bytes32 indexed passHash);

    /// @notice The owner recovered a token that had been sent here by mistake.
    /// @param token The token contract.
    /// @param amount The amount recovered.
    event TokenRescued(address indexed token, uint256 amount);

    /// @notice The caller holds no Agent ID, or the registry did not give three matching answers.
    error NoAgentId();
    /// @notice The registry reports a different name for this wallet than the one recorded at its first advance.
    error NameMismatch();
    /// @notice The caller already has an advance open.
    /// @param owed The amount still owed, in wei.
    error AdvanceOpen(uint256 owed);
    /// @notice The caller may not borrow yet.
    /// @param notBefore The earliest time a new advance may start.
    error TooEarly(uint256 notBefore);
    /// @notice No first-step advance is available right now.
    /// @param nextSlotAt When the next one opens. Zero when the pace is zero.
    error PaceExhausted(uint256 nextSlotAt);
    /// @notice The pool cannot cover this.
    /// @param needed The BNB that would have to be here, in wei.
    /// @param available The BNB that is here, in wei.
    error PoolEmpty(uint256 needed, uint256 available);
    /// @notice The receiving wallet refused the BNB.
    error PayoutFailed();
    /// @notice There is no open advance for this wallet.
    error NothingOwed();
    /// @notice Less than the full amount was sent.
    /// @param owed The amount owed, in wei.
    error Underpaid(uint256 owed);
    /// @notice The advance is not overdue yet.
    /// @param overdueAt The time after which it can be marked missed.
    error NotOverdue(uint256 overdueAt);
    /// @notice The advance has already been marked missed.
    error AlreadyMarked();
    /// @notice One of the four settings is outside its limits.
    error SettingsOutOfBounds();
    /// @notice No settings are scheduled.
    error NothingScheduled();
    /// @notice The delay has not passed.
    /// @param effectiveAt The earliest time the settings can be applied.
    error TooSoon(uint256 effectiveAt);
    /// @notice The pass is unknown, used, revoked or expired.
    error BadPass();
    /// @notice The expiry is not in the future.
    error BadExpiry();
    /// @notice More entries than `MAX_BATCH`.
    error BatchTooLarge();
    /// @notice BNB was sent without calling `topUp` or `repay`.
    error DirectTransfer();
    /// @notice Ownership cannot be given up, because the pool could then never be withdrawn.
    error RenounceDisabled();
    /// @notice The amount is zero.
    error ZeroAmount();
    /// @notice The registry address holds no code.
    error NotAContract();

    /// @notice Deploys the pool with its starting settings. It holds no BNB until the owner tops it up.
    /// @param registry The Agent ID registry. Must be a deployed contract.
    /// @param initialOwner The wallet that funds and administers the pool.
    /// @param initial The starting settings. Reverts `SettingsOutOfBounds` outside the limits above.
    constructor(address registry, address initialOwner, Settings memory initial) Ownable(initialOwner) {
        if (registry.code.length == 0) revert NotAContract();
        _checkBounds(initial);
        REGISTRY = IAgentIdRegistry(registry);
        settings = initial;
        _paceCredit = _paceCeiling(initial.pacePerDay).toUint64();
        _paceUpdated = block.timestamp.toUint40();
        emit SettingsApplied(initial);
    }

    /// @notice A plain transfer is refused so that nobody's BNB lands here by mistake.
    receive() external payable {
        revert DirectTransfer();
    }

    /// @notice Take an advance at the caller's current step.
    /// @dev    The caller must hold an Agent ID in this same transaction, have no open advance, and be past
    ///         `notBefore`. At the first step the release pace must allow it. Above the first step the pool must
    ///         hold the advance plus one day of first advances, which stay back for newcomers. Reverts
    ///         `NoAgentId`, `NameMismatch`, `AdvanceOpen`, `TooEarly`, `PaceExhausted`, `PoolEmpty` or
    ///         `PayoutFailed`. Emits `Borrowed`.
    /// @return amount The BNB sent to the caller, in wei.
    function borrow() external nonReentrant whenNotPaused returns (uint256 amount) {
        return _borrow(false);
    }

    /// @notice Take an advance using a single-use pass, which skips the release pace and nothing else.
    /// @dev    Reverts `BadPass` if the code is unknown, used or expired. Every other rule of `borrow` applies.
    ///         A code seen in a pending transaction could be used first by another Agent ID holder.
    /// @param code The secret whose hash the owner registered with `addPasses`.
    /// @return amount The BNB sent to the caller, in wei.
    function borrowWithPass(bytes32 code) external nonReentrant whenNotPaused returns (uint256 amount) {
        bytes32 passHash = keccak256(abi.encode(code));
        uint256 expires = _passExpiry[passHash];
        if (expires == 0 || expires < block.timestamp) revert BadPass();
        delete _passExpiry[passHash];
        return _borrow(true);
    }

    /// @notice Repay the open advance of `borrower`. Anyone may pay, from any wallet.
    /// @dev    Works while new advances are paused and never reads the registry. Send at least the amount owed;
    ///         anything above it is returned to the payer in the same transaction. Paid by the due time plus
    ///         `GRACE`, the borrower moves up one step and may borrow again once the original term has ended.
    ///         Paid later, the borrower restarts at the first step after `COOLING_OFF`.
    ///         Reverts `NothingOwed`, `Underpaid` or `PayoutFailed`. Emits `Repaid`.
    /// @param borrower The wallet whose advance is being settled.
    function repay(address borrower) external payable nonReentrant {
        Account storage a = _accounts[borrower];
        uint256 owed = a.owed;
        if (owed == 0) revert NothingOwed();
        if (msg.value < owed) revert Underpaid(owed);

        uint8 step = a.step;
        uint32 day = a.madeDay;
        uint40 due = a.due;
        bool wasMissed = a.missed;
        bool onTime = block.timestamp <= uint256(due) + GRACE;

        a.owed = 0;
        a.due = 0;
        a.missed = false;

        if (onTime) {
            if (a.onTime != type(uint16).max) ++a.onTime;
            Settings memory s = settings;
            if (step < MAX_STEP && _limit(step, s) < s.cap) a.step = step + 1;
            // One advance per term: paying back in a minute does not let a borrower run up the ladder in an hour.
            if (due > a.notBefore) a.notBefore = due;
            ++_stepTally[step].onTime;
            ++_dayTally[day].onTime;
        } else {
            if (a.late != type(uint16).max) ++a.late;
            a.step = 0;
            a.notBefore = (block.timestamp + COOLING_OFF).toUint40();
            ++_stepTally[step].late;
            ++_dayTally[day].late;
            if (wasMissed) {
                --_stepTally[step].missed;
                --_dayTally[day].missed;
            }
        }

        _stepTally[step].repaid += owed.toUint128();
        _totals.repaid += owed.toUint128();
        _totals.outstanding -= owed.toUint128();
        emit Repaid(borrower, msg.sender, step, owed, onTime);

        uint256 extra = msg.value - owed;
        if (extra != 0) {
            (bool ok,) = msg.sender.call{value: extra}("");
            if (!ok) revert PayoutFailed();
        }
    }

    /// @notice Record that an open advance has gone past its due time plus `GRACE`. Anyone may call.
    /// @dev    Changes counters and the `missed` flag only. Reverts `NothingOwed`, `AlreadyMarked` or `NotOverdue`.
    /// @param borrower The wallet whose advance is overdue.
    function markMissed(address borrower) external {
        Account storage a = _accounts[borrower];
        if (a.owed == 0) revert NothingOwed();
        if (a.missed) revert AlreadyMarked();
        uint256 overdueAt = uint256(a.due) + GRACE;
        if (block.timestamp <= overdueAt) revert NotOverdue(overdueAt);
        _mark(borrower, a);
    }

    /// @notice Mark every overdue advance in `list`, skipping wallets that are not overdue. Anyone may call.
    /// @dev    Reverts `BatchTooLarge` above `MAX_BATCH` entries.
    /// @param list Wallets to check.
    /// @return marked How many were marked.
    function markMissedMany(address[] calldata list) external returns (uint256 marked) {
        if (list.length > MAX_BATCH) revert BatchTooLarge();
        for (uint256 i; i < list.length; ++i) {
            Account storage a = _accounts[list[i]];
            if (a.owed != 0 && !a.missed && block.timestamp > uint256(a.due) + GRACE) {
                _mark(list[i], a);
                ++marked;
            }
        }
    }

    /// @notice The record of a wallet.
    /// @param who The wallet to look up.
    /// @return The wallet's standing. A wallet that never borrowed shows no name hash, nothing owed and the
    ///         first-step limit.
    function standingOf(address who) external view returns (Standing memory) {
        Account storage a = _accounts[who];
        bool open = a.owed != 0;
        return Standing({
            nameHash: a.nameHash,
            step: a.step,
            limit: _limit(a.step, settings),
            owed: a.owed,
            due: a.due,
            overdueAt: open ? uint256(a.due) + GRACE : 0,
            missed: a.missed,
            notBefore: a.notBefore,
            onTime: a.onTime,
            late: a.late
        });
    }

    /// @notice What `borrow` would do for a wallet right now, without sending anything.
    /// @param who The wallet to check.
    /// @return refusal `None` when an advance would be made, otherwise the first rule that stops it.
    /// @return amount The advance in wei at the wallet's step.
    /// @return due When it would fall due.
    function quoteBorrow(address who) external view returns (Refusal refusal, uint256 amount, uint256 due) {
        Account storage a = _accounts[who];
        Settings memory s = settings;
        amount = _limit(a.step, s);
        due = block.timestamp + s.term;
        if (paused()) return (Refusal.Paused, amount, due);
        if (a.owed != 0) return (Refusal.AdvanceOpen, amount, due);
        if (block.timestamp < a.notBefore) return (Refusal.TooEarly, amount, due);
        bytes32 nameHash = _nameHashOf(who);
        if (nameHash == bytes32(0) || (a.nameHash != bytes32(0) && a.nameHash != nameHash)) {
            return (Refusal.NoAgentId, amount, due);
        }
        if (a.step == 0 && _paceNow(s.pacePerDay) < SLOT) return (Refusal.PaceExhausted, amount, due);
        if (address(this).balance < amount + _heldForNewcomers(a.step, s)) return (Refusal.PoolEmpty, amount, due);
        return (Refusal.None, amount, due);
    }

    /// @notice Whether the registry reports that a wallet holds an Agent ID whose name maps back to it.
    /// @param who The wallet to check.
    /// @return True when all three registry answers agree.
    function holdsAgentId(address who) external view returns (bool) {
        return _nameHashOf(who) != bytes32(0);
    }

    /// @notice The pool and the release pace right now.
    /// @return The pool as the site shows it.
    function pool() external view returns (PoolView memory) {
        uint32 pace = settings.pacePerDay;
        uint256 credit = _paceNow(pace);
        uint256 nextSlotAt = 0;
        if (credit >= SLOT) {
            nextSlotAt = block.timestamp;
        } else if (pace != 0) {
            nextSlotAt = block.timestamp + (SLOT - credit + pace - 1) / pace;
        }
        return PoolView({
            balance: address(this).balance,
            outstanding: _totals.outstanding,
            slotsNow: credit / SLOT,
            nextSlotAt: nextSlotAt,
            newAdvancesPaused: paused()
        });
    }

    /// @notice Running totals.
    /// @return Totals in wei, and the number of distinct borrowers.
    function totals() external view returns (Totals memory) {
        return _totals;
    }

    /// @notice Outcome counts for one ladder step.
    /// @param step The ladder step, starting at zero.
    /// @return The counts and amounts for that step.
    function stepTally(uint8 step) external view returns (StepTally memory) {
        return _stepTally[step];
    }

    /// @notice Outcome counts for the advances made on one UTC day.
    /// @param day Unix time divided by 86,400.
    /// @return The counts for advances made that day.
    function dayTally(uint32 day) external view returns (DayTally memory) {
        return _dayTally[day];
    }

    /// @notice How many distinct wallets have ever borrowed.
    /// @return The number of wallets.
    function borrowerCount() external view returns (uint256) {
        return _borrowers.length;
    }

    /// @notice A page of borrower wallets in the order they first borrowed.
    /// @dev    Returns at most `MAX_PAGE` entries and stops at the end of the list.
    /// @param start Index of the first wallet to return.
    /// @param count How many to return.
    /// @return page The wallets, possibly fewer than asked for.
    function borrowersPage(uint256 start, uint256 count) external view returns (address[] memory page) {
        uint256 length = _borrowers.length;
        if (start >= length) return new address[](0);
        if (count > MAX_PAGE) count = MAX_PAGE;
        uint256 end = start + count > length ? length : start + count;
        page = new address[](end - start);
        for (uint256 i = start; i < end; ++i) {
            page[i - start] = _borrowers[i];
        }
    }

    /// @notice When a pass expires.
    /// @param passHash keccak256(abi.encode(code)) of the pass.
    /// @return The expiry time. Zero when the pass is unknown, used or revoked.
    function passExpiry(bytes32 passHash) external view returns (uint256) {
        return _passExpiry[passHash];
    }

    /// @notice Add BNB to the pool. Owner only, so the pool is only ever the owner's money.
    /// @dev    Reverts `ZeroAmount`. Emits `ToppedUp`.
    function topUp() external payable onlyOwner {
        if (msg.value == 0) revert ZeroAmount();
        _totals.toppedUp += msg.value.toUint128();
        emit ToppedUp(msg.sender, msg.value);
    }

    /// @notice Take BNB out of the pool to the owner. Money already lent out is not here to take.
    /// @dev    Reverts `ZeroAmount`, `PoolEmpty` or `PayoutFailed`. Emits `Withdrawn`.
    /// @param amount The BNB to take, in wei.
    function withdraw(uint256 amount) external nonReentrant onlyOwner {
        if (amount == 0) revert ZeroAmount();
        uint256 available = address(this).balance;
        if (amount > available) revert PoolEmpty(amount, available);
        _totals.withdrawn += amount.toUint128();
        emit Withdrawn(msg.sender, amount);
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert PayoutFailed();
    }

    /// @notice Stop new advances. Repayment is never paused.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Allow new advances again.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Schedule new settings. They take effect only after `SETTINGS_DELAY`, through `applySettings`.
    /// @dev    Reverts `SettingsOutOfBounds`. Replaces anything already scheduled. Emits `SettingsScheduled`.
    /// @param next The settings to schedule.
    function scheduleSettings(Settings calldata next) external onlyOwner {
        _checkBounds(next);
        pendingSettings = next;
        pendingSettingsAt = block.timestamp + SETTINGS_DELAY;
        emit SettingsScheduled(next, pendingSettingsAt);
    }

    /// @notice Drop the scheduled settings.
    /// @dev    Reverts `NothingScheduled`. Emits `SettingsCancelled`.
    function cancelSettings() external onlyOwner {
        if (pendingSettingsAt == 0) revert NothingScheduled();
        delete pendingSettings;
        pendingSettingsAt = 0;
        emit SettingsCancelled();
    }

    /// @notice Put the scheduled settings into force once the delay has passed. Anyone may call.
    /// @dev    Open advances keep the amount and due time they were made with. Reverts `NothingScheduled` or
    ///         `TooSoon`. Emits `SettingsApplied`.
    function applySettings() external {
        uint256 effectiveAt = pendingSettingsAt;
        // Zero is the marker for "nothing scheduled", not a time being compared.
        // slither-disable-next-line incorrect-equality
        if (effectiveAt == 0) revert NothingScheduled();
        if (block.timestamp < effectiveAt) revert TooSoon(effectiveAt);
        Settings memory next = pendingSettings;
        // Credit earned under the old pace is settled first, then held to the new ceiling.
        uint256 credit = _paceNow(settings.pacePerDay);
        uint256 ceiling = _paceCeiling(next.pacePerDay);
        _paceCredit = (credit > ceiling ? ceiling : credit).toUint64();
        _paceUpdated = block.timestamp.toUint40();
        settings = next;
        delete pendingSettings;
        pendingSettingsAt = 0;
        emit SettingsApplied(next);
    }

    /// @notice Register single-use passes that let a holder skip the release pace once.
    /// @dev    A pass changes no amount and no record. Reverts `BatchTooLarge` or `BadExpiry`. Emits `PassesAdded`.
    /// @param passHashes keccak256(abi.encode(code)) for each secret code.
    /// @param expires Unix time after which the passes stop working.
    function addPasses(bytes32[] calldata passHashes, uint40 expires) external onlyOwner {
        if (passHashes.length > MAX_BATCH) revert BatchTooLarge();
        if (expires <= block.timestamp) revert BadExpiry();
        for (uint256 i; i < passHashes.length; ++i) {
            _passExpiry[passHashes[i]] = expires;
        }
        emit PassesAdded(passHashes.length, expires);
    }

    /// @notice Cancel an unused pass. Emits `PassRevoked`.
    /// @param passHash keccak256(abi.encode(code)) of the pass.
    function revokePass(bytes32 passHash) external onlyOwner {
        delete _passExpiry[passHash];
        emit PassRevoked(passHash);
    }

    /// @notice Recover a token sent here by mistake. This contract keeps no token balances for anyone.
    /// @dev    Reverts `ZeroAmount`. Emits `TokenRescued`.
    /// @param token The token contract.
    /// @param amount The amount to recover.
    function rescueToken(IERC20 token, uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        emit TokenRescued(address(token), amount);
        token.safeTransfer(msg.sender, amount);
    }

    /// @notice Disabled: with no owner the pool could never be withdrawn.
    function renounceOwnership() public view override onlyOwner {
        revert RenounceDisabled();
    }

    function _borrow(bool withPass) private returns (uint256 amount) {
        Account storage a = _accounts[msg.sender];
        if (a.owed != 0) revert AdvanceOpen(a.owed);
        if (block.timestamp < a.notBefore) revert TooEarly(a.notBefore);

        bytes32 nameHash = _nameHashOf(msg.sender);
        if (nameHash == bytes32(0)) revert NoAgentId();

        Settings memory s = settings;
        uint8 step = a.step;
        amount = _limit(step, s);

        if (a.nameHash == bytes32(0)) {
            a.nameHash = nameHash;
            _borrowers.push(msg.sender);
            ++_totals.people;
        } else if (a.nameHash != nameHash) {
            revert NameMismatch();
        }

        if (step == 0 && !withPass) {
            uint256 credit = _paceNow(s.pacePerDay);
            if (credit < SLOT) {
                revert PaceExhausted(s.pacePerDay == 0 ? 0 : block.timestamp + (SLOT - credit + s.pacePerDay - 1) / s.pacePerDay);
            }
            _paceCredit = (credit - SLOT).toUint64();
            _paceUpdated = block.timestamp.toUint40();
        }

        uint256 available = address(this).balance;
        uint256 needed = amount + _heldForNewcomers(step, s);
        if (available < needed) revert PoolEmpty(needed, available);

        uint40 due = (block.timestamp + s.term).toUint40();
        uint32 day = (block.timestamp / 1 days).toUint32();
        a.owed = amount.toUint96();
        a.due = due;
        a.madeDay = day;
        a.missed = false;

        ++_stepTally[step].advances;
        _stepTally[step].lent += amount.toUint128();
        ++_dayTally[day].advances;
        _totals.lent += amount.toUint128();
        _totals.outstanding += amount.toUint128();
        // The only calls before this point are static reads of the registry, which cannot write or re-enter.
        // forge-lint: disable-next-line(reentrancy-events)
        emit Borrowed(msg.sender, nameHash, step, amount, due, withPass);

        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert PayoutFailed();
    }

    function _mark(address borrower, Account storage a) private {
        a.missed = true;
        ++_stepTally[a.step].missed;
        ++_dayTally[a.madeDay].missed;
        emit Missed(borrower, a.step, a.owed);
    }

    /// @dev Returns keccak256 of the name when the registry says, in three separate answers, that `who` holds a
    ///      name, what it is, and that the name's holder is `who`. Returns zero on any revert, empty answer,
    ///      malformed answer or disagreement. The name is handed back to the registry byte for byte, so the
    ///      check and the lookup share the registry's own reading of it.
    function _nameHashOf(address who) private view returns (bytes32) {
        (bool ok, bytes memory out) = _readRegistry(abi.encodeCall(IAgentIdRegistry.balanceOf, (who)), 32);
        if (!ok || out.length != 32 || abi.decode(out, (uint256)) == 0) return bytes32(0);

        // A string of 1 to 64 bytes comes back as an offset word, a length word and one or two padded words.
        (ok, out) = _readRegistry(abi.encodeCall(IAgentIdRegistry.handleOf, (who)), 128);
        if (!ok || out.length < 96) return bytes32(0);
        (uint256 offset, uint256 length) = abi.decode(out, (uint256, uint256));
        if (offset != 32 || length == 0 || length > MAX_NAME_LENGTH) return bytes32(0);
        if (out.length != 64 + ((length + 31) & ~uint256(31))) return bytes32(0);
        string memory name = abi.decode(out, (string));

        (ok, out) = _readRegistry(abi.encodeCall(IAgentIdRegistry.ownerOfHandle, (name)), 32);
        if (!ok || out.length != 32 || abi.decode(out, (uint256)) != uint256(uint160(who))) return bytes32(0);

        return keccak256(bytes(name));
    }

    /// @dev A read on the registry with a gas ceiling and a ceiling on how much it may send back. An answer
    ///      longer than `maxReturn` bytes counts as a failure, so the registry cannot make the caller pay to
    ///      copy a large reply.
    function _readRegistry(bytes memory data, uint256 maxReturn) private view returns (bool ok, bytes memory out) {
        address registry = address(REGISTRY);
        out = new bytes(maxReturn);
        uint256 size;
        // The one use of assembly here: a plain staticcall would copy back whatever the registry returns.
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            ok := staticcall(REGISTRY_GAS, registry, add(data, 32), mload(data), add(out, 32), maxReturn)
            size := returndatasize()
            if lt(size, maxReturn) { mstore(out, size) }
        }
        if (size > maxReturn) ok = false;
    }

    function _limit(uint8 step, Settings memory s) private pure returns (uint256) {
        if (step > MAX_STEP) return s.cap;
        uint256 doubled = uint256(s.firstAdvance) << step;
        return doubled > s.cap ? s.cap : doubled;
    }

    /// @dev Advances above the first step leave one day of first advances in the pool. Without this, borrowers
    ///      who repay and double their limit absorb the whole pool and newcomers find it empty: the 16-day
    ///      simulation served fewer people with good repayers than with none.
    function _heldForNewcomers(uint8 step, Settings memory s) private pure returns (uint256) {
        return step == 0 ? 0 : uint256(s.pacePerDay) * s.firstAdvance;
    }

    function _paceCeiling(uint32 pace) private pure returns (uint256) {
        if (pace == 0) return 0;
        uint256 burst = uint256(pace) * PACE_BURST;
        return burst > SLOT ? burst : SLOT;
    }

    function _paceNow(uint32 pace) private view returns (uint256 credit) {
        credit = uint256(_paceCredit) + (block.timestamp - _paceUpdated) * pace;
        uint256 ceiling = _paceCeiling(pace);
        if (credit > ceiling) credit = ceiling;
    }

    function _checkBounds(Settings memory s) private pure {
        if (
            s.firstAdvance < MIN_FIRST_ADVANCE || s.firstAdvance > MAX_FIRST_ADVANCE || s.cap < s.firstAdvance
                || s.cap > MAX_CAP || s.term < MIN_TERM || s.term > MAX_TERM || s.pacePerDay > MAX_PACE_PER_DAY
        ) revert SettingsOutOfBounds();
    }
}
