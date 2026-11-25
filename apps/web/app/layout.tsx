import type { Metadata, Viewport } from "next";
import { Big_Shoulders, Hanken_Grotesk, IBM_Plex_Mono } from "next/font/google";
import { MotionPreferences } from "@/components/MotionPreferences";
import { SmoothScroll } from "@/components/SmoothScroll";
import "./globals.css";

const display = Big_Shoulders({ subsets: ["latin"], variable: "--font-big-shoulders", display: "swap" });
const sans = Hanken_Grotesk({ subsets: ["latin"], variable: "--font-hanken", display: "swap" });
const mono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["400", "500"], variable: "--font-plex-mono", display: "swap" });

export const metadata: Metadata = {
  title: "Nan. Credit on a name.",
  description:
    "Small BNB advances for Agent ID holders, with nothing locked up. Repay on time and your limit doubles. One name per person.",
};

export const viewport: Viewport = {
  themeColor: "#06080b",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${display.variable} ${sans.variable} ${mono.variable} dark`}>
      <body className="bg-ink text-paper">
        <MotionPreferences>
          <SmoothScroll />
          {children}
        </MotionPreferences>
      </body>
    </html>
  );
}
