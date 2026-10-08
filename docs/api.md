# mojo_wasm Library API

Everything is importable from one module:

```mojo
from src.mojo_wasm import compile, try_compile, validate
```

(Run your program from the repo root with `mojo -I . your_file.mojo` so that
`src` can be found.)

## Error handling

Functions marked **raises** raise an `Error` when the program is invalid. The
message starts with one of `Lexer error`, `Parser error`, `Semantic error` or
`Emitter error`, and includes the line number when known:

```
Semantic error on line 2: unknown variable 'z'
```

If you prefer values to exceptions, use `try_compile` or `validate`.

## Compiling

| Function | Returns | Description |
|----------|---------|-------------|
| `compile(source: String)` **raises** | `List[UInt8]` | Compile source to the bytes of a `.wasm` module. |
| `try_compile(source: String)` | `CompileResult` | Same, but never raises. Check `result.ok`, then use `result.wasm` or `result.error`. |
| `compile_to_hex(source: String)` **raises** | `String` | Compile and format as hex, e.g. `00 61 73 6d 01 00 00 00 ...`. |
| `compile_to_file(source: String, output_path: String)` **raises** | `Int` | Compile and write the `.wasm` file. Returns the number of bytes written. |
| `compile_file(input_path: String, output_path: String)` **raises** | `Int` | Read a source file, compile it, write the `.wasm` file. |

### `CompileResult`

| Field | Type | Meaning |
|-------|------|---------|
| `ok` | `Bool` | `True` if compilation succeeded |
| `wasm` | `List[UInt8]` | The module bytes (empty if `ok` is `False`) |
| `error` | `String` | The error message (empty if `ok` is `True`) |

```mojo
var result = try_compile(source)
if result.ok:
    print("compiled", len(result.wasm), "bytes")
else:
    print("failed:", result.error)
```

## Checking and inspecting

| Function | Returns | Description |
|----------|---------|-------------|
| `validate(source: String)` | `String` | Runs every stage except code generation. Returns `""` if the program is valid, otherwise the error message. |
| `is_valid(source: String)` | `Bool` | `True` if `validate` finds no problem. |
| `list_functions(source: String)` **raises** | `List[FunctionInfo]` | Describes each function of the (checked) program, in the order they become WASM exports. |
| `tokenize(source: String)` **raises** | `List[Token]` | The token stream, including `NEWLINE`, `INDENT`, `DEDENT` and `EOF`. |
| `parse(source: String)` **raises** | `Module` | The parsed program (no semantic checks). |

### `FunctionInfo`

| Member | Type | Meaning |
|--------|------|---------|
| `name` | `String` | Function name (also its WASM export name) |
| `parameters` | `List[String]` | Parameter names, in order |
| `return_type` | `String` | Always `Int` for now |
| `parameter_count()` | `Int` | Number of parameters |
| `signature()` | `String` | e.g. `add(a, b) -> Int` |

## Debug output

| Function | Returns | Description |
|----------|---------|-------------|
| `dump_tokens(source: String)` **raises** | `String` | One token per line: `line:KIND 'lexeme'` |
| `dump_ast(source: String)` **raises** | `String` | The parsed program as an indented outline |

`dump_tokens` for `examples/add.mojo`:

```
1:DEF 'def'
1:IDENTIFIER 'add'
1:LPAREN '('
1:IDENTIFIER 'a'
1:COLON ':'
1:INT 'Int'
1:COMMA ','
1:IDENTIFIER 'b'
1:COLON ':'
1:INT 'Int'
1:RPAREN ')'
1:ARROW '->'
1:INT 'Int'
1:COLON ':'
1:NEWLINE '\n'
2:INDENT
2:RETURN 'return'
2:IDENTIFIER 'a'
2:PLUS '+'
2:IDENTIFIER 'b'
2:NEWLINE '\n'
3:DEDENT
3:EOF
```

`dump_ast` for `examples/fibonacci.mojo` (expressions are in prefix form):

```
def fib(n: Int) -> Int
  if (< n 2)
    return n
  return (+ (call fib (- n 1)) (call fib (- n 2)))

def fib_iter(n: Int) -> Int
  var a = 0
  var b = 1
  var i = 0
  while (< i n)
    var t = (+ a b)
    a = b
    b = t
    i = (+ i 1)
  return a
```

## Utilities

| Function | Module | Description |
|----------|--------|-------------|
| `version() -> String` | `src.mojo_wasm` | The library version |
| `to_hex(data: List[UInt8]) -> String` | `src.util.hex` | Bytes as `"00 61 73 ..."` |
| `read_file(path: String) raises -> String` | `src.util.files` | Read a text file |
| `write_file(path: String, data: List[UInt8]) raises` | `src.util.files` | Write bytes to a file |

## Command line

`main.mojo` is a thin wrapper over this API:

```
mojo -I . main.mojo build     examples/fibonacci.mojo fib.wasm
mojo -I . main.mojo hex       examples/add.mojo
mojo -I . main.mojo check     examples/features.mojo
mojo -I . main.mojo functions examples/features.mojo
mojo -I . main.mojo tokens    examples/add.mojo
mojo -I . main.mojo ast       examples/fibonacci.mojo
mojo -I . main.mojo version
```

The older form `main.mojo input.mojo output.wasm` still works and means `build`.

## Complete example

See `examples/library_usage.mojo`.
