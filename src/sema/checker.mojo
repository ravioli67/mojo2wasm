from ..parser.ast import Module


def is_comparison_op(op: String) -> Bool:
    return (
        op == "<"
        or op == "<="
        or op == ">"
        or op == ">="
        or op == "=="
        or op == "!="
    )


def contains(names: List[String], name: String) -> Bool:
    for i in range(len(names)):
        if names[i] == name:
            return True
    return False


def check_expr(module: Module, index: Int, scope: List[String]) raises -> String:
    """Checks one expression and returns its type: "Int" or "Bool".

    Only comparisons produce a Bool, and a Bool can only be used as the
    condition of `if` / `while` (there are no Bool variables yet).
    """
    var expr = module.exprs[index].copy()

    if expr.kind == "INT":
        return "Int"

    if expr.kind == "VAR":
        if not contains(scope, expr.name):
            raise Error(
                "Semantic error on line "
                + String(expr.line)
                + ": unknown variable '"
                + expr.name
                + "'"
            )
        return "Int"

    if expr.kind == "NOT":
        if check_expr(module, expr.left, scope) != "Bool":
            raise Error(
                "Semantic error on line "
                + String(expr.line)
                + ": 'not' needs a comparison (like a < b)"
            )
        return "Bool"

    if expr.kind == "LOGIC":
        var left_type = check_expr(module, expr.left, scope)
        var right_type = check_expr(module, expr.right, scope)
        if left_type != "Bool" or right_type != "Bool":
            raise Error(
                "Semantic error on line "
                + String(expr.line)
                + ": '"
                + expr.op
                + "' needs a comparison on both sides"
            )
        return "Bool"

    if expr.kind == "BINARY":
        var left_type = check_expr(module, expr.left, scope)
        var right_type = check_expr(module, expr.right, scope)

        if left_type != "Int" or right_type != "Int":
            raise Error(
                "Semantic error on line "
                + String(expr.line)
                + ": operands of '"
                + expr.op
                + "' must be Int"
            )

        if is_comparison_op(expr.op):
            return "Bool"
        return "Int"

    # CALL
    var target = module.find_function(expr.name)
    if target < 0:
        raise Error(
            "Semantic error on line "
            + String(expr.line)
            + ": unknown function '"
            + expr.name
            + "'"
        )

    var expected = len(module.functions[target].parameters)
    if len(expr.args) != expected:
        raise Error(
            "Semantic error on line "
            + String(expr.line)
            + ": '"
            + expr.name
            + "' takes "
            + String(expected)
            + " argument(s) but "
            + String(len(expr.args))
            + " were given"
        )

    for i in range(len(expr.args)):
        if check_expr(module, expr.args[i], scope) != "Int":
            raise Error(
                "Semantic error on line "
                + String(expr.line)
                + ": arguments to '"
                + expr.name
                + "' must be Int"
            )

    return "Int"


def check_block(
    module: Module, body: List[Int], mut scope: List[String], in_loop: Bool
) raises:
    """Checks a list of statements.

    Variables live for the whole function once declared (no block scopes
    yet), so `scope` just keeps growing as `var` statements are seen.
    `in_loop` is True inside a `while` body (where break/continue are legal).
    """
    for i in range(len(body)):
        var stmt = module.stmts[body[i]].copy()

        if stmt.kind == "RETURN":
            if check_expr(module, stmt.expr, scope) != "Int":
                raise Error(
                    "Semantic error on line "
                    + String(stmt.line)
                    + ": return needs an Int value"
                )

        elif stmt.kind == "BREAK" or stmt.kind == "CONTINUE":
            if not in_loop:
                raise Error(
                    "Semantic error on line "
                    + String(stmt.line)
                    + ": '"
                    + stmt.kind.lower()
                    + "' outside of a loop"
                )

        elif stmt.kind == "IF" or stmt.kind == "WHILE":
            if check_expr(module, stmt.expr, scope) != "Bool":
                raise Error(
                    "Semantic error on line "
                    + String(stmt.line)
                    + ": the condition must be a comparison (like a < b)"
                )
            if stmt.kind == "WHILE":
                check_block(module, stmt.body, scope, True)
            else:
                check_block(module, stmt.body, scope, in_loop)
                check_block(module, stmt.else_body, scope, in_loop)

        elif stmt.kind == "VAR":
            if contains(scope, stmt.name):
                raise Error(
                    "Semantic error on line "
                    + String(stmt.line)
                    + ": '"
                    + stmt.name
                    + "' is already declared"
                )
            if check_expr(module, stmt.expr, scope) != "Int":
                raise Error(
                    "Semantic error on line "
                    + String(stmt.line)
                    + ": variables must hold an Int"
                )
            scope.append(stmt.name)

        else:  # ASSIGN
            if not contains(scope, stmt.name):
                raise Error(
                    "Semantic error on line "
                    + String(stmt.line)
                    + ": unknown variable '"
                    + stmt.name
                    + "'"
                )
            if check_expr(module, stmt.expr, scope) != "Int":
                raise Error(
                    "Semantic error on line "
                    + String(stmt.line)
                    + ": variables must hold an Int"
                )


def always_returns(module: Module, body: List[Int]) -> Bool:
    """True if every path through `body` ends in a `return`."""
    if len(body) == 0:
        return False

    var last = module.stmts[body[len(body) - 1]].copy()

    if last.kind == "RETURN":
        return True

    if last.kind == "IF" and len(last.else_body) > 0:
        return always_returns(module, last.body) and always_returns(
            module, last.else_body
        )

    return False


def check(module: Module) raises:
    """Validates a parsed module. Raises an Error on the first problem."""

    if len(module.functions) == 0:
        raise Error("Semantic error: the file contains no functions")

    for i in range(len(module.functions)):
        var function = module.functions[i].copy()

        # Unique function names
        for j in range(i):
            if module.functions[j].name == function.name:
                raise Error(
                    "Semantic error on line "
                    + String(function.line)
                    + ": function '"
                    + function.name
                    + "' is defined twice"
                )

        if function.return_type != "Int":
            raise Error(
                "Semantic error on line "
                + String(function.line)
                + ": unsupported return type '"
                + function.return_type
                + "'"
            )

        # Parameters become the first entries of the scope.
        var scope = List[String]()
        for p in range(len(function.parameters)):
            var parameter = function.parameters[p].copy()

            if parameter.type_name != "Int":
                raise Error(
                    "Semantic error on line "
                    + String(function.line)
                    + ": parameter '"
                    + parameter.name
                    + "' has unsupported type '"
                    + parameter.type_name
                    + "'"
                )
            if contains(scope, parameter.name):
                raise Error(
                    "Semantic error on line "
                    + String(function.line)
                    + ": duplicate parameter '"
                    + parameter.name
                    + "'"
                )
            scope.append(parameter.name)

        check_block(module, function.body, scope, False)

        if not always_returns(module, function.body):
            raise Error(
                "Semantic error on line "
                + String(function.line)
                + ": function '"
                + function.name
                + "' does not return a value on every path"
            )
