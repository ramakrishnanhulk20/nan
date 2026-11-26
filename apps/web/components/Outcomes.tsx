"use client";

import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import {
  AnimatePresence,
  cubicBezier,
  motion,
  useMotionValue,
  useMotionValueEvent,
  useScroll,
  useTransform,
  type MotionValue,
} from "motion/react";
import type { PoolSnapshot } from "@/lib/pool";
import { bnb, days } from "@/lib/format";
import { nameCreditAddress } from "@/lib/generated/nameCredit";
import { usePool } from "@/lib/usePool";
import { useStill } from "./MotionPreferences";

const EASE = [0.16, 1, 0.3, 1] as const;
const ease = cubicBezier(0.16, 1, 0.3, 1);
const EASED = { clamp: true, ease };

const RING_X = 44;
const PAPER = "#f2eee6";
const DIM = "#979da6";
const WAIT = "#9db2ff";
const WIDE = "(min-width: 768px)";

type Kind = "onTime" | "late" | "never";
/** Sizes tied to the figure grow by k on phones, where the drawing is narrow. The ground sits 28 units above the bottom edge. */
type Geo = { k: number; ground: number; height: number };
type Leg = readonly [number, number];
type Hand = (v: number) => { x: number; y: number };

type Rules = {
  d: number;
  g: number;
  c: number;
  T: number;
  first: bigint;
  doubled: bigint;
  captions: string[];
  x: (day: number) => number;
};

function rulesOf(termSeconds: number, graceSeconds: number, coolingOffSeconds: number, firstAdvanceWei: string, capWei: string): Rules {
  const d = termSeconds / 86_400;
  const g = graceSeconds / 86_400;
  const c = coolingOffSeconds / 86_400;
  const T = d + g + 1 + c + 0.5;
  const first = BigInt(firstAdvanceWei);
  const cap = BigInt(capWei);
  return {
    d,
    g,
    c,
    T,
    first,
    doubled: first * 2n > cap ? cap : first * 2n,
    captions: [
      "The advance is out. Three roads from here.",
      `Due. ${days(graceSeconds)} of grace is running.`,
      "Grace is over. Two of the three have not paid.",
      "The late payer has settled and waits out the cooling-off.",
      "Two names can borrow again. One cannot.",
    ],
    x: (day) => 110 + (day / T) * 840,
  };
}

function geoOf(wide: boolean): Geo {
  const height = wide ? 150 : 190;
  return { k: wide ? 1 : 1.7, ground: height - 28, height };
}

