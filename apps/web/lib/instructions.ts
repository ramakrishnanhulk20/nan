import { encodeFunctionData, formatEther, getAddress, type Address, type Hex } from "viem";
import { nameCreditAbi, nameCreditAddress } from "./generated/nameCredit";

export type Lang = "en" | "zh";

/**
 * What a holder's agent is asked to send. Everything here comes from the contract's published address, a function
 * of its compiled ABI, and values read from the chain: the wallet, its name and an amount. The name has already
 * passed the registry's character rules in readWallet, so it cannot carry instructions into the text.
 */
export type Instruction = {
  kind: "borrow" | "borrowWithPass" | "repay";
  to: Address;
  valueWei: string;
  valueBnb: string;
  data: Hex;
  text: Record<Lang, string>;
};

const PREVIEW: Record<Lang, string> = {
  en: "Preview it for me first and only execute after I confirm. When it is done, send me the BscScan link.",
  zh: "请先给我预览，等我确认后再执行。完成后把 BscScan 链接发给我。",
};

const UNKNOWN_NAME: Record<Lang, string> = { en: "my Agent ID", zh: "我的 Agent ID" };

/** The slip: an opening sentence, a preview-first line, an empty line, then the call as to, value and data. */
function slip(opening: string, lang: Lang, call: string, value: string, data: Hex): string {
  return [opening, PREVIEW[lang], "", call, `to: ${nameCreditAddress}`, `value: ${value}`, `data: ${data}`].join("\n");
}

function advanceText(wallet: Address, name: string | null, amountWei: string, data: Hex, withPass: boolean): Record<Lang, string> {
  const address = getAddress(wallet);
  const amount = formatEther(BigInt(amountWei));
  const who = (lang: Lang) => (name ? `${name}.ai` : UNKNOWN_NAME[lang]);
  const fn = withPass ? "borrowWithPass()" : "borrow()";
  return {
    en: slip(
      `Using my Agentic Wallet (${address}) on BSC (chainId 56), run the contract call below to borrow a BNB advance on Nan for ${who("en")}.`,
      "en",
      `Call 1: ${fn} on Nan${withPass ? ", using my pass" : ""}. It sends my wallet an advance of ${amount} BNB. This call takes nothing from my wallet except gas. I repay the advance later in a separate call.`,
      "0",
      data,
    ),
    zh: slip(
      `使用我的 Agentic Wallet（${address}），在 BSC（chainId 56）上执行下面这笔合约调用，为 ${who("zh")} 在 Nan 借一笔 BNB 预支款。`,
      "zh",
      `调用 1：Nan 的 ${fn}${withPass ? "，使用我的通行码" : ""}。它会向我的钱包转入 ${amount} BNB 预支款。这笔调用除 gas 费外不会从我的钱包转出任何资产。预支款之后由我通过另一笔调用偿还。`,
      "0",
      data,
    ),
  };
}

export function borrowInstruction(wallet: Address, name: string | null, amountWei: string): Instruction {
  const data = encodeFunctionData({ abi: nameCreditAbi, functionName: "borrow" });
  return {
    kind: "borrow",
    to: nameCreditAddress,
    valueWei: "0",
    valueBnb: "0",
    data,
    text: advanceText(wallet, name, amountWei, data, false),
  };
}

export function borrowWithPassInstruction(wallet: Address, name: string | null, amountWei: string, code: Hex): Instruction {
  const data = encodeFunctionData({ abi: nameCreditAbi, functionName: "borrowWithPass", args: [code] });
  return {
    kind: "borrowWithPass",
    to: nameCreditAddress,
    valueWei: "0",
    valueBnb: "0",
    data,
    text: advanceText(wallet, name, amountWei, data, true),
  };
}

export function repayInstruction(borrower: Address, owedWei: string): Instruction {
  const data = encodeFunctionData({ abi: nameCreditAbi, functionName: "repay", args: [borrower] });
  const address = getAddress(borrower);
  const valueBnb = formatEther(BigInt(owedWei));
  return {
    kind: "repay",
    to: nameCreditAddress,
    valueWei: owedWei,
    valueBnb,
    data,
    text: {
      en: slip(
        `Using my Agentic Wallet (${address}) on BSC (chainId 56), run the contract call below to repay an advance on Nan in full.`,
        "en",
        `Call 1: repay() on Nan. It sends ${valueBnb} BNB from my wallet to the Nan pool and settles the advance of ${address}.`,
        `${owedWei} (wei, = ${valueBnb} BNB)`,
        data,
      ),
      zh: slip(
        `使用我的 Agentic Wallet（${address}），在 BSC（chainId 56）上执行下面这笔合约调用，全额偿还 Nan 的一笔预支款。`,
        "zh",
        `调用 1：Nan 的 repay()。它会从我的钱包向 Nan 资金池转出 ${valueBnb} BNB，结清 ${address} 的预支款。`,
        `${owedWei}（wei，= ${valueBnb} BNB）`,
        data,
      ),
    },
  };
}

/** A pass is 32 bytes written as 0x and 64 hex characters. */
export function isPassCode(value: string): value is Hex {
  return /^0x[0-9a-fA-F]{64}$/.test(value);
}
