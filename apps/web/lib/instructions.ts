import { encodeFunctionData, formatEther, type Address, type Hex } from "viem";
import { nameCreditAbi, nameCreditAddress } from "./generated/nameCredit";

/**
 * What a holder's agent is asked to send. Everything here comes from three places only: the contract's
 * published address, a function of its compiled ABI, and an amount read from the contract.
 */
export type Instruction = {
  kind: "borrow" | "borrowWithPass" | "repay";
  to: Address;
  valueWei: string;
  valueBnb: string;
  data: Hex;
  text: string;
};

const CHECK = `Show me the preview first. The recipient must be ${nameCreditAddress}; if it is any other address, cancel.`;

export function borrowInstruction(): Instruction {
  const data = encodeFunctionData({ abi: nameCreditAbi, functionName: "borrow" });
  return {
    kind: "borrow",
    to: nameCreditAddress,
    valueWei: "0",
    valueBnb: "0",
    data,
    text: `On BNB Smart Chain, call the contract ${nameCreditAddress} from my Agentic Wallet with 0 BNB and input data ${data}. This is borrow() on Nan: it sends my wallet a small BNB advance that I repay later. ${CHECK}`,
  };
}

export function borrowWithPassInstruction(code: Hex): Instruction {
  const data = encodeFunctionData({ abi: nameCreditAbi, functionName: "borrowWithPass", args: [code] });
  return {
    kind: "borrowWithPass",
    to: nameCreditAddress,
    valueWei: "0",
    valueBnb: "0",
    data,
    text: `On BNB Smart Chain, call the contract ${nameCreditAddress} from my Agentic Wallet with 0 BNB and input data ${data}. This is borrowWithPass() on Nan: it sends my wallet a small BNB advance that I repay later, using my pass. ${CHECK}`,
  };
}

export function repayInstruction(borrower: Address, owedWei: string): Instruction {
  const data = encodeFunctionData({ abi: nameCreditAbi, functionName: "repay", args: [borrower] });
  const valueBnb = formatEther(BigInt(owedWei));
  return {
    kind: "repay",
    to: nameCreditAddress,
    valueWei: owedWei,
    valueBnb,
    data,
    text: `On BNB Smart Chain, call the contract ${nameCreditAddress} from my Agentic Wallet, sending exactly ${valueBnb} BNB, with input data ${data}. This is repay() on Nan: it repays the advance of ${borrower} in full. ${CHECK}`,
  };
}

/** A pass is 32 bytes written as 0x and 64 hex characters. */
export function isPassCode(value: string): value is Hex {
  return /^0x[0-9a-fA-F]{64}$/.test(value);
}