function dayText(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

function captionIndex(v: number, { d, g, c }: Rules): number {
  if (v < d) return 0;
  if (v < d + g) return 1;
  if (v < d + g + 1) return 2;
  if (v < d + g + 1 + c) return 3;
  return 4;
}

/** 0 before a, 1 after b, eased in between. Coins and the hand they follow share it so they never drift apart. */
function ramp(v: number, a: number, b: number): number {
  return ease(Math.min(1, Math.max(0, (v - a) / (b - a))));
}

// The server cannot know the screen, so every answer starts as "no" and the browser corrects it after hydration.
function useMedia(query: string): boolean {
  const subscribe = useCallback(
    (notify: () => void) => {
      const list = window.matchMedia(query);
      list.addEventListener("change", notify);
      return () => list.removeEventListener("change", notify);
    },
    [query],
  );
  return useSyncExternalStore(subscribe, () => window.matchMedia(query).matches, () => false);
}

type DrawingProps = { day: MotionValue<number>; rules: Rules; geo: Geo };

function Figure({ fx, lift, fill, geo }: { fx: MotionValue<number>; lift?: MotionValue<number>; fill: string | MotionValue<string>; geo: Geo }) {
  return (
    <motion.g style={lift ? { x: fx, y: lift } : { x: fx }}>
      <g transform={`translate(0 ${geo.ground}) scale(${1.4 * geo.k})`}>
        <motion.circle cx="0" cy="-44" r="7.5" fill={fill} />
        <motion.rect x="-4.6" y="-33" width="9.2" height="33" rx="3" fill={fill} />
      </g>
    </motion.g>
  );
}

/** A coin that travels from the pool ring to the figure's hand, and optionally back to the ring. */
function Coin({ day, hand, geo, out, back, show, r = 9 }: { day: MotionValue<number>; hand: Hand; geo: Geo; out: Leg; back?: Leg; show?: Leg; r?: number }) {
  const ringY = geo.ground - 30 * geo.k;
  const along = (v: number) => ramp(v, out[0], out[1]) * (back ? 1 - ramp(v, back[0], back[1]) : 1);
  const cx = useTransform(day, (v) => RING_X + (hand(v).x - RING_X) * along(v));
  const cy = useTransform(day, (v) => ringY + (hand(v).y - ringY) * along(v));
  const opacity = useTransform(day, (v) => (show ? ramp(v, show[0], show[1]) : 1) * (back ? 1 - ramp(v, back[1] - 0.05, back[1]) : 1));
  return <motion.circle cx={cx} cy={cy} r={r * geo.k} fill="var(--color-accent)" style={{ opacity }} />;
}

function OnTimeDrawing({ day, rules, geo }: DrawingProps) {
  const { d, x } = rules;
  const { k, ground } = geo;
  const stand = d - 0.5;
  const standX = x(stand);
  const liftAt = (v: number) => -34 * k * ramp(v, d - 0.2, d);
  const hand: Hand = (v) => ({ x: x(Math.min(v, stand)) + 26 * k, y: ground - 70 * k + liftAt(v) });

  const fx = useTransform(day, (v) => x(Math.min(v, stand)));
  const lift = useTransform(day, liftAt);
  const blockHeight = useTransform(day, [d - 0.2, d], [0, 34 * k], EASED);
  const blockY = useTransform(blockHeight, (h) => ground - h);
  const doubleOpacity = useTransform(day, [d - 0.05, d + 0.15], [0, 1], EASED);

  return (
    <>
      <motion.rect x={standX - 23 * k} y={blockY} width={46 * k} height={blockHeight} fill="none" stroke="var(--color-paper)" strokeOpacity={0.9} />
      <Figure fx={fx} lift={lift} fill={PAPER} geo={geo} />
      <motion.text
        x={standX + 32 * k}
        y={ground - 42 * k}
        className="font-display"
        fontSize={22 * k}
        fontWeight={800}
        fill="var(--color-accent)"
        style={{ opacity: doubleOpacity }}
      >
        ×2
      </motion.text>
      <Coin day={day} hand={hand} geo={geo} out={[0, 0.4]} back={[d - 0.5, d - 0.2]} />
      <Coin day={day} hand={hand} geo={geo} out={[d, d + 0.4]} show={[d, d + 0.05]} r={12.7} />
    </>
  );
}

function LateDrawing({ day, rules, geo }: DrawingProps) {
  const { d, g, c, T, x } = rules;
  const { k, ground } = geo;
  const stop = d + g + 1;
  const hand: Hand = (v) => ({ x: x(Math.min(v, stop)) + 26 * k, y: ground - 70 * k });

  const fx = useTransform(day, (v) => x(Math.min(v, stop)));
  const dashedOpacity = useTransform(day, [d + g, d + g + 0.1], [0, 1], EASED);
  const barWidth = useTransform(day, [stop, stop + c], [0, x(stop + c) - x(stop)], { clamp: true });
  const fill = useTransform(day, [stop, stop + 0.3, stop + c, stop + c + 0.3], [PAPER, WAIT, WAIT, PAPER]);
  const endCoinOpacity = useTransform(day, [stop + c, stop + c + 0.3], [0, 1], EASED);

  return (
    <>
      <motion.line
        x1={x(d + g)}
        y1={ground}
        x2={x(T)}
        y2={ground}
        stroke="var(--color-wait)"
        strokeOpacity={0.7}
        strokeDasharray="4 6"
        style={{ opacity: dashedOpacity }}
      />
      <motion.rect x={x(stop)} y={ground - 10 * k} width={barWidth} height={10 * k} fill="var(--color-wait)" fillOpacity={0.28} />
      <Figure fx={fx} fill={fill} geo={geo} />
      <Coin day={day} hand={hand} geo={geo} out={[0, 0.4]} back={[stop, stop + 0.3]} />
      <motion.circle cx={x(stop + c)} cy={ground - 26 * k} r={9 * k} fill="var(--color-accent)" style={{ opacity: endCoinOpacity }} />
      <motion.text
        x={x(stop + c) - 16 * k}
        y={ground - 26 * k + 5 * k}
        textAnchor="end"
        className="font-mono"
        fontSize={14 * k}
        fill={WAIT}
        style={{ opacity: endCoinOpacity }}
      >
        first step again
      </motion.text>
    </>
  );
}

function NeverDrawing({ day, rules, geo }: DrawingProps) {
  const { d, g, x } = rules;
  const { k, ground } = geo;
  const stop = d + g;
  const hand: Hand = (v) => ({ x: x(Math.min(v, stop)) + 26 * k, y: ground - 70 * k });

  const fx = useTransform(day, (v) => x(Math.min(v, stop)));
  const fill = useTransform(day, [stop, stop + 0.3], [PAPER, DIM], EASED);
  const stampScale = useTransform(day, [stop, stop + 0.25], [1.6, 1], EASED);
  const stampOpacity = useTransform(day, [stop, stop + 0.1], [0, 1], EASED);

  return (
    <>
      <Figure fx={fx} fill={fill} geo={geo} />
      <Coin day={day} hand={hand} geo={geo} out={[0, 0.4]} />
      <motion.g
        style={{
          // 120k keeps the rectangle clear of the coin at the hand even at its largest, scale 1.6. At 100k it crosses the coin.
          x: x(stop) + 120 * k,
          y: ground - 64 * k,
          rotate: -6,
          scale: stampScale,
          opacity: stampOpacity,
          transformBox: "fill-box",
          transformOrigin: "center",
        }}
      >
        <rect x={-48 * k} y={-16 * k} width={96 * k} height={32 * k} fill="none" stroke="var(--color-wait)" strokeWidth={1.5 * k} />
        <text
          x={0}
          y={0}
          textAnchor="middle"
          dominantBaseline="central"
          className="font-display"
          fontSize={20 * k}
          fontWeight={800}
          letterSpacing={2 * k}
          fill="var(--color-wait)"
        >
          MISSED
        </text>
      </motion.g>
    </>
  );
}

function Ground({ kind, day, rules, geo }: DrawingProps & { kind: Kind }) {
  const { d, g, T, x } = rules;
  const { ground } = geo;
  const fade = useTransform(day, [d + g, d + g + 0.3], [0.35, 0.06], EASED);
  if (kind !== "never") {
    return <line x1={x(0)} y1={ground} x2={x(T)} y2={ground} stroke="var(--color-paper)" strokeOpacity={0.35} />;
  }
  return (
    <>
      <line x1={x(0)} y1={ground} x2={x(d + g)} y2={ground} stroke="var(--color-paper)" strokeOpacity={0.35} />
      <motion.line x1={x(d + g)} y1={ground} x2={x(T)} y2={ground} stroke="var(--color-paper)" strokeOpacity={fade} />
    </>
  );
}

function Playhead({ day, rules, geo }: DrawingProps) {
  const at = useTransform(day, (v) => rules.x(v));
  return <motion.line x1={at} y1={6} x2={at} y2={geo.ground + 16} stroke="var(--color-accent)" strokeWidth={1.25} />;
}

type LaneCopy = { kind: Kind; title: string; dot: string; text: string; counter: string };

function Lane({
  copy,
  shared,
  wide,
  still,
  rules,
  faded,
  onEnter,
  onLeave,
}: {
  copy: LaneCopy;
  shared: MotionValue<number>;
  wide: boolean;
  still: boolean;
  rules: Rules;
  faded: boolean;
  onEnter: () => void;
  onLeave: () => void;
}) {
  const drawing = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({ target: drawing, offset: ["start 0.9", "start 0.45"] });
  const own = useTransform(scrollYProgress, [0, 1], [0, rules.T], { clamp: true });
  // Reduced motion hands every lane the finished clock, so the phone path must not pick its own.
  const day = wide || still ? shared : own;
  const { d, g, T, x } = rules;
  const geo = geoOf(wide);
  const { k, ground } = geo;

  return (
    <div
      onMouseEnter={onEnter}
      onMouseLeave={onLeave}
      className="flex flex-col border-t border-line py-3 transition-opacity duration-300 ease-[var(--ease-poster)] md:grid md:grid-cols-[20rem_minmax(0,1fr)] md:gap-x-12"
      style={{ opacity: wide && faded ? 0.45 : 1 }}
    >
      <div className="contents md:block">
        <div className="order-1 flex items-center gap-3">
          <span className={`h-2 w-2 rounded-full ${copy.dot}`} aria-hidden="true" />
          <h3 className="font-display text-2xl font-extrabold uppercase leading-none">{copy.title}</h3>
        </div>
        <p className="order-3 mt-2 text-base leading-snug text-paper">{copy.text}</p>
        <p className="order-4 mt-2 font-mono text-[11px] uppercase tracking-[0.14em] text-dim">{copy.counter}</p>
      </div>

      <div ref={drawing} className="order-2 mt-2 md:mt-0">
        <svg viewBox={`0 0 1000 ${geo.height}`} className="block h-auto w-full overflow-visible" aria-hidden="true">
          <rect x={x(d)} y={14} width={x(d + g) - x(d)} height={ground - 14} fill="var(--color-paper)" fillOpacity={0.05} />
          {Array.from({ length: Math.floor(T) + 1 }, (_, i) => (
            <line key={i} x1={x(i)} y1={ground} x2={x(i)} y2={ground + 6} stroke="var(--color-paper)" strokeOpacity={0.3} />
          ))}
          <circle cx={RING_X} cy={ground - 30 * k} r={22 * k} fill="none" stroke="var(--color-paper)" strokeOpacity={0.45} />
          <circle cx={RING_X} cy={ground - 30 * k} r={15 * k} fill="none" stroke="var(--color-paper)" strokeOpacity={0.16} strokeDasharray="3 6" />
          <Ground kind={copy.kind} day={day} rules={rules} geo={geo} />
          {still ? null : <Playhead day={day} rules={rules} geo={geo} />}
          {copy.kind === "onTime" ? <OnTimeDrawing day={day} rules={rules} geo={geo} /> : null}
          {copy.kind === "late" ? <LateDrawing day={day} rules={rules} geo={geo} /> : null}
          {copy.kind === "never" ? <NeverDrawing day={day} rules={rules} geo={geo} /> : null}
        </svg>
      </div>
    </div>
  );
}

function DayLabels({ rules }: { rules: Rules }) {
  const { d, g, c, x } = rules;
  const label = "absolute font-mono text-[11px] uppercase tracking-[0.14em] text-dim whitespace-nowrap";
  const left = (day: number) => ({ left: `${x(day) / 10}%` });
  const end = d + g + 1 + c;
  return (
    <div className="relative h-12">
      <span className={`${label} top-0 border-l border-line pl-2`} style={{ left: "4.4%" }}>
        Pool
      </span>
      <span className={`${label} top-0 border-l border-line pl-2`} style={left(d)}>
        Due · day {dayText(d)}
      </span>
      <span className={`${label} top-0 border-r border-line pr-2`} style={{ right: `${100 - x(end) / 10}%` }}>
        Day {dayText(end)}
      </span>
      <span className={`${label} top-6 border-l border-line pl-2`} style={left(0)}>
        Borrow
      </span>
      <span className={`${label} top-6 border-l border-line pl-2`} style={left(d + g)}>
        Grace ends · day {dayText(d + g)}
      </span>
    </div>
  );
}

function Legend({ className }: { className: string }) {
  return (
    <div className={`flex flex-wrap gap-x-6 gap-y-2 font-mono text-[11px] uppercase tracking-[0.14em] text-dim ${className}`}>
      <span className="inline-flex items-center gap-2">
        <span className="h-2.5 w-2.5 shrink-0 rounded-full bg-accent" aria-hidden="true" />
        The advance
      </span>
      <span className="inline-flex items-center gap-2">
        <span className="h-3 w-3 shrink-0 rounded-full border border-paper/45" aria-hidden="true" />
        The pool
      </span>
    </div>
  );
}

function ClockRow({ day, rules }: { day: MotionValue<number>; rules: Rules }) {
  const whole = useTransform(day, (v) => Math.floor(v));
  const hint = useTransform(day, [0, 0.3], [1, 0]);
  const [index, setIndex] = useState(() => captionIndex(day.get(), rules));

  useMotionValueEvent(day, "change", (v) => {
    const next = captionIndex(v, rules);
    if (next !== index) setIndex(next);
  });

  // A switch to the finished clock (reduced motion) fires no change event, so the caption is read again here.
  useEffect(() => {
    setIndex(captionIndex(day.get(), rules));
  }, [day, rules]);

  return (
    <>
      <div className="hidden md:grid md:grid-cols-[20rem_minmax(0,1fr)] md:gap-x-12">
        <div>
          <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-dim">Day</p>
          <p className="mt-2 block font-display font-black leading-[0.8] text-paper" style={{ fontSize: "clamp(3.5rem, 7vw, 6.5rem)" }}>
            <motion.span>{whole}</motion.span>
          </p>
          <div className="mt-3 min-h-12 text-base leading-snug text-dim">
            <AnimatePresence mode="wait">
              <motion.p
                key={index}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -8 }}
                transition={{ duration: 0.35, ease: EASE }}
              >
                {rules.captions[index]}
              </motion.p>
            </AnimatePresence>
          </div>
          <Legend className="mt-4" />
        </div>
        <div className="self-end">
          <DayLabels rules={rules} />
        </div>
      </div>
      <motion.p
        className="hidden font-mono text-[11px] uppercase tracking-[0.16em] text-dim md:block"
        style={{ opacity: hint }}
      >
        Scroll to run the clock
      </motion.p>
    </>
  );
}

