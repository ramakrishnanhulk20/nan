import type { Metadata } from "next";
import { Mark } from "@/components/Mark";

export const metadata: Metadata = { title: "Nan lab", robots: { index: false, follow: false } };

const OPTIONS = [
  {
    href: "/lab/poster",
    name: "The poster",
    from: "SpaceX and A24",
    line: "A film still, a giant title across its horizon, a credits block. Your name can replace the title.",
  },
  {
    href: "/lab/coin",
    name: "The coin",
    from: "Lusion and Ethnocare",
    line: "A real 3D coin, struck with your name. It follows the pointer and turns over when the name changes.",
  },
  {
    href: "/lab/ladder",
    name: "The ladder",
    from: "Hadrian and Kiva",
    line: "The product as a moving picture: a figure borrows, repays, and climbs steps that double in height.",
  },
] as const;

export default function Lab() {
  return (
    <main className="min-h-[100svh] px-5 py-8 md:px-10">
      <div className="flex items-center gap-3">
        <Mark className="h-11 w-11 text-paper" />
        <span className="font-display text-xl font-black uppercase tracking-[0.08em]">Nan lab</span>
      </div>
      <p className="mt-10 max-w-xl font-mono text-xs uppercase tracking-[0.16em] text-dim">
        Three first screens to choose between. Each one reads its numbers from the live contract.
      </p>
      <ol className="mt-6 border-t border-line">
        {OPTIONS.map((option, i) => (
          <li key={option.href} className="border-b border-line">
            <a href={option.href} className="group grid items-baseline gap-x-8 gap-y-2 py-7 md:grid-cols-[4rem_minmax(0,1fr)_minmax(0,1.2fr)]">
              <span className="font-mono text-sm text-dim">0{i + 1}</span>
              <span className="font-display text-6xl font-black uppercase leading-none transition-colors duration-300 group-hover:text-accent md:text-8xl">
                {option.name}
              </span>
              <span className="max-w-md text-lg leading-snug text-paper/90">
                {option.line}
                <span className="mt-2 block font-mono text-xs uppercase tracking-[0.16em] text-dim">Measured off {option.from}</span>
              </span>
            </a>
          </li>
        ))}
      </ol>
    </main>
  );
}
