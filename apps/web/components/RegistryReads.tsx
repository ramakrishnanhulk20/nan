"use client";

import { motion } from "motion/react";
import type { WalletView } from "@/lib/wallet";
import { useStill } from "./MotionPreferences";

const EASE = [0.16, 1, 0.3, 1] as const;
const ZERO_HASH = /^0x0{64}$/;

type Tone = "ok" | "fail" | "neutral";
type Row = { call: string; callTitle?: string; tone: Tone; answer: string; leadTitle?: string };

function short(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

/** Splits an answer into its coloured lead and the rest: before the first colon, else the first sentence. */
function splitAnswer(answer: string): [string, string] {
  const colon = answer.indexOf(": ");
  if (colon >= 0) return [answer.slice(0, colon), answer.slice(colon)];
  const stop = answer.indexOf(". ");
  if (stop >= 0) return [answer.slice(0, stop + 1), answer.slice(stop + 1)];
  return [answer, ""];
}

function rowsFor(wallet: WalletView): Row[] {
  const { registry } = wallet;
  const me = short(wallet.address);

  let balanceRow: Row;
  if (registry.balance === null) {
    balanceRow = { call: `balanceOf(${me})`, callTitle: wallet.address, tone: "fail", answer: "No answer from the registry." };
  } else if (BigInt(registry.balance) > 0n) {
    balanceRow = { call: `balanceOf(${me})`, callTitle: wallet.address, tone: "ok", answer: `${registry.balance}: this wallet holds an Agent ID.` };
  } else {
    balanceRow = { call: `balanceOf(${me})`, callTitle: wallet.address, tone: "fail", answer: `${registry.balance}: this wallet holds no Agent ID.` };
  }

  let handleRow: Row;
  if (registry.handle) {
    handleRow = { call: `handleOf(${me})`, callTitle: wallet.address, tone: "ok", answer: `"${registry.handle}": the name this wallet holds.` };
  } else if (registry.hasHandle) {
    handleRow = {
      call: `handleOf(${me})`,
      callTitle: wallet.address,
      tone: "ok",
      answer: "A name that is not shown here, because it has characters other than letters and digits.",
    };
  } else {
    handleRow = { call: `handleOf(${me})`, callTitle: wallet.address, tone: "fail", answer: "No name." };
  }

  let ownerRow: Row;
  if (!registry.hasHandle) {
    ownerRow = { call: "ownerOfHandle(…)", tone: "neutral", answer: "Not asked: there is no name to look up." };
  } else {
    const call = `ownerOfHandle("${registry.handle ?? "…"}")`;
    if (registry.owner === null) {
      ownerRow = { call, tone: "fail", answer: "No answer from the registry." };
    } else if (registry.owner.toLowerCase() === wallet.address.toLowerCase()) {
      ownerRow = { call, tone: "ok", answer: `${short(registry.owner)}: the name points back to this wallet.`, leadTitle: registry.owner };
    } else {
      ownerRow = { call, tone: "fail", answer: `${short(registry.owner)}: the name points to a different wallet.`, leadTitle: registry.owner };
    }
  }

  const recordedRow: Row = { call: `standingOf(${me}).nameHash`, callTitle: wallet.address, tone: "fail", answer: "" };
  if (ZERO_HASH.test(registry.recordedHash)) {
    recordedRow.tone = "neutral";
    recordedRow.answer = "Not recorded yet. The pool records the name at this wallet's first advance.";
  } else if (registry.handleHash !== null && registry.handleHash.toLowerCase() === registry.recordedHash.toLowerCase()) {
    recordedRow.tone = "ok";
    recordedRow.answer = "Matches the name recorded at this wallet's first advance.";
  } else {
    recordedRow.answer = "Differs from the name recorded at the first advance, so the pool refuses this wallet.";
  }

  return [balanceRow, handleRow, ownerRow, recordedRow];
}

const TONE_TEXT: Record<Tone, string> = { ok: "text-live", fail: "text-wait", neutral: "text-dim" };

function StatusIcon({ tone, delay }: { tone: Tone; delay: number }) {
  // MotionConfig's reduced-motion setting drops movement but still draws paths, so the mark starts drawn here.
  const still = useStill();
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true" className="block">
      {tone === "ok" ? (
        <>
          <circle cx="10" cy="10" r="8.75" stroke="#7fd6c2" strokeWidth="1.25" />
          <motion.path
            d="M6.2 10.3 L8.9 13 L13.9 7.2"
            stroke="#7fd6c2"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            initial={{ pathLength: still ? 1 : 0 }}
            animate={{ pathLength: 1 }}
            transition={still ? { duration: 0 } : { duration: 0.45, ease: EASE, delay }}
          />
        </>
      ) : null}
      {tone === "fail" ? (
        <>
          <circle cx="10" cy="10" r="8.75" stroke="#9db2ff" strokeWidth="1.25" />
          <path d="M6.5 10 H13.5" stroke="#9db2ff" strokeWidth="1.5" strokeLinecap="round" />
        </>
      ) : null}
      {tone === "neutral" ? <circle cx="10" cy="10" r="8.75" stroke="#979da6" strokeWidth="1.25" strokeDasharray="3 3" /> : null}
    </svg>
  );
}

/** The registry's answers to the questions the contract asks before it lends, with the pool's own record of the name beside them. */
export function RegistryReads({ wallet }: { wallet: WalletView }) {
  const rows = rowsFor(wallet);
  return (
    <div className="mt-6 border-t border-line pt-5">
      <div className="flex items-baseline justify-between gap-4 font-mono text-[11px] uppercase tracking-[0.16em] text-dim">
        <span>Read from the Agent ID registry</span>
        <span className="shrink-0">block {wallet.block}</span>
      </div>
      <ul key={wallet.address.toLowerCase()} className="mt-4 space-y-4">
        {rows.map((row, index) => {
          const [lead, rest] = splitAnswer(row.answer);
          return (
            <motion.li
              key={index}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.45, ease: EASE, delay: index * 0.15 }}
              className="grid grid-cols-[1.25rem_minmax(0,1fr)] gap-x-3"
            >
              <div className="relative">
                <StatusIcon tone={row.tone} delay={index * 0.15 + 0.2} />
                {index < rows.length - 1 ? <span className="absolute -bottom-4 left-[9.5px] top-5 border-l border-line" aria-hidden="true" /> : null}
              </div>
              <div className="min-w-0">
                <p title={row.callTitle} className="font-mono text-[13px] text-paper wrap-anywhere">
                  {row.call}
                </p>
                <p className="mt-1 text-base leading-snug text-paper wrap-anywhere">
                  <span title={row.leadTitle} className={TONE_TEXT[row.tone]}>
                    {lead}
                  </span>
                  {rest}
                </p>
              </div>
            </motion.li>
          );
        })}
      </ul>
      <p className="mt-5 text-sm leading-snug text-dim">
        The pool asks the registry the first three questions itself, in the same transaction, every time it lends. A missing or disagreeing answer stops the advance.
      </p>
    </div>
  );
}
