// Behaviour tests for the compiled examples.
//
//   mojo -I . main.mojo build examples/fibonacci.mojo build/fibonacci.wasm
//   mojo -I . main.mojo build examples/features.mojo  build/features.wasm
//   mojo -I . main.mojo build examples/logic.mojo     build/logic.wasm
//   node tests/behavior.js build
//
// Mojo `Int` is 64-bit, so everything is a BigInt here.
const fs = require("fs");
const dir = process.argv[2] || "build";

const load = (name) => {
  const bytes = fs.readFileSync(`${dir}/${name}.wasm`);
  if (!WebAssembly.validate(bytes)) throw new Error(`${name}.wasm is not valid WebAssembly`);
  return new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
};

let fails = 0, checks = 0;
const eq = (name, got, want) => {
  checks++;
  if (got !== want) { fails++; console.log(`FAIL ${name}: got ${got}, want ${want}`); }
};

const Fi = load("fibonacci"), F = load("features"), L = load("logic");

// fibonacci
const fibs = [0n, 1n, 1n, 2n, 3n, 5n, 8n, 13n, 21n, 34n, 55n, 89n, 144n];
fibs.forEach((v, n) => { eq(`fib(${n})`, Fi.fib(BigInt(n)), v); eq(`fib_iter(${n})`, Fi.fib_iter(BigInt(n)), v); });
eq("fib(20)", Fi.fib(20n), 6765n);
eq("fib_iter(50)", Fi.fib_iter(50n), 12586269025n);

// features
eq("gcd", F.gcd(48n, 18n), 6n);
eq("abs", F.abs(-7n), 7n);
eq("sign", F.sign(-9n), -1n); eq("sign0", F.sign(0n), 0n); eq("sign+", F.sign(4n), 1n);
eq("poly", F.poly(10n), 21n);
eq("fact", F.fact(10n), 3628800n);
eq("forward call", F.twice(1n), 246913578044n);

// floor division and modulo (Mojo/Python semantics, not WASM truncation)
const fdiv = (a, b) => { let q = a / b; if (a % b !== 0n && (a < 0n) !== (b < 0n)) q -= 1n; return q; };
const fmod = (a, b) => a - b * fdiv(a, b);
for (const a of [-9n, -7n, -1n, 0n, 1n, 7n, 9n, -100n, 123456789012n])
  for (const b of [-4n, -3n, -1n, 1n, 2n, 3n, 7n]) {
    eq(`${a}//${b}`, L.fdiv(a, b), fdiv(a, b));
    eq(`${a}%${b}`, L.fmod(a, b), fmod(a, b));
  }
eq("-7 // 2", L.fdiv(-7n, 2n), -4n);
eq("-7 % 3", L.fmod(-7n, 3n), 2n);
let trapped = false; try { L.fdiv(1n, 0n); } catch (e) { trapped = true; }
eq("division by zero traps", trapped, true);

// loops, break, continue, compound assignment
const isPrime = (n) => { if (n < 2) return 0n; for (let i = 2; i * i <= n; i++) if (n % i === 0) return 0n; return 1n; };
for (let k = 0; k < 200; k++) eq(`is_prime(${k})`, L.is_prime(BigInt(k)), isPrime(k));
const collatz = (n) => { let s = 0; while (n !== 1) { n = n % 2 === 0 ? n / 2 : 3 * n + 1; s++; } return BigInt(s); };
for (let k = 1; k < 60; k++) eq(`collatz(${k})`, L.collatz_steps(BigInt(k)), collatz(k));
const sumOdd = (lim) => { let t = 0, i = 0; while (i < 1000) { i++; if (i % 2 === 0) continue; if (t + i > lim) break; t += i; } return BigInt(t); };
for (const lim of [0, 1, 5, 10, 50, 100, 1000, 100000]) eq(`sum_odd_until(${lim})`, L.sum_odd_until(BigInt(lim)), sumOdd(lim));

// and / or / not
for (let x = -2; x <= 12; x++) eq(`in_range(${x})`, L.in_range(BigInt(x), 3n, 9n), x >= 3 && x <= 9 ? 1n : 0n);
for (const y of [1900, 2000, 2023, 2024, 2100, 2400]) eq(`is_leap(${y})`, L.is_leap(BigInt(y)), (y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0)) ? 1n : 0n);
for (const [a, b] of [[1n, 2n], [2n, 1n], [3n, 3n]]) eq(`not_demo(${a},${b})`, L.not_demo(a, b), a < b ? 0n : 1n);

// short-circuit: `10 // n` must NOT run when n == 0
eq("safe_ratio(0)", L.safe_ratio(0n), 0n);
eq("safe_ratio(3)", L.safe_ratio(3n), 1n);
eq("safe_ratio(6)", L.safe_ratio(6n), 0n);

// constant folding gives the same answer as the runtime would
eq("folded()", L.folded(), 16n);

console.log(fails === 0 ? `ALL ${checks} CHECKS PASSED` : `${fails} of ${checks} CHECKS FAILED`);
process.exit(fails === 0 ? 0 : 1);
