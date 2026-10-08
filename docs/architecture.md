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
     │  wasm/emitter.mojo
     ▼
 .wasm bytes (List[UInt8])
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
| Statements | `return`, `if` / `elif` / `else`, `while`, `var x = e` (optionally `var x: Int = e`), `x = e` |
| Operators | `+ - * // %` (arithmetic), `< <= > >= == !=` (comparison), unary `-`, parentheses |
| Comments | `#` to end of line |
| Blocks | Indentation-based, like Python (a tab counts as 4 spaces) |

Rules enforced by the checker:

- A comparison produces a Bool; Bools may only be used as the condition of
  `if` / `while` (there are no Bool variables or parameters yet).
- Variables are function-wide: once declared with `var`, a name is visible to
  the rest of the function, including after the block it was declared in.
  Declaring the same name twice is an error.
- Every function must return on every path.
- `//` and `%` use signed truncating division (WASM `i64.div_s` / `i64.rem_s`),
  and trap at runtime on division by zero.

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
| `src/util/hex.mojo` | `to_hex` |
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
types, duplicate declarations, and that all paths return.

### WASM emitter
Function `i` in the source becomes WASM function `i` and is exported under
its source name. Sections, in order:

| Section | Id | Content |
|---------|----|---------|
| header | | `00 61 73 6D` + version `01 00 00 00` |
| type | 1 | one signature `(i64 × n) -> i64` per function |
| function | 3 | function `i` uses type `i` |
| export | 7 | every function, by name |
| code | 10 | one body per function |

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
```

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

The `.hex` files were produced by a reference implementation of exactly this
design and validated in a real WebAssembly engine, so a mismatch points at a
bug in the Mojo code (or a Mojo-version syntax difference), not in the design.
`examples/features.mojo` exercises `while`, `elif`/`else`, unary minus,
precedence, `%`, `//`, `*` and forward calls.

## Roadmap

1. Run all examples (including `examples/library_usage.mojo`) through the Mojo implementation and fix any
   Mojo-version syntax differences.
2. Unit tests per stage under `tests/lexer`, `tests/parser`, `tests/wasm`.
3. A `Bool` type (variables, parameters, `and` / `or` / `not`), `+=` style
   assignment, `break` / `continue`.
4. Block-scoped variables with shadowing rules.
5. More types (`Float64`, `Int32`, `Bool`) and implicit type promotion rules.
6. An IR in `src/ir/` between the checker and the emitter, enabling
   optimizations (constant folding, dead code removal) and richer lowering.
7. Replace string token / node kinds with a compact enum-like representation.
8. Source-level diagnostics: show the offending line with a caret.
