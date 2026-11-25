/**
 * The mark: one figure standing on a line. It is the person in the hero's film still, and it is the
 * letter "i", which is what Nan means.
 */
export function Mark({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 44 44" className={className} aria-hidden="true">
      <circle cx="22" cy="22" r="21" fill="none" stroke="currentColor" strokeWidth="1.25" className="text-accent" />
      <circle cx="22" cy="13.5" r="2.6" fill="currentColor" />
      <rect x="20.3" y="18" width="3.4" height="11.5" rx="1.2" fill="currentColor" />
      <rect x="9" y="29.5" width="26" height="1.4" fill="currentColor" />
    </svg>
  );
}
