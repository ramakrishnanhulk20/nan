import type { Metadata } from "next";
import { Borrow } from "@/components/Borrow";
import { Outcomes } from "@/components/Outcomes";
import { SiteHeader } from "@/components/Parts";
import { initialPool } from "@/lib/initial";

export const metadata: Metadata = { title: "Nan lab", robots: { index: false, follow: false } };

export const dynamic = "force-dynamic";

export default async function Lab() {
  return (
    <main className="bg-ink">
      <SiteHeader />
      <p className="px-5 pt-8 font-mono text-xs uppercase tracking-[0.16em] text-dim md:px-10">
        Lab page. The borrow screen, then what happens if you do not repay. Both go under the first screen on the home page once approved.
      </p>
      <Borrow />
      <Outcomes initial={await initialPool()} />
    </main>
  );
}
