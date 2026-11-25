import { NextResponse } from "next/server";
import { getAddress, isAddress } from "viem";
import { readWallet } from "@/lib/wallet";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const raw = new URL(request.url).searchParams.get("address") ?? "";
  if (!isAddress(raw, { strict: false })) {
    return NextResponse.json({ error: "That is not a wallet address. It starts with 0x and has 40 more characters." }, { status: 400 });
  }
  try {
    return NextResponse.json(await readWallet(getAddress(raw)), { headers: { "cache-control": "no-store" } });
  } catch (error) {
    console.error("wallet read failed", error);
    return NextResponse.json({ error: "The chain did not answer. Try again in a few seconds." }, { status: 503 });
  }
}
