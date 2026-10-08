from sys import argv
from src.mojo_wasm import compile


def main() raises:
    """Usage:  mojo -I . main.mojo examples/fibonacci.mojo out.wasm"""
    var args = argv()

    if len(args) < 3:
        print("usage: mojo -I . main.mojo <input.mojo> <output.wasm>")
        return

    var input_file = open(String(args[1]), "r")
    var source = input_file.read()
    input_file.close()

    var wasm = compile(source)

    var output_file = open(String(args[2]), "w")
    output_file.write_bytes(wasm)
    output_file.close()

    print("wrote", len(wasm), "bytes to", String(args[2]))
