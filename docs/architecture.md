# mojo_wasm Architecture

mojo_wasm is a compiler written in Mojo that translates a small subset of
Mojo into WebAssembly (`.wasm`) binaries.

## Pipeline

```
 source text
     │  lexer/lexer.mojo      (adds NEWLINE / INDENT / DEDENT)
     ▼
 tokens (List[Token])
     │  parser/parser.mojo
     ▼
 Module (functions + expression arena + statement arena)
     │  sema/checker.mojo
     ▼
 validated Module
     │  opt/fold.mojo         (constant folding, optional)
     ▼
 optimized Module
     │  wasm/emitter.mojo     (binary)     or     wasm/wat.mojo  (text)
     ▼                                              ▼
 .wasm bytes (List[UInt8])                      WAT source (String)
```

`compiler.mojo` wires the stages together; `mojo_wasm.mojo` is the public
API (see `docs/api.md`): `compile`, `try_compile`, `validate`,
`list_functions`, `dump_ast` and more. `main.mojo` (repo root) is a
command-line wrapper around it.

Every stage reports problems by raising an `Error` whose message starts with
`Lexer error`, `Parser error`, `Semantic error` or `Emitter error` and
includes a line number where one is known.

## The supported language

```mojo
def fib(n: Int) -> Int:
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)

def fib_iter(n: Int) -> Int:
    var a = 0
    var b = 1
    var i = 0
    while i < n:
        var t = a + b
        a = b
        b = t
        i = i + 1
    return a
```

| Feature | Notes |
|---------|-------|
| Types | `Int` only (64-bit, signed). Maps to WASM `i64`. |
| Functions | Any number per file, any order. Calls (including recursion and forward calls) are supported. |
| Statements | `return`, `if` / `elif` / `else`, `while`, `break`, `continue`, `var x = e` (optionally `var x: Int = e`), `x = e`, and `x += e` (also `-=`, `*=`, `//=`, `%=`) |
| Operators | `+ - * // %` (arithmetic), `< <= > >= == !=` (comparison), `and` `or` `not` (logic), unary `-`, parentheses |
| Comments | `#` to end of line |
| Blocks | Indentation-based, like Python (a tab counts as 4 spaces) |

Rules enforced by the checker:

- A comparison produces a Bool, and `and` / `or` / `not` combine Bools.
  Bools may only be used as the condition of `if` / `while` (there are no
  Bool variables or parameters yet), so `if a:` and `a + (b < c)` are errors.
- `and` / `or` short-circuit: the right side is only evaluated when needed,
  so `n > 0 and 10 // n >= 2` is safe when `n` is 0.
- `break` and `continue` are only allowed inside a `while` body.
- Variables are function-wide: once declared with `var`, a name is visible to
  the rest of the function, including after the block it was declared in.
  Declaring the same name twice is an error.
- Every function must return on every path.
- `//` and `%` use floor semantics like Mojo and Python: `-7 // 2` is `-4`
  and `-7 % 3` is `2`. Division by zero traps at runtime. (WASM's own
  `i64.div_s` / `i64.rem_s` truncate toward zero, so programs that use these
  operators get small helper functions; see "Floor division" below.)

## Directory layout

| Path | Role |
|------|------|
| `main.mojo` | Command-line entry: `mojo -I . main.mojo build in.mojo out.wasm` (also `hex`, `check`, `functions`, `tokens`, `ast`) |
| `src/mojo_wasm.mojo` | Public API (documented in `docs/api.md`) |
| `src/compiler.mojo` | Runs the pipeline |
| `src/lexer/tokens.mojo` | `Token(kind, lexeme, line)` |
| `src/lexer/lexer.mojo` | `lex(source) -> List[Token]` |
| `src/parser/ast.mojo` | `Expr`, `Stmt`, `Function`, `Module` and builder helpers |
| `src/parser/parser.mojo` | Recursive-descent `Parser` |
| `src/sema/checker.mojo` | Semantic checks |
| `src/wasm/types.mojo` | WASM opcodes, section ids, LEB128 encoders |
| `src/wasm/emitter.mojo` | `Module` to binary |
| `src/opt/fold.mojo` | Constant folding |
| `src/wasm/wat.mojo` | `Module` to WAT text |
| `src/util/hex.mojo` | `to_hex`, `from_hex` |
| `src/util/files.mojo` | `read_file`, `write_file` |
| `src/util/dump.mojo` | `format_tokens`, `format_module` (used by `dump_tokens` / `dump_ast`) |
| `src/ir/` | Reserved for a future IR |
| `examples/` | Sample programs |
| `tests/` | Expected output (`tests/wasm/*.hex`) and Node helper scripts |

