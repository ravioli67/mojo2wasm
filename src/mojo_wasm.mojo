"""mojo_wasm public API.

Everything a library user needs is importable from this one module:

    from src.mojo_wasm import compile, try_compile, validate

Functions that can fail are marked `raises` and raise an `Error` whose
message starts with `Lexer error`, `Parser error`, `Semantic error` or
`Emitter error`. If you would rather not use try/except, use
`try_compile` or `validate`, which return the error as a value instead.
"""

from .compiler import Compiler
from .lexer.lexer import lex
from .lexer.tokens import Token
from .parser.parser import Parser
from .parser.ast import Module
from .sema.checker import check
from .util.hex import to_hex
from .util.files import read_file
from .util.files import write_file
from .util.dump import format_tokens
from .util.dump import format_module


def version() -> String:
    return "0.3.0"


# ---------------------------------------------------------------------------
# Result types
# ---------------------------------------------------------------------------


struct CompileResult(Copyable, Movable):
    """What `try_compile` returns. Check `ok` first."""

    var ok: Bool
    var wasm: List[UInt8]  # the module bytes; empty when ok is False
    var error: String  # the error message; empty when ok is True

    def __init__(out self, ok: Bool, wasm: List[UInt8], error: String):
        self.ok = ok
        self.wasm = wasm.copy()
        self.error = error


struct FunctionInfo(Copyable, Movable):
    """Describes one function in a source file (see `list_functions`)."""

    var name: String
    var parameters: List[String]  # parameter names, in order
    var return_type: String

    def __init__(
        out self, name: String, parameters: List[String], return_type: String
    ):
        self.name = name
        self.parameters = parameters.copy()
        self.return_type = return_type

    def parameter_count(self) -> Int:
        return len(self.parameters)

    def signature(self) -> String:
        """For example `add(a, b) -> Int`."""
        var out = self.name + "("
        for i in range(len(self.parameters)):
            if i > 0:
                out += ", "
            out += self.parameters[i]
        out += ") -> " + self.return_type
        return out^


# ---------------------------------------------------------------------------
# Compiling
# ---------------------------------------------------------------------------


def compile(source: String) raises -> List[UInt8]:
    """Compiles Mojo source to the bytes of a .wasm module."""
    var compiler = Compiler()
    return compiler.compile(source)


def try_compile(source: String) -> CompileResult:
    """Like `compile`, but never raises: errors come back in the result."""
    try:
        var wasm = compile(source)
        return CompileResult(True, wasm, "")
    except e:
        return CompileResult(False, List[UInt8](), String(e))


def compile_unoptimized(source: String) raises -> List[UInt8]:
    """Like `compile`, but skips constant folding (handy for debugging)."""
    var compiler = Compiler()
    return compiler.compile_with(source, False)


def compile_to_wat(source: String) raises -> String:
    """Compiles to WebAssembly text format (WAT) instead of bytes.

    The text describes exactly the same program as `compile` produces, and
    can be fed to tools such as `wat2wasm`.
    """
    var compiler = Compiler()
    return compiler.compile_wat(source, True)


def compile_to_hex(source: String) raises -> String:
    """Compiles and formats the bytes as hex, e.g. "00 61 73 6d ..."."""
    return to_hex(compile(source))


def compile_to_file(source: String, output_path: String) raises -> Int:
    """Compiles `source` and writes the .wasm file. Returns the byte count."""
    var wasm = compile(source)
    write_file(output_path, wasm)
    return len(wasm)


def compile_file(input_path: String, output_path: String) raises -> Int:
    """Reads a source file, compiles it, writes the .wasm file.
    Returns the number of bytes written."""
    return compile_to_file(read_file(input_path), output_path)


# ---------------------------------------------------------------------------
# Checking and inspecting
# ---------------------------------------------------------------------------


def parse(source: String) raises -> Module:
    """Lexes and parses `source` into a Module (no semantic checks)."""
    var parser = Parser(lex(source))
    return parser.parse()


def tokenize(source: String) raises -> List[Token]:
    """Returns the tokens of `source`, including NEWLINE/INDENT/DEDENT/EOF."""
    return lex(source)


def validate(source: String) -> String:
    """Runs every stage except code generation.

    Returns "" if the program is valid, otherwise the error message.
    """
    try:
        var module = parse(source)
        check(module)
        return ""
    except e:
        return String(e)


def is_valid(source: String) -> Bool:
    return validate(source) == ""


def list_functions(source: String) raises -> List[FunctionInfo]:
    """Describes every function in `source` (the checked program).

    Useful for tools that load the compiled module and need to know which
    exports exist and how many arguments each takes.
    """
    var module = parse(source)
    check(module)

    var infos = List[FunctionInfo]()
    for i in range(len(module.functions)):
        var function = module.functions[i].copy()
        var names = List[String]()
        for p in range(len(function.parameters)):
            names.append(function.parameters[p].name)
        infos.append(FunctionInfo(function.name, names, function.return_type))

    return infos^


# ---------------------------------------------------------------------------
# Debug output
# ---------------------------------------------------------------------------


def dump_tokens(source: String) raises -> String:
    """The token stream as text, one token per line (`line:KIND 'lexeme'`)."""
    return format_tokens(lex(source))


def dump_ast(source: String) raises -> String:
    """The parsed program as an indented outline with prefix expressions."""
    return format_module(parse(source))
