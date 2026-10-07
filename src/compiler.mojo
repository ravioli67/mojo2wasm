from .lexer.lexer import lex
from .parser.parser import Parser


struct Compiler:

    def __init__(out self):
        pass

    def compile(self, source: String) -> String:
        # 1. Source - tokens
        var tokens = lex(source)

        # 2. Tokens - AST
        var parser = Parser(tokens)
        var ast = parser.parse()

        # 3. AST - WASM
        #
        # Not implemented yet.
        #
        # For now, prove that the front-end worked.
        return ast.name