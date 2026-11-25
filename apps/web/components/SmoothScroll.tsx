"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";
import Lenis from "lenis";

export function SmoothScroll() {
  const pathname = usePathname();
  // Lenis swallows wheel events inside nested scroll boxes, which breaks the docs sidebar and search list.
  const onDocs = pathname.startsWith("/docs");

  useEffect(() => {
    if (onDocs) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const lenis = new Lenis({ duration: 1.1 });
    let frame = requestAnimationFrame(function tick(time) {
      lenis.raf(time);
      frame = requestAnimationFrame(tick);
    });
    return () => {
      cancelAnimationFrame(frame);
      lenis.destroy();
    };
  }, [onDocs]);
  return null;
}
