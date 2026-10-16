from ..lexer.tokens import Token
from ..util.diagnostics import error_at
from .ast import Parameter
from .ast import Function
from .ast import AliasDecl
from .ast import Module
from .ast import int_expr
from .ast import float_expr
from .ast import bool_expr
from .ast import string_expr
from .ast import ternary_expr
from .ast import var_expr
from .ast import neg_expr
from .ast import not_expr
from .ast import binary_expr
from .ast import logic_expr
from .ast import call_expr
from .ast import cast_expr
from .ast import return_stmt
from .ast import if_stmt
from .ast import while_stmt
from .ast import var_stmt
from .ast import assign_stmt
from .ast import break_stmt
from .ast import continue_stmt
from .ast import pass_stmt
from .ast import expr_stmt
from .ast import print_stmt
from .ast import for_stmt


def is_comparison(kind: String) -> Bool:
    return (
        kind == "LT"
        or kind == "LE"
        or kind == "GT"
        or kind == "GE"
        or kind == "EQ"
        or kind == "NE"
    )


def is_type_kind(kind: String) -> Bool:
    return kind == "INT" or kind == "FLOAT64" or kind == "BOOL"


def compound_op(kind: String) -> String:
    """The operator behind `+=`, `-=`, ... or "" if `kind` is not one."""
    if kind == "PLUSEQ":
        return "+"
    if kind == "MINUSEQ":
        return "-"
    if kind == "STAREQ":
        return "*"
    if kind == "SLASHEQ":
        return "/"
    if kind == "SLASHSLASHEQ":
        return "//"
    if kind == "PERCENTEQ":
        return "%"
    return ""


def describe_kind(kind: String) -> String:
    """How to name a token kind in "expected ..." messages."""
    if kind == "COLON":
        return "':'"
    if kind == "LPAREN":
        return "'('"
    if kind == "RPAREN":
        return "')'"
    if kind == "COMMA":
        return "','"
    if kind == "ARROW":
        return "'->'"
    if kind == "ASSIGN":
        return "'='"
    if kind == "NEWLINE":
        return "the end of the line"
    if kind == "INDENT":
        return "an indented block"
    if kind == "DEDENT":
        return "the end of the block"
    if kind == "DEF":
        return "'def'"
    if kind == "RETURN":
        return "'return'"
    if kind == "IDENTIFIER":
        return "a name"
    if is_type_kind(kind):
        return "a type"
    if kind == "EOF":
        return "the end of the file"
    return kind


def describe(token: Token) -> String:
    """How to name the token that was actually found."""
    if token.kind == "EOF":
        return "the end of the file"
    if token.kind == "NEWLINE":
        return "the end of the line"
    if token.kind == "INDENT":
        return "an unexpected indent"
    if token.kind == "DEDENT":
        return "the end of the block"
    if token.kind == "STRING":
        return "a string"
    if token.kind == "IDENTIFIER":
        return "the name '" + token.lexeme + "'"
    if token.kind == "INTEGER" or token.kind == "FLOAT":
        return "the number " + token.lexeme
    return "'" + token.lexeme + "'"


def integer_too_large(text: String) -> Bool:
    """True if the decimal digits in `text` exceed the largest Int."""
    var start = 0
    while start < len(text) - 1 and text[start : start + 1] == "0":
        start += 1
    var digits = text[start:]
    var largest = "9223372036854775807"
    if len(digits) > len(largest):
        return True
    if len(digits) < len(largest):
        return False
    return digits > largest


def parse_float_text(text: String, line: Int, column: Int) raises -> Float64:
    """Converts decimal text such as "3.14" to a Float64.

    The value is (all the digits as one integer) / 10^(digits after the
    point). With at most 15 significant digits, both numbers are exactly
    representable, so one IEEE division gives the correctly rounded result.
    """
    var whole = String("")
    var fraction = String("")
    var seen_dot = False

    for i in range(len(text)):
        var c = text[i : i + 1]
        if c == ".":
            seen_dot = True
        elif seen_dot:
            fraction += c
        else:
            whole += c

    var digits = whole + fraction

    var significant = 0
    var leading = True
    for i in range(len(digits)):
        if leading and digits[i : i + 1] == "0":
            continue
        leading = False
        significant += 1

    if significant > 15:
        raise Error(
            error_at(
                "Parser",
                line,
                column,
                (
                    "floating-point literal has too many digits (at most 15"
                    " significant digits are supported)"
                ),
            )
        )

    if len(fraction) > 22:
        raise Error(
            error_at(
                "Parser",
                line,
                column,
                (
                    "floating-point literal has too many decimal places (at"
                    " most 22)"
                ),
            )
        )

    var numerator = 0
    for i in range(len(digits)):
        numerator = numerator * 10 + Int(digits[i : i + 1])

    var scale = 1.0
    for _ in range(len(fraction)):
        scale = scale * 10.0

    return Float64(numerator) / scale


