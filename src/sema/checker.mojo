from ..parser.ast import Module
from ..parser.ast import Expr
from ..util.diagnostics import error_at
from ..util.diagnostics import suggest


def semantic_error(line: Int, column: Int, message: String) -> Error:
    return Error(error_at("Semantic", line, column, message))


def lookup(names: List[String], types: List[String], name: String) -> String:
    """The type of variable `name`, or "" if it is not in scope."""
    for i in range(len(names)):
        if names[i] == name:
            return types[i]
    return ""


def contains(names: List[String], name: String) -> Bool:
    for i in range(len(names)):
        if names[i] == name:
            return True
    return False


def is_order_comparison(op: String) -> Bool:
    return op == "<" or op == "<=" or op == ">" or op == ">="


def is_number_type(type_name: String) -> Bool:
    return type_name == "Int" or type_name == "Float64"


def mismatch_error(
    op: String, line: Int, column: Int, left: String, right: String
) -> Error:
    var hint = String("")
    if (left == "Int" and right == "Float64") or (
        left == "Float64" and right == "Int"
    ):
        hint = " (convert one side, e.g. Float64(x) or Int(x))"
    return semantic_error(
        line,
        column,
        "cannot use '" + op + "' with " + left + " and " + right + hint,
    )


def conversion_allowed(target: String, source: String) -> Bool:
    """Which explicit conversions exist: Float64(Int), Int(Float64), ..."""
    if target == "Float64":
        return source == "Int" or source == "Float64"
    if target == "Int":
        return source == "Int" or source == "Float64" or source == "Bool"
    if target == "Bool":
        return source == "Bool" or source == "Int"
    return False


def check_expr(
    mut module: Module,
    index: Int,
    names: List[String],
    types: List[String],
) raises -> String:
    """Checks one expression, records its type in `Expr.etype` and returns it.

    Types are "Int", "Float64" and "Bool".
    """
    var expr = module.exprs[index].copy()
    var result = check_expr_inner(module, expr, names, types)

    expr.etype = result
    module.exprs[index] = expr^

    return result


def check_expr_inner(
    mut module: Module,
    expr: Expr,
    names: List[String],
    types: List[String],
) raises -> String:
    var kind = expr.kind

    if kind == "INT":
        return "Int"

    if kind == "FLOAT":
        return "Float64"

    if kind == "BOOL":
        return "Bool"

    if kind == "VAR":
        var found = lookup(names, types, expr.name)
        if found == "":
            raise semantic_error(
                expr.line,
                expr.column,
                "unknown variable '"
                + expr.name
                + "'."
                + suggest(expr.name, names),
            )
        return found

    if kind == "NEG":
        var operand = check_expr(module, expr.left, names, types)
        if not is_number_type(operand):
            raise semantic_error(
                expr.line, expr.column, "cannot negate a " + operand
            )
        return operand

    if kind == "NOT":
        var operand = check_expr(module, expr.left, names, types)
        if operand != "Bool":
            raise semantic_error(
                expr.line,
                expr.column,
                "'not' needs a Bool but got " + operand,
            )
        return "Bool"

    if kind == "LOGIC":
        var left = check_expr(module, expr.left, names, types)
        var right = check_expr(module, expr.right, names, types)
        if left != "Bool" or right != "Bool":
            raise semantic_error(
                expr.line,
                expr.column,
                "'"
                + expr.op
                + "' needs Bool on both sides but got "
                + left
                + " and "
                + right,
            )
        return "Bool"

    if kind == "BINARY":
        var left = check_expr(module, expr.left, names, types)
        var right = check_expr(module, expr.right, names, types)
        var op = expr.op

        if op == "+" or op == "-" or op == "*":
            if left == right and is_number_type(left):
                return left
            raise mismatch_error(op, expr.line, expr.column, left, right)

        if op == "/":
            if left == "Float64" and right == "Float64":
                return "Float64"
            if left == "Int" and right == "Int":
                raise semantic_error(
                    expr.line,
                    expr.column,
                    "'/' needs Float64 operands. Use '//' for integer"
                    " division",
                )
            raise mismatch_error(op, expr.line, expr.column, left, right)

        if op == "//" or op == "%":
            if left == "Int" and right == "Int":
                return "Int"
            raise semantic_error(
                expr.line,
                expr.column,
                "'"
                + op
                + "' needs Int operands but got "
                + left
                + " and "
                + right,
            )

        if is_order_comparison(op):
            if left == right and is_number_type(left):
                return "Bool"
            raise mismatch_error(op, expr.line, expr.column, left, right)

        # == and !=
        if left == right:
            return "Bool"
        raise mismatch_error(op, expr.line, expr.column, left, right)

    if kind == "CAST":
        var source = check_expr(module, expr.left, names, types)
        if not conversion_allowed(expr.name, source):
            raise semantic_error(
                expr.line,
                expr.column,
                "cannot convert " + source + " to " + expr.name,
            )
        return expr.name

    # CALL
    var target = module.find_function(expr.name)
    if target < 0:
        var function_names = List[String]()
        for i in range(len(module.functions)):
            function_names.append(module.functions[i].name)
        raise semantic_error(
            expr.line,
            expr.column,
            "unknown function '"
            + expr.name
            + "'."
            + suggest(expr.name, function_names),
        )

    var function = module.functions[target].copy()

    if len(function.parameters) != len(expr.args):
        raise semantic_error(
            expr.line,
            expr.column,
            "'"
            + expr.name
            + "' takes "
            + String(len(function.parameters))
            + " argument(s) but "
            + String(len(expr.args))
            + " were given",
        )

    for i in range(len(expr.args)):
        var argument_type = check_expr(module, expr.args[i], names, types)
        var wanted = function.parameters[i].type_name
        if argument_type != wanted:
            var argument = module.exprs[expr.args[i]].copy()
            raise semantic_error(
                argument.line,
                argument.column,
                "argument "
                + String(i + 1)
                + " of '"
                + expr.name
                + "' should be "
                + wanted
                + " but is "
                + argument_type,
            )

    return function.return_type


