"use client";

import { useEffect, useMemo, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { isAddress } from "viem";
import type { WalletView } from "@/lib/wallet";
import { bnb, countdown } from "@/lib/format";
import { nameCreditAddress } from "@/lib/generated/nameCredit";
import { borrowInstruction, borrowWithPassInstruction, isPassCode, repayInstruction, type Instruction, type Lang } from "@/lib/instructions";

const POLL_MS = 15_000;
const RETRY_MS = 3_000;
const EASE = [0.16, 1, 0.3, 1] as const;
const LANG_KEY = "nan-lang";

const WORDS: Record<Lang, { copy: string; copied: string; borrowHint: string; repayHint: string; pasted: string; replyLabel: string; reply: string; replyCopy: string }> = {
  en: {
    copy: "Copy the text",
    copied: "Copied",
    borrowHint: "It only works from the wallet that holds the Agent ID.",
    repayHint: "Any wallet may send this. It settles this one advance and nothing else.",
    pasted: "Now paste it into Binance AI Pro and read the preview before you confirm.",
    replyLabel: "If it only previews, reply",
    reply: "Confirmed, execute call 1",
    replyCopy: "Copy",
  },
  zh: {
    copy: "复制文本",
    copied: "已复制",
    borrowHint: "只能从持有该 Agent ID 的钱包发起。",
    repayHint: "任何钱包都可以发送。它只结清这一笔预支款。",
    pasted: "现在粘贴到 Binance AI Pro，确认前先看预览。",
    replyLabel: "如果只预览没有执行，回复",
    reply: "已确认，执行调用 1",
    replyCopy: "复制",
  },
};

type View = { tone: "live" | "wait"; line: string; instruction: Instruction | null; takesPass?: boolean };
type Load = { state: "idle" } | { state: "bad" } | { state: "loading" } | { state: "failed" } | { state: "ready"; wallet: WalletView; stale: boolean };

function when(unix: number): string {
  return new Date(unix * 1000).toLocaleString(undefined, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZoneName: "short" });
}

function LangSwitch({ lang, onPick }: { lang: Lang; onPick: (next: Lang) => void }) {
  const button = (value: Lang, label: string) => (
    <button
      type="button"
      lang={value === "zh" ? "zh" : undefined}
      aria-pressed={lang === value}
      onClick={() => onPick(value)}
      className={`border-b font-mono text-[11px] uppercase tracking-[0.16em] ${
        lang === value ? "border-accent text-paper" : "border-transparent text-dim transition-colors duration-200 hover:text-paper"
      }`}
    >
      {label}
    </button>
  );
  return (
    <div role="group" aria-label="Language of the text" className="flex items-center gap-4">
      {button("en", "EN")}
      {button("zh", "中文")}
    </div>
  );
}

