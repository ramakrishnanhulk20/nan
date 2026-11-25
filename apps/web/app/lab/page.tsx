import type { Metadata } from "next";
import { SiteHeader } from "@/components/Parts";

export const metadata: Metadata = { title: "Nan lab", robots: { index: false, follow: false } };

export default function Lab() {
  return (
    <main className="min-h-svh bg-ink">
      <SiteHeader />
      <p className="px-5 pt-8 font-mono text-xs uppercase tracking-[0.16em] text-dim md:px-10">
        Lab page. Nothing waiting for a look right now. The next section appears here before it goes on the home page.
      </p>
    </main>
  );
}