def check_block(
    mut module: Module,
    body: List[Int],
    mut names: List[String],
    mut types: List[String],
    in_loop: Bool,
    return_type: String,
) raises:
    """Checks a list of statements.

    Variables live for the whole function once declared (no block scopes
    yet), so `names` / `types` just keep growing as `var` statements are
    seen. `in_loop` is True inside a `while` body (where break/continue are
    legal).
    """
    for i in range(len(body)):
        var stmt = module.stmts[body[i]].copy()

        if stmt.kind == "RETURN":
            var value_type = check_expr(module, stmt.expr, names, types)
            if value_type != return_type:
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "this function returns "
                    + return_type
                    + " but the value is "
                    + value_type,
                )

        elif stmt.kind == "BREAK" or stmt.kind == "CONTINUE":
            if not in_loop:
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "'" + stmt.kind.lower() + "' outside of a loop",
                )

        elif stmt.kind == "IF" or stmt.kind == "WHILE":
            var condition_type = check_expr(module, stmt.expr, names, types)
            if condition_type != "Bool":
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "the condition must be a Bool (like a < b), not "
                    + condition_type,
                )
            if stmt.kind == "WHILE":
                check_block(
                    module, stmt.body, names, types, True, return_type
                )
            else:
                check_block(
                    module, stmt.body, names, types, in_loop, return_type
                )
                check_block(
                    module, stmt.else_body, names, types, in_loop, return_type
                )

        elif stmt.kind == "VAR":
            if contains(names, stmt.name):
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "'" + stmt.name + "' is already declared",
                )
            var value_type = check_expr(module, stmt.expr, names, types)
            if stmt.type_name != "" and stmt.type_name != value_type:
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "'"
                    + stmt.name
                    + "' is declared as "
                    + stmt.type_name
                    + " but the value is "
                    + value_type,
                )
            # Remember the variable's type: the emitter needs it.
            stmt.type_name = value_type
            module.stmts[body[i]] = stmt.copy()
            names.append(stmt.name)
            types.append(value_type)

        else:  # ASSIGN
            var variable_type = lookup(names, types, stmt.name)
            if variable_type == "":
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "unknown variable '"
                    + stmt.name
                    + "'."
                    + suggest(stmt.name, names),
                )
            var value_type = check_expr(module, stmt.expr, names, types)
            if value_type != variable_type:
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "'"
                    + stmt.name
                    + "' is "
                    + variable_type
                    + " but the value is "
                    + value_type,
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


def check(mut module: Module) raises:
    """Validates a parsed module and annotates it with types.

    Raises an Error on the first problem.
    """
    if len(module.functions) == 0:
        raise Error("Semantic error: the file contains no functions")

    for i in range(len(module.functions)):
        var function = module.functions[i].copy()

        # Unique function names
        for j in range(i):
            if module.functions[j].name == function.name:
                raise semantic_error(
                    function.line,
                    function.column,
                    "function '" + function.name + "' is defined twice",
                )

        if function.name.startswith("__"):
            raise semantic_error(
                function.line,
                function.column,
                "function names starting with '__' are reserved ('"
                + function.name
                + "')",
            )

        # Parameters become the first entries of the scope.
        var names = List[String]()
        var types = List[String]()
        for p in range(len(function.parameters)):
            var parameter = function.parameters[p].copy()

            if contains(names, parameter.name):
                raise semantic_error(
                    parameter.line,
                    parameter.column,
                    "duplicate parameter '" + parameter.name + "'",
                )
            names.append(parameter.name)
            types.append(parameter.type_name)

        check_block(
            module, function.body, names, types, False, function.return_type
        )

        if not always_returns(module, function.body):
            raise semantic_error(
                function.line,
                function.column,
                "function '"
                + function.name
                + "' does not return a value on every path",
            )