Each folder under `src/` contains an empty `__init__.mojo` so Mojo treats it
as a package (required for the relative imports).

## Stages

### Lexer
Reads characters left to right. Identifiers are read in full and then looked
up in a keyword table (`def return if elif else while var Int`), so `default`
is an identifier. Two-character operators (`-> <= >= == != //`) are matched
before single-character ones.

Indentation works like Python: a stack of indentation widths starts at `[0]`.
At the start of every non-blank line, a deeper indent emits `INDENT`, a
shallower one emits one `DEDENT` per level closed (an indent that matches no
open level is an error). Each logical line ends with `NEWLINE`. Newlines
inside parentheses are ignored. At end of file all open blocks are closed.

Token kinds are strings: `DEF RETURN IF ELIF ELSE WHILE VAR INT IDENTIFIER
INTEGER LPAREN RPAREN COLON COMMA ARROW ASSIGN PLUS MINUS STAR SLASHSLASH
PERCENT LT LE GT GE EQ NE NEWLINE INDENT DEDENT UNKNOWN EOF`.

### Parser
Recursive descent; the grammar is documented in the docstring of `Parser`.
Operator precedence, loosest to tightest: comparison, `+ -`, `* // %`,
unary `-`, then calls / parentheses / literals / variables. Comparisons do
not chain (`a < b < c` is a syntax error). `-x` is parsed as `0 - x`, and
`elif` is parsed as an `if` nested inside the `else` branch.

### AST: an arena with indices
Mojo structs cannot contain themselves, so the tree is stored flat in
`Module`:

```
Module
 ├─ functions : List[Function]     Function.body   -> indices into stmts
 ├─ stmts     : List[Stmt]         Stmt.expr       -> index into exprs
 │                                 Stmt.body / else_body -> indices into stmts
 └─ exprs     : List[Expr]         Expr.left / right / args -> indices into exprs
```

`Expr.kind` is `INT`, `VAR`, `BINARY` or `CALL`. `Stmt.kind` is `RETURN`,
`IF`, `WHILE`, `VAR` or `ASSIGN`. Builder helpers (`int_expr`, `binary_expr`,
`if_stmt`, ...) fill in the unused fields.

### Semantic checker
Walks every function with a growing list of names in scope (parameters first).
It computes a type (`Int` or `Bool`) for each expression and verifies:
declared names, function names and argument counts, operand types, condition
types, duplicate declarations, `break` / `continue` placement, and that all
paths return.

### Optimizer
`opt/fold.mojo` makes one pass over the expression arena. Because the parser
creates a node's children before the node, a forward pass folds bottom-up:
`2 + 3 * 4` becomes `14` and `-5` (parsed as `0 - 5`) becomes `-5`. Only
`+ - * // %` on two integer literals is folded, using the same floor
semantics as the runtime. A division by zero is left alone so the program
traps when run instead of failing to compile. Use `compile_unoptimized` to
skip this pass.

### WASM emitter
Function `i` in the source becomes WASM function `i` and is exported under
its source name. Sections, in order:

| Section | Id | Content |
|---------|----|---------|
| header | | `00 61 73 6D` + version `01 00 00 00` |
| type | 1 | one signature `(i64 × n) -> i64` per function |
| function | 3 | function `i` uses type `i` |
| export | 7 | every source function, by name |
| code | 10 | one body per function |

If the program uses `//` and/or `%`, one or two helper functions follow the
user's functions (not exported); see "Floor division" below.

A body starts with its local declarations (all `var`s collected in advance,
numbered after the parameters), then the statements, then `unreachable` and
`end`. The trailing `unreachable` is never executed (the checker guarantees
a `return` on every path) but keeps WASM validation happy.

Statement lowering:

```
return e        e ; return
x = e / var x   e ; local.set x
if c: A else: B c ; if A else B end
while c: A      block  loop  c ; i32.eqz ; br_if 1 ;  A ; br 0  end end
f(a, b)         a ; b ; call <index of f>
not c           c ; i32.eqz
a and b         a ; if (result i32)  b  else  i32.const 0  end
a or b          a ; if (result i32)  i32.const 1  else  b  end
break           br <depth of the loop's outer block>
continue        br <depth of the loop's loop>
```

`break` and `continue` branch by *depth*: inside a `while` body, `br 1`
leaves the `block` and `br 0` jumps to the `loop` top. Every `if` entered
adds one level, so the emitter tracks the two depths and increases them by
one for each nested `if`.

