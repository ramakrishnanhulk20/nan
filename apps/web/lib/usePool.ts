"use client";

import { useEffect, useState } from "react";
import type { PoolSnapshot } from "./pool";
import { countdown } from "./format";

const POLL_MS = 15_000;

/** The pool as read from the chain, refreshed while the page is open, with a clock for countdowns. */
export function usePool(initial: PoolSnapshot | null) {
  const [pool, setPool] = useState(initial);
  const [failed, setFailed] = useState(initial === null);
  const [now, setNow] = useState(() => initial?.readAt ?? 0);

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

  return { pool, failed, now };
}

export type Status = { tone: "live" | "wait"; text: string };

/** One honest sentence about whether the pool is lending right now. */
export function statusOf(pool: PoolSnapshot | null, failed: boolean, now: number): Status {
  if (!pool) return { tone: "wait", text: failed ? "The chain is not answering. Trying again." : "Reading the chain" };
  if (pool.paused) return { tone: "wait", text: "New advances are paused. Repayments still work." };
  if (BigInt(pool.balanceWei) < BigInt(pool.firstAdvanceWei)) return { tone: "wait", text: "The pool is empty. Not lending yet." };
  if (pool.slotsNow > 0) {
    return { tone: "live", text: `Lending now. ${pool.slotsNow} first ${pool.slotsNow === 1 ? "advance" : "advances"} open.` };
  }
  return { tone: "wait", text: `Next first advance opens in ${countdown(pool.nextSlotAt, now)}` };
}

/** The amount of an advance at each step of the ladder, in wei, from the first advance up to the cap. */
export function ladderOf(pool: PoolSnapshot): bigint[] {
  const cap = BigInt(pool.capWei);
  const steps: bigint[] = [];
  let amount = BigInt(pool.firstAdvanceWei);
  while (steps.length < 12) {
    steps.push(amount > cap ? cap : amount);
    if (amount >= cap) break;
    amount *= 2n;
  }
  return steps;
}
