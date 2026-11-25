const OPTIONS = [
  { href: "/lab/poster", name: "The poster" },
  { href: "/lab/coin", name: "The coin" },
  { href: "/lab/ladder", name: "The ladder" },
] as const;

/** Lab pages only: a note that nothing below the first screen exists yet, and a way across to the other options. */
export function LabTail({ current }: { current: (typeof OPTIONS)[number]["href"] }) {
  return (
    <section id="borrow" className="border-t border-line bg-ink px-5 py-20 md:px-10">
      <p className="max-w-xl font-mono text-xs uppercase tracking-[0.16em] text-dim">
        Lab page. Only the first screen is built. The sections below it come after one of these is approved.
      </p>
      <nav className="mt-6 flex flex-wrap gap-x-8 gap-y-3 font-display text-3xl font-black uppercase">
        {OPTIONS.map((option) => (
          <a
            key={option.href}
            href={option.href}
            aria-current={option.href === current ? "page" : undefined}
            className={`draw pb-1 ${option.href === current ? "text-accent" : "text-paper"}`}
          >
            {option.name}
          </a>
        ))}
      </nav>
    </section>
  );
}
