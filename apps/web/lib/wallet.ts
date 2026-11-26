import { keccak256, parseAbi, stringToBytes, type Address, type Hex } from "viem";
import { registryAddress } from "./generated/nameCredit";
import { client, contract } from "./pool";

const registryAbi = parseAbi([
  "function handleOf(address) view returns (string)",
  "function balanceOf(address) view returns (uint256)",
  "function ownerOfHandle(string) view returns (address)",
]);

/** Why the contract would refuse an advance, in the order of its own `Refusal` enum. */
export const REFUSALS = ["none", "paused", "open", "early", "noAgentId", "pace", "poolEmpty"] as const;
export type Refusal = (typeof REFUSALS)[number];

/** One wallet as the contract and the registry see it right now. Amounts are wei as strings. */
export type WalletView = {
  address: Address;
  holdsAgentId: boolean;
  name: string | null;
  refusal: Refusal;
  amountWei: string;
  dueIfBorrowedNow: number;
  step: number;
  limitWei: string;
  owedWei: string;
  due: number;
  overdueAt: number;
  missed: boolean;
  notBefore: number;
  onTime: number;
  late: number;
  nextSlotAt: number;
  poolBalanceWei: string;
  chainTime: number;
  block: number;
  /** The registry's own answers for this wallet, and the name hash the pool recorded at its first advance. */
  registry: {
    balance: string | null;
    handle: string | null;
    hasHandle: boolean;
    owner: Address | null;
    handleHash: Hex | null;
    recordedHash: Hex;
  };
};

// The registry allows only these characters. Anything else is not shown, so a name can never carry markup.
const NAME = /^[a-z0-9]{1,64}$/;

export async function readWallet(address: Address): Promise<WalletView> {
  const [quote, standing, holds, handle, balance, pool, block] = await Promise.all([
    client.readContract({ ...contract, functionName: "quoteBorrow", args: [address] }),
    client.readContract({ ...contract, functionName: "standingOf", args: [address] }),
    client.readContract({ ...contract, functionName: "holdsAgentId", args: [address] }),
    client.readContract({ address: registryAddress, abi: registryAbi, functionName: "handleOf", args: [address] }).catch(() => ""),
    client.readContract({ address: registryAddress, abi: registryAbi, functionName: "balanceOf", args: [address] }).catch(() => null),
    client.readContract({ ...contract, functionName: "pool" }),
    client.getBlock(),
  ]);
  const [refusal, amount, due] = quote;
  // The registry is asked about the name exactly as it answered, so this read matches what the contract does.
  const hasHandle = handle !== "";
  const owner = hasHandle
    ? await client.readContract({ address: registryAddress, abi: registryAbi, functionName: "ownerOfHandle", args: [handle] }).catch(() => null)
    : null;
  return {
    address,
    holdsAgentId: holds,
    name: holds && NAME.test(handle) ? handle : null,
    refusal: REFUSALS[refusal] ?? "noAgentId",
    amountWei: amount.toString(),
    dueIfBorrowedNow: Number(due),
    step: standing.step,
    limitWei: standing.limit.toString(),
    owedWei: standing.owed.toString(),
    due: Number(standing.due),
    overdueAt: Number(standing.overdueAt),
    missed: standing.missed,
    notBefore: Number(standing.notBefore),
    onTime: standing.onTime,
    late: standing.late,
    nextSlotAt: Number(pool.nextSlotAt),
    poolBalanceWei: pool.balance.toString(),
    chainTime: Number(block.timestamp),
    block: Number(block.number),
    registry: {
      balance: balance === null ? null : balance.toString(),
      handle: hasHandle && NAME.test(handle) ? handle : null,
      hasHandle,
      owner,
      handleHash: hasHandle ? keccak256(stringToBytes(handle)) : null,
      recordedHash: standing.nameHash,
    },
  };
}
