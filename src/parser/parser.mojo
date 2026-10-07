from ..lexer.tokens import Token
from .ast import Parameter
from .ast import BinaryExpr
from .ast import ReturnStmt
from .ast import Function

struct Parser:
    var tokens: List[Token]
    var current: Int

    def __init__(out self, tokens: List[Token]):
        self.tokens = tokens
        self.current = 0

    def peek(self) -> Token:
        return self.tokens[self.current]

    def advance(mut self) -> Token:
        var token = self.tokens[self.current]
        self.current += 1
        return token

    def check(self, kind: String) -> Bool:
        return self.peek().kind == kind

    def expect(mut self, kind: String) -> Token:
        var token = self.advance()

        if token.kind != kind:
            print("Parser error:")
            print("Expected:", kind)
            print("Got:", token.kind)

        return token

    def parse(mut self) -> Function:
        return self.parse_function()

    def parse_function(mut self) -> Function:
        self.expect("DEF")

        var name = self.expect("IDENTIFIER").lexeme

        self.expect("LPAREN")

        var parameters = List[Parameter]()

        if not self.check("RPAREN"):
            parameters.append(self.parse_parameter())

            while self.check("COMMA"):
                self.advance()
                parameters.append(self.parse_parameter())

        self.expect("RPAREN")
        self.expect("ARROW")

        var return_type = self.expect("INT").lexeme

        self.expect("COLON")

        var body = self.parse_return()

        return Function(
            name,
            parameters,
            return_type,
            body
        )

    def parse_parameter(mut self) -> Parameter:
        var name = self.expect("IDENTIFIER").lexeme

        self.expect("COLON")

        var type_name = self.expect("INT").lexeme

        return Parameter(name, type_name)

    def parse_return(mut self) -> ReturnStmt:
        self.expect("RETURN")

        var left = self.expect("IDENTIFIER").lexeme
        var operator = self.expect("PLUS").lexeme
        var right = self.expect("IDENTIFIER").lexeme

        return ReturnStmt(
            BinaryExpr(left, operator, right)
        )