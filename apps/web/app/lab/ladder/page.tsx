import type { Metadata } from "next";
import { HeroLadder } from "@/components/HeroLadder";
import { LabTail } from "@/components/LabTail";
import { initialPool } from "@/lib/initial";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Nan lab: the ladder", robots: { index: false, follow: false } };

export default async function Page() {
  return (
    <main>
      <HeroLadder initial={await initialPool()} />
      <LabTail current="/lab/ladder" />
    </main>
  );
}
