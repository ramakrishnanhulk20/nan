# Threat model

First written before any contract code on 23 November 2026, and updated the same day as the contract landed. It is the definition of done for the contract: the build is complete only when every rule in section C is shown to hold by a test that would fail without it. Section D lists that test for each rule.

Revised on 24 November 2026 after a second read by reviewers who had not written the code. Two rules (C4 and C8) said more than the code does and were reworded. Two checks were added to the contract (a pass is refused above the first step; scheduled settings lapse). Several tests and attacks were rebuilt so that each one would fail against a broken contract, and section D says where a rule still rests on reading the source.

This review was written by the same team that designs the product. It is not an outside audit.

## The system, in plain terms

One contract on BNB Smart Chain, `NameCredit`, lends small amounts of BNB from a pool that its owner funds. It never holds anyone else's money.

- **Borrow.** A wallet calls `borrow()` with no arguments. The contract asks the Agent ID registry three things about the caller: does it hold a name, what is the name, and does that name map back to the caller. If all three agree, the caller has no open advance, enough time has passed since its last one, the release pace allows it and the pool has the money, the contract records the advance (amount and due time) and sends the BNB to the caller.
- **Borrow with a pass.** `borrowWithPass(code)` is the same call with one difference: a valid single-use code skips the release pace. Nothing else is waived. It works only at the first step, the one place the pace applies.
- **Repay.** Anyone calls `repay(borrower)` and attaches the amount owed. The contract marks the advance repaid. Repaid by the due time plus one day of grace, the borrower's limit moves up one step, up to a fixed cap, and the next advance can start once the original term has ended. Repaid later, the borrower starts again at the first step after a seven day wait. Extra BNB sent by mistake is returned in the same transaction.
- **Mark missed.** After the due time plus grace, anyone can call `markMissed(borrower)`. It only updates counters and the borrower's standing.
- **Read.** View functions return a wallet's standing, the pool's state, and running counters for every step of the ladder and every day. The website shows only what these return.
- **Owner.** The owner can add BNB, pause new advances, withdraw BNB that is in the contract, change four numbers (first advance, term, cap, release pace) inside limits fixed in the code after a 12 hour public delay (a scheduled change can be cancelled, and one that nobody applies within 7 days of the delay lapses), issue and cancel passes, and recover a token sent here by mistake. Ownership moves in two steps and cannot be given up.

Two rules shape who gets served. First advances are released at a steady pace, with at most one hour of unused pace stored (or one advance, where an hour of pace is less than one), so a crowd cannot empty the pool in one block. Passes, which only the owner can issue, are the one way round the pace. Advances above the first step always leave one day of first advances in the pool, so borrowers who repay and double their limit cannot crowd newcomers out.

Around the contract: a static website that reads the chain through public nodes and writes the instruction text a holder pastes into their AI agent, and an agent skill file that says the same thing in a form agents follow. There is no server, no database and no stored secret. The deploy key is used once, from a local machine, and keeps no power afterwards.

Outside parties the contract depends on: the Agent ID registry (run by SPACE ID for Binance, with an owner key and a signing key that can each issue names; its code has no way to move or remove a name and is not behind a proxy), BNB Smart Chain itself, and the holder's wallet software, which previews each call and asks the holder to confirm.

## A. What kind of system this is, and what usually goes wrong with that kind

It is an unsecured lender whose only check on a borrower is an identity held in someone else's contract, and it pays out native currency to the caller.

| Usual failure for this kind of system | Where it could bite here | Applies |
|---|---|---|
| One borrower takes many loans by appearing as many people | `borrow()` trusts the registry's answer about the caller | Yes. This is the main risk and the reason the product needs Agent ID |
| A borrower builds trust cheaply, then defaults on the largest loan | The limit doubles after each on-time repayment, and an advance can be repaid with its own money a minute later | Yes |
| The pool is emptied faster than repayments return | Thousands of holders can call `borrow()` in the same hour | Yes |
| Returning borrowers absorb the pool and newcomers find it empty | Limits double while the pool does not | Yes. Found by simulation, not by reasoning |
| Re-entry while paying out | `borrow()` sends BNB to the caller, who may be a contract or an account with delegated code; `repay()` returns extra BNB | Yes |
| The identity source lies, fails, stalls or floods the caller with data | Three reads of the registry on every borrow | Yes |
| A privileged key changes the rules or takes money | Owner functions | Yes, limited to the owner's own pool |
| Borrowers locked into debt they cannot settle | A borrower loses access to their agent before the due time; the contract is paused; the registry is down | Yes |
| Accounting drift | Advances, repayments, refunds of extra BNB, owner top-ups and withdrawals all move the same balance | Yes |
| Stale or manipulated prices | Amounts are fixed BNB figures; no price is read | No. Nothing in the contract depends on a price |
| Token approval abuse | No token is used and no approval is ever requested | No |
| Injection through stored text | The contract stores no text written by users. Names come from the registry, which allows only `a-z` and `0-9`, and only their hash is kept | No, as long as the site prints names as text and never as markup |
| Front-running for profit | A pass code is visible in a pending transaction | Yes, narrowly: see the non-goals |

