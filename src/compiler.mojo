from .lexer.lexer import lex
from .parser.parser import Parser
from .parser.ast import Module
from .sema.checker import check
from .opt.fold import fold_constants
from .wasm.emitter import emit
from .wasm.wat import emit_wat


struct Compiler:
    def __init__(out self):
        pass

    def analyze(self, source: String, optimize: Bool) raises -> Module:
        """Runs the front end: lex, parse, check, and (optionally) optimize."""
        # 1. Source -> tokens (including INDENT / DEDENT / NEWLINE)
        var tokens = lex(source)

        # 2. Tokens -> AST
        var parser = Parser(tokens)
        var module = parser.parse()

        # 3. Semantic checks (raises on the first error)
        check(module)

        # 4. Constant folding
        if optimize:
            fold_constants(module)

        return module^

    def compile(self, source: String) raises -> List[UInt8]:
        return self.compile_with(source, True)

    def compile_with(
        self, source: String, optimize: Bool
    ) raises -> List[UInt8]:
        var module = self.analyze(source, optimize)
        return emit(module)

    def compile_wat(self, source: String, optimize: Bool) raises -> String:
        var module = self.analyze(source, optimize)
        return emit_wat(module)
