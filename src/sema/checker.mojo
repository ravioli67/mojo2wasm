from ..parser.ast import Module
from ..parser.ast import Expr
from ..util.diagnostics import error_at
from ..util.diagnostics import suggest


def semantic_error(line: Int, column: Int, message: String) -> Error:
    return Error(error_at("Semantic", line, column, message))


struct Scope(Copyable, Movable):
    """The variables visible at one point of a function.

    `names` / `types` / `slots` describe the variables in scope, innermost
    last; leaving a block removes the ones it declared (so a name can be
    reused in a sibling block). `slot_names` / `slot_types` list EVERY local
    the function has ever declared (parameters first), because each
    declaration gets its own WASM local, even when it reuses a name.
    """

    var names: List[String]
    var types: List[String]
    var slots: List[Int]
    var slot_names: List[String]
    var slot_types: List[String]

    def __init__(out self):
        self.names = List[String]()
        self.types = List[String]()
        self.slots = List[Int]()
        self.slot_names = List[String]()
        self.slot_types = List[String]()

    def declare(mut self, name: String, type_name: String) -> Int:
        """Adds a visible variable and returns its slot."""
        var slot = len(self.slot_names)
        self.slot_names.append(name)
        self.slot_types.append(type_name)
        self.names.append(name)
        self.types.append(type_name)
        self.slots.append(slot)
        return slot

    def hidden(mut self, name: String, type_name: String) -> Int:
        """Adds a slot the program cannot name (e.g. a loop counter)."""
        var slot = len(self.slot_names)
        self.slot_names.append(name)
        self.slot_types.append(type_name)
        return slot

    def find(self, name: String) -> Int:
        """Position in `names` of the innermost variable called `name`."""
        var i = len(self.names) - 1
        while i >= 0:
            if self.names[i] == name:
                return i
            i -= 1
        return -1

    def mark(self) -> Int:
        return len(self.names)

    def leave(mut self, mark: Int):
        """Forgets every variable declared since `mark`."""
        while len(self.names) > mark:
            _ = self.names.pop()
            _ = self.types.pop()
            _ = self.slots.pop()

    def declared_in_block(self, name: String, start: Int) -> Bool:
        for i in range(start, len(self.names)):
            if self.names[i] == name:
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


def is_constant(module: Module, index: Int) -> Bool:
    """True if the expression only uses literals and other aliases."""
    var expr = module.exprs[index].copy()
    var kind = expr.kind

    if not (
        kind == "INT"
        or kind == "FLOAT"
        or kind == "BOOL"
        or kind == "VAR"
        or kind == "ALIAS"
        or kind == "NEG"
        or kind == "NOT"
        or kind == "BINARY"
        or kind == "LOGIC"
        or kind == "CAST"
    ):
        return False

    if expr.left >= 0 and kind != "ALIAS":
        if not is_constant(module, expr.left):
            return False
    if expr.right >= 0:
        if not is_constant(module, expr.right):
            return False

    return True


def check_expr(
    mut module: Module, index: Int, scope: Scope
) raises -> String:
    """Checks an expression that must produce a value; returns its type."""
    var result = check_expr_any(module, index, scope)
    if result == "None":
        var call = module.exprs[index].copy()
        raise semantic_error(
            call.line,
            call.column,
            "'" + call.name + "' does not return a value",
        )
    return result


def check_expr_any(
    mut module: Module, index: Int, scope: Scope
) raises -> String:
    """Checks one expression, records its type in `Expr.etype` and returns
    it. The type is "Int", "Float64", "Bool", or "None" for a call to a
    function without a return type."""
    var expr = module.exprs[index].copy()
    var result = check_expr_inner(module, expr, scope)

    expr.etype = result
    module.exprs[index] = expr^

    return result