## B. Threat model

**Trust boundaries**
1. Any wallet to the contract: every public function.
2. The registry to the contract: three return values per borrow.
3. The contract to the caller: the BNB payout and the refund of extra BNB.
4. The chain to the website: values the page shows and the instruction text it builds.
5. The website to the holder's agent: the instruction text, which a copycat site could alter.

**Values an attacker can influence**
- The caller's address, and whether it is a plain wallet, a contract or an account with delegated code.
- The BNB attached to `repay`, and the `borrower` argument.
- The pass code passed to `borrowWithPass`.
- The time a transaction lands, within a few seconds.
- The registry's answers and their size, if the attacker is the registry's owner or the registry is replaced upstream.
- The caller's own name, within the registry's character rules.
- What a holder's agent reads on a web page that is not ours.

**What this contract holds that an outsider cannot reach directly**
- The pool: BNB that belongs to the owner.
- Each wallet's standing: its step on the ladder, its open advance and its history. Other contracts may come to rely on it.
- The right to change four parameters, to pause, and to issue passes.

**What an attacker would try, highest value first**
1. Borrow many times as many people. Enabled by the holder check in `borrow()`.
2. Climb the ladder in minutes by repaying each advance with its own money, then default at the top. Enabled by the limit rule in `repay()`.
3. Take a second advance before the first is recorded, by re-entering during the payout in `borrow()` or the refund in `repay()`.
4. Empty the pool in the first hour with a fleet of real holders, so the product looks dead. Enabled by the absence of a pace limit.
5. Take the owner key, drain the pool and set hostile parameters.
6. Damage other people's standing: mark an advance missed early, or block someone's repayment.

## C. Rules the code must uphold (the definition of done)

Each rule is an outcome.

**Identity**
- C1. A wallet receives an advance only if, in that same transaction, the registry reports that it holds a name, returns a well-formed name of 1 to 64 bytes for it, and reports that name's owner as that same wallet. Any revert, empty answer, malformed answer or mismatch means no advance. This holds for a wallet that was served before as much as for a new one: the name on file is never enough.
- C2. Registry reads are static calls with a gas ceiling and a size ceiling. A registry that reverts, stalls or returns too much cannot change this contract's state (a failed read reverts the whole call, so nothing written before it survives), cannot cost the caller more than a bounded amount, and cannot lock anyone's repayment.

What these two rest on: a record here is kept per wallet, so "cannot come back as someone new" holds only while a name never moves to another wallet. The registry's code makes that so. Every transfer and approval reverts, there is no burn, a wallet can be given one name and never a second, and the code is not behind a proxy, so it cannot be swapped. A fork test checks all of this on the live registry.

**One line of credit per person**
- C3. A wallet has at most one open advance at any time.
- C4. An advance is never more than the wallet's limit: the first advance doubled once per step, held to the cap, under the settings in force when the advance is made. A wallet's step rises only by one, only through an on-time repayment of the full amount. The owner can move every wallet's limit at once by changing the first advance or the cap, inside the fixed bounds and after the public delay. The owner cannot edit anyone's step. What the cap does decide is whether an on-time repayment adds one: a wallet whose limit already equals the cap stays on its step, so a lower cap stops every climb sooner and a higher one lets it go on.
- C5. A wallet that repaid late or was marked missed cannot borrow until it has settled in full and seven days have passed, and then only at the first step.
- C6. One advance per term. After an on-time repayment the next advance cannot start before the due time of the one just repaid, so paying back in a minute does not let a borrower run up the ladder in an hour.

