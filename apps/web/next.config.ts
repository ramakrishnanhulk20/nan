import type { NextConfig } from "next";
import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();

const config: NextConfig = {
  // A second output folder for verification builds, so they never touch the one the dev server is using.
  distDir: process.env.NEXT_DIST_DIR || ".next",
  reactStrictMode: true,
};

export default withMDX(config);
