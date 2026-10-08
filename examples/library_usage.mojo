# Shows how another Mojo program can use mojo_wasm as a library.
#
# Run from the repo root:   mojo -I . examples/library_usage.mojo
from src.mojo_wasm import compile
from src.mojo_wasm import try_compile
from src.mojo_wasm import compile_to_hex
from src.mojo_wasm import validate
from src.mojo_wasm import list_functions
from src.mojo_wasm import dump_ast


def main() raises:
    var source = (
        "def add(a: Int, b: Int) -> Int:\n"
        + "    return a + b\n"
        + "\n"
        + "def double(x: Int) -> Int:\n"
        + "    return add(x, x)\n"
    )

    # 1. Compile to bytes
    var wasm = compile(source)
    print("compiled", len(wasm), "bytes")

    # 2. Or as a readable hex string
    print(compile_to_hex(source))

    # 3. Ask what the module exports
    var functions = list_functions(source)
    for i in range(len(functions)):
        print("exports:", functions[i].signature())

    # 4. Look at the parsed program
    print(dump_ast(source))

    # 5. Handle errors without try/except
    var bad = "def f(a: Int) -> Int:\n    return a + z\n"

    var message = validate(bad)
    if message != "":
        print("validate says:", message)

    var result = try_compile(bad)
    if not result.ok:
        print("try_compile says:", result.error)