function Slip({ instruction, lang, onPick }: { instruction: Instruction; lang: Lang; onPick: (next: Lang) => void }) {
  const [copied, setCopied] = useState(false);
  const [replyCopied, setReplyCopied] = useState(false);
  const words = WORDS[lang];
  const body = instruction.text[lang];
  useEffect(() => setCopied(false), [body]);

  useEffect(() => {
    if (!replyCopied) return;
    const timer = setTimeout(() => setReplyCopied(false), 2000);
    return () => clearTimeout(timer);
  }, [replyCopied]);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(body);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  };

  const copyReply = async () => {
    try {
      await navigator.clipboard.writeText(words.reply);
      setReplyCopied(true);
    } catch {
      setReplyCopied(false);
    }
  };

  return (
    <motion.div
      key={instruction.kind + instruction.data}
      initial={{ opacity: 0, y: 28, rotate: -1.2 }}
      animate={{ opacity: 1, y: 0, rotate: 0 }}
      exit={{ opacity: 0, y: -16 }}
      transition={{ duration: 0.7, ease: EASE }}
      className="relative border border-paper/40 bg-ink"
    >
      <div className="flex flex-wrap items-center justify-between gap-x-6 gap-y-1 border-b border-dashed border-paper/30 px-5 py-3 font-mono text-[11px] uppercase tracking-[0.16em] text-dim">
        <span>{instruction.kind === "repay" ? "Repay slip" : "Borrow slip"}</span>
        <LangSwitch lang={lang} onPick={onPick} />
      </div>
      <p
        data-slip="text"
        lang={lang === "zh" ? "zh" : undefined}
        className="select-all wrap-anywhere whitespace-pre-wrap px-5 py-5 font-mono text-[15px] leading-relaxed text-paper"
      >
        {body}
      </p>
      <dl className="grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-4 gap-y-2 border-t border-dashed border-paper/30 px-5 py-4 font-mono text-xs text-dim">
        <dt className="uppercase tracking-[0.14em]">To</dt>
        <dd data-slip="to" className="break-all text-paper">
          {instruction.to}
        </dd>
        <dt className="uppercase tracking-[0.14em]">Value</dt>
        <dd data-slip="value" className="text-paper">
          {instruction.valueBnb} BNB
          {instruction.kind === "repay" ? ` · ${instruction.valueWei} wei` : ""}
        </dd>
        <dt className="uppercase tracking-[0.14em]">Data</dt>
        <dd data-slip="data" className="break-all text-paper">
          {instruction.data}
        </dd>
      </dl>
      <div className="flex flex-wrap items-center gap-4 border-t border-paper/40 px-5 py-4">
        <button
          type="button"
          onClick={copy}
          className="rounded-lg bg-accent px-5 py-3 font-display text-lg font-extrabold uppercase tracking-[0.04em] text-ink transition-transform duration-300 hover:-translate-y-0.5 active:translate-y-0"
        >
          {copied ? words.copied : words.copy}
        </button>
        <span data-slip="hint" lang={lang === "zh" ? "zh" : undefined} className="text-sm text-dim" aria-live="polite">
          {copied ? words.pasted : instruction.kind === "repay" ? words.repayHint : words.borrowHint}
        </span>
      </div>
      <div className="border-t border-dashed border-paper/30 px-5 py-4">
        <p lang={lang === "zh" ? "zh" : undefined} className="font-mono text-[11px] uppercase tracking-[0.14em] text-dim">
          {words.replyLabel}
        </p>
        <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-2">
          <span data-slip="reply" lang={lang === "zh" ? "zh" : undefined} className="select-all font-mono text-sm text-paper">
            {words.reply}
          </span>
          <button
            type="button"
            data-slip="reply-copy"
            onClick={copyReply}
            className="rounded-lg border border-line px-3 py-2 font-mono text-[11px] uppercase tracking-[0.14em] text-paper transition-colors duration-200 hover:border-accent"
          >
            {replyCopied ? words.copied : words.replyCopy}
          </button>
        </div>
      </div>
    </motion.div>
  );
}

