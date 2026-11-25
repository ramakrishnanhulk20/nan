"use client";

import { useState } from "react";
import dynamic from "next/dynamic";
import { motion, useReducedMotion } from "motion/react";
import type { PoolSnapshot } from "@/lib/pool";
import { bnb, nameFrom } from "@/lib/format";
import { statusOf, usePool } from "@/lib/usePool";
import { Facts, LiveRow, NameBox, SiteHeader, StatusLine } from "./Parts";

const Coin = dynamic(() => import("./Coin"), { ssr: false });
const EASE = [0.16, 1, 0.3, 1] as const;

export function HeroCoin({ initial }: { initial: PoolSnapshot | null }) {
  const { pool, failed, now } = usePool(initial);
  const [typed, setTyped] = useState("");
  const still = useReducedMotion() ?? false;
  const name = nameFrom(typed);
  const first = pool ? bnb(pool.firstAdvanceWei) : null;

  const rise = (delay: number) =>
    still ? {} : { initial: { opacity: 0, y: 24 }, animate: { opacity: 1, y: 0 }, transition: { duration: 0.9, delay, ease: EASE } };

  return (
    <section className="grain relative isolate min-h-[100svh] overflow-hidden bg-ink">
      <div
        className="pointer-events-none absolute left-1/2 top-[30svh] h-[90svh] w-[90svh] -translate-x-1/2 -translate-y-1/2 rounded-full opacity-70 blur-3xl md:left-[70%] md:top-1/2"
        style={{ background: "radial-gradient(closest-side, rgb(255 77 31 / 0.32), rgb(255 77 31 / 0.08) 55%, transparent)" }}
        aria-hidden="true"
      />

      <SiteHeader />

      <div className="relative z-10 grid min-h-[calc(100svh-9.5rem)] items-center gap-x-6 px-5 pb-6 pt-4 md:grid-cols-[minmax(0,1.05fr)_minmax(0,1fr)] md:px-10">
        <motion.div
          className="relative order-1 h-[44svh] md:order-2 md:h-[72svh]"
          initial={still ? false : { opacity: 0, scale: 0.86, rotate: -8 }}
          animate={{ opacity: 1, scale: 1, rotate: 0 }}
          transition={{ duration: 1.6, ease: EASE }}
        >
          <Coin name={name} amount={first} still={still} />
        </motion.div>

        <div className="order-2 md:order-1">
          <motion.div {...rise(0.3)}>
            <StatusLine status={statusOf(pool, failed, now)} />
          </motion.div>
          <motion.h1
            {...rise(0.45)}
            className="mt-4 font-display font-black uppercase leading-[0.82] tracking-[-0.015em] text-paper"
            style={{ fontSize: "clamp(3.6rem, 10.5vw, 10.5rem)" }}
          >
            Your name
            <br />
            is the <span className="text-accent">coin</span>
          </motion.h1>
          <motion.p {...rise(0.6)} className="mt-5 max-w-xl text-lg leading-snug text-paper md:text-xl">
            Nan is Tamil for I. Borrow a little BNB on your Agent ID name alone, with nothing locked up. Repay on time and the
            coin is worth twice as much next time.
          </motion.p>
          <motion.div {...rise(0.75)} className="mt-6 max-w-xl">
            <Facts pool={pool} />
            <div className="mt-5">
              <NameBox typed={typed} onTyped={setTyped} label="Strike a coin with your name" first={first} />
            </div>
          </motion.div>
        </div>
      </div>

      <motion.div {...rise(0.95)} className="relative z-10 px-5 pb-6 md:px-10 md:pb-8">
        <LiveRow pool={pool} />
      </motion.div>
    </section>
  );
}