**The pool**
- C7. The contract's balance is never less than owner top-ups plus repayments, minus advances, minus owner withdrawals, and is exactly that unless BNB is forced in from outside. Extra BNB sent with a repayment leaves in the same transaction.
- C8. Without a pass, first advances never exceed the release pace. The store of unused pace holds at most one hour of it, or one advance where an hour of pace is less than one (below 24 a day), and a change of pace does not refill it. Passes are the one way round the pace, and the owner can issue as many as it likes.
- C9. An advance above the first step never takes the pool below one day of first advances.
- C10. The contract accepts BNB only through the owner's top-up and through `repay`. A plain transfer is refused, so nobody's money lands here by mistake.

**Repayment can never be blocked**
- C11. `repay` works for any open advance, from any wallet, at any time, whether or not new advances are paused, whether or not the registry answers, and whoever the owner is.
- C12. The terms of an open advance (amount and due time) are fixed when it is made. No parameter change, pause or owner action alters them.

**Standing cannot be attacked**
- C13. `markMissed` succeeds only when the advance is open and the due time plus grace has passed, and at most once per advance.
- C14. A wallet's earned record changes only through its own borrow, a repayment of its advance, or a valid `markMissed`. The earned record is its step, its counts of on-time and late repayments, its name hash, its open advance and the time it may next borrow. The owner has no function that edits any of it. The limit shown for a wallet is not part of the record: it is the step read through the settings in force (C4).

**Payout safety**
- C15. Every function that sends BNB changes state first and sends last, under a reentrancy guard. A recipient that reverts, re-enters or burns gas can make only its own call fail.

**The owner**
- C16. The owner's powers are exactly: add BNB; pause and unpause new advances; withdraw BNB from the contract; schedule a change to first advance, term, cap or release pace inside limits fixed in the code, which anyone can bring into force from the end of the 12 hour delay until 7 days later and not after; cancel a scheduled change; issue and cancel passes; recover a token sent here by mistake; hand over ownership in two steps. Nothing else. A test pins the complete list of functions the contract answers to.
- C17. The contract cannot be upgraded, and has no function that moves BNB to any address other than a borrower (their advance), a repayer (their extra) or the owner (a withdrawal).

**Passes**
- C18. A pass lets one holder at the first step skip the release pace once. It is refused above the first step, where there is no pace to skip. It waives no other rule, is not used up by a call that is refused, cannot be used twice, and stops working after its expiry time or when the owner cancels it.

**What leaves the contract is treated like input**
- C19. Events and views expose numbers, addresses and hashes only. The contract stores and emits no text supplied by a caller.
- C20. Every figure the website shows comes from a view call on this contract or the registry. The instruction text contains only the fixed contract address, a fixed function and an amount read from the contract.

**The deployment is the one that was published**
- C21. At deployment, the mainnet contract's registry, owner and four settings are the ones stated in the README, and anyone can check that with three reads. Every later change of settings is a public event, and the README records each one that has been applied. On mainnet the deploy script takes the settings from its own source and not from the environment, refuses this project's testnet wallet as owner whether or not the environment names it, and needs the owner address typed twice.

### The five general standards, applied

1. **One rule over a list.** There is no allow list or deny list of wallets. Eligibility is the registry's own three answers, checked the same way for everyone. What that covers: one name per wallet. What it does not: whether two names belong to one human behind two Binance accounts. Passes are the one list in the contract; a pass changes no eligibility, only the queue.
2. **Same parser on both sides.** The name is never parsed or normalised here. It is handed back to the registry byte for byte to ask who owns it, so the check and the use are the registry's own code.
3. **Outputs as inputs.** Standing is the one output others may build on. It is written only by the three paths in C14. A contract that builds on it should read the step and the repayment counts, never the limit, which moves when the owner changes the settings.
4. **Fail closed.** Any registry error, any unexpected state, an empty pool, a pause or an exhausted pace means no advance. The one deliberate exception is repayment, which fails open: it must always be possible to settle.
5. **Named non-goals.** Below.

## D. Where each rule is proven

Test files are in `packages/contracts/test`. Every test passes at the time of writing: 95 as the test tool counts them (it runs the five invariants as one campaign), including 12 fuzz tests at 1,000 runs each and 5 invariants over 20,000 random calls.

