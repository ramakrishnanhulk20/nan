import type { Metadata } from "next";
import { Borrow } from "@/components/Borrow";
import { SiteHeader } from "@/components/Parts";

export const metadata: Metadata = { title: "Nan lab", robots: { index: false, follow: false } };

export default function Lab() {
  return (
    <main className="min-h-svh bg-ink">
      <SiteHeader />
      <p className="px-5 pt-8 font-mono text-xs uppercase tracking-[0.16em] text-dim md:px-10">
        Lab page. The borrow screen with the Agent ID registry&apos;s checks shown live. It replaces the borrow screen on the home page once approved.
      </p>
      <Borrow registryPanel />
    </main>
  );
}