def check_expr_inner(
    mut module: Module, mut expr: Expr, scope: Scope
) raises -> String:
    var kind = expr.kind

    if kind == "INT":
        return "Int"

    if kind == "FLOAT":
        return "Float64"

    if kind == "BOOL":
        return "Bool"

    if kind == "STRING":
        raise semantic_error(
            expr.line,
            expr.column,
            "string literals can only be used as arguments to print() for now",
        )

    if kind == "VAR":
        var found = scope.find(expr.name)
        if found >= 0:
            expr.value = scope.slots[found]
            return scope.types[found]

        var alias_index = module.find_alias(expr.name, module.visible_aliases)
        if alias_index >= 0:
            expr.kind = "ALIAS"
            expr.left = alias_index
            return module.aliases[alias_index].type_name

        var candidates = scope.names.copy()
        for i in range(module.visible_aliases):
            candidates.append(module.aliases[i].name)
        raise semantic_error(
            expr.line,
            expr.column,
            "unknown variable '"
            + expr.name
            + "'"
            + suggest(expr.name, candidates),
        )

    if kind == "NEG":
        var operand = check_expr(module, expr.left, scope)
        if not is_number_type(operand):
            raise semantic_error(
                expr.line, expr.column, "cannot negate a " + operand
            )
        return operand

    if kind == "NOT":
        var operand = check_expr(module, expr.left, scope)
        if operand != "Bool":
            raise semantic_error(
                expr.line,
                expr.column,
                "'not' needs a Bool but got " + operand,
            )
        return "Bool"

    if kind == "LOGIC":
        var left = check_expr(module, expr.left, scope)
        var right = check_expr(module, expr.right, scope)
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

    if kind == "TERNARY":
        var condition_index = expr.args[0]
        var condition = check_expr(module, condition_index, scope)
        if condition != "Bool":
            var condition_expr = module.exprs[condition_index].copy()
            raise semantic_error(
                condition_expr.line,
                condition_expr.column,
                "the condition of 'if ... else' must be a Bool, not "
                + condition,
            )
        var when_true = check_expr(module, expr.left, scope)
        var when_false = check_expr(module, expr.right, scope)
        if when_true != when_false:
            raise semantic_error(
                expr.line,
                expr.column,
                "both sides of 'if ... else' must have the same type but got "
                + when_true
                + " and "
                + when_false,
            )
        return when_true

    if kind == "BINARY":
        var left = check_expr(module, expr.left, scope)
        var right = check_expr(module, expr.right, scope)
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
        var source = check_expr(module, expr.left, scope)
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
            + "'"
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
        var argument_type = check_expr(module, expr.args[i], scope)
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

    if function.return_type == "":
        return "None"
    return function.return_type


def check_sub_block(
    mut module: Module,
    body: List[Int],
    mut scope: Scope,
    in_loop: Bool,
    return_type: String,
) raises:
    """Checks a nested block: variables it declares disappear afterwards."""
    var mark = scope.mark()
    check_block(module, body, scope, mark, in_loop, return_type)
    scope.leave(mark)


