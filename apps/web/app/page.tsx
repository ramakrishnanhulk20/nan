import { Mark } from "@/components/Mark";
import { nameCreditAddress } from "@/lib/generated/nameCredit";

export default function Home() {
  return (
    <main className="grid min-h-[100svh] place-items-center px-6">
      <div className="max-w-md text-center">
        <Mark className="mx-auto h-14 w-14 text-paper" />
        <h1 className="mt-6 font-display text-6xl font-black uppercase leading-none tracking-tight">Nan</h1>
        <p className="mt-4 text-lg text-dim">Credit on a name. The site is being built; the contract is live.</p>
        <a
          className="draw mt-6 inline-block pb-1 font-mono text-xs uppercase tracking-[0.16em] text-paper"
          href={`https://bscscan.com/address/${nameCreditAddress}`}
          target="_blank"
          rel="noreferrer"
        >
          See the contract on BNB Smart Chain
        </a>
      </div>
    </main>
  );
}
