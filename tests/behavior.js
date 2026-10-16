// Behaviour tests for the compiled examples.
//
//   mojo -I . main.mojo build examples/fibonacci.mojo build/fibonacci.wasm
//   mojo -I . main.mojo build examples/features.mojo  build/features.wasm
//   mojo -I . main.mojo build examples/logic.mojo     build/logic.wasm
//   mojo -I . main.mojo build examples/types.mojo     build/types.wasm
//   mojo -I . main.mojo build examples/hello.mojo     build/hello.wasm
//   mojo -I . main.mojo build examples/language.mojo  build/language.wasm
//   node tests/behavior.js build
//
// From JavaScript: Int is a BigInt, Float64 is a number, Bool is 0 or 1.
const { loadWasm } = require("./host.js");
const dir = process.argv[2] || "build";

// Everything the programs print() is collected here.
let output = "";
const take = () => { const text = output; output = ""; return text; };
const load = (name) => loadWasm(`${dir}/${name}.wasm`, (text) => { output += text; });

let fails = 0, checks = 0;
const eq = (name, got, want) => {
  checks++;
  if (got !== want) { fails++; console.log(`FAIL ${name}: got ${got}, want ${want}`); }
};

const Fi = load("fibonacci"), F = load("features"), L = load("logic"), T = load("types");
const H = load("hello"), G = load("language");
const near = (name, got, want) => {
  checks++;
  if (Math.abs(got - want) > 1e-9 * Math.max(1, Math.abs(want))) { fails++; console.log(`FAIL ${name}: got ${got}, want ${want}`); }
};

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

// ---- Float64 ----
near("circle_area", T.circle_area(2), 3.14159 * 4);
eq("average", T.average(3, 4), 3.5);
eq("c2f(100)", T.celsius_to_fahrenheit(100), 212); eq("c2f(0)", T.celsius_to_fahrenheit(0), 32); eq("c2f(-40)", T.celsius_to_fahrenheit(-40), -40);
eq("to_float", T.to_float(7n), 7); eq("to_float(-3)", T.to_float(-3n), -3);
eq("truncate(3.99)", T.truncate(3.99), 3n); eq("truncate(-3.99)", T.truncate(-3.99), -3n);
eq("negate", T.negate(2.5), -2.5); eq("negate(-1.25)", T.negate(-1.25), 1.25);
for (const x of [2, 9, 100, 0.25, 1e6, 123.456]) near(`sqrt_newton(${x})`, T.sqrt_newton(x), Math.sqrt(x));
eq("sqrt_newton(0)", T.sqrt_newton(0), 0); eq("sqrt_newton(-4)", T.sqrt_newton(-4), 0);
eq("mean_of_first(10)", T.mean_of_first(10n), 5.5);
eq("clamp01(-5)", T.clamp01(-5), 0); eq("clamp01(9)", T.clamp01(9), 1); eq("clamp01(0.25)", T.clamp01(0.25), 0.25);

// ---- Bool (0 or 1 from JavaScript) ----
for (let n = -3; n <= 4; n++) eq(`is_even(${n})`, T.is_even(BigInt(n)), n % 2 === 0 ? 1 : 0);
eq("is_positive(1.5)", T.is_positive(1.5), 1); eq("is_positive(0)", T.is_positive(0), 0); eq("is_positive(-1)", T.is_positive(-1), 0);
eq("truth()", T.truth(), 1); eq("invert(0)", T.invert(0), 1); eq("invert(1)", T.invert(1), 0);
for (const a of [0, 1]) for (const c of [0, 1]) {
  eq(`both(${a},${c})`, T.both(a, c), a && c ? 1 : 0);
  eq(`either(${a},${c})`, T.either(a, c), a || c ? 1 : 0);
  eq(`exactly_one(${a},${c})`, T.exactly_one(a, c), a ^ c);
  eq(`same(${a},${c})`, T.same(a, c), a === c ? 1 : 0);
}
eq("bool_to_int(1)", T.bool_to_int(1), 1n); eq("bool_to_int(0)", T.bool_to_int(0), 0n);
eq("int_to_bool(5)", T.int_to_bool(5n), 1); eq("int_to_bool(0)", T.int_to_bool(0n), 0); eq("int_to_bool(-3)", T.int_to_bool(-3n), 1);
eq("in_unit_range(0.5)", T.in_unit_range(0.5), 1); eq("in_unit_range(1.5)", T.in_unit_range(1.5), 0); eq("in_unit_range(-0.1)", T.in_unit_range(-0.1), 0);
eq("count_primes_below(30)", T.count_primes_below(30n), 10n); eq("count_primes_below(100)", T.count_primes_below(100n), 25n);

// ---- print(), strings, void functions ----
H.main();
eq("hello output", take(), "Hello, Mojo!\nThe answer is 42\n3.5 True 7\n\n");

// ---- for loops, alias, ternary, block scoping, fn ----
eq("sum_to(10)", G.sum_to(10n), 55n); eq("sum_to(0)", G.sum_to(0n), 0n);
eq("count_even(10)", G.count_even(10n), 5n); eq("count_even(7)", G.count_even(7n), 4n);
eq("first_multiple(7, 20)", G.first_multiple(7n, 20n), 21n);
eq("first_multiple none", G.first_multiple(5000n, 1n), -1n);
take(); G.countdown(); eq("countdown", take(), "5\n4\n3\n2\n1\nliftoff\n");
G.evens(); eq("evens", take(), "0\n2\n4\n6\n8\n");
eq("two_loops (reuses `i`)", G.two_loops(), 36n);
eq("nested", G.nested(5n), 10n);
eq("shadowing", G.shadowing(), 1n);
eq("max_of", G.max_of(3n, 9n), 9n); eq("max_of swapped", G.max_of(9n, 3n), 9n);
eq("abs_float(-2.5)", G.abs_float(-2.5), 2.5); eq("abs_float(2.5)", G.abs_float(2.5), 2.5);
eq("grade", [95n, 85n, 75n, 50n].map((x) => G.grade(x)).join(), "4,3,2,0");
eq("scaled (alias)", G.scaled(2), 5);
eq("limits (aliases)", G.limits(), 30n);
take(); eq("use_result", G.use_result(), 42n);
eq("use_result output", take(), "doubling 21\ndoubling 5\n");
G.fizzbuzz(15n);
eq("fizzbuzz", take(), "1\n2\nFizz\n4\nBuzz\nFizz\n7\n8\nFizz\nBuzz\n11\nFizz\n13\n14\nFizzBuzz\n");
G.early(-1n); eq("early(-1)", take(), "negative\n");
G.early(3n); eq("early(3)", take(), "ok 3\n");
eq("void function returns nothing", G.noop(), undefined);

console.log(fails === 0 ? `ALL ${checks} CHECKS PASSED` : `${fails} of ${checks} CHECKS FAILED`);
process.exit(fails === 0 ? 0 : 1);
