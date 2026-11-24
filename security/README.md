# Security tests

Two things live here: attacks on the live testnet deployment, and a check that the test suite itself can be trusted.

The attack scripts go after this project's own `NameCredit` deployment on BNB testnet and leave the record on chain. Each attack is a real transaction: a runner contract tries it, records whether the pool refused it and with which error, and never reverts itself.

## Scope

- BNB testnet (chain 97) only. Every script checks the chain id before it sends anything and stops on any other chain.
- Only the contracts this project deployed, at the addresses in `packages/contracts/deployments/97.json`.
- Signed only with `SECURITY_TESTNET_KEY`, a fresh wallet that holds test BNB and nothing else. See `.env.example`.
- Nothing here touches mainnet, the Agent ID registry, Binance's services or anyone else's contracts.

## What is in the folder next door

The Solidity lives in `packages/contracts/security/` so that it compiles with the contract it attacks.

| File | What it does |
|---|---|
| `AttackRunner.sol` | The attacker. It owns ten puppet wallets that can hold a name, borrow, repay and call back into the pool when sent BNB. For each attempt it records what happened next to the error the rule says must come back |
| `Phase1.s.sol` | 43 attacks and 2 controls that can run at once: no name, a second advance, re-entry from the payout and from a refund, spoiling someone's advance, unwanted BNB, every owner function, pass reuse, a repeat borrower spending a newcomer's pass, beating the pace, climbing the ladder in a minute, rushing settings, and ten kinds of lying, stalled or flooding registry |
| `Phase2.s.sol` | 8 attacks and 1 control that need a day to pass: marking twice, borrowing while a missed advance is unpaid, borrowing during the cooling-off with and without a pass, a repeat borrower reaching into the newcomers' reserve, a burst when a faster pace comes into force, and a returning borrower the registry no longer vouches for |
| `Report.s.sol` | Reads the record from the chain and prints it. Needs no key. Fails unless every attack was refused with exactly the expected error and every control went through |

Each attack names the rule it tests, by its number in `docs/security/threat-model.md`, and the error that rule says it must be refused with. A refusal for any other reason counts as a failure. The controls are calls that must succeed, placed next to the refusals so that a refusal cannot be an accident: a named wallet is served by the plain call in the same block where the next one is turned away, and the wallet that ten broken registries refused is served once the registry answers honestly.

## Run it

From `packages/contracts`, with `.env` loaded into the shell:

```bash
forge script script/Deploy.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
forge script security/Phase1.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
forge script security/Report.s.sol --rpc-url $BSC_TESTNET_RPC_URL
```

At least 25 hours later, and no more than 7 days after phase one (it applies settings that phase one scheduled, and those lapse):

```bash
forge script security/Phase2.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
forge script security/Report.s.sol --rpc-url $BSC_TESTNET_RPC_URL
```

For the testnet deploy, set `OWNER` to the security wallet's address, `TERM_SECONDS=3600` and `PACE_PER_DAY=24`, so that the pace holds exactly one first advance and the late-payment attacks need one day instead of four. Set them on the command line for that one command, not in the shell. On mainnet the deploy script refuses to run while any of the four settings is set in the environment, and refuses the security wallet as owner.

Do not run these with `-vvvv`. At that level Foundry prints the values its scripts read from the environment, and the key is one of them.

## Do the tests notice a broken contract?

`security/mutation.mjs` answers that. It takes a private copy of the source, breaks one rule at a time (52 breaks: a boundary moved by a second, an owner check removed, the pace never used up, the BNB sent before the debt is recorded, an extra owner function added, and so on), and runs the test suite against each broken copy. A break the tests do not notice is a hole in the tests.

```bash
node security/mutation.mjs
```

It needs no key and no network, takes about twenty minutes, and writes `security/outputs/mutation.txt`. It leaves out the fork tests and the 16-day simulation, so it says nothing about those.

## What these do not cover

- A transaction signed by a real Binance Agentic Wallet, and Binance's own preview and risk check. Those exist on mainnet only.
- The real Agent ID registry. On testnet the registry is a stand-in deployed from the registry's verified source; the fork tests in `packages/contracts/test/NameCredit.fork.t.sol` cover the real one.
- Anything that needs an exact second or a week of waiting on a live chain. The grace boundary and the lapse of scheduled settings are tested in the unit tests, where the clock can be set.
- The website and the agent skill.
- This is a self-audit by the team that wrote the contract. It is not an outside audit.

The compiler warns that `selfdestruct` is deprecated. It is used once, on purpose, in the attack that forces BNB into the pool without calling it.

## Results

Saved runs go in `security/outputs/`, one file per run, with the chain, the block and the transaction hashes.
