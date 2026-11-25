#!/usr/bin/env node
// Reads one wallet's standing on Nan from BNB Smart Chain mainnet and prints it as one JSON object.
// Usage: node read.mjs <wallet address>
// Exit 0 with the standing, 2 when the address is not valid, 3 when no node answers.
// Needs Node 18 or later. No packages.

const POOL = "0xc0337932e0Cd049aFa990A9A470c059586B2d9AE";
const NODES = [
  "https://bsc-dataseed.binance.org",
  "https://bsc-rpc.publicnode.com",
  "https://bsc-dataseed1.bnbchain.org",
];
const TIMEOUT_MS = 8000;

// The contract's Refusal enum, in its declared order.
const REFUSALS = ["none", "paused", "open", "early", "noAgentId", "pace", "poolEmpty"];

const QUOTE_BORROW = "0x2f82f894";
const STANDING_OF = "0x2254f925";
const HOLDS_AGENT_ID = "0x11213086";
const POOL_VIEW = "0x16f0115b";

function print(value, code) {
  process.stdout.write(JSON.stringify(value) + "\n");
  process.exitCode = code;
}

async function rpc(node, method, params, signal) {
  const response = await fetch(node, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    signal,
  });
  if (!response.ok) throw new Error(`${method}: HTTP ${response.status}`);
  const body = await response.json();
  if (body === null || typeof body !== "object" || body.error) throw new Error(`${method}: node error`);
  return body.result;
}

// Splits an ABI answer into exactly `count` 32-byte words. Any other shape means the node or the contract is
// not what we expect, so the caller moves to the next node instead of printing a guess.
function words(hex, count) {
  if (typeof hex !== "string" || !/^0x[0-9a-fA-F]*$/.test(hex) || hex.length !== 2 + 64 * count) {
    throw new Error("unexpected answer shape");
  }
  const out = [];
  for (let i = 0; i < count; i++) out.push(BigInt("0x" + hex.slice(2 + 64 * i, 66 + 64 * i)));
  return out;
}

function small(word, max) {
  if (word > BigInt(max)) throw new Error("value out of range");
  return Number(word);
}

function flag(word) {
  if (word > 1n) throw new Error("not a bool");
  return word === 1n;
}

function quantity(hex) {
  if (typeof hex !== "string" || !/^0x[0-9a-fA-F]{1,16}$/.test(hex)) throw new Error("bad quantity");
  return small(BigInt(hex), Number.MAX_SAFE_INTEGER);
}

async function readFrom(node, wallet) {
  const signal = AbortSignal.timeout(TIMEOUT_MS);
  const blockNumber = quantity(await rpc(node, "eth_blockNumber", [], signal));
  const tag = "0x" + blockNumber.toString(16);
  const arg = wallet.slice(2).padStart(64, "0");
  // Every read is pinned to the same block so the answer is one moment of the chain, not a mix of two.
  const call = (data) => rpc(node, "eth_call", [{ to: POOL, data }, tag], signal);

  const [quoteHex, standingHex, holdsHex, poolHex, block] = await Promise.all([
    call(QUOTE_BORROW + arg),
    call(STANDING_OF + arg),
    call(HOLDS_AGENT_ID + arg),
    call(POOL_VIEW),
    rpc(node, "eth_getBlockByNumber", [tag, false], signal),
  ]);

  if (block === null || typeof block !== "object" || quantity(block.number) !== blockNumber) {
    throw new Error("block does not match");
  }

  const [refusal, amount, dueIfBorrowedNow] = words(quoteHex, 3);
  const [, step, limit, owed, due, overdueAt, missed, notBefore, onTime, late] = words(standingHex, 10);
  const [holds] = words(holdsHex, 1);
  const [balance, , , nextSlotAt] = words(poolHex, 5);
  const time = Number.MAX_SAFE_INTEGER;

  return {
    wallet,
    holdsAgentId: flag(holds),
    refusal: REFUSALS[small(refusal, REFUSALS.length - 1)],
    amountWei: amount.toString(),
    dueIfBorrowedNow: small(dueIfBorrowedNow, time),
    step: small(step, 255),
    limitWei: limit.toString(),
    owedWei: owed.toString(),
    due: small(due, time),
    overdueAt: small(overdueAt, time),
    missed: flag(missed),
    notBefore: small(notBefore, time),
    onTime: small(onTime, 65535),
    late: small(late, 65535),
    poolBalanceWei: balance.toString(),
    nextSlotAt: small(nextSlotAt, time),
    block: blockNumber,
    chainTime: quantity(block.timestamp),
    node,
  };
}

async function main() {
  const input = process.argv[2] ?? "";
  if (process.argv.length !== 3 || !/^0x[0-9a-fA-F]{40}$/.test(input)) {
    print({ error: "Give one wallet address: 0x followed by 40 hex characters." }, 2);
    return;
  }
  const wallet = input.toLowerCase();
  for (const node of NODES) {
    try {
      print(await readFrom(node, wallet), 0);
      return;
    } catch {
      // A failure part way through starts again on the next node, so one answer never mixes two nodes.
    }
  }
  print({ error: "No BNB Smart Chain node answered. Try again in a few seconds." }, 3);
}

main();
