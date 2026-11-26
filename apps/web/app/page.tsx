import { Borrow } from "@/components/Borrow";
import { HeroLadder } from "@/components/HeroLadder";
import { Outcomes } from "@/components/Outcomes";
import { initialPool } from "@/lib/initial";

export const dynamic = "force-dynamic";

export default async function Home() {
  const initial = await initialPool();
  return (
    <main>
      <HeroLadder initial={initial} />
      <Borrow registryPanel />
      <Outcomes initial={initial} />
    </main>
  );
}
