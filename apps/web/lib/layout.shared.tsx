import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { Mark } from "@/components/Mark";

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: (
        <span className="flex items-center gap-2">
          <Mark className="h-7 w-7 text-paper" />
          <span className="font-display text-xl font-extrabold uppercase tracking-[0.02em]">Nan</span>
        </span>
      ),
      url: "/",
    },
    themeSwitch: { enabled: false },
  };
}