export function Borrow() {
  const [typed, setTyped] = useState("");
  const [load, setLoad] = useState<Load>({ state: "idle" });
  const [pass, setPass] = useState("");
  const [now, setNow] = useState(0);
  const [lang, setLang] = useState<Lang>("en");
  const address = typed.trim();

  // The server renders English. After mount a saved choice wins, then the browser's own language.
  useEffect(() => {
    let saved: string | null = null;
    try {
      saved = localStorage.getItem(LANG_KEY);
    } catch {
      // Storage can be blocked, for example in private browsing. The default then applies.
    }
    if (saved === "en" || saved === "zh") setLang(saved);
    else if (navigator.language.toLowerCase().startsWith("zh")) setLang("zh");
  }, []);

  const pickLang = (next: Lang) => {
    setLang(next);
    try {
      localStorage.setItem(LANG_KEY, next);
    } catch {
      // The choice then lasts for this visit only.
    }
  };

  useEffect(() => {
    const clock = setInterval(() => setNow(Date.now()), 1000);
    setNow(Date.now());
    return () => clearInterval(clock);
  }, []);

  useEffect(() => {
    if (!address) {
      setLoad({ state: "idle" });
      return;
    }
    if (!isAddress(address, { strict: false })) {
      setLoad({ state: "bad" });
      return;
    }
    let alive = true;
    let timer: ReturnType<typeof setTimeout>;
    setLoad((current) => (current.state === "ready" && current.wallet.address.toLowerCase() === address.toLowerCase() ? current : { state: "loading" }));
    const read = async () => {
      let answered = false;
      try {
        const response = await fetch(`/api/wallet?address=${address}`, { cache: "no-store" });
        const body = await response.json();
        if (!alive) return;
        if (!response.ok) throw new Error(body.error);
        setLoad({ state: "ready", wallet: body as WalletView, stale: false });
        answered = true;
      } catch {
        // One missed read must not wipe a slip the holder may be copying. The last answer stays, marked as such.
        if (alive) setLoad((current) => (current.state === "ready" ? { ...current, stale: true } : { state: "failed" }));
      }
      if (alive) timer = setTimeout(read, answered ? POLL_MS : RETRY_MS);
    };
    timer = setTimeout(read, 350);
    return () => {
      alive = false;
      clearTimeout(timer);
    };
  }, [address]);

  const wallet = load.state === "ready" ? load.wallet : null;
  const who = wallet?.name ? `${wallet.name}.ai` : "This wallet";

  const view = useMemo<View | null>(() => {
    if (!wallet) return null;
    if (!wallet.holdsAgentId) {
      return {
        tone: "wait",
        line: "This wallet holds no Agent ID, so the contract will refuse it. Claim one in the Binance app under Web3 Wallet, then Agent ID, and come back.",
        instruction: null,
      };
    }
    if (wallet.owedWei !== "0") {
      const late = wallet.chainTime > wallet.overdueAt;
      return {
        tone: late ? "wait" : "live",
        line: late
          ? `${who} owes ${bnb(wallet.owedWei, 18)} BNB and is past its day of grace. Repaying now settles it. The name can borrow again 7 days later, from the first step.`
          : `${who} owes ${bnb(wallet.owedWei, 18)} BNB, due ${when(wallet.due)}. Paid by ${when(wallet.overdueAt)} it still counts as on time, and the limit doubles.`,
        instruction: repayInstruction(wallet.address, wallet.owedWei),
      };
    }
    if (wallet.refusal === "none") {
      return {
        tone: "live",
        line: `${who} can borrow ${bnb(wallet.amountWei, 18)} BNB now, with nothing locked up. It would fall due ${when(wallet.dueIfBorrowedNow)}.`,
        instruction: borrowInstruction(wallet.address, wallet.name, wallet.amountWei),
      };
    }
    // The contract checks the pace before the pool, and a pass skips only the pace. Nothing is held back from a
    // first advance, so the pool can pay one exactly when its balance covers the amount.
    const dry = wallet.refusal === "poolEmpty" || (wallet.refusal === "pace" && BigInt(wallet.poolBalanceWei) < BigInt(wallet.amountWei));
    if (dry) {
      return { tone: "wait", line: "The pool cannot cover this advance right now. Nothing is wrong with the name. Try again later.", instruction: null };
    }
    if (wallet.refusal === "pace") {
      return {
        tone: "wait",
        line: `Every first advance released so far is taken. The next one opens in ${countdown(wallet.nextSlotAt, now)}. A pass skips this wait.`,
        instruction: isPassCode(pass) ? borrowWithPassInstruction(wallet.address, wallet.name, wallet.amountWei, pass) : null,
        takesPass: true,
      };
    }
    if (wallet.refusal === "early") return { tone: "wait", line: `${who} can borrow again from ${when(wallet.notBefore)}.`, instruction: null };
    if (wallet.refusal === "paused") return { tone: "wait", line: "New advances are paused. Repayments still work.", instruction: null };
    return { tone: "wait", line: "The registry does not confirm an Agent ID for this wallet right now.", instruction: null };
  }, [wallet, who, pass, now]);

  return (
    <section
      id="borrow"
      className="relative border-t border-line bg-ink px-5 py-20 md:px-10 md:py-28"
      style={{
        backgroundImage:
          "linear-gradient(rgb(242 238 230 / 0.03) 1px, transparent 1px), linear-gradient(90deg, rgb(242 238 230 / 0.03) 1px, transparent 1px)",
        backgroundSize: "64px 64px",
      }}
    >
      <motion.div
        initial={{ opacity: 0, y: 24 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: "-15%" }}
        transition={{ duration: 0.9, ease: EASE }}
      >
        <p className="font-mono text-xs uppercase tracking-[0.18em] text-dim">How to borrow</p>
        <h2 className="mt-3 font-display font-black uppercase leading-[0.86] tracking-[-0.01em]" style={{ fontSize: "clamp(2.6rem, 7.2vw, 7rem)" }}>
          One line
          <br />
          <span className="text-accent">to your agent.</span>
        </h2>
        <p className="mt-5 max-w-2xl text-lg leading-snug text-paper md:text-xl">
          There is no wallet to connect. Your Agent ID lives in a Binance Agentic Wallet, so the borrowing is done by your own
          agent: you paste one line into it, read its preview, and confirm. This page never asks for a signature, a QR scan or a
          seed phrase.
        </p>
      </motion.div>

      <div className="mt-12 grid grid-cols-1 gap-x-12 gap-y-10 md:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
        <ol className="min-w-0 space-y-9">
          <li className="grid grid-cols-[2.5rem_minmax(0,1fr)] gap-x-4">
            <span className="font-display text-4xl font-black leading-none text-paper/35">1</span>
            <div>
              <label htmlFor="wallet" className="font-display text-2xl font-extrabold uppercase leading-none">
                Your Agentic Wallet address
              </label>
              <p className="mt-2 text-dim">
                Not sure of it? Ask Binance AI Pro: <span className="select-all font-mono text-sm text-paper">What is my Agentic Wallet address?</span>
              </p>
              <input
                id="wallet"
                value={typed}
                onChange={(event) => setTyped(event.target.value)}
                placeholder="0x..."
                autoComplete="off"
                autoCapitalize="none"
                spellCheck={false}
                className="mt-3 w-full rounded-lg border border-line bg-ink/70 px-3 py-3 font-mono text-sm text-paper outline-none placeholder:text-dim/70 focus:border-accent"
              />
              <p className="mt-2 min-h-6 text-sm text-dim" aria-live="polite">
                {load.state === "bad" ? "That is not a wallet address yet. It starts with 0x and has 40 more characters." : null}
                {load.state === "loading" ? "Asking the contract" : null}
                {load.state === "failed" ? "The chain did not answer. Trying again." : null}
                {load.state === "ready" && load.stale ? "The chain did not answer just now. This is its last answer, and the page is trying again." : null}
              </p>
            </div>
          </li>

          <li className="grid grid-cols-[2.5rem_minmax(0,1fr)] gap-x-4">
            <span className="font-display text-4xl font-black leading-none text-paper/35">2</span>
            <div>
              <h3 className="font-display text-2xl font-extrabold uppercase leading-none">What the contract says</h3>
              <p data-says className="mt-3 flex min-h-14 gap-3 text-lg leading-snug text-paper" aria-live="polite">
                {view ? (
                  <>
                    <span className={`live-dot mt-2 inline-block h-2 w-2 shrink-0 rounded-full ${view.tone === "live" ? "bg-live" : "bg-wait"}`} aria-hidden="true" />
                    <span>{view.line}</span>
                  </>
                ) : (
                  <span className="text-dim">It answers here as soon as there is an address above. The page uses the address only to read the public chain, and asks for nothing else.</span>
                )}
              </p>
              {wallet && wallet.holdsAgentId ? (
                <p className="mt-3 font-mono text-xs uppercase tracking-[0.14em] text-dim">
                  {wallet.name ? `${wallet.name}.ai · ` : ""}Step {wallet.step + 1} · limit {bnb(wallet.limitWei, 18)} BNB · repaid on time {wallet.onTime} · late{" "}
                  {wallet.late}
                </p>
              ) : null}
              {view?.takesPass ? (
                <div className="mt-4">
                  <label htmlFor="pass" className="font-mono text-[11px] uppercase tracking-[0.14em] text-dim">
                    I have a pass
                  </label>
                  <input
                    id="pass"
                    value={pass}
                    onChange={(event) => setPass(event.target.value.trim())}
                    placeholder="0x and 64 characters"
                    autoComplete="off"
                    spellCheck={false}
                    className="mt-2 w-full rounded-lg border border-line bg-ink/70 px-3 py-3 font-mono text-sm text-paper outline-none placeholder:text-dim/70 focus:border-accent"
                  />
                  {pass && !isPassCode(pass) ? <p className="mt-2 text-sm text-dim">A pass is 0x followed by 64 letters and digits.</p> : null}
                </div>
              ) : null}
            </div>
          </li>

          <li className="grid grid-cols-[2.5rem_minmax(0,1fr)] gap-x-4">
            <span className="font-display text-4xl font-black leading-none text-paper/35">3</span>
            <div>
              <h3 className="font-display text-2xl font-extrabold uppercase leading-none">Paste, read the preview, confirm</h3>
              <p className="mt-2 text-dim">
                In the Binance app open Binance AI and switch to Pro. Paste the slip. Before you confirm, check that the recipient in
                the preview is <span className="break-all font-mono text-sm text-paper">{nameCreditAddress}</span>.
              </p>
            </div>
          </li>
        </ol>

        <div className="min-w-0 md:sticky md:top-10 md:self-start">
          <AnimatePresence mode="wait">
            {view?.instruction ? (
              <Slip key={view.instruction.kind + view.instruction.data} instruction={view.instruction} lang={lang} onPick={pickLang} />
            ) : (
              <motion.div
                key="empty"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="grid min-h-72 place-items-center border border-dashed border-paper/25 p-8 text-center text-dim"
              >
                <div>
                  <p>The slip to paste appears here when the contract says this wallet can borrow, or has something to repay.</p>
                  <a href="/docs/borrow" className="draw mt-4 inline-block pb-1 font-mono text-xs uppercase tracking-[0.16em] text-paper">
                    See what the slip looks like
                  </a>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
          <p className="mt-4 text-sm leading-snug text-dim">
            Miss the due time and its one day of grace, and the name starts again at the first step, 7 days after it has paid. An
            advance that is never repaid closes this name's credit here for good.
          </p>
        </div>
      </div>
    </section>
  );
}
