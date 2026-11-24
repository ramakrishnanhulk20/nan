// Breaks NameCredit.sol on purpose, one rule at a time, and checks that the test suite notices every time.
// It works on a private copy in the system temp folder. The real source is never touched.
// Run from the repo root:  node security/mutation.mjs
// Needs Foundry and Node 18 or newer. Takes about fifteen minutes. Writes security/outputs/mutation.txt.
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, rmSync, mkdirSync, cpSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const root = resolve(".");
const real = join(root, "packages", "contracts");
const work = mkdtempSync(join(tmpdir(), "namecredit-mutation-"));
const outFile = join(root, "security", "outputs", "mutation.txt");

for (const item of ["src", "test", "dependencies", "foundry.toml", "remappings.txt", "soldeer.lock"]) {
  cpSync(join(real, item), join(work, item), { recursive: true });
}
mkdirSync(join(work, "deployments"), { recursive: true });
mkdirSync(join(root, "security", "outputs"), { recursive: true });

const target = join(work, "src", "NameCredit.sol");
const original = readFileSync(target, "utf8").replace(/\r\n/g, "\n");

// [what the break does, the exact source text to find, what to put in its place]
const MUTATIONS = [
  ["on-time boundary moved by one second", "bool onTime = block.timestamp <= uint256(due) + GRACE;", "bool onTime = block.timestamp < uint256(due) + GRACE;"],
  ["one advance per term removed", "if (due > a.notBefore) a.notBefore = due;", ""],
  ["newcomers' reserve removed", "return step == 0 ? 0 : uint256(s.pacePerDay) * s.firstAdvance;", "return step == 0 ? 0 : 0 * uint256(s.pacePerDay) * s.firstAdvance;"],
  ["a pass can be used again", "delete _passExpiry[passHash];\n        return _borrow(true);", "return _borrow(true);"],
  ["name's owner not compared with the caller", "abi.decode(out, (uint256)) != uint256(uint160(who))) return bytes32(0);", "abi.decode(out, (uint256)) == 0) return bytes32(0);"],
  ["late repayment keeps the step", "a.step = 0;\n            a.notBefore = (block.timestamp + COOLING_OFF).toUint40();", "a.notBefore = (block.timestamp + COOLING_OFF).toUint40();"],
  ["no cooling-off after a late repayment", "a.notBefore = (block.timestamp + COOLING_OFF).toUint40();", ""],
  ["markMissed allowed one second early", "if (block.timestamp <= overdueAt) revert NotOverdue(overdueAt);", "if (block.timestamp < overdueAt) revert NotOverdue(overdueAt);"],
  ["second advance while one is open", "if (a.owed != 0) revert AdvanceOpen(a.owed);", ""],
  ["pace never used up", "_paceCredit = (credit - SLOT).toUint64();", "_paceCredit = credit.toUint64();"],
  ["oversized registry reply accepted", "if (size > maxReturn) ok = false;", ""],
  ["settings applied without the delay", "if (block.timestamp < effectiveAt) revert TooSoon(effectiveAt);", ""],
  ["anyone can withdraw", "function withdraw(uint256 amount) external nonReentrant onlyOwner {", "function withdraw(uint256 amount) external nonReentrant {"],
  ["step keeps rising at the cap", "if (step < MAX_STEP && _limit(step, s) < s.cap) a.step = step + 1;", "if (step < MAX_STEP) a.step = step + 1;"],
  ["missed count not corrected on late repayment", "--_stepTally[step].missed;", ""],
  ["non-canonical name reply accepted", "if (out.length != 64 + ((length + 31) & ~uint256(31))) return bytes32(0);", ""],
  ["name length ceiling removed", "length == 0 || length > MAX_NAME_LENGTH", "length == 0"],
  ["stored pace has no ceiling", "if (credit > ceiling) credit = ceiling;", ""],
  ["a changed name is accepted", "} else if (a.nameHash != nameHash) {\n            revert NameMismatch();\n        }", "}"],
  ["repayment can be paused", "function repay(address borrower) external payable nonReentrant {", "function repay(address borrower) external payable nonReentrant whenNotPaused {"],
  ["repayment does not clear the debt", "a.owed = 0;\n        a.due = 0;", "a.due = 0;"],
  ["limit grows in a line, not by doubling", "uint256 doubled = uint256(s.firstAdvance) << step;", "uint256 doubled = uint256(s.firstAdvance) * (uint256(step) + 1);"],
  ["extra BNB kept instead of returned", "if (extra != 0) {", "if (extra > type(uint256).max - 1) {"],
  ["zero balance in the registry accepted", "if (!ok || out.length != 32 || abi.decode(out, (uint256)) == 0) return bytes32(0);", "if (!ok || out.length != 32) return bytes32(0);"],
  ["anyone can top up", "function topUp() external payable onlyOwner {", "function topUp() external payable {"],
  ["an advance can be marked missed twice", "if (a.missed) revert AlreadyMarked();", ""],
  ["expired pass accepted", "if (expires == 0 || expires < block.timestamp) revert BadPass();", "if (expires == 0) revert BadPass();"],
  ["release pace never checked", "if (step == 0 && !withPass) {", "if (step == 0 && !withPass && block.timestamp == 0) {"],
  ["plain transfers accepted", "revert DirectTransfer();", ""],
  ["registry read has no gas ceiling", "staticcall(REGISTRY_GAS, registry,", "staticcall(gas(), registry,"],
  ["outstanding total not reduced on repayment", "_totals.outstanding -= owed.toUint128();", ""],
  ["empty pool not checked before paying out", "if (available < needed) revert PoolEmpty(needed, available);", ""],
  ["cap limit not enforced on settings", "|| s.cap > MAX_CAP ", "|| s.cap > type(uint96).max "],
  ["first advance floor not enforced on settings", "s.firstAdvance < MIN_FIRST_ADVANCE || ", ""],
  ["term ceiling not enforced on settings", "|| s.term > MAX_TERM ", ""],
  ["pace ceiling not enforced on settings", " || s.pacePerDay > MAX_PACE_PER_DAY", ""],
  ["missed flag never set", "a.missed = true;", ""],
  ["ownership can be renounced", "revert RenounceDisabled();", ""],
  ["withdrawals not counted", "_totals.withdrawn += amount.toUint128();", ""],
  ["batch limit removed on marking", "if (list.length > MAX_BATCH) revert BatchTooLarge();", ""],
  ["underpayment accepted", "if (msg.value < owed) revert Underpaid(owed);", "if (msg.value == 0) revert Underpaid(owed);"],
  ["name reply with a wrong offset accepted", "if (offset != 32 || ", "if ("],
  ["stranger can issue passes", "function addPasses(bytes32[] calldata passHashes, uint40 expires) external onlyOwner {", "function addPasses(bytes32[] calldata passHashes, uint40 expires) external {"],
  ["stranger can schedule settings", "function scheduleSettings(Settings calldata next) external onlyOwner {", "function scheduleSettings(Settings calldata next) external {"],
  ["stranger can pause", "function pause() external onlyOwner {", "function pause() external {"],
];

