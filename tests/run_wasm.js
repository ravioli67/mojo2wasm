// Run an exported function from a compiled .wasm file.
//
//   node tests/run_wasm.js out.wasm fib 10
//   node tests/run_wasm.js out.wasm add 2 3
//
// Mojo `Int` is 64-bit, so arguments and results are BigInt.
const fs = require("fs");

const [, , file, name, ...rest] = process.argv;
if (!file || !name) {
  console.error("usage: node tests/run_wasm.js <file.wasm> <function> [args...]");
  process.exit(1);
}

const bytes = fs.readFileSync(file);
if (!WebAssembly.validate(bytes)) {
  console.error("The file is not a valid WebAssembly module.");
  process.exit(1);
}

const instance = new WebAssembly.Instance(new WebAssembly.Module(bytes));
const fn = instance.exports[name];
if (typeof fn !== "function") {
  console.error(`No exported function '${name}'. Exports: ${Object.keys(instance.exports).join(", ")}`);
  process.exit(1);
}

console.log(String(fn(...rest.map((a) => BigInt(a)))));
