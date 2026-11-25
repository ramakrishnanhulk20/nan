import type { Metadata } from "next";
import { Hero } from "@/components/Hero";
import { readPool, type PoolSnapshot } from "@/lib/pool";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Nan lab", robots: { index: false, follow: false } };

export default async function Lab() {
  let initial: PoolSnapshot | null = null;
  try {
    initial = await readPool();
  } catch {
    initial = null;
  }
  return (
    <main>
      <Hero initial={initial} />
      <section id="borrow" className="border-t border-line px-5 py-24 md:px-10">
        <p className="max-w-xl font-mono text-xs uppercase tracking-[0.16em] text-dim">
          Lab page. Only the first screen is built. The sections below it come after the first screen is approved.
        </p>
      </section>
    </main>
  );
}
