"use client";

import type { PoolSnapshot } from "@/lib/pool";
import type { Status } from "@/lib/usePool";
import { nameCreditAddress } from "@/lib/generated/nameCredit";
import { bnb, cleanTyped, days, nameFrom } from "@/lib/format";
import { Mark } from "./Mark";

export function SiteHeader() {
  return (
    <header className="relative z-20 flex items-center justify-between px-5 pt-5 md:px-10 md:pt-8">
      <a href="/" className="group flex items-center gap-3" aria-label="Nan, home">
        <Mark className="h-11 w-11 text-paper transition-transform duration-500 ease-[var(--ease-poster)] group-hover:-translate-y-0.5" />
        <span className="font-display text-xl font-black uppercase tracking-[0.08em]">Nan</span>
      </a>
      <nav className="flex items-center gap-5 font-mono text-[11px] uppercase tracking-[0.16em] text-paper/80 md:gap-8 md:text-xs">
        <a className="draw pb-1 hover:text-paper" href="/docs">
          Docs
        </a>
        <a className="draw pb-1 hover:text-paper" href={`https://bscscan.com/address/${nameCreditAddress}`} target="_blank" rel="noreferrer">
          Contract
        </a>
        <a className="draw pb-1 hover:text-paper" href={`https://repo.sourcify.dev/56/${nameCreditAddress}`} target="_blank" rel="noreferrer">
          Source
        </a>
      </nav>
    </header>
  );
}

export function StatusLine({ status }: { status: Status }) {
  return (
    <p className="flex items-center gap-3 font-mono text-[11px] uppercase tracking-[0.18em] text-paper md:text-xs">
      <span className={`live-dot inline-block h-2 w-2 rounded-full ${status.tone === "live" ? "bg-live" : "bg-wait"}`} aria-hidden="true" />
      <span aria-live="polite">{status.text}</span>
    </p>
  );
}

export function Facts({ pool }: { pool: PoolSnapshot | null }) {
  return (
    <dl className="grid grid-cols-2 gap-x-6 gap-y-3 border-t border-line pt-4 font-mono text-[11px] uppercase tracking-[0.14em] text-dim">
      <div>
        <dt>First advance</dt>
        <dd className="mt-1 text-sm tracking-normal text-paper">{pool ? `${bnb(pool.firstAdvanceWei)} BNB` : "reading"}</dd>
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
  );
}

type NameBoxProps = { typed: string; onTyped: (next: string) => void; label: string; first: string | null };

export function NameBox({ typed, onTyped, label, first }: NameBoxProps) {
  const name = nameFrom(typed);
  return (
    <div>
      <label className="block font-mono text-[11px] uppercase tracking-[0.14em] text-dim" htmlFor="name">
        {label}
      </label>
      <div className="mt-2 flex items-stretch gap-2">
        <div className="flex min-w-0 flex-1 items-center rounded-lg border border-line bg-ink/60 px-3 backdrop-blur focus-within:border-accent">
          <input
            id="name"
            value={typed}
            onChange={(event) => onTyped(cleanTyped(event.target.value))}
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
    </div>
  );
}

export function LiveRow({ pool }: { pool: PoolSnapshot | null }) {
  const settled = pool ? pool.firstStep.onTime + pool.firstStep.late + pool.firstStep.missed : 0;
  const onTimeRate = pool && settled > 0 ? `${Math.floor((pool.firstStep.onTime * 100) / settled)}%` : null;
  return (
    <div className="flex flex-wrap items-center gap-x-8 gap-y-2 border-t border-line pt-4 font-mono text-[11px] uppercase tracking-[0.16em] text-dim">
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
        First advances repaid on time <b className="font-medium text-paper">{pool ? (onTimeRate ?? "none settled yet") : "reading"}</b>
      </span>
      {pool ? <span className="ml-auto hidden text-dim/70 lg:inline">Read at block {pool.block.toLocaleString("en-US")}</span> : null}
    </div>
  );
}
