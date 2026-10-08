"""Human-readable dumps of the compiler's intermediate results."""

from ..lexer.tokens import Token
from ..parser.ast import Module


def spaces(count: Int) -> String:
    var out = String()
    for _ in range(count):
        out += " "
    return out^


def format_tokens(tokens: List[Token]) -> String:
    """One token per line:  `line:KIND 'lexeme'`."""
    var out = String()
    for i in range(len(tokens)):
        var token = tokens[i].copy()
        out += String(token.line) + ":" + token.kind
        if token.lexeme != "":
            out += " '" + token.lexeme + "'"
        out += "\n"
    return out^


def format_expr(module: Module, index: Int) -> String:
    """Expressions in prefix form: `(+ a (* b 2))`, `(call fib (- n 1))`."""
    var expr = module.exprs[index].copy()

    if expr.kind == "INT":
        return String(expr.value)

    if expr.kind == "VAR":
        return expr.name

    if expr.kind == "BINARY":
        return (
            "("
            + expr.op
            + " "
            + format_expr(module, expr.left)
            + " "
            + format_expr(module, expr.right)
            + ")"
        )

    var out = "(call " + expr.name
    for i in range(len(expr.args)):
        out += " " + format_expr(module, expr.args[i])
    out += ")"
    return out^


def format_block(module: Module, body: List[Int], depth: Int) -> String:
    var out = String()

    for i in range(len(body)):
        var stmt = module.stmts[body[i]].copy()
        var indent = spaces(depth * 2)

        if stmt.kind == "RETURN":
            out += indent + "return " + format_expr(module, stmt.expr) + "\n"

        elif stmt.kind == "IF":
            out += indent + "if " + format_expr(module, stmt.expr) + "\n"
            out += format_block(module, stmt.body, depth + 1)
            if len(stmt.else_body) > 0:
                out += indent + "else\n"
                out += format_block(module, stmt.else_body, depth + 1)

        elif stmt.kind == "WHILE":
            out += indent + "while " + format_expr(module, stmt.expr) + "\n"
            out += format_block(module, stmt.body, depth + 1)

        elif stmt.kind == "VAR":
            out += (
                indent
                + "var "
                + stmt.name
                + " = "
                + format_expr(module, stmt.expr)
                + "\n"
            )

        else:  # ASSIGN
            out += (
                indent
                + stmt.name
                + " = "
                + format_expr(module, stmt.expr)
                + "\n"
            )

    return out^


def format_module(module: Module) -> String:
    """The whole program as an indented outline."""
    var out = String()

    for i in range(len(module.functions)):
        var function = module.functions[i].copy()

        if i > 0:
            out += "\n"

        out += "def " + function.name + "("
        for p in range(len(function.parameters)):
            if p > 0:
                out += ", "
            out += (
                function.parameters[p].name
                + ": "
                + function.parameters[p].type_name
            )
        out += ") -> " + function.return_type + "\n"
        out += format_block(module, function.body, 1)

    return out^
