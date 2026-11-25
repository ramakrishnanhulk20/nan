"use client";

import { useSyncExternalStore, type ReactNode } from "react";
import { MotionConfig } from "motion/react";

const QUERY = "(prefers-reduced-motion: reduce)";

function subscribe(notify: () => void) {
  const list = window.matchMedia(QUERY);
  list.addEventListener("change", notify);
  return () => list.removeEventListener("change", notify);
}

/** True when the visitor asked for reduced motion. The server answers false, so the first browser render matches the server HTML. */
export function useStill(): boolean {
  return useSyncExternalStore(subscribe, () => window.matchMedia(QUERY).matches, () => false);
}

/** Every entrance on the site reads the visitor's motion setting from here: movement is dropped, fades stay. */
export function MotionPreferences({ children }: { children: ReactNode }) {
  return <MotionConfig reducedMotion="user">{children}</MotionConfig>;
}
