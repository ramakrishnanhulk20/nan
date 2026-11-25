"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import type { PoolSnapshot } from "@/lib/pool";
import { nameCreditAddress } from "@/lib/generated/nameCredit";
import { bnb, cleanTyped, countdown, days, nameFrom } from "@/lib/format";
import { Mark } from "./Mark";
import { Still } from "./Still";

const POLL_MS = 15_000;
const EASE = [0.16, 1, 0.3, 1] as const;

type Props = { initial: PoolSnapshot | null };

export function Hero({ initial }: Props) {
  const [pool, setPool] = useState(initial);
  const [failed, setFailed] = useState(initial === null);
  const [now, setNow] = useState(() => initial?.readAt ?? 0);
  const [typed, setTyped] = useState("");
  const name = nameFrom(typed);
  const root = useRef<HTMLElement>(null);
  const still = useReducedMotion();

  useEffect(() => {
    let alive = true;
    const load = async () => {
      try {
        const response = await fetch("/api/pool", { cache: "no-store" });
        if (!response.ok) throw new Error("no answer");
        const next = (await response.json()) as PoolSnapshot;
        if (alive) {
          setPool(next);
          setFailed(false);
        }
      } catch {
        if (alive) setFailed(true);
      }
    };
    if (initial === null) void load();
    const poll = setInterval(load, POLL_MS);
    const clock = setInterval(() => setNow(Date.now()), 1000);
    setNow(Date.now());
    return () => {
      alive = false;
      clearInterval(poll);
      clearInterval(clock);
    };
  }, [initial]);

  // Scroll progress is written to a CSS variable from one animation frame callback, so scrolling never
  // re-renders React.
  useEffect(() => {
    const node = root.current;
    if (!node || still) return;
    let frame = 0;
    const update = () => {
      frame = 0;
      const progress = Math.min(1, Math.max(0, window.scrollY / window.innerHeight));
      node.style.setProperty("--p", progress.toFixed(4));
    };
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };
    update();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (frame) cancelAnimationFrame(frame);
    };
  }, [still]);

  const title = name ? `${name}.ai` : "Nan";
  const first = pool ? bnb(pool.firstAdvanceWei) : null;

  const status = useMemo(() => {
    if (!pool) return failed ? { tone: "wait", text: "The chain is not answering. Trying again." } : { tone: "wait", text: "Reading the chain" };
    if (pool.paused) return { tone: "wait", text: "New advances are paused. Repayments still work." };
    if (BigInt(pool.balanceWei) < BigInt(pool.firstAdvanceWei)) return { tone: "wait", text: "The pool is empty. Not lending yet." };
    if (pool.slotsNow > 0) {
      return { tone: "live", text: `Lending now. ${pool.slotsNow} first ${pool.slotsNow === 1 ? "advance" : "advances"} open.` };
    }
    return { tone: "wait", text: `Next first advance opens in ${countdown(pool.nextSlotAt, now)}` };
  }, [pool, failed, now]);

  const settled = pool ? pool.firstStep.onTime + pool.firstStep.late + pool.firstStep.missed : 0;
  const onTimeRate = pool && settled > 0 ? `${Math.floor((pool.firstStep.onTime * 100) / settled)}%` : null;

  const rise = (delay: number) =>
    still
      ? {}
      : { initial: { opacity: 0, y: 24 }, animate: { opacity: 1, y: 0 }, transition: { duration: 0.9, delay, ease: EASE } };

  return (
    <section ref={root} className="relative isolate min-h-[100svh] overflow-hidden bg-ink" style={{ "--p": 0 } as React.CSSProperties}>
      <motion.div
        className="grain absolute inset-x-0 top-0 h-[50svh] overflow-hidden md:h-[78svh]"
        initial={still ? false : { opacity: 0, scale: 1.08 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 1.8, ease: EASE }}
      >
        <div
          className="absolute inset-0 will-change-transform"
          style={{ transform: "translate3d(0, calc(var(--p) * -7svh), 0) scale(calc(1.05 - var(--p) * 0.05))" }}
        >
          {/* SWAP: hero image. Replace <Still /> with the real photograph or film, full-bleed, when there is one. */}
          <Still />
        </div>
        <div className="absolute inset-0 bg-gradient-to-t from-ink via-ink/25 to-transparent" />
        <div className="absolute inset-0 bg-gradient-to-r from-ink/60 via-transparent to-transparent" />
      </motion.div>

      <header className="relative z-10 flex items-center justify-between px-5 pt-5 md:px-10 md:pt-8">
        <a href="/lab" className="group flex items-center gap-3" aria-label="Nan, home">
          <Mark className="h-11 w-11 text-paper transition-transform duration-500 ease-[var(--ease-poster)] group-hover:-translate-y-0.5" />
          <span className="font-display text-xl font-black uppercase tracking-[0.08em]">Nan</span>
          <span className="font-tamil text-base text-paper/70" lang="ta">
            நான்
          </span>
        </a>
        <nav className="flex items-center gap-5 font-mono text-[11px] uppercase tracking-[0.16em] text-paper/80 md:gap-8 md:text-xs">
          <a className="draw pb-1 hover:text-paper" href={`https://bscscan.com/address/${nameCreditAddress}`} target="_blank" rel="noreferrer">
            Contract
          </a>
          <a className="draw pb-1 hover:text-paper" href={`https://repo.sourcify.dev/56/${nameCreditAddress}`} target="_blank" rel="noreferrer">
            Source
          </a>
        </nav>
      </header>

      <div className="relative z-10 flex min-h-[calc(100svh-4.75rem)] flex-col justify-end px-5 pb-6 pt-12 md:px-10 md:pb-8 md:pt-0">
        <motion.p {...rise(0.5)} className="flex items-center gap-3 font-mono text-[11px] uppercase tracking-[0.18em] text-paper md:text-xs">
          <span
            className={`live-dot inline-block h-2 w-2 rounded-full ${status.tone === "live" ? "bg-live" : "bg-wait"}`}
            aria-hidden="true"
          />
          <span aria-live="polite">{status.text}</span>
        </motion.p>

        <div className="mt-3 grid items-end gap-x-10 gap-y-6 md:mt-4 md:grid-cols-[minmax(0,1fr)_minmax(17rem,24rem)]">
          <h1
            className="font-display font-black uppercase leading-[0.78] tracking-[-0.02em] text-paper will-change-transform"
            style={{
              fontSize: `min(var(--title-max), calc(var(--title-room) * ${(1 / (title.length * 0.5)).toFixed(4)}vw), 46svh)`,
              transform: "translate3d(0, calc(var(--p) * 5svh), 0)",
            }}
          >
            <span className="sr-only">Nan. Credit on a name.</span>
            <span aria-hidden="true" className="block overflow-hidden pb-[0.06em] pt-[0.04em]">
              <AnimatePresence mode="popLayout" initial={!still}>
                <motion.span
                  key={title}
                  className="block whitespace-nowrap"
                  initial={still ? false : { y: "62%", opacity: 0 }}
                  animate={{ y: "0%", opacity: 1 }}
                  exit={still ? undefined : { y: "-40%", opacity: 0 }}
                  transition={{ duration: name ? 0.55 : 1.2, delay: name ? 0 : 0.15, ease: EASE }}
                >
                  {title}
                </motion.span>
              </AnimatePresence>
            </span>
          </h1>

          <motion.div {...rise(0.8)} className="max-w-md pb-2 md:pb-4">
            <p className="text-lg leading-snug text-paper md:text-xl">
              Nan is Tamil for I. Borrow a little BNB on your Agent ID name alone, with nothing locked up.
            </p>
            <dl className="mt-5 grid grid-cols-2 gap-x-6 gap-y-3 border-t border-line pt-4 font-mono text-[11px] uppercase tracking-[0.14em] text-dim">
              <div>
                <dt>First advance</dt>
                <dd className="mt-1 text-sm tracking-normal text-paper">{first ? `${first} BNB` : "reading"}</dd>
              </div>
              <div>
                <dt>Time to repay</dt>
                <dd className="mt-1 text-sm tracking-normal text-paper">{pool ? `${days(pool.termSeconds)}, plus 1 of grace` : "reading"}</dd>
              </div>
              <div>
                <dt>Repay on time</dt>
                <dd className="mt-1 text-sm tracking-normal text-paper">{pool ? `Limit doubles, up to ${bnb(pool.capWei)} BNB` : "reading"}</dd>
              </div>
              <div>
                <dt>Interest and fees</dt>
                <dd className="mt-1 text-sm tracking-normal text-paper">None</dd>
              </div>
            </dl>

            <label className="mt-5 block font-mono text-[11px] uppercase tracking-[0.14em] text-dim" htmlFor="name">
              Put your name on the poster
            </label>
            <div className="mt-2 flex items-stretch gap-2">
              <div className="flex min-w-0 flex-1 items-center rounded-lg border border-line bg-ink/60 px-3 backdrop-blur focus-within:border-accent">
                <input
                  id="name"
                  value={typed}
                  onChange={(event) => setTyped(cleanTyped(event.target.value))}
                  placeholder="yourname"
                  autoComplete="off"
                  autoCapitalize="none"
                  spellCheck={false}
                  inputMode="text"
                  maxLength={23}
                  className="min-w-0 flex-1 bg-transparent py-3 text-base text-paper outline-none placeholder:text-dim/70"
                />
                {typed.includes(".") ? null : <span className="pl-1 font-mono text-sm text-dim">.ai</span>}
              </div>
              <a
                href="#borrow"
                className="grid place-items-center rounded-lg bg-accent px-5 font-display text-lg font-extrabold uppercase tracking-[0.04em] text-ink transition-transform duration-300 hover:-translate-y-0.5 active:translate-y-0"
              >
                Borrow
              </a>
            </div>
            <p className="mt-3 min-h-10 text-sm leading-snug text-dim" aria-live="polite">
              {name && first
                ? `If ${name}.ai is yours, it is good for ${first} BNB today. Nothing is checked until your agent asks the contract.`
                : "One name per person, for life. A name that does not repay cannot start again as someone new."}
            </p>
          </motion.div>
        </div>

        <motion.div
          {...rise(1.05)}
          className="mt-6 flex flex-wrap items-center gap-x-8 gap-y-2 border-t border-line pt-4 font-mono text-[11px] uppercase tracking-[0.16em] text-dim md:mt-8"
        >
          <span>BNB Smart Chain</span>
          <span>No collateral</span>
          <span>
            In the pool <b className="font-medium text-paper">{pool ? `${bnb(pool.balanceWei)} BNB` : "reading"}</b>
          </span>
          <span>
            Out with borrowers <b className="font-medium text-paper">{pool ? `${bnb(pool.outstandingWei)} BNB` : "reading"}</b>
          </span>
          <span>
            Borrowers so far <b className="font-medium text-paper">{pool ? pool.people : "reading"}</b>
          </span>
          <span>
            First advances repaid on time{" "}
            <b className="font-medium text-paper">{pool ? (onTimeRate ?? "none settled yet") : "reading"}</b>
          </span>
          {pool ? <span className="ml-auto hidden text-dim/70 lg:inline">Read at block {pool.block.toLocaleString("en-US")}</span> : null}
        </motion.div>
      </div>
    </section>
  );
}
