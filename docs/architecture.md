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
| Types | `Int` (64-bit signed, WASM `i64`), `Float64` (WASM `f64`) and `Bool` (WASM `i32`). Use them for parameters, return values and variables. |
| Literals | `42`, `3.14` (up to 15 significant digits), `True`, `False` |
| Conversions | Always explicit: `Float64(n)`, `Int(x)` (truncates toward zero; traps on NaN / overflow), `Int(b)`, `Bool(n)` (`n != 0`) |
| Functions | `def` or `fn`, any number per file, in any order. Recursion and forward calls work. `raises` is accepted (and ignored). A function with no `-> type` (or `-> None`) returns nothing, and a call to it is a statement. |
| Constants | Top-level `alias N = 10` (or `comptime`), optionally typed (`alias PI: Float64 = 3.14`). Values may use literals and earlier aliases. |
| Statements | `return` (bare in functions with no return type), `if` / `elif` / `else`, `while`, `for i in range(...)`, `break`, `continue`, `pass`, `var x = e` (optionally `var x: Int = e`), `x = e`, `x += e` (also `-=`, `*=`, `/=`, `//=`, `%=`), `print(...)`, and calls on their own line |
| Loops | `for i in range(stop)`, `range(start, stop)`, `range(start, stop, step)`; `step` must be an integer literal such as `2` or `-1` |
| Conditional expression | `a if condition else b` (only the chosen side is evaluated) |
| Output | `print(a, b, ...)` prints its arguments separated by spaces, then a newline. Arguments are `Int`, `Float64`, `Bool` values or string literals. The host must supply the printing functions (see `docs/api.md`). |
| Strings | Only as arguments to `print()` (and as docstrings, which are ignored). Escapes `\n \t \r \\ \" \' \0`; `"""triple quotes"""` may span lines. |
| Operators | `+ - * // %` and `/` (arithmetic), `< <= > >= == !=` (comparison), `and` `or` `not` (logic), unary `-`, parentheses |
| Comments | `#` to end of line |
| Blocks | Indentation-based, like Python (a tab counts as 4 spaces) |

Rules enforced by the checker:

- There is no implicit conversion. `+ - *` need two `Int`s or two `Float64`s
  (`x * 2` with `x: Float64` is an error: write `x * 2.0`). `/` needs two
  `Float64`s (use `//` for integers), `//` and `%` need two `Int`s.
  Comparisons need matching types (`==` and `!=` also accept two `Bool`s).
- A comparison produces a `Bool`, and `and` / `or` / `not` combine `Bool`s.
  `Bool`s can be stored in variables, passed to functions and returned; an
  `if` / `while` condition must be a `Bool` (so `if n:` is an error).
- A `var` takes the type of its value (`var x = 1.5` is a `Float64`), or its
  annotation, which must agree. Assigning a different type is an error.
- A `return` value must have the function's declared return type.
- `and` / `or` short-circuit: the right side is only evaluated when needed,
  so `n > 0 and 10 // n >= 2` is safe when `n` is 0.
- `break` and `continue` are only allowed inside a loop. In a `for` loop,
  `continue` still advances the counter.
- Variables are block-scoped like in Mojo: a variable disappears at the end
  of the `if`, `while` or `for` block that declared it, a loop variable only
  lives inside its loop (so two loops can both use `i`), and an inner block
  may shadow an outer variable. Declaring a name twice in the same block is an
  error, as is reusing the name of an alias.
- Assigning to a `for` loop variable does not change the iteration (the loop
  keeps its own counter, as in Mojo).
- A function with a return type must return on every path. A function without
  one may end without `return`, and a bare `return` leaves it early.
- A call to a function with no return type cannot be used as a value
  (`x = log(1)`, `print(log(1))`).
