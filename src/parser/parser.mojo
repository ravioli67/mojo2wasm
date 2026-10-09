from ..lexer.tokens import Token
from .ast import Parameter
from .ast import Function
from .ast import Module
from .ast import int_expr
from .ast import var_expr
from .ast import binary_expr
from .ast import call_expr
from .ast import logic_expr
from .ast import not_expr
from .ast import return_stmt
from .ast import if_stmt
from .ast import while_stmt
from .ast import var_stmt
from .ast import assign_stmt
from .ast import break_stmt
from .ast import continue_stmt


def is_comparison(kind: String) -> Bool:
    return (
        kind == "LT"
        or kind == "LE"
        or kind == "GT"
        or kind == "GE"
        or kind == "EQ"
        or kind == "NE"
    )


def compound_op(kind: String) -> String:
    """The operator behind `+=`, `-=`, ... or "" if `kind` is not one."""
    if kind == "PLUSEQ":
        return "+"
    if kind == "MINUSEQ":
        return "-"
    if kind == "STAREQ":
        return "*"
    if kind == "SLASHSLASHEQ":
        return "//"
    if kind == "PERCENTEQ":
        return "%"
    return ""


struct Parser:
    """Recursive-descent parser.

    Grammar (NEWLINE / INDENT / DEDENT come from the lexer):

      module         := (function)* EOF
      function       := "def" IDENT "(" [param ("," param)*] ")" "->" "Int"
                        ":" block
      param          := IDENT ":" "Int"
      block          := NEWLINE INDENT statement+ DEDENT
      statement      := "return" expr NEWLINE
                      | if
                      | "while" expr ":" block
                      | "var" IDENT [":" "Int"] "=" expr NEWLINE
                      | IDENT "=" expr NEWLINE
                      | IDENT ("+=" | "-=" | "*=" | "//=" | "%=") expr NEWLINE
                      | "break" NEWLINE
                      | "continue" NEWLINE
      if             := ("if" | "elif") expr ":" block
                        [ if_tail ]
      if_tail        := "elif" ...   |   "else" ":" block

      expr           := and_expr ("or" and_expr)*
      and_expr       := not_expr ("and" not_expr)*
      not_expr       := "not" not_expr | comparison
      comparison     := additive [("<"|"<="|">"|">="|"=="|"!=") additive]
      additive       := multiplicative (("+"|"-") multiplicative)*
      multiplicative := unary (("*"|"//"|"%") unary)*
      unary          := "-" unary | primary
      primary        := INTEGER | IDENT | IDENT "(" [expr ("," expr)*] ")"
                      | "(" expr ")"
    """

    var tokens: List[Token]
    var current: Int
    var module: Module

    def __init__(out self, tokens: List[Token]):
        self.tokens = tokens.copy()
        self.current = 0
        self.module = Module()

    # ---- Token helpers ----------------------------------------------------

    def peek_at(self, offset: Int) -> Token:
        # Never read past the last token (EOF).
        var index = self.current + offset
        if index >= len(self.tokens):
            index = len(self.tokens) - 1
        return self.tokens[index].copy()

    def peek(self) -> Token:
        return self.peek_at(0)

    def advance(mut self) -> Token:
        var token = self.peek()
        # Stay on EOF instead of running off the end.
        if self.current < len(self.tokens) - 1:
            self.current += 1
        return token^

    def check(self, kind: String) -> Bool:
        return self.peek().kind == kind

    def expect(mut self, kind: String) raises -> Token:
        var token = self.advance()

        if token.kind != kind:
            raise Error(
                "Parser error on line "
                + String(token.line)
                + ": expected "
                + kind
                + " but got "
                + token.kind
            )

        return token^

    def skip_newlines(mut self):
        while self.check("NEWLINE"):
            _ = self.advance()

    # ---- Module and functions ---------------------------------------------

    def parse(mut self) raises -> Module:
        self.skip_newlines()

        while not self.check("EOF"):
            var function = self.parse_function()
            self.module.functions.append(function^)
            self.skip_newlines()

        return self.module.copy()

    def parse_function(mut self) raises -> Function:
        var line = self.expect("DEF").line
        var name = self.expect("IDENTIFIER").lexeme

        _ = self.expect("LPAREN")

        var parameters = List[Parameter]()

        if not self.check("RPAREN"):
            parameters.append(self.parse_parameter())

            while self.check("COMMA"):
                _ = self.advance()
                parameters.append(self.parse_parameter())

        _ = self.expect("RPAREN")
        _ = self.expect("ARROW")

        var return_type = self.expect("INT").lexeme

        _ = self.expect("COLON")

        var body = self.parse_block()

        return Function(name, parameters, return_type, body, line)

    def parse_parameter(mut self) raises -> Parameter:
        var name = self.expect("IDENTIFIER").lexeme
        _ = self.expect("COLON")
        var type_name = self.expect("INT").lexeme
        return Parameter(name, type_name)

    # ---- Statements -------------------------------------------------------

    def parse_block(mut self) raises -> List[Int]:
        _ = self.expect("NEWLINE")
        _ = self.expect("INDENT")

        var body = List[Int]()
        body.append(self.parse_statement())

        while not self.check("DEDENT") and not self.check("EOF"):
            body.append(self.parse_statement())

        _ = self.expect("DEDENT")

        return body^

    def parse_statement(mut self) raises -> Int:
        var kind = self.peek().kind
        var line = self.peek().line

        if kind == "RETURN":
            _ = self.advance()
            var value = self.parse_expr()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(return_stmt(value, line))

        if kind == "BREAK":
            _ = self.advance()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(break_stmt(line))

        if kind == "CONTINUE":
            _ = self.advance()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(continue_stmt(line))

        if kind == "IF":
            return self.parse_if()

        if kind == "WHILE":
            _ = self.advance()
            var condition = self.parse_expr()
            _ = self.expect("COLON")
            var body = self.parse_block()
            return self.module.add_stmt(while_stmt(condition, body, line))

        if kind == "VAR":
            _ = self.advance()
            var name = self.expect("IDENTIFIER").lexeme
            if self.check("COLON"):
                _ = self.advance()
                _ = self.expect("INT")
            _ = self.expect("ASSIGN")
            var value = self.parse_expr()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(var_stmt(name, value, line))

        if kind == "IDENTIFIER" and self.peek_at(1).kind == "ASSIGN":
            var name = self.advance().lexeme
            _ = self.advance()  # "="
            var value = self.parse_expr()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(assign_stmt(name, value, line))

        if kind == "IDENTIFIER" and compound_op(self.peek_at(1).kind) != "":
            # `x += e` becomes `x = x + e`
            var name = self.advance().lexeme
            var op = compound_op(self.advance().kind)
            var value = self.parse_expr()
            _ = self.expect("NEWLINE")
            var current = self.module.add_expr(var_expr(name, line))
            var combined = self.module.add_expr(
                binary_expr(op, current, value, line)
            )
            return self.module.add_stmt(assign_stmt(name, combined, line))

        raise Error(
            "Parser error on line "
            + String(line)
            + ": unexpected "
            + kind
            + " at the start of a statement"
        )

    def parse_if(mut self) raises -> Int:
        # Consumes "if" or "elif".
        var line = self.advance().line
        var condition = self.parse_expr()
        _ = self.expect("COLON")
        var body = self.parse_block()

        var else_body = List[Int]()
        if self.check("ELIF"):
            # `elif` is an `if` nested inside the else branch.
            else_body.append(self.parse_if())
        elif self.check("ELSE"):
            _ = self.advance()
            _ = self.expect("COLON")
            else_body = self.parse_block()

        return self.module.add_stmt(if_stmt(condition, body, else_body, line))

    # ---- Expressions (each returns an index into Module.exprs) ------------

    def parse_expr(mut self) raises -> Int:
        return self.parse_or()

    def parse_or(mut self) raises -> Int:
        var left = self.parse_and()

        while self.check("OR"):
            var operator = self.advance()
            var right = self.parse_and()
            left = self.module.add_expr(
                logic_expr("or", left, right, operator.line)
            )

        return left

    def parse_and(mut self) raises -> Int:
        var left = self.parse_not()

        while self.check("AND"):
            var operator = self.advance()
            var right = self.parse_not()
            left = self.module.add_expr(
                logic_expr("and", left, right, operator.line)
            )

        return left

    def parse_not(mut self) raises -> Int:
        if self.check("NOT"):
            var line = self.advance().line
            var operand = self.parse_not()
            return self.module.add_expr(not_expr(operand, line))

        return self.parse_comparison()

    def parse_comparison(mut self) raises -> Int:
        var left = self.parse_additive()

        if is_comparison(self.peek().kind):
            var operator = self.advance()
            var right = self.parse_additive()
            return self.module.add_expr(
                binary_expr(operator.lexeme, left, right, operator.line)
            )

        return left

    def parse_additive(mut self) raises -> Int:
        var left = self.parse_multiplicative()

        while self.check("PLUS") or self.check("MINUS"):
            var operator = self.advance()
            var right = self.parse_multiplicative()
            left = self.module.add_expr(
                binary_expr(operator.lexeme, left, right, operator.line)
            )

        return left

    def parse_multiplicative(mut self) raises -> Int:
        var left = self.parse_unary()

        while (
            self.check("STAR")
            or self.check("SLASHSLASH")
            or self.check("PERCENT")
        ):
            var operator = self.advance()
            var right = self.parse_unary()
            left = self.module.add_expr(
                binary_expr(operator.lexeme, left, right, operator.line)
            )

        return left

    def parse_unary(mut self) raises -> Int:
        if self.check("MINUS"):
            # -x is parsed as 0 - x
            var line = self.advance().line
            var zero = self.module.add_expr(int_expr(0, line))
            var operand = self.parse_unary()
            return self.module.add_expr(binary_expr("-", zero, operand, line))

        return self.parse_primary()

    def parse_primary(mut self) raises -> Int:
        var token = self.peek()

        if token.kind == "INTEGER":
            _ = self.advance()
            return self.module.add_expr(
                int_expr(Int(token.lexeme), token.line)
            )

        if token.kind == "IDENTIFIER":
            _ = self.advance()

            # Function call
            if self.check("LPAREN"):
                _ = self.advance()
                var args = List[Int]()

                if not self.check("RPAREN"):
                    args.append(self.parse_expr())
                    while self.check("COMMA"):
                        _ = self.advance()
                        args.append(self.parse_expr())

                _ = self.expect("RPAREN")
                return self.module.add_expr(
                    call_expr(token.lexeme, args, token.line)
                )

            # Variable
            return self.module.add_expr(var_expr(token.lexeme, token.line))

        if token.kind == "LPAREN":
            _ = self.advance()
            var inner = self.parse_expr()
            _ = self.expect("RPAREN")
            return inner

        raise Error(
            "Parser error on line "
            + String(token.line)
            + ": expected an expression but got "
            + token.kind
        )
