const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const dir = path.join(__dirname, "errors");
const root = path.join(__dirname, "..");
const names = fs.readdirSync(dir).filter((f) => f.endsWith(".mojo")).map((f) => f.slice(0, -5)).sort();

let failed = 0;
for (const name of names) {
  const result = spawnSync("mojo", ["-I", ".", "main.mojo", "check", `tests/errors/${name}.mojo`], { cwd: root, encoding: "utf8" });
  const actual = (result.stdout || "").trim();
  const expected = fs.readFileSync(path.join(dir, `${name}.expected`), "utf8").trim();
  if (actual === expected) {
    console.log(`ok    ${name}`);
  } else {
    failed++;
    console.log(`FAIL  ${name}\n--- expected\n${expected}\n--- actual\n${actual}${result.stderr ? "\n--- stderr\n" + result.stderr : ""}\n`);
  }
}
console.log(failed === 0 ? `\nall ${names.length} error messages match` : `\n${failed} of ${names.length} differ`);
process.exit(failed === 0 ? 0 : 1);