- Aliases cannot be assigned to, and may only use literals and earlier aliases.
- `print` is a reserved function name, as are names starting with `__`.
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
| `src/lexer/tokens.mojo` | `Token(kind, lexeme, line, column)` |
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
| `src/util/diagnostics.mojo` | Error messages with source excerpts, "did you mean" suggestions |
| `src/util/dump.mojo` | `format_tokens`, `format_module` (used by `dump_tokens` / `dump_ast`) |
| `src/ir/` | Reserved for a future IR |
| `examples/` | Sample programs |
| `tests/` | Expected output (`tests/wasm/*.hex` / `*.wat`, `tests/errors/*`) and Node scripts |

Each folder under `src/` contains an empty `__init__.mojo` so Mojo treats it
as a package (required for the relative imports).

## Stages

### Lexer
Reads characters left to right. Identifiers are read in full and then looked
up in a keyword table (`def return if elif else while var and or not break
continue pass for in raises alias comptime fn None True False Int Float64
Bool`), so `default` is an identifier.
Longer operators (`//=`, then `-> <= >= == != // += -= *= /= %=`) are matched
before single-character ones. A number followed by `.` and a digit is a
`FLOAT`, otherwise an `INTEGER`. Every token records its line and column.
The lexer raises an error for characters it does not understand and tracks
parentheses, so it can point at a `(` that is never closed or a stray `)`.

Indentation works like Python: a stack of indentation widths starts at `[0]`.
At the start of every non-blank line, a deeper indent emits `INDENT`, a
shallower one emits one `DEDENT` per level closed (an indent that matches no
open level is an error). Each logical line ends with `NEWLINE`. Newlines
inside parentheses are ignored. At end of file all open blocks are closed.

Token kinds are strings: `DEF RETURN IF ELIF ELSE WHILE VAR BREAK CONTINUE
AND OR NOT TRUE FALSE INT FLOAT64 BOOL IDENTIFIER INTEGER FLOAT LPAREN
RPAREN COLON COMMA ARROW ASSIGN PLUS MINUS STAR SLASH SLASHSLASH PERCENT
PLUSEQ MINUSEQ STAREQ SLASHEQ SLASHSLASHEQ PERCENTEQ LT LE GT GE EQ NE
NEWLINE INDENT DEDENT EOF`.

### Parser
Recursive descent; the grammar is documented in the docstring of `Parser`.
Operator precedence, loosest to tightest: comparison, `+ -`, `* // %`,
unary `-`, then calls / conversions / parentheses / literals / variables
(`or` and `and` / `not` bind looser than comparisons). Comparisons do not
chain (`a < b < c` is an error that suggests `and`), and `elif` is parsed as
an `if` nested inside the `else` branch. A type name followed by `(` is a
conversion (`Float64(n)`).

`fn` is the same as `def`, `alias` / `comptime` declare constants, and a
function's `-> type` is optional. Statements that start with a name are an
assignment, a compound assignment, `print(...)` or a call; anything else that
looks like an expression gets "this is not a statement". `for` loops are only
accepted over `range(...)` and the step must be a literal, so the direction
of the loop is known at compile time. `a if c else b` is parsed after the
`or` level, so `x = 1 if a or b else 2` works.

