import { RootProvider } from "fumadocs-ui/provider/next";
import type { ReactNode } from "react";

export default function DocsRootLayout({ children }: { children: ReactNode }) {
  return (
    <RootProvider theme={{ enabled: false }}>
      <div className="flex min-h-screen flex-col">{children}</div>
    </RootProvider>
  );
}