function Stage({ pool }: { pool: PoolSnapshot }) {
  const { termSeconds, graceSeconds, coolingOffSeconds, firstAdvanceWei, capWei } = pool;
  const rules = useMemo(
    () => rulesOf(termSeconds, graceSeconds, coolingOffSeconds, firstAdvanceWei, capWei),
    [termSeconds, graceSeconds, coolingOffSeconds, firstAdvanceWei, capWei],
  );
  const wide = useMedia(WIDE);
  const still = useStill();
  const track = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({ target: track, offset: ["start start", "end end"] });
  const scrolled = useTransform(scrollYProgress, [0.06, 0.94], [0, rules.T], { clamp: true });
  const finished = useMotionValue(rules.T);
  useEffect(() => finished.set(rules.T), [finished, rules.T]);
  const day = still ? finished : scrolled;
  const [hovered, setHovered] = useState<Kind | null>(null);

  const sum = (key: "onTime" | "late" | "missed") => pool.byStep.reduce((total, step) => total + step[key], 0);
  const lanes: LaneCopy[] = [
    {
      kind: "onTime",
      title: "On time",
      dot: "bg-live",
      text: `Repaid by the end of grace. The limit doubles to ${bnb(rules.doubled.toString(), 18)} BNB, and the name can borrow again from day ${dayText(rules.d)}.`,
      counter: `So far: ${sum("onTime")} on time`,
    },
    {
      kind: "late",
      title: "Late",
      dot: "bg-wait",
      text: `Repaid after the grace. The debt is settled, and the name restarts at the first step, ${bnb(rules.first.toString(), 18)} BNB, after waiting ${days(coolingOffSeconds)}.`,
      counter: `So far: ${sum("late")} late`,
    },
    {
      kind: "never",
      title: "Never",
      dot: "bg-dim",
      text: "Not repaid. After the grace anyone can mark it missed, in public, and the name cannot borrow here again until it pays. One wallet holds one Agent ID for good: it cannot be sold, moved or swapped for a clean one.",
      counter: `So far: ${sum("missed")} missed`,
    },
  ];

  return (
    <div ref={track} className={`relative ${still ? "" : "md:h-[360vh]"}`}>
      <div
        className={`px-5 py-10 md:px-10 md:py-6 ${still ? "" : "md:sticky md:top-0 md:flex md:h-[100svh] md:flex-col md:justify-center"}`}
      >
        <ClockRow day={day} rules={rules} />
        <div className="md:hidden">
          <Legend className="mb-3" />
          <DayLabels rules={rules} />
        </div>
        {lanes.map((copy) => (
          <Lane
            key={copy.kind}
            copy={copy}
            shared={day}
            wide={wide}
            still={still}
            rules={rules}
            faded={hovered !== null && hovered !== copy.kind}
            onEnter={() => setHovered(copy.kind)}
            onLeave={() => setHovered(null)}
          />
        ))}
      </div>
    </div>
  );
}