| Rule | Test |
|---|---|
| C1 | `NameCredit.registry.t.sol`: `test_balance_revertZeroOrWrongSizeIsRefused`, `test_handle_revertEmptyOrMalformedIsRefused`, `test_handle_aNameLongerThan64BytesIsRefused`, `test_ownerOf_revertMismatchOrDirtyIsRefused`, `test_aNameThatChangesIsRefused`, `test_aReturningBorrowerIsRefusedOnceTheRegistryStopsAnswering`, `testFuzz_onlyACanonicalNameAnswerIsAccepted`, `testFuzz_nameAnswersBuiltFromParts`. `invariant_noNameNoAdvance`. On the real registry: `test_fork_walletWithNoNameIsRefused`, and `test_fork_aNameCanNeverMoveOrBeDestroyed` for what the rule rests on |
| C2 | `test_aStalledReadCostsTheCallerABoundedAmount` (each of the three reads in turn, against a gas bound a little above the measured cost), `test_aFloodOfReturnDataIsRefusedOnEveryRead` (a 100,000 byte reply that opens with a well-formed answer, so only the size ceiling can refuse it), `test_aDeadRegistryCannotBlockRepaymentOrMarking` |
| C3 | `test_borrow_refusesASecondAdvanceWhileOneIsOpen`, `invariant_outstandingIsTheSumOfOpenAdvances` |
| C4 | `test_ladder_climbsToTheCapAndStopsThere`, `testFuzz_everyAdvanceSitsBetweenTheFirstAdvanceAndTheCap`, `test_settings_anOpenAdvanceKeepsItsTerms` (which also shows the limit moving with the settings while the step stays put) |
| C5 | `test_repay_oneSecondAfterGraceIsLate`, `test_markMissed_onlyAfterGraceAndOnlyOnce`, `test_pass_doesNotSkipTheCoolingOff` |
| C6 | `test_repay_onTimeMovesUpOneStepAndWaitsOutTheTerm`, `testFuzz_repaymentTimeDecidesTheOutcome` |
| C7 | `invariant_theBooksBalance`, `test_forcedBnbChangesNoRecordAndTheOwnerCanTakeIt`, `test_repay_extraIsReturnedToThePayer` |
| C8 | The ceiling of the store: `test_pace_unusedSlotsStopBuildingAfterOneHour`, `testFuzz_aQuietSpellStoresAtMostTheCeiling`, `test_settings_storedPaceIsHeldToTheNewCeiling`, and `test_settings_aFasterPaceDoesNotRefillTheStore` for the change of pace. The running total: `test_pace_fifthFirstAdvanceInOneBlockMustWait`, `testFuzz_firstAdvancesNeverBeatThePace`. Passes as the exception: `test_paceOfZero_onlyAPassCanStartAFirstAdvance`. On the real registry: `test_fork_holdersGetOneAdvanceEachAndThePaceHolds`, which is skipped, not passed, when the fork has fewer than five recent holders |
| C9 | `test_reserve_aRepeatBorrowerLeavesOneDayOfFirstAdvances`, `test_reserve_isZeroWhenThePaceIsZero` |
| C10 | `test_plainTransferIsRefused`, `test_topUp_ownerOnlyAndCounted` |
| C11 | `test_repay_worksWhilePaused`, `test_repay_aWalletWithNoNameCanPay`, `test_theRealRegistryReplacedByBrokenCodeCannotBlockRepayment`, `test_aDeadRegistryCannotBlockRepaymentOrMarking`, `invariant_repaymentNeverFailsAndOpenTermsNeverMove` |
| C12 | `test_settings_anOpenAdvanceKeepsItsTerms`, `invariant_repaymentNeverFailsAndOpenTermsNeverMove` |
| C13 | `test_markMissed_onlyAfterGraceAndOnlyOnce`, `testFuzz_markingMissedNeedsTheGraceToHavePassed`, `test_markMissedMany_marksOnlyTheOverdueOnes` |
| C14 | `test_owner_hasNoWayToEditARecord`, `testFuzz_aStrangerCanOnlySettleNeverSpoil`, and `test_theContractAnswersToExactlyTheseFunctions`, which fails if any function is added |
| C15 | `test_borrow_reenteringDuringThePayoutGetsNothingExtra` and `test_repay_reenteringOnTheRefundFails`: the wallet calls back from inside the payment, and the tests read the exact reason the call back was refused and check that the books were already updated when the BNB arrived. `test_borrow_failsCleanlyWhenTheBorrowerRefusesBnb`, `test_repay_aPayerThatRefusesItsChangeFailsOnlyItsOwnCall`, `test_withdraw_anOwnerThatRefusesBnbFailsCleanly`, `test_borrow_aBorrowerThatBurnsGasOnlyFailsItsOwnCall` |
| C16 | `NameCredit.owner.t.sol`, all 24 tests. "Nothing else" is `test_theContractAnswersToExactlyTheseFunctions`. The lapse is `test_settings_lapseAWeekAfterTheDelay` |
| C17 | `test_withdraw_cannotReachMoneyThatIsLentOut`, `test_ownership_movesInTwoStepsAndCannotBeRenounced`, `test_theContractAnswersToExactlyTheseFunctions`. That the contract has no proxy and no delegatecall is by reading the source |
| C18 | `test_pass_skipsThePaceOnceAndOnlyOnce`, `test_pass_unknownExpiredOrRevokedIsRefused`, `test_pass_doesNotWaiveAnyOtherRule`, `test_pass_doesNotSkipTheCoolingOff`, `test_pass_isRefusedAboveTheFirstStepAndStaysUnused` |
| C19 | By reading the source: no `string` or `bytes` in storage or in any event. `invariant_everyAdvanceIsCountedOnce` checks that the counters agree with each other |
| C20 | Not provable yet: the website does not exist. It becomes a check on the site when it is built |
| C21 | `script/Check.s.sol`, with no key needed. Run against mainnet straight after the deployment of 24 November 2026: the real registry, the recorded owner, the four settings as planned. Output saved in `security/outputs/mainnet-2026-11-24.txt`, with the comparison that shows the mainnet code is the testnet code apart from the registry address. The deploy script's refusals were shown by dry runs on a fork of mainnet |

