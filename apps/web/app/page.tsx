import { HeroLadder } from "@/components/HeroLadder";
import { initialPool } from "@/lib/initial";
import { nameCreditAddress } from "@/lib/generated/nameCredit";

export const dynamic = "force-dynamic";

export default async function Home() {
  return (
    <main>
      <HeroLadder initial={await initialPool()} />
      <section id="borrow" className="border-t border-line bg-ink px-5 py-20 md:px-10">
        <p className="max-w-xl text-lg leading-snug text-paper">
          The borrow screen is being built. The contract is already live, and anyone can read it.
        </p>
        <a
          className="draw mt-4 inline-block pb-1 font-mono text-xs uppercase tracking-[0.16em] text-paper"
          href={`https://bscscan.com/address/${nameCreditAddress}`}
          target="_blank"
          rel="noreferrer"
        >
          See the contract on BNB Smart Chain
        </a>
      </section>
    </main>
  );
}
