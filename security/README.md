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
| `AttackRunner.sol` | The attacker. It owns eight puppet wallets that can hold a name, borrow, repay and misbehave when sent BNB |
| `Phase1.s.sol` | 34 attacks that can run at once: no name, a second advance, re-entry, spoiling someone's advance, unwanted BNB, every owner function, pass reuse, beating the pace, climbing the ladder in a minute, rushing settings, and six kinds of lying or broken registry |
| `Phase2.s.sol` | 3 attacks that need a day to pass: marking twice, borrowing while a missed advance is unpaid, borrowing during the cooling-off |
| `Report.s.sol` | Reads the record from the chain and prints it. Fails if any attack went through |

Each attack names the rule it tests, by its number in `docs/security/threat-model.md`.

## Run it

From `packages/contracts`, with `.env` loaded into the shell:

```bash
forge script script/Deploy.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
forge script security/Phase1.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
forge script security/Report.s.sol --rpc-url $BSC_TESTNET_RPC_URL
```

At least 25 hours later:

```bash
forge script security/Phase2.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
forge script security/Report.s.sol --rpc-url $BSC_TESTNET_RPC_URL
```

For the testnet deploy, set `OWNER` to the security wallet's address, `TERM_SECONDS=3600` and `PACE_PER_DAY=24`, so that the pace can be exhausted with two wallets and the late-payment attacks need one day instead of four.

Do not run these with `-vvvv`. At that level Foundry prints the values its scripts read from the environment, and the key is one of them.

## Do the tests notice a broken contract?

`security/mutation.mjs` answers that. It takes a private copy of the source, breaks one rule at a time (45 breaks: a boundary moved by a second, an owner check removed, the pace never used up, and so on), and runs the test suite against each broken copy. A break the tests do not notice is a hole in the tests.

```bash
node security/mutation.mjs
```

It needs no key and no network, takes about fifteen minutes, and writes `security/outputs/mutation.txt`. It leaves out the fork tests and the 16-day simulation, so it says nothing about those.

## What these do not cover

- A transaction signed by a real Binance Agentic Wallet, and Binance's own preview and risk check. Those exist on mainnet only.
- The real Agent ID registry. On testnet the registry is a stand-in deployed from the registry's verified source; the fork tests in `packages/contracts/test/NameCredit.fork.t.sol` cover the real one.
- The website and the agent skill.
- This is a self-audit by the team that wrote the contract. It is not an outside audit.

The compiler warns that `selfdestruct` is deprecated. It is used once, on purpose, in the attack that forces BNB into the pool without calling it.

## Results

Saved runs go in `security/outputs/`, one file per run, with the chain, the block and the transaction hashes.
