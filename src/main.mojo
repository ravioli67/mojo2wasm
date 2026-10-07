from lexer.lexer import lex


def main():
    var source = """
def add(a: Int, b: Int) -> Int:      # Here I am not actually using the example/add.mojo just to make sure we don't misuse the api's, hurting syntax support
    return a + b
"""

    var tokens = lex(source)

    for token in tokens:
        token.dump()