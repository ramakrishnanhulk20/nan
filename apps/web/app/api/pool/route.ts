import { NextResponse } from "next/server";
import { readPool } from "@/lib/pool";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    return NextResponse.json(await readPool(), { headers: { "cache-control": "no-store" } });
  } catch (error) {
    console.error("pool read failed", error);
    return NextResponse.json({ error: "The chain did not answer. Try again in a few seconds." }, { status: 503 });
  }
}
