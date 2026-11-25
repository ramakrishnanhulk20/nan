const WEI_PER_BNB = 10n ** 18n;

/** BNB with up to `places` decimals, cut and never rounded up: a pool must not look fuller than it is. */
export function bnb(wei: string, places = 4): string {
  const value = BigInt(wei);
  const whole = value / WEI_PER_BNB;
  const fraction = (value % WEI_PER_BNB).toString().padStart(18, "0").slice(0, places).replace(/0+$/, "");
  return fraction ? `${whole}.${fraction}` : whole.toString();
}

export function days(seconds: number): string {
  const d = seconds / 86_400;
  if (Number.isInteger(d)) return d === 1 ? "1 day" : `${d} days`;
  const h = Math.round(seconds / 3_600);
  return h === 1 ? "1 hour" : `${h} hours`;
}

export function countdown(untilUnix: number, nowMs: number): string {
  const left = Math.max(0, untilUnix - Math.floor(nowMs / 1000));
  const m = Math.floor(left / 60);
  const s = left % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

/** What a visitor may type in the name box: lower case letters, digits, and a dot so that "name.ai" can be typed whole. */
export function cleanTyped(raw: string): string {
  return raw.toLowerCase().replace(/[^a-z0-9.]/g, "").slice(0, 23);
}

/** The Agent ID name inside what was typed, as the registry allows it: letters and digits before any dot, 20 at most. */
export function nameFrom(typed: string): string {
  return typed.split(".")[0].slice(0, 20);
}
