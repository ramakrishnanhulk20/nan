import type { Metadata } from "next";
import { HeroCoin } from "@/components/HeroCoin";
import { LabTail } from "@/components/LabTail";
import { initialPool } from "@/lib/initial";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Nan lab: the coin", robots: { index: false, follow: false } };

export default async function Page() {
  return (
    <main>
      <HeroCoin initial={await initialPool()} />
      <LabTail current="/lab/coin" />
    </main>
  );
}
