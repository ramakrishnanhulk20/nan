// Makes single-use pass codes for the pool's owner to register with addPasses.
// Each code is 32 bytes from the system's random source. The codes are written to a private file under
// passes/, which git ignores. Only their hashes go to the chain, so a code stays secret until it is used.
//
// Run from the repo root:  node tools/passes.mjs <how many> <days valid>
// Needs Node 18 or newer and Foundry's cast. It sends nothing: it prints what the owner sends.
//
// Never register the same code on two deployments or two chains. The hash on chain does not include the
// contract's address, so a code that has been seen in a transaction on one could be used on the other.
import { randomBytes } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";

const MAX_BATCH = 200;
const count = Number(process.argv[2]);
const days = Number(process.argv[3]);
if (!Number.isInteger(count) || count < 1 || count > MAX_BATCH || !Number.isInteger(days) || days < 1 || days > 365) {
  console.error(`usage: node tools/passes.mjs <how many, 1 to ${MAX_BATCH}> <days valid, 1 to 365>`);
  process.exit(1);
}

const cast = (args) => execFileSync("cast", args, { encoding: "utf8" }).trim();
const expires = Math.floor(Date.now() / 1000) + days * 86400;

const passes = [];
for (let i = 0; i < count; i++) {
  const code = "0x" + randomBytes(32).toString("hex");
  // The contract checks keccak256(abi.encode(code)), and the encoding of 32 bytes is those same 32 bytes.
  passes.push({ code, hash: cast(["keccak", code]), givenTo: "" });
}
if (new Set(passes.map((p) => p.hash)).size !== count) throw new Error("two passes came out the same, which should be impossible: run it again");

const hashes = `[${passes.map((p) => p.hash).join(",")}]`;
const calldata = cast(["calldata", "addPasses(bytes32[],uint40)", hashes, String(expires)]);

const dir = resolve("passes");
mkdirSync(dir, { recursive: true });
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const file = join(dir, `passes-${stamp}.json`);
if (existsSync(file)) throw new Error("that file already exists: run it again");
writeFileSync(file, JSON.stringify({ created: new Date().toISOString(), expires, expiresAt: new Date(expires * 1000).toISOString(), registeredOn: "", passes }, null, 2) + "\n");

console.log(`${count} pass codes written to ${file}`);
console.log("Keep that file private. Hand out one code per person, and note who got it in the file.");
console.log("");
console.log("To register them, the owner calls addPasses on the pool with:");
console.log(`  passHashes: ${hashes}`);
console.log(`  expires:    ${expires}   (${new Date(expires * 1000).toISOString()})`);
console.log("");
console.log("The same call as one piece of hex data, for a wallet that sends raw data to the pool's address with 0 BNB:");
console.log(`  ${calldata}`);