Error messages name tokens in plain words ("expected ':' but found the end
of the line") and special-case common slips: `if x = 5:` suggests `==`, and a
block that is not indented says so. Float literals are converted exactly: all
digits are read as one integer and divided by a power of ten, which is
correctly rounded for up to 15 significant digits.

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

`Expr.kind` is `INT`, `FLOAT`, `BOOL`, `STRING`, `VAR`, `ALIAS`, `NEG`, `NOT`,
`BINARY`, `LOGIC`, `TERNARY`, `CALL` or `CAST`. `Stmt.kind` is `RETURN`, `IF`,
`WHILE`, `FOR`, `VAR`, `ASSIGN`, `PRINT`, `EXPR`, `PASS`, `BREAK` or
`CONTINUE`. `Module` also holds the `aliases`. Builder helpers (`int_expr`, `binary_expr`,
`if_stmt`, ...) fill in the unused fields.

Every node stores the `line` and `column` it came from (a binary expression
points at its operator, a call at the function name). The checker fills in
`Expr.etype` (`"Int"`, `"Float64"` or `"Bool"`) for every expression and the
type of every `var`, because the emitter chooses instructions from them. The
checker also resolves every variable to a *local slot* (parameters first, then
one new slot per declaration, even when a name is reused in another block) and
records the slots in `Function.slot_names` / `slot_types`, so the emitter never
has to deal with names or scopes. A `for` loop uses three consecutive slots:
the loop variable and two hidden ones (its counter and its end value).

### Semantic checker
Checks the aliases first, then walks every function with a `Scope` (a stack of
the variables currently visible, parameters first; leaving a block removes the
variables it declared).
It computes a type (`Int`, `Float64` or `Bool`) for each expression, stores it
on the node, and verifies: declared names, function names, argument counts and
types, operand types, condition types, return types, conversions,
duplicate declarations, `break` / `continue` placement, reserved names
(anything starting with `__`) and that all paths return. When a name is
unknown it suggests a close match from the names in scope.

### Error messages
Each stage raises `<Kind> error at <line>:<column>: <text>`. The compiler
catches that and expands it, using the source text, to:

```
Semantic error: unknown variable 'cout'. Did you mean 'count'?
  --> line 2, column 20
  |
2 |     return price * cout
  |                    ^^^^
```

The carets cover the word, number or operator at the reported column. All
the messages are covered by `tests/errors/`.

### Optimizer
`opt/fold.mojo` makes one pass over the expression arena. Because the parser
creates a node's children before the node, a forward pass folds bottom-up:
`2 + 3 * 4` becomes `14` and `-5` (negating the literal 5) becomes `-5`. Only
`+ - * // %` on two integer literals is folded, using the same floor
semantics as the runtime. `Float64` arithmetic is not folded. A division by zero is left alone so the program
traps when run instead of failing to compile. Use `compile_unoptimized` to
skip this pass.

### WASM emitter
Function `i` in the source becomes WASM function `i` and is exported under
its source name. Sections, in order:

| Section | Id | Content |
|---------|----|---------|
| header | | `00 61 73 6D` + version `01 00 00 00` |
| type | 1 | one signature per function (and per import), built from the parameter and return types |
| import | 2 | only when the program prints: the `print_*` functions from module `env` |
| function | 3 | defined function `i` uses type `imports + i` |
| memory | 5 | only when the program prints: one 64 KiB page |
| export | 7 | every source function by name, plus `memory` |
| code | 10 | one body per function |
| data | 11 | only when the program prints: the string literals, at address 0 |

WASM numbers imported functions first, so the function index of source
function `f` is `imports + f`, and the `//` / `%` helpers come after the
source functions.

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

Type mapping: `Int` is `i64`, `Float64` is `f64`, `Bool` is `i32` (0 or 1).
Local variables are declared up front in groups of consecutive locals with the
same type. Instructions are chosen from the operand types, e.g. `+` becomes
`i64.add` or `f64.add`, and `==` on two Bools becomes `i32.eq`. Conversions
use `f64.convert_i64_s`, `i64.trunc_f64_s`, `i64.extend_i32_u` and
`i64.eqz` + `i32.eqz`. Negation is `0 - x` for `Int` and `f64.neg` for
`Float64`.

A `Float64` literal becomes `f64.const` followed by its 8 IEEE-754 bytes. They
are computed with plain arithmetic (halving or doubling until the value is
in [1, 2) is exact in binary floating point), so no bit-casting is needed;
this was checked against Python's `struct.pack` on 40,000 values.

### print, strings and imports
`print(a, "x", b)` becomes, for each argument, a call of an imported host
function, with a call to `print_str(" ")` between arguments and
`print_str("\n")` at the end:

```
print_i64(Int)   print_f64(Float64)   print_bool(0 | 1)   print_str(address, length)
```

Only the imports a program uses are declared. String literals are collected
into one table (each distinct text once, plus `" "` and `"\n"` when needed)
that becomes the data segment at address 0; `print_str` receives an address
and a length, and the host reads the text from the exported `memory`.
Strings are UTF-8. See `docs/api.md` for how to write a host, and
`tests/host.js` for a working one.

### Loops, scopes and void functions
`for i in range(a, b, step)` is lowered with a hidden counter, so the loop
variable behaves as in Mojo even if the body assigns to it:

```
counter = a ; end = b
block                                  ;; break leaves this
  loop
    br_if exit  unless  counter < end   (counter > end when step < 0)
    i = counter
    block  body  end                   ;; continue leaves this
    counter += step
    br 0
  end
end
```

Functions with no return type have no WASM result, a bare `return` is a plain
`return`, and a call used as a statement is followed by `drop` when the callee
returns a value. `a if c else b` becomes `c ; if (result T) a else b end`.
Aliases are inlined: a use of an alias emits the alias's expression (the
optimizer replaces uses of literal aliases with the literal itself).

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