export function Outcomes({ initial }: { initial: PoolSnapshot | null }) {
  const { pool } = usePool(initial);

  return (
    <section id="outcomes" className="relative grain overflow-clip border-t border-line bg-night">
      <motion.div
        className="px-5 pt-20 md:px-10 md:pt-28"
        initial={{ opacity: 0, y: 24 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: "-15%" }}
        transition={{ duration: 0.9, ease: EASE }}
      >
        <p className="font-mono text-xs uppercase tracking-[0.18em] text-dim">If you do not repay</p>
        <h2 className="mt-3 font-display font-black uppercase leading-[0.86] tracking-[-0.01em]" style={{ fontSize: "clamp(2.6rem, 7.2vw, 7rem)" }}>
          Nothing locked up.
          <br />
          <span className="text-accent">The name is on the line.</span>
        </h2>
        <p className="mt-5 max-w-2xl text-lg leading-snug text-paper md:text-xl">
          No collateral is taken and no interest is charged. What stands behind an advance is the name&apos;s own record, out in the
          open. Scroll to run the clock on one advance, three ways.
        </p>
      </motion.div>

      {pool ? (
        <>
          <Stage pool={pool} />
          <div className="px-5 pb-20 pt-6 md:px-10 md:pb-28">
            <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-dim">
              Term {days(pool.termSeconds)} · grace {days(pool.graceSeconds)} · cooling-off {days(pool.coolingOffSeconds)} · read from the
              contract at block {pool.block}
            </p>
            <a
              className="draw mt-3 inline-block pb-1 font-mono text-xs uppercase tracking-[0.16em] text-paper"
              href={`https://bscscan.com/address/${nameCreditAddress}#code`}
              target="_blank"
              rel="noreferrer"
            >
              Read the rules in the verified source
            </a>
          </div>
        </>
      ) : (
        <p className="px-5 pb-20 pt-6 text-dim md:px-10 md:pb-28">Reading the rules from the contract.</p>
      )}
    </section>
  );
}
