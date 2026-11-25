import { createPublicClient, fallback, http } from "viem";
import { bsc } from "viem/chains";
import { nameCreditAbi, nameCreditAddress } from "./generated/nameCredit";

/** Everything the first screen shows, read from the chain. Amounts are wei as strings so they survive JSON. */
export type StepCount = { advances: number; onTime: number; late: number; missed: number };

export type PoolSnapshot = {
  balanceWei: string;
  outstandingWei: string;
  slotsNow: number;
  nextSlotAt: number;
  paused: boolean;
  firstAdvanceWei: string;
  capWei: string;
  termSeconds: number;
  pacePerDay: number;
  people: number;
  lentWei: string;
  repaidWei: string;
  firstStep: StepCount;
  /** One entry per step of the ladder, from the first advance up to the cap. */
  byStep: StepCount[];
  graceSeconds: number;
  coolingOffSeconds: number;
  block: number;
  readAt: number;
};

// Public nodes drop the odd request, so a read that gets no answer goes to the next node in the list.
// Reads made together travel as one call, which also means they all describe the same block.
const NODES = [
  process.env.BSC_RPC_URL,
  "https://bsc-rpc.publicnode.com",
  "https://bsc-dataseed1.bnbchain.org",
  "https://bsc-dataseed.defibit.io",
  "https://bsc-dataseed.ninicoin.io",
].filter((url, index, all): url is string => Boolean(url) && all.indexOf(url) === index);

export const client = createPublicClient({
  chain: bsc,
  transport: fallback(NODES.map((url) => http(url, { timeout: 6_000, retryCount: 1 }))),
  batch: { multicall: true },
});

export const contract = { address: nameCreditAddress, abi: nameCreditAbi } as const;

// Every visitor's page asks for the same reads. One answer is shared for a few seconds so a busy
// page does not lean on a public node.
const SHARE_FOR_MS = 8_000;
let shared: { at: number; value: Promise<PoolSnapshot> } | null = null;

async function read(): Promise<PoolSnapshot> {
  const [pool, totals, settings, grace, coolingOff, block] = await Promise.all([
    client.readContract({ ...contract, functionName: "pool" }),
    client.readContract({ ...contract, functionName: "totals" }),
    client.readContract({ ...contract, functionName: "settings" }),
    client.readContract({ ...contract, functionName: "GRACE" }),
    client.readContract({ ...contract, functionName: "COOLING_OFF" }),
    client.getBlockNumber(),
  ]);
  const [firstAdvance, cap, term, pacePerDay] = settings;
  // The contract doubles the limit per step until it reaches the cap, and never goes above step 15.
  let steps = 1;
  for (let amount = firstAdvance; amount < cap && steps < 16; amount *= 2n) steps++;
  const tallies = await Promise.all(
    Array.from({ length: steps }, (_, step) => client.readContract({ ...contract, functionName: "stepTally", args: [step] })),
  );
  const byStep = tallies.map((tally) => ({
    advances: Number(tally.advances),
    onTime: Number(tally.onTime),
    late: Number(tally.late),
    missed: Number(tally.missed),
  }));
  return {
    balanceWei: pool.balance.toString(),
    outstandingWei: pool.outstanding.toString(),
    slotsNow: Number(pool.slotsNow),
    nextSlotAt: Number(pool.nextSlotAt),
    paused: pool.newAdvancesPaused,
    firstAdvanceWei: firstAdvance.toString(),
    capWei: cap.toString(),
    termSeconds: term,
    pacePerDay,
    people: Number(totals.people),
    lentWei: totals.lent.toString(),
    repaidWei: totals.repaid.toString(),
    firstStep: byStep[0],
    byStep,
    graceSeconds: Number(grace),
    coolingOffSeconds: Number(coolingOff),
    block: Number(block),
    readAt: Date.now(),
  };
}

export function readPool(): Promise<PoolSnapshot> {
  const now = Date.now();
  if (shared && now - shared.at < SHARE_FOR_MS) return shared.value;
  const value = read();
  shared = { at: now, value };
  value.catch(() => {
    if (shared?.value === value) shared = null;
  });
  return value;
}
