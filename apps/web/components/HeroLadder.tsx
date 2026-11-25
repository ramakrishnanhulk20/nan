"use client";

import { useEffect, useState } from "react";
import { motion } from "motion/react";
import type { PoolSnapshot } from "@/lib/pool";
import { bnb, days, nameFrom } from "@/lib/format";
import { ladderOf, statusOf, usePool } from "@/lib/usePool";
import { useStill } from "./MotionPreferences";
import { Facts, LiveRow, NameBox, SiteHeader, StatusLine } from "./Parts";

const EASE = [0.16, 1, 0.3, 1] as const;

const BASE = 520;
const BAR = 118;
const GAP = 22;
const LEFT = 150;
const TALLEST = 400;
const VAULT = { x: 72, y: 98, r: 46 };

type Phase = "borrow" | "hold" | "repay" | "rise" | "top";
const LASTS: Record<Phase, number> = { borrow: 1100, hold: 1300, repay: 1100, rise: 900, top: 2600 };

function Ladder({ pool, still }: { pool: PoolSnapshot | null; still: boolean }) {
  const steps = pool ? ladderOf(pool) : [];
  const count = steps.length || 5;
  const unit = TALLEST / 2 ** (count - 1);
  const height = (i: number) => unit * 2 ** i;
  const centre = (i: number) => LEFT + i * (BAR + GAP) + BAR / 2;

  const [loop, setLoop] = useState<{ step: number; phase: Phase }>({ step: 0, phase: "borrow" });
  // Reduced motion shows the finished ladder and never starts the loop. The loop state stays put so the first render matches the server.
  const at: { step: number; phase: Phase } = still ? { step: count - 1, phase: "top" } : loop;

  useEffect(() => {
    if (still || !pool) return;
    const timer = setTimeout(() => {
      setLoop(({ step, phase }) => {
        if (phase === "borrow") return { step, phase: "hold" };
        if (phase === "hold") return { step, phase: "repay" };
        if (phase === "repay") return step === count - 1 ? { step, phase: "top" } : { step, phase: "rise" };
        if (phase === "rise") return { step: step + 1, phase: "borrow" };
        return { step: 0, phase: "borrow" };
      });
    }, LASTS[loop.phase]);
    return () => clearTimeout(timer);
  }, [loop, still, pool, count]);

  const standing = at.phase === "rise" ? Math.min(at.step + 1, count - 1) : at.step;
  const fx = centre(standing);
  const fy = BASE - height(standing);
  const coinAtFigure = at.phase === "borrow" || at.phase === "hold";
  const amount = (i: number) => (steps[i] !== undefined ? bnb(steps[i].toString()) : null);

  let caption = "Reading the chain";
  if (pool) {
    if (at.phase === "borrow") caption = `Borrow ${amount(at.step)} BNB. Nothing locked.`;
    if (at.phase === "hold") caption = `${days(pool.termSeconds)} to repay.`;
    if (at.phase === "repay") caption = "Repaid on time.";
    if (at.phase === "rise") caption = `Limit doubles to ${amount(Math.min(at.step + 1, count - 1))} BNB.`;
    if (at.phase === "top") caption = `${amount(count - 1)} BNB is the top. It stays yours while you keep repaying.`;
  }

  return (
    <figure className="relative">
      <svg
        viewBox="0 0 880 600"
        preserveAspectRatio="xMaxYMax meet"
        className="h-auto w-full md:max-h-[50svh]"
        role="img"
        aria-label="A figure borrows, repays on time, and climbs steps that double in height."
      >
        <defs>
          <linearGradient id="lit" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#ff4d1f" stopOpacity="0.5" />
            <stop offset="1" stopColor="#ff4d1f" stopOpacity="0.06" />
          </linearGradient>
          <filter id="glow" x="-200%" y="-200%" width="500%" height="500%">
            <feGaussianBlur stdDeviation="7" result="b" />
            <feMerge>
              <feMergeNode in="b" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        <line x1="20" y1={BASE} x2="860" y2={BASE} stroke="#f2eee6" strokeOpacity="0.35" />

        <g fontFamily="var(--font-mono)" fill="#979da6" fontSize="14" letterSpacing="1.6">
          <circle cx={VAULT.x} cy={VAULT.y} r={VAULT.r} fill="none" stroke="#f2eee6" strokeOpacity="0.45" />
          <circle cx={VAULT.x} cy={VAULT.y} r={VAULT.r - 9} fill="none" stroke="#f2eee6" strokeOpacity="0.16" strokeDasharray="3 6" />
          <text x={VAULT.x} y={VAULT.y - 4} textAnchor="middle">
            POOL
          </text>
          <text x={VAULT.x} y={VAULT.y + 16} textAnchor="middle" fill="#f2eee6" letterSpacing="0">
            {pool ? bnb(pool.balanceWei) : "reading"}
          </text>
        </g>

        {Array.from({ length: count }, (_, i) => {
          const x = LEFT + i * (BAR + GAP);
          const h = height(i);
          const lit = i < standing || (i === standing && at.phase !== "borrow") || at.phase === "top";
          return (
            <g key={i}>
              <motion.rect
                x={x}
                y={BASE - h}
                width={BAR}
                height={h}
                fill="url(#lit)"
                initial={false}
                animate={{ opacity: lit ? 1 : 0 }}
                transition={{ duration: 0.6, ease: EASE }}
              />
              <rect x={x} y={BASE - h} width={BAR} height={h} fill="none" stroke="#f2eee6" strokeOpacity={i === standing ? 0.9 : 0.32} />
              {i > 0 ? (
                <text
                  x={x - GAP / 2}
                  y={BASE - h - 12}
                  textAnchor="middle"
                  fontFamily="var(--font-display)"
                  fontWeight="900"
                  fontSize="26"
                  fill={i <= standing ? "#ff4d1f" : "#f2eee6"}
                  fillOpacity={i <= standing ? 1 : 0.28}
                >
                  ×2
                </text>
              ) : null}
              <text
                className="hidden md:block"
                x={x + BAR / 2}
                y={BASE + 26}
                textAnchor="middle"
                fontFamily="var(--font-mono)"
                fontSize="12"
                letterSpacing="1.6"
                fill="#979da6"
              >
                STEP {i + 1}
              </text>
              <text
                className="hidden md:block"
                x={x + BAR / 2}
                y={BASE + 48}
                textAnchor="middle"
                fontFamily="var(--font-mono)"
                fontSize="15"
                fill={i === standing ? "#f2eee6" : "#979da6"}
              >
                {amount(i) ?? ""}
              </text>
              <text
                className="md:hidden"
                x={x + BAR / 2}
                y={BASE + 40}
                textAnchor="middle"
                fontFamily="var(--font-mono)"
                fontSize="25"
                fill={i === standing ? "#f2eee6" : "#979da6"}
              >
                {amount(i) ?? ""}
              </text>
            </g>
          );
        })}

        <motion.g initial={false} animate={{ x: fx, y: fy }} transition={{ type: "spring", stiffness: 90, damping: 14 }}>
          <g transform="scale(1.4)">
            <circle cx="0" cy="-44" r="7.5" fill="#f2eee6" />
            <rect x="-4.6" y="-33" width="9.2" height="33" rx="3" fill="#f2eee6" />
            {at.phase === "hold" ? (
              <motion.circle
                cx="0"
                cy="-44"
                r="16"
                fill="none"
                stroke="#9db2ff"
                strokeWidth="2"
                strokeLinecap="round"
                transform="rotate(-90 0 -44)"
                initial={{ pathLength: 0 }}
                animate={{ pathLength: 1 }}
                transition={{ duration: LASTS.hold / 1000, ease: "linear" }}
              />
            ) : null}
          </g>
        </motion.g>

        {pool && !still ? (
          <motion.circle
            r="11"
            fill="#ff4d1f"
            filter="url(#glow)"
            initial={false}
            animate={{
              cx: coinAtFigure ? fx + 34 : VAULT.x,
              cy: coinAtFigure ? fy - 62 : VAULT.y + VAULT.r + 16,
              opacity: at.phase === "rise" || at.phase === "top" ? 0 : 1,
            }}
            transition={{ duration: 0.95, ease: [0.65, 0, 0.35, 1] }}
          />
        ) : null}
      </svg>
      <figcaption className="mt-2 min-h-7 font-mono text-sm text-paper" aria-live="polite">
        {caption}
      </figcaption>
    </figure>
  );
}

