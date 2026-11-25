import type { Metadata } from "next";
import { Borrow } from "@/components/Borrow";
import { SiteHeader } from "@/components/Parts";

export const metadata: Metadata = { title: "Nan lab", robots: { index: false, follow: false } };

export default function Lab() {
  return (
    <main className="bg-ink">
      <SiteHeader />
      <p className="px-5 pt-8 font-mono text-xs uppercase tracking-[0.16em] text-dim md:px-10">
        Lab page. The borrow screen, before it goes under the first screen on the home page.
      </p>
      <Borrow />
    </main>
  );
}