What these tests do not cover: a transaction signed by a real Agentic Wallet, Binance's own preview and risk check, and how real people behave. Those need real use of the mainnet deployment, which at the time of writing holds no BNB and has had no borrower.

### Would the tests notice if a rule were broken?

Passing tests prove little if they would also pass against a broken contract. `security/mutation.mjs` breaks the contract on purpose, one rule at a time, 52 ways, and runs the tests against each broken copy. The saved run is `security/outputs/mutation.txt`: all 52 were noticed. It covers the unit, fuzz and invariant tests, not the fork tests or the simulation. One thing it cannot show: the 64 byte limit on a name is a second guard behind the 128 byte limit on the registry's reply, so removing it alone changes nothing a test can see.

### The same rules, attacked on a live network

The tests above run inside the test tool. The scripts in `packages/contracts/security` make the same attempts as real transactions against the BNB testnet deployment, and the record stays on chain for anyone to read. A runner contract makes each attempt and writes down what happened next to the error the rule says it must be refused with. An attempt that fails for any other reason counts against the run. Three entries are controls, calls that must succeed, so that the refusals around them mean something. How to run them is in `security/README.md`.

| Rule | Attack, as a real transaction | Must be refused with |
|---|---|---|
| C1 | A wallet with no name asks for an advance, with and without a valid pass | `NoAgentId` |
| C1 | Four registries that lie: one that reverts, one that returns an empty name, one that says the name belongs to someone else, one that returns a name longer than 64 bytes | `NoAgentId` |
| C1 | After a day: a returning borrower once the registry stops answering, and a returning borrower whose name has changed | `NoAgentId`, `NameMismatch` |
| C2 | Each of the three reads in turn never answers, or answers correctly and then floods. The attempt must also cost less gas than three capped reads | `NoAgentId` |
| C3 | A second advance while one is open | `AdvanceOpen` |
| C4, C14 | A stranger pays one wei less than is owed on someone's advance | `Underpaid` |
| C5 | After the grace: borrowing while a missed advance is unpaid, borrowing during the cooling-off, and using a valid pass to skip the cooling-off | `AdvanceOpen`, `TooEarly`, `TooEarly` |
| C6 | Borrowing again before the term of a repaid advance has ended | `TooEarly` |
| C7 | The balance equals the books to the wei after real use, and sits exactly one wei above them after one wei is forced in | a check, not a refusal |
| C8 | One more first advance than the pace allows, in the same block. After a day: a second first advance in the block where a faster pace comes into force | `PaceExhausted` |
| C9 | After a day: a repeat borrower asks when the pool is one wei short of the advance plus the newcomers' reserve | `PoolEmpty` |
| C10 | BNB sent with a plain transfer, and BNB sent to a function that does not exist | `DirectTransfer`, and a bare revert |
| C13 | Marking an advance missed before its grace ends (from outside, and from inside its own payout), marking it twice, and marking 201 wallets in one call | `NotOverdue`, `AlreadyMarked`, `BatchTooLarge` |
| C15 | Calling back into `borrow` and `repay` from inside the payout, and into `borrow` from inside the refund of an overpayment. The advance or repayment itself goes through; the call back is what must fail, and the books must already be right when the BNB arrives: the debt recorded for a payout, cleared for a refund | `ReentrancyGuardReentrantCall` |
| C16 | A stranger calls each of the twelve owner functions. Anyone tries to apply settings when none are scheduled, and before the delay has passed | `OwnableUnauthorizedAccount`, `NothingScheduled`, `TooSoon` |
| C18 | The same pass used twice, a code that was never issued, and a repeat borrower trying to spend a newcomer's pass | `BadPass`, `BadPass`, `PassNotNeeded` |

