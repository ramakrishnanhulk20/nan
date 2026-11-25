import { createPublicClient, http } from "viem";
import { bsc } from "viem/chains";
import { nameCreditAbi, nameCreditAddress } from "./generated/nameCredit";

/** Everything the first screen shows, read from the chain. Amounts are wei as strings so they survive JSON. */
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
  firstStep: { advances: number; onTime: number; late: number; missed: number };
  block: number;
  readAt: number;
};

const client = createPublicClient({
  chain: bsc,
  transport: http(process.env.BSC_RPC_URL || "https://bsc-dataseed.bnbchain.org"),
});

const contract = { address: nameCreditAddress, abi: nameCreditAbi } as const;

// Every visitor's page asks for the same five reads. One answer is shared for a few seconds so a busy
// page does not lean on a public node.
const SHARE_FOR_MS = 8_000;
let shared: { at: number; value: Promise<PoolSnapshot> } | null = null;

async function read(): Promise<PoolSnapshot> {
  const [pool, totals, settings, firstStep, block] = await Promise.all([
    client.readContract({ ...contract, functionName: "pool" }),
    client.readContract({ ...contract, functionName: "totals" }),
    client.readContract({ ...contract, functionName: "settings" }),
    client.readContract({ ...contract, functionName: "stepTally", args: [0] }),
    client.getBlockNumber(),
  ]);
  const [firstAdvance, cap, term, pacePerDay] = settings;
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
    firstStep: {
      advances: Number(firstStep.advances),
      onTime: Number(firstStep.onTime),
      late: Number(firstStep.late),
      missed: Number(firstStep.missed),
    },
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
