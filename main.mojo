from sys import argv
from src.mojo_wasm import compile_to_file
from src.mojo_wasm import compile_to_hex
from src.mojo_wasm import validate
from src.mojo_wasm import list_functions
from src.mojo_wasm import dump_tokens
from src.mojo_wasm import dump_ast
from src.mojo_wasm import version
from src.util.files import read_file


def print_usage():
    print("mojo_wasm", version())
    print("")
    print("usage: mojo -I . main.mojo <command> <input.mojo> [output.wasm]")
    print("")
    print("commands:")
    print("  build      compile to a .wasm file   (needs output.wasm)")
    print("  hex        compile and print the bytes as hex")
    print("  check      check the program, print OK or the error")
    print("  functions  list the functions and their parameters")
    print("  tokens     print the token stream")
    print("  ast        print the parsed program")
    print("  version    print the version")
    print("")
    print("Shortcut: `main.mojo in.mojo out.wasm` is the same as `build`.")


def is_command(name: String) -> Bool:
    return (
        name == "build"
        or name == "hex"
        or name == "check"
        or name == "functions"
        or name == "tokens"
        or name == "ast"
    )


def run(command: String, input_path: String, output_path: String) raises:
    var source = read_file(input_path)

    if command == "build":
        var size = compile_to_file(source, output_path)
        print("wrote", size, "bytes to", output_path)

    elif command == "hex":
        print(compile_to_hex(source))

    elif command == "check":
        var message = validate(source)
        if message == "":
            print("OK")
        else:
            print(message)

    elif command == "functions":
        var functions = list_functions(source)
        for i in range(len(functions)):
            print(functions[i].signature())

    elif command == "tokens":
        print(dump_tokens(source))

    elif command == "ast":
        print(dump_ast(source))


def main() raises:
    var args = argv()

    if len(args) < 2:
        print_usage()
        return

    var first = String(args[1])

    if first == "version":
        print(version())
        return

    # Old form: `main.mojo in.mojo out.wasm` means `build`.
    var command = first
    var input_index = 2
    if not is_command(first):
        command = "build"
        input_index = 1

    if len(args) <= input_index:
        print_usage()
        return

    var input_path = String(args[input_index])
    var output_path = String("")

    if command == "build":
        if len(args) <= input_index + 1:
            print("error: `build` needs an output file, e.g. out.wasm")
            return
        output_path = String(args[input_index + 1])

    try:
        run(command, input_path, output_path)
    except e:
        print("error:", e)