Programs that print can be run with `tests/run_wasm.js`, which supplies the
printing functions:

```
mojo -I . main.mojo build examples/hello.mojo hello.wasm
node tests/run_wasm.js hello.wasm main
```

Behaviour tests (548 checks: fib, gcd, primes, collatz, floor division with
negative numbers, short-circuiting, `break` / `continue`, constant folding,
`Float64` arithmetic and conversions, `Bool` parameters and results,
`print` output, `for` loops, aliases, conditional expressions, block scoping):

```
mojo -I . main.mojo build examples/fibonacci.mojo build/fibonacci.wasm
mojo -I . main.mojo build examples/features.mojo  build/features.wasm
mojo -I . main.mojo build examples/logic.mojo     build/logic.wasm
mojo -I . main.mojo build examples/types.mojo     build/types.wasm
mojo -I . main.mojo build examples/hello.mojo     build/hello.wasm
mojo -I . main.mojo build examples/language.mojo  build/language.wasm
node tests/behavior.js build
```

Error messages are checked against the expected text in `tests/errors/`:

```
node tests/check_errors.js
```

WAT output can be compared with `tests/wasm/*.wat`:

```
mojo -I . main.mojo wat examples/fibonacci.mojo
```

The `.hex` and `.wat` files were produced by a reference implementation of exactly this
design and validated in a real WebAssembly engine, so a mismatch points at a
bug in the Mojo code (or a Mojo-version syntax difference), not in the design.
`examples/hello.mojo` and `examples/language.mojo` cover `fn`, `print`, `for`,
`alias`, `a if c else b`, scoping and functions without a return type.
`examples/types.mojo` covers `Float64` and `Bool`. `examples/features.mojo` exercises `while`, `elif`/`else`, unary minus,
precedence, `%`, `//`, `*` and forward calls; `examples/logic.mojo` covers
`and` / `or` / `not`, compound assignment, `break` / `continue`, floor
division and constant folding.

## Roadmap

1. Run every example (including `examples/library_usage.mojo`) through the
   Mojo implementation and fix any Mojo-version syntax differences.
2. Unit tests per stage under `tests/lexer`, `tests/parser`, `tests/wasm`.
3. A `String` type (variables, parameters, concatenation, `len`), built on
   the linear memory that `print` already uses.
4. `struct`s with fields and methods (needs memory layout and pointers),
   then `List[Int]`.
5. `for x in collection`, `while ... else`, default and keyword arguments.
6. More numeric types (`Int32`, `UInt8`, `Float32`) and `Float64`
   arithmetic folding.
7. Imports between files and a standard library of `math` functions.
8. An IR in `src/ir/` between the checker and the emitter, enabling more
   optimizations (dead code removal, strength reduction).
9. Report several errors per run instead of stopping at the first, and add
   warnings (unused variables, unreachable code).