struct Parser:
    """Recursive-descent parser.

    Grammar (NEWLINE / INDENT / DEDENT come from the lexer):

      module         := (alias | function | STRING)* EOF
      alias          := ("alias" | "comptime") IDENT [":" type] "=" expr
                        NEWLINE
      function       := ("def" | "fn") IDENT "(" [param ("," param)*] ")"
                        ["raises"] ["->" (type | "None")] ":" block
      param          := IDENT ":" type
      type           := "Int" | "Float64" | "Bool"
      block          := NEWLINE INDENT statement+ DEDENT
      statement      := "return" [expr] NEWLINE
                      | if
                      | "while" expr ":" block
                      | "for" IDENT "in" "range" "(" expr ["," expr
                        ["," INTEGER]] ")" ":" block
                      | "print" "(" [expr ("," expr)*] ")" NEWLINE
                      | call NEWLINE                  (result ignored)
                      | "pass" NEWLINE
                      | STRING NEWLINE                (docstring, ignored)
                      | "var" IDENT [":" type] "=" expr NEWLINE
                      | IDENT "=" expr NEWLINE
                      | IDENT ("+=" | "-=" | "*=" | "/=" | "//=" | "%=")
                        expr NEWLINE
                      | "break" NEWLINE
                      | "continue" NEWLINE
      if             := ("if" | "elif") expr ":" block [ if_tail ]
      if_tail        := "elif" ...   |   "else" ":" block

      expr           := or_expr ["if" or_expr "else" expr]
      or_expr        := and_expr ("or" and_expr)*
      and_expr       := not_expr ("and" not_expr)*
      not_expr       := "not" not_expr | comparison
      comparison     := additive [("<"|"<="|">"|">="|"=="|"!=") additive]
      additive       := multiplicative (("+"|"-") multiplicative)*
      multiplicative := unary (("*"|"/"|"//"|"%") unary)*
      unary          := "-" unary | primary
      primary        := INTEGER | FLOAT | STRING | "True" | "False"
                      | IDENT | IDENT "(" [expr ("," expr)*] ")"
                      | type "(" expr ")"            (conversion)
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

    def fail(self, token: Token, message: String) -> Error:
        return Error(error_at("Parser", token.line, token.column, message))

    def expect(mut self, kind: String) raises -> Token:
        var token = self.advance()

        if token.kind != kind:
            raise self.fail(
                token,
                "expected "
                + describe_kind(kind)
                + " but found "
                + describe(token),
            )

        return token^

    def skip_newlines(mut self):
        while self.check("NEWLINE"):
            _ = self.advance()

    # ---- Module and functions ---------------------------------------------

    def parse(mut self) raises -> Module:
        self.skip_newlines()

        while not self.check("EOF"):
            if self.check("STRING"):
                # A module docstring: ignored.
                _ = self.advance()
                _ = self.expect("NEWLINE")
            elif self.check("ALIAS"):
                self.parse_alias()
            elif self.check("DEF"):
                var function = self.parse_function()
                self.module.functions.append(function^)
            else:
                raise self.fail(
                    self.peek(),
                    "expected 'def', 'fn' or 'alias' at the top level but"
                    " found "
                    + describe(self.peek()),
                )
            self.skip_newlines()

        return self.module.copy()

    def parse_alias(mut self) raises:
        _ = self.advance()  # "alias" / "comptime"
        var name = self.expect("IDENTIFIER")
        var type_name = String("")
        if self.check("COLON"):
            _ = self.advance()
            type_name = self.parse_type()
        _ = self.expect("ASSIGN")
        var value = self.parse_expr()
        _ = self.expect("NEWLINE")
        self.module.aliases.append(
            AliasDecl(name.lexeme, type_name, value, name.line, name.column)
        )

    def parse_type(mut self) raises -> String:
        var token = self.advance()
        if not is_type_kind(token.kind):
            raise self.fail(
                token,
                "expected a type (Int, Float64 or Bool) but found "
                + describe(token),
            )
        return token.lexeme

    def parse_function(mut self) raises -> Function:
        _ = self.expect("DEF")
        var name = self.expect("IDENTIFIER")

        _ = self.expect("LPAREN")

        var parameters = List[Parameter]()

        if not self.check("RPAREN"):
            parameters.append(self.parse_parameter())

            while self.check("COMMA"):
                _ = self.advance()
                parameters.append(self.parse_parameter())

        _ = self.expect("RPAREN")

        if self.check("RAISES"):
            _ = self.advance()  # accepted and ignored

        # No `-> type` (or `-> None`) means the function returns nothing.
        var return_type = String("")
        if self.check("ARROW"):
            _ = self.advance()
            if self.check("NONE"):
                _ = self.advance()
            else:
                return_type = self.parse_type()

        _ = self.expect("COLON")

        var body = self.parse_block()

        return Function(
            name.lexeme, parameters, return_type, body, name.line, name.column
        )

    def parse_parameter(mut self) raises -> Parameter:
        var name = self.expect("IDENTIFIER")
        _ = self.expect("COLON")
        var type_name = self.parse_type()
        return Parameter(name.lexeme, type_name, name.line, name.column)

    # ---- Statements -------------------------------------------------------

    def parse_block(mut self) raises -> List[Int]:
        _ = self.expect("NEWLINE")

        if not self.check("INDENT"):
            raise self.fail(
                self.peek(),
                "expected an indented block but found "
                + describe(self.peek()),
            )
        _ = self.advance()

        var body = List[Int]()
        body.append(self.parse_statement())

        while not self.check("DEDENT") and not self.check("EOF"):
            body.append(self.parse_statement())

        _ = self.expect("DEDENT")

        return body^

    def parse_condition(mut self) raises -> Int:
        """An expression followed by ':' (used by `if` and `while`)."""
        var condition = self.parse_expr()

        if self.check("ASSIGN"):
            raise self.fail(
                self.peek(),
                "found '=' where ':' was expected. Did you mean '==' to"
                " compare?",
            )

        _ = self.expect("COLON")
        return condition

    def parse_statement(mut self) raises -> Int:
        var token = self.peek()
        var kind = token.kind

        if kind == "RETURN":
            _ = self.advance()
            var value = -1
            if not self.check("NEWLINE"):
                value = self.parse_expr()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(
                return_stmt(value, token.line, token.column)
            )

        if kind == "BREAK":
            _ = self.advance()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(break_stmt(token.line, token.column))

        if kind == "CONTINUE":
            _ = self.advance()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(
                continue_stmt(token.line, token.column)
            )

        if kind == "PASS":
            _ = self.advance()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(pass_stmt(token.line, token.column))

        if kind == "STRING":
            # A docstring (or any bare string): ignored.
            _ = self.advance()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(pass_stmt(token.line, token.column))

        if kind == "IF":
            return self.parse_if()

        if kind == "FOR":
            return self.parse_for()

        if kind == "WHILE":
            _ = self.advance()
            var condition = self.parse_condition()
            var body = self.parse_block()
            return self.module.add_stmt(
                while_stmt(condition, body, token.line, token.column)
            )

        if kind == "VAR":
            _ = self.advance()
            var name = self.expect("IDENTIFIER")
            var type_name = String("")
            if self.check("COLON"):
                _ = self.advance()
                type_name = self.parse_type()
            _ = self.expect("ASSIGN")
            var value = self.parse_expr()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(
                var_stmt(name.lexeme, type_name, value, name.line, name.column)
            )

        if kind == "IDENTIFIER" and self.peek_at(1).kind == "ASSIGN":
            var name = self.advance()
            _ = self.advance()  # "="
            var value = self.parse_expr()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(
                assign_stmt(name.lexeme, value, name.line, name.column)
            )

        if kind == "IDENTIFIER" and compound_op(self.peek_at(1).kind) != "":
            # `x += e` becomes `x = x + e`
            var name = self.advance()
            var operator = self.advance()
            var op = compound_op(operator.kind)
            var value = self.parse_expr()
            _ = self.expect("NEWLINE")
            var current = self.module.add_expr(
                var_expr(name.lexeme, name.line, name.column)
            )
            var combined = self.module.add_expr(
                binary_expr(op, current, value, operator.line, operator.column)
            )
            return self.module.add_stmt(
                assign_stmt(name.lexeme, combined, name.line, name.column)
            )

        if (
            kind == "IDENTIFIER"
            and token.lexeme == "print"
            and self.peek_at(1).kind == "LPAREN"
        ):
            _ = self.advance()
            _ = self.advance()  # "("
            var args = List[Int]()
            if not self.check("RPAREN"):
                args.append(self.parse_expr())
                while self.check("COMMA"):
                    _ = self.advance()
                    args.append(self.parse_expr())
            _ = self.expect("RPAREN")
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(
                print_stmt(args, token.line, token.column)
            )

        if kind == "IDENTIFIER" and self.peek_at(1).kind == "LPAREN":
            # A call whose result is ignored.
            var call = self.parse_expr()
            _ = self.expect("NEWLINE")
            return self.module.add_stmt(
                expr_stmt(call, token.line, token.column)
            )

        if (
            kind == "IDENTIFIER"
            or kind == "INTEGER"
            or kind == "FLOAT"
            or kind == "LPAREN"
            or kind == "TRUE"
            or kind == "FALSE"
            or kind == "MINUS"
            or kind == "NOT"
            or is_type_kind(kind)
        ):
            raise self.fail(
                token,
                "this is not a statement. A statement can be an assignment"
                " (x = ...), a function call (f(x)) or start with a keyword"
                " such as 'return' or 'if'",
            )

        raise self.fail(
            token,
            "unexpected " + describe(token) + " at the start of a statement",
        )

    def parse_for(mut self) raises -> Int:
        # for NAME in range(stop) / range(start, stop) / range(start, stop, step)
        var token = self.advance()
        var variable = self.expect("IDENTIFIER")
        _ = self.expect("IN")
        var range_token = self.expect("IDENTIFIER")

        if range_token.lexeme != "range":
            raise self.fail(
                range_token,
                "only 'for ... in range(...)' loops are supported for now",
            )

        _ = self.expect("LPAREN")
        var arguments = List[Int]()
        if not self.check("RPAREN"):
            arguments.append(self.parse_expr())
            while self.check("COMMA"):
                _ = self.advance()
                arguments.append(self.parse_expr())
        _ = self.expect("RPAREN")

        if len(arguments) == 0 or len(arguments) > 3:
            raise self.fail(range_token, "range() takes 1 to 3 arguments")

        # The step must be a literal so the direction of the loop is known.
        var step = 1
        if len(arguments) == 3:
            var third = self.module.exprs[arguments[2]].copy()
            if third.kind == "INT":
                step = third.value
            elif third.kind == "NEG" and self.module.exprs[third.left].kind == "INT":
                step = 0 - self.module.exprs[third.left].value
            else:
                raise Error(
                    error_at(
                        "Parser",
                        third.line,
                        third.column,
                        "the step of range() must be an integer literal (like"
                        " 2 or -1)",
                    )
                )
            if step == 0:
                raise Error(
                    error_at(
                        "Parser",
                        third.line,
                        third.column,
                        "the step of range() cannot be 0",
                    )
                )

        # Normalize to [start, stop].
        var bounds = List[Int]()
        if len(arguments) == 1:
            bounds.append(
                self.module.add_expr(int_expr(0, token.line, token.column))
            )
            bounds.append(arguments[0])
        else:
            bounds.append(arguments[0])
            bounds.append(arguments[1])

        _ = self.expect("COLON")
        var body = self.parse_block()

        return self.module.add_stmt(
            for_stmt(
                variable.lexeme,
                bounds,
                body,
                step,
                variable.line,
                variable.column,
            )
        )

    def parse_if(mut self) raises -> Int:
        # Consumes "if" or "elif".
        var token = self.advance()
        var condition = self.parse_condition()
        var body = self.parse_block()

        var else_body = List[Int]()
        if self.check("ELIF"):
            # `elif` is an `if` nested inside the else branch.
            else_body.append(self.parse_if())
        elif self.check("ELSE"):
            _ = self.advance()
            _ = self.expect("COLON")
            else_body = self.parse_block()

        return self.module.add_stmt(
            if_stmt(condition, body, else_body, token.line, token.column)
        )

    # ---- Expressions (each returns an index into Module.exprs) ------------

    def parse_expr(mut self) raises -> Int:
        var value = self.parse_or()

        # a if condition else b
        if self.check("IF"):
            var operator = self.advance()
            var condition = self.parse_or()
            _ = self.expect("ELSE")
            var other = self.parse_expr()
            return self.module.add_expr(
                ternary_expr(
                    value, other, condition, operator.line, operator.column
                )
            )

        return value

    def parse_or(mut self) raises -> Int:
        var left = self.parse_and()

        while self.check("OR"):
            var operator = self.advance()
            var right = self.parse_and()
            left = self.module.add_expr(
                logic_expr("or", left, right, operator.line, operator.column)
            )

        return left

    def parse_and(mut self) raises -> Int:
        var left = self.parse_not()

        while self.check("AND"):
            var operator = self.advance()
            var right = self.parse_not()
            left = self.module.add_expr(
                logic_expr("and", left, right, operator.line, operator.column)
            )

        return left

    def parse_not(mut self) raises -> Int:
        if self.check("NOT"):
            var operator = self.advance()
            var operand = self.parse_not()
            return self.module.add_expr(
                not_expr(operand, operator.line, operator.column)
            )

        return self.parse_comparison()

    def parse_comparison(mut self) raises -> Int:
        var left = self.parse_additive()

        if is_comparison(self.peek().kind):
            var operator = self.advance()
            var right = self.parse_additive()
            left = self.module.add_expr(
                binary_expr(
                    operator.lexeme,
                    left,
                    right,
                    operator.line,
                    operator.column,
                )
            )

            if is_comparison(self.peek().kind):
                raise self.fail(
                    self.peek(),
                    "comparisons cannot be chained. Use 'and', e.g. a < b and"
                    " b < c",
                )

        return left

    def parse_additive(mut self) raises -> Int:
        var left = self.parse_multiplicative()

        while self.check("PLUS") or self.check("MINUS"):
            var operator = self.advance()
            var right = self.parse_multiplicative()
            left = self.module.add_expr(
                binary_expr(
                    operator.lexeme,
                    left,
                    right,
                    operator.line,
                    operator.column,
                )
            )

        return left

    def parse_multiplicative(mut self) raises -> Int:
        var left = self.parse_unary()

        while (
            self.check("STAR")
            or self.check("SLASH")
            or self.check("SLASHSLASH")
            or self.check("PERCENT")
        ):
            var operator = self.advance()
            var right = self.parse_unary()
            left = self.module.add_expr(
                binary_expr(
                    operator.lexeme,
                    left,
                    right,
                    operator.line,
                    operator.column,
                )
            )

        return left

    def parse_unary(mut self) raises -> Int:
        if self.check("MINUS"):
            var operator = self.advance()
            var operand = self.parse_unary()
            return self.module.add_expr(
                neg_expr(operand, operator.line, operator.column)
            )

        return self.parse_primary()

    def parse_primary(mut self) raises -> Int:
        var token = self.peek()
        var kind = token.kind

        if kind == "INTEGER":
            _ = self.advance()
            if integer_too_large(token.lexeme):
                raise self.fail(
                    token,
                    "integer literal is too large (the largest Int is"
                    " 9223372036854775807)",
                )
            return self.module.add_expr(
                int_expr(Int(token.lexeme), token.line, token.column)
            )

        if kind == "FLOAT":
            _ = self.advance()
            var value = parse_float_text(token.lexeme, token.line, token.column)
            return self.module.add_expr(
                float_expr(token.lexeme, value, token.line, token.column)
            )

        if kind == "STRING":
            _ = self.advance()
            return self.module.add_expr(
                string_expr(token.lexeme, token.line, token.column)
            )

        if kind == "TRUE" or kind == "FALSE":
            _ = self.advance()
            var truth = 0
            if kind == "TRUE":
                truth = 1
            return self.module.add_expr(
                bool_expr(truth, token.line, token.column)
            )

        # Conversion: Int(x), Float64(x), Bool(x)
        if is_type_kind(kind):
            _ = self.advance()
            if not self.check("LPAREN"):
                raise self.fail(
                    self.peek(),
                    "expected '(' after the type name "
                    + token.lexeme
                    + " (to convert a value, write "
                    + token.lexeme
                    + "(x))",
                )
            _ = self.advance()
            var operand = self.parse_expr()
            _ = self.expect("RPAREN")
            return self.module.add_expr(
                cast_expr(token.lexeme, operand, token.line, token.column)
            )

        if kind == "IDENTIFIER":
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
                    call_expr(token.lexeme, args, token.line, token.column)
                )

            # Variable
            return self.module.add_expr(
                var_expr(token.lexeme, token.line, token.column)
            )

        if kind == "LPAREN":
            _ = self.advance()
            var inner = self.parse_expr()
            _ = self.expect("RPAREN")
            return inner

        raise self.fail(
            token, "expected a value but found " + describe(token)
        )