### Floor division
Mojo's `//` and `%` round toward negative infinity, but WASM's `i64.div_s` /
`i64.rem_s` truncate toward zero (`-7 // 2` would give `-3`, not `-4`). The
emitter appends two small functions when needed:

```
floordiv(a, b):  q = a / b ;  if (a % b != 0) and ((a ^ b) < 0):  q - 1  else q
floormod(a, b):  r = a % b ;  if (r != 0)     and ((r ^ b) < 0):  r + b  else r
```

Their indices come right after the user's functions (floordiv first, if used).

### WAT output
`wasm/wat.mojo` lowers the same constructs to the WebAssembly text format in
flat style, one instruction per line, with names instead of indices
(`local.get $n`, `call $fib`). Every function is exported by name and ends
with `unreachable`, mirroring the binary emitter. The text of every example
is in `tests/wasm/*.wat`, and each was checked to assemble to bytes identical
to the binary emitter's output.

Comparisons produce a WASM `i32`, which is exactly what `if` and `br_if`
consume. Sizes, counts and indices use unsigned LEB128; `i64.const`
immediates use signed LEB128.

## Worked example

`examples/add.mojo` compiles to these 43 bytes (`tests/wasm/add.hex`):

```
00 61 73 6d 01 00 00 00                     header
01 07 01 60 02 7e 7e 01 7e                  type:     (i64, i64) -> i64
03 02 01 00                                 function: uses type 0
07 07 01 03 61 64 64 00 00                  export:   "add" = function 0
0a 0b 01 09 00 20 00 20 01 7c 0f 00 0b      code:     local.get 0
                                                      local.get 1
                                                      i64.add
                                                      return
                                                      unreachable
                                                      end
```

`fib` from `examples/fibonacci.mojo` lowers to:

```
local.get 0 ; i64.const 2 ; i64.lt_s
if
  local.get 0 ; return
end
local.get 0 ; i64.const 1 ; i64.sub ; call 0
local.get 0 ; i64.const 2 ; i64.sub ; call 0
i64.add ; return
unreachable
end
```

## Testing

```
mojo -I . main.mojo build examples/add.mojo add.wasm
node tests/compare_hex.js add.wasm tests/wasm/add.hex   # byte-for-byte check
mojo -I . main.mojo hex examples/add.mojo               # compare with tests/wasm/add.hex by eye
node tests/run_wasm.js add.wasm add 2 3                 # prints 5

mojo -I . main.mojo build examples/fibonacci.mojo fib.wasm
node tests/compare_hex.js fib.wasm tests/wasm/fibonacci.hex
node tests/run_wasm.js fib.wasm fib 20                  # prints 6765
node tests/run_wasm.js fib.wasm fib_iter 50             # prints 12586269025
```

Behaviour tests (460 checks: fib, gcd, primes, collatz, floor division with
negative numbers, short-circuiting, `break` / `continue`, constant folding):

```
mojo -I . main.mojo build examples/fibonacci.mojo build/fibonacci.wasm
mojo -I . main.mojo build examples/features.mojo  build/features.wasm
mojo -I . main.mojo build examples/logic.mojo     build/logic.wasm
node tests/behavior.js build
```

WAT output can be compared with `tests/wasm/*.wat`:

```
mojo -I . main.mojo wat examples/fibonacci.mojo
```

The `.hex` and `.wat` files were produced by a reference implementation of exactly this
design and validated in a real WebAssembly engine, so a mismatch points at a
bug in the Mojo code (or a Mojo-version syntax difference), not in the design.
`examples/features.mojo` exercises `while`, `elif`/`else`, unary minus,
precedence, `%`, `//`, `*` and forward calls; `examples/logic.mojo` covers
`and` / `or` / `not`, compound assignment, `break` / `continue`, floor
division and constant folding.

## Roadmap

1. Run all examples (including `examples/library_usage.mojo`) through the Mojo implementation and fix any
   Mojo-version syntax differences.
2. Unit tests per stage under `tests/lexer`, `tests/parser`, `tests/wasm`.
3. A real `Bool` type (variables, parameters, return values).
4. Block-scoped variables with shadowing rules.
5. More types (`Float64`, `Int32`, `Bool`) and implicit type promotion rules.
6. An IR in `src/ir/` between the checker and the emitter, enabling more
   optimizations (dead code removal, strength reduction) and richer lowering.
7. Replace string token / node kinds with a compact enum-like representation.
8. Source-level diagnostics: show the offending line with a caret.