def check_block(
    mut module: Module,
    body: List[Int],
    mut scope: Scope,
    start: Int,
    in_loop: Bool,
    return_type: String,
) raises:
    """Checks a list of statements.

    `start` is where this block's own variables begin in `scope` (declaring
    the same name twice within one block is an error, but a nested block may
    shadow an outer variable). `in_loop` is True inside a loop body, where
    break/continue are legal.
    """
    for i in range(len(body)):
        var stmt = module.stmts[body[i]].copy()

        if stmt.kind == "RETURN":
            if stmt.expr == -1:
                if return_type != "":
                    raise semantic_error(
                        stmt.line,
                        stmt.column,
                        "this function must return a value of type "
                        + return_type,
                    )
            else:
                var value_type = check_expr(module, stmt.expr, scope)
                if return_type == "":
                    raise semantic_error(
                        stmt.line,
                        stmt.column,
                        "this function has no return type, so it cannot"
                        " return a value",
                    )
                if value_type != return_type:
                    raise semantic_error(
                        stmt.line,
                        stmt.column,
                        "this function returns "
                        + return_type
                        + " but the value is "
                        + value_type,
                    )

        elif stmt.kind == "PASS":
            pass

        elif stmt.kind == "BREAK" or stmt.kind == "CONTINUE":
            if not in_loop:
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "'" + stmt.kind.lower() + "' outside of a loop",
                )

        elif stmt.kind == "IF" or stmt.kind == "WHILE":
            var condition_type = check_expr(module, stmt.expr, scope)
            if condition_type != "Bool":
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "the condition must be a Bool (like a < b), not "
                    + condition_type,
                )
            if stmt.kind == "WHILE":
                check_sub_block(module, stmt.body, scope, True, return_type)
            else:
                check_sub_block(
                    module, stmt.body, scope, in_loop, return_type
                )
                check_sub_block(
                    module, stmt.else_body, scope, in_loop, return_type
                )

        elif stmt.kind == "FOR":
            for a in range(len(stmt.args)):
                if check_expr(module, stmt.args[a], scope) != "Int":
                    var bound = module.exprs[stmt.args[a]].copy()
                    raise semantic_error(
                        bound.line,
                        bound.column,
                        "range() arguments must be Int",
                    )
            var mark = scope.mark()
            # Three consecutive slots: the loop variable, a hidden counter
            # and a hidden copy of the end value.
            stmt.slot = scope.declare(stmt.name, "Int")
            _ = scope.hidden("__for_counter", "Int")
            _ = scope.hidden("__for_end", "Int")
            module.stmts[body[i]] = stmt.copy()
            check_block(module, stmt.body, scope, mark, True, return_type)
            scope.leave(mark)

        elif stmt.kind == "PRINT":
            for a in range(len(stmt.args)):
                var argument = module.exprs[stmt.args[a]].copy()
                if argument.kind == "STRING":
                    argument.etype = "String"
                    module.exprs[stmt.args[a]] = argument^
                else:
                    _ = check_expr(module, stmt.args[a], scope)

        elif stmt.kind == "EXPR":
            var call = module.exprs[stmt.expr].copy()
            if call.kind != "CALL":
                raise semantic_error(
                    call.line,
                    call.column,
                    "only a function call can be used as a statement",
                )
            _ = check_expr_any(module, stmt.expr, scope)

        elif stmt.kind == "VAR":
            if scope.declared_in_block(stmt.name, start):
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "'" + stmt.name + "' is already declared",
                )
            if module.find_alias(stmt.name, len(module.aliases)) >= 0:
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "'" + stmt.name + "' is already declared as an alias",
                )
            var value_type = check_expr(module, stmt.expr, scope)
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
            # Remember the variable's type and slot: the emitter needs them.
            stmt.type_name = value_type
            stmt.slot = scope.declare(stmt.name, value_type)
            module.stmts[body[i]] = stmt.copy()

        else:  # ASSIGN
            var found = scope.find(stmt.name)
            if found < 0:
                if module.find_alias(stmt.name, len(module.aliases)) >= 0:
                    raise semantic_error(
                        stmt.line,
                        stmt.column,
                        "cannot assign to the alias '" + stmt.name + "'",
                    )
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "unknown variable '"
                    + stmt.name
                    + "'"
                    + suggest(stmt.name, scope.names),
                )
            var value_type = check_expr(module, stmt.expr, scope)
            if value_type != scope.types[found]:
                raise semantic_error(
                    stmt.line,
                    stmt.column,
                    "'"
                    + stmt.name
                    + "' is "
                    + scope.types[found]
                    + " but the value is "
                    + value_type,
                )
            stmt.slot = scope.slots[found]
            module.stmts[body[i]] = stmt.copy()


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
    """Validates a parsed module and annotates it with types and slots.

    Raises an Error on the first problem.
    """
    if len(module.functions) == 0:
        raise Error("Semantic error: the file contains no functions")

    # ---- Aliases (constants), in order -------------------------------------
    for i in range(len(module.aliases)):
        var item = module.aliases[i].copy()

        for j in range(i):
            if module.aliases[j].name == item.name:
                raise semantic_error(
                    item.line,
                    item.column,
                    "alias '" + item.name + "' is defined twice",
                )

        module.visible_aliases = i

        var value = module.exprs[item.expr].copy()
        if not is_constant(module, item.expr):
            raise semantic_error(
                value.line,
                value.column,
                "an alias must be a constant expression (numbers,"
                " True/False and other aliases)",
            )

        var empty = Scope()
        var value_type = check_expr(module, item.expr, empty)
        if item.type_name != "" and item.type_name != value_type:
            raise semantic_error(
                item.line,
                item.column,
                "alias '"
                + item.name
                + "' is declared as "
                + item.type_name
                + " but the value is "
                + value_type,
            )
        item.type_name = value_type
        module.aliases[i] = item^

    module.visible_aliases = len(module.aliases)

    # ---- Functions ----------------------------------------------------------
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

        if function.name.startswith("__") or function.name == "print":
            raise semantic_error(
                function.line,
                function.column,
                "the function name '" + function.name + "' is reserved",
            )

        # Parameters become the first variables in scope.
        var scope = Scope()
        for p in range(len(function.parameters)):
            var parameter = function.parameters[p].copy()

            if scope.declared_in_block(parameter.name, 0):
                raise semantic_error(
                    parameter.line,
                    parameter.column,
                    "duplicate parameter '" + parameter.name + "'",
                )
            if module.find_alias(parameter.name, len(module.aliases)) >= 0:
                raise semantic_error(
                    parameter.line,
                    parameter.column,
                    "'" + parameter.name + "' is already declared as an alias",
                )
            _ = scope.declare(parameter.name, parameter.type_name)

        check_block(
            module, function.body, scope, 0, False, function.return_type
        )

        if function.return_type != "" and not always_returns(
            module, function.body
        ):
            raise semantic_error(
                function.line,
                function.column,
                "function '"
                + function.name
                + "' does not return a value on every path",
            )

        function.slot_names = scope.slot_names.copy()
        function.slot_types = scope.slot_types.copy()
        module.functions[i] = function^
