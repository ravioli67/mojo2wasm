// Compare a compiled .wasm file with an expected .hex file.
//
//   node tests/compare_hex.js out.wasm tests/wasm/add.hex
const fs = require("fs");
const [, , wasmFile, hexFile] = process.argv;
const actual = fs.readFileSync(wasmFile).toString("hex").match(/../g).join(" ");
const expected = fs.readFileSync(hexFile, "utf8").trim();
if (actual === expected) {
  console.log("MATCH");
} else {
  console.log("DIFFERENT");
  console.log("expected:", expected);
  console.log("actual:  ", actual);
  process.exit(1);
}