// The fork tests and the 16-day simulation are left out: they need the network or minutes per run.
// The gas limit is finite here because one mutation lets a hostile registry spin, and under the test
// tool's default of 2^64 gas that run would never end.
const env = { ...process.env, FOUNDRY_FUZZ_RUNS: "256", FOUNDRY_INVARIANT_RUNS: "40", FOUNDRY_GAS_LIMIT: "3000000000" };
delete env.BSC_RPC_URL;

function runTests() {
  const r = spawnSync("forge", ["test", "--no-match-contract", "Fork|LadderSim"], {
    cwd: work,
    env,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    timeout: 10 * 60 * 1000,
  });
  const text = (r.stdout || "") + (r.stderr || "");
  const failed = text
    .split("\n")
    .filter((line) => line.startsWith("[FAIL"))
    .map((line) => (line.match(/\]\s+(\w+)\(/g) || []).pop())
    .filter(Boolean)
    .map((hit) => hit.replace(/^\]\s+/, "").replace("(", ""));
  return { code: r.status, text, failed: [...new Set(failed)] };
}

const lines = [];
const save = () => writeFileSync(outFile, lines.join("\n") + "\n");
let caught = 0;
let survived = 0;
let notRun = 0;

try {
  const base = runTests();
  const summary = base.text.split("\n").filter((line) => /tests passed/.test(line)).pop() || "no summary line";
  lines.push(`run started ${new Date().toISOString()}`);
  lines.push(`unchanged source: ${summary.trim()}`);
  lines.push("");
  if (base.code !== 0) {
    lines.push("the unchanged source does not pass its tests, so no mutation was run");
    save();
    process.exit(1);
  }

  for (const [name, find, replacement] of MUTATIONS) {
    if (original.split(find).length - 1 !== 1) {
      lines.push(`NOT RUN   ${name}: the source text to change was not found exactly once`);
      notRun++;
    } else {
      writeFileSync(target, original.replace(find, replacement));
      const r = runTests();
      if (/Compiler run failed/.test(r.text)) {
        lines.push(`NOT RUN   ${name}: the changed source did not compile`);
        notRun++;
      } else if (r.code === 0) {
        lines.push(`SURVIVED  ${name}`);
        survived++;
      } else {
        const how = r.failed.length ? `${r.failed.length} failed: ${r.failed.slice(0, 4).join(", ")}` : "the tests did not finish";
        lines.push(`CAUGHT    ${name} -> ${how}`);
        caught++;
      }
    }
    save();
  }

  lines.push("");
  lines.push(`mutations ${MUTATIONS.length}, caught ${caught}, survived ${survived}, not run ${notRun}`);
  save();
  console.log(lines.join("\n"));
} finally {
  rmSync(work, { recursive: true, force: true });
}
process.exit(survived === 0 && notRun === 0 ? 0 : 1);