Controls that must succeed: a named wallet borrows with the plain call; the attacking wallet is served by the second pool once its registry answers honestly; a named wallet borrows right after the faster pace comes into force.

Run on BNB testnet on 24 November 2026: 43 attacks, each refused with exactly the expected error, and 2 controls served, in 60 transactions that all succeeded. The record, with every transaction hash, is `security/outputs/testnet-2026-11-24.txt`, and the runner's source is verified so anyone can read its results from the chain. On 25 November the eight attacks that need a day were run too: each was refused with exactly the expected error, and the control was served, in 12 more transactions that all succeeded. On a local copy of the chain, with the clock moved forward, all 51 attacks were refused as expected and all 3 controls were served.

What the live run cannot do that the tests can: land a transaction on an exact second (the grace boundary is tested to the second in the unit tests), and wait seven days for scheduled settings to lapse.

## What this does not defend against

- **Many accounts, one human.** A person or a farm that controls many verified Binance accounts holds many names and can take one first advance with each. The first step is sized as an acceptable loss per name, and the release pace limits the loss per day.
- **Whoever calls first gets the slot.** The release pace is first come, first served. A script that watches for the next slot (one every 864 seconds at 100 a day) can take each one as it opens. The reserve protects newcomers from repeat borrowers, not from a queue of other newcomers. Passes exist so that a person who was given one is not stuck behind that queue.
- **People who simply do not repay.** That is the experiment. The pool is the owner's money and the most it can lose is all of it. The repayment rate is published as it is.
- **Patient ladder climbing.** A borrower can repay each advance with its own money, wait out each term, and default once at the cap. The loss per person is the cap, and it takes four full terms to get there: 12 days at the planned term of 3 days. The owner could shorten the term to as little as 1 hour, after the public delay, which would shorten that wait to 4 hours. The release pace applies to first advances only, so a group that climbs together can default together; what limits them is the pool, the day of first advances held back for newcomers, and the fact that each of them had to enter through a paced first advance.
- **The registry's keys.** Two keys can issue names in the registry: its owner and its signer. Whoever controls either can give a name to any address that has none. This contract trusts them in the same way every Agent ID application does. They cannot move or remove a name that has been given.
- **A stolen owner key.** The thief can take the pool, issue passes that skip the pace, and set the four parameters to their worst allowed values, which moves every wallet's limit inside the fixed bounds. They cannot take anything from borrowers, edit anyone's step or history, or stop anyone repaying.
- **A pass code seen in the open.** A code is visible in a pending transaction, and another Agent ID holder at the first step could use it first. The cost is one first advance going to a different holder. A holder above the first step cannot use it at all.
- **Copycat websites.** A page that imitates ours can show an instruction with a different address. The defence is on the holder's side: the wallet's preview shows the real destination, and our skill tells agents to refuse any address but the published one.
- **BNB's price.** Amounts are in BNB. A borrower repays the BNB figure they received, whatever it is worth in dollars on the day.
