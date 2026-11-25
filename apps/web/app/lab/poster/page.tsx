import type { Metadata } from "next";
import { Hero } from "@/components/Hero";
import { LabTail } from "@/components/LabTail";
import { initialPool } from "@/lib/initial";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Nan lab: the poster", robots: { index: false, follow: false } };

export default async function Page() {
  return (
    <main>
      <Hero initial={await initialPool()} />
      <LabTail current="/lab/poster" />
    </main>
  );
}
