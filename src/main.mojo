from lexer.lexer import lex
from parser.parser import Parser


def main():
    var source = """
def add(a: Int, b: Int) -> Int:
    return a + b
"""

    var tokens = lex(source)

    var parser = Parser(tokens)

    var function = parser.parse()

    print("Function:", function.name)
    print("Return type:", function.return_type)
    print("Parameters:", len(function.parameters))