export function HeroLadder({ initial }: { initial: PoolSnapshot | null }) {
  const { pool, failed, now } = usePool(initial);
  const [typed, setTyped] = useState("");
  const still = useStill();
  const first = pool ? bnb(pool.firstAdvanceWei) : null;
  const name = nameFrom(typed);

  const rise = (delay: number) => ({
    initial: { opacity: 0, y: 24 },
    animate: { opacity: 1, y: 0 },
    transition: { duration: 0.9, delay, ease: EASE },
  });

  return (
    <section
      className="grain relative isolate flex min-h-[100svh] flex-col overflow-hidden bg-night md:h-[100svh] md:min-h-[780px]"
      style={{
        backgroundImage:
          "linear-gradient(rgb(242 238 230 / 0.035) 1px, transparent 1px), linear-gradient(90deg, rgb(242 238 230 / 0.035) 1px, transparent 1px)",
        backgroundSize: "64px 64px",
      }}
    >
      <SiteHeader />

      <div className="relative z-10 shrink-0 px-5 pt-8 md:px-10 md:pt-6">
        <motion.div {...rise(0.2)}>
          <StatusLine status={statusOf(pool, failed, now)} />
        </motion.div>
        <motion.h1
          {...rise(0.35)}
          className="mt-4 font-display font-black uppercase leading-[0.84] tracking-[-0.015em] text-paper"
          style={{ fontSize: "clamp(2.7rem, min(8vw, 15svh), 8.4rem)" }}
        >
          Repay on time.
          <br />
          <span className="text-accent">Your limit doubles.</span>
        </motion.h1>
      </div>

      <div className="relative z-10 grid min-h-0 flex-1 items-end gap-x-10 gap-y-8 px-5 pb-6 pt-6 md:grid-cols-[minmax(0,0.85fr)_minmax(0,1.15fr)] md:px-10 md:pt-2">
        <div className="order-2 md:order-1">
          <motion.p {...rise(0.5)} className="max-w-xl text-lg leading-snug text-paper md:text-xl">
            {name ? `${name}.ai` : "Your Agent ID name"} borrows a little BNB with nothing locked up. Each repayment on time
            moves it one step up, and each step is twice the last.
          </motion.p>
          <motion.div {...rise(0.65)} className="mt-6 max-w-xl">
            <Facts pool={pool} />
            <div className="mt-5">
              <NameBox typed={typed} onTyped={setTyped} label="Your Agent ID name" first={first} />
            </div>
          </motion.div>
        </div>

        <motion.div {...rise(0.5)} className="order-1 md:order-2 md:ml-auto md:w-full md:max-w-[44rem]">
          <Ladder key={pool ? "live" : "waiting"} pool={pool} still={still} />
        </motion.div>
      </div>

      <motion.div {...rise(0.9)} className="relative z-10 shrink-0 px-5 pb-6 md:px-10">
        <LiveRow pool={pool} />
      </motion.div>
    </section>
  );
}
