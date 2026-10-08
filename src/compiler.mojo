from .lexer.lexer import lex
from .parser.parser import Parser
from .sema.checker import check
from .wasm.emitter import emit


struct Compiler:
    def __init__(out self):
        pass

    def compile(self, source: String) raises -> List[UInt8]:
        # 1. Source -> tokens (including INDENT / DEDENT / NEWLINE)
        var tokens = lex(source)

        # 2. Tokens -> AST
        var parser = Parser(tokens)
        var module = parser.parse()

        # 3. Semantic checks (raises on the first error)
        check(module)

        # 4. AST -> WASM bytes
        return emit(module)
