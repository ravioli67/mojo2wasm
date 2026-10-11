"""AST definitions.

Mojo structs cannot contain themselves, so the tree is stored in flat lists
(an "arena") inside `Module`. Nodes refer to their children by INDEX:

  * `Expr.left`, `Expr.right`, `Expr.args`  -> indices into `Module.exprs`
  * `Stmt.expr`                             -> index into `Module.exprs`
  * `Stmt.body`, `Stmt.else_body`,
    `Function.body`                         -> indices into `Module.stmts`

Every node records the `line` and `column` it came from, for error messages.
The checker fills in `Expr.etype` (the type of each expression) and the type
of every `var` statement (`Stmt.type_name`); the emitter relies on these.
Types are the strings "Int", "Float64" and "Bool".
"""


struct Parameter(Copyable, Movable):
    var name: String
    var type_name: String
    var line: Int
    var column: Int

    def __init__(out self, name: String, type_name: String, line: Int, column: Int):
        self.name = name
        self.type_name = type_name
        self.line = line
        self.column = column


# ---------------------------------------------------------------------------
# Expressions
# ---------------------------------------------------------------------------
# kind is one of:
#   "INT"     value
#   "FLOAT"   fvalue, name (the literal's source text, e.g. "3.14")
#   "BOOL"    value (1 = True, 0 = False)
#   "VAR"     name
#   "NEG"     left                  (unary minus)
#   "NOT"     left
#   "BINARY"  op, left, right       (arithmetic or comparison)
#   "LOGIC"   op ("and"/"or"), left, right
#   "CALL"    name, args
#   "CAST"    name (target type), left   e.g. Float64(x)


struct Expr(Copyable, Movable):
    var kind: String
    var value: Int
    var fvalue: Float64
    var name: String
    var op: String
    var left: Int
    var right: Int
    var args: List[Int]
    var etype: String
    var line: Int
    var column: Int

    def __init__(
        out self,
        kind: String,
        value: Int,
        fvalue: Float64,
        name: String,
        op: String,
        left: Int,
        right: Int,
        args: List[Int],
        etype: String,
        line: Int,
        column: Int,
    ):
        self.kind = kind
        self.value = value
        self.fvalue = fvalue
        self.name = name
        self.op = op
        self.left = left
        self.right = right
        self.args = args.copy()
        self.etype = etype
        self.line = line
        self.column = column


def int_expr(value: Int, line: Int, column: Int) -> Expr:
    return Expr("INT", value, 0.0, "", "", -1, -1, List[Int](), "Int", line, column)


def float_expr(text: String, value: Float64, line: Int, column: Int) -> Expr:
    return Expr("FLOAT", 0, value, text, "", -1, -1, List[Int](), "Float64", line, column)


def bool_expr(value: Int, line: Int, column: Int) -> Expr:
    return Expr("BOOL", value, 0.0, "", "", -1, -1, List[Int](), "Bool", line, column)


def var_expr(name: String, line: Int, column: Int) -> Expr:
    return Expr("VAR", 0, 0.0, name, "", -1, -1, List[Int](), "", line, column)


def neg_expr(operand: Int, line: Int, column: Int) -> Expr:
    return Expr("NEG", 0, 0.0, "", "", operand, -1, List[Int](), "", line, column)


def not_expr(operand: Int, line: Int, column: Int) -> Expr:
    return Expr("NOT", 0, 0.0, "", "", operand, -1, List[Int](), "", line, column)


def binary_expr(op: String, left: Int, right: Int, line: Int, column: Int) -> Expr:
    return Expr("BINARY", 0, 0.0, "", op, left, right, List[Int](), "", line, column)


def logic_expr(op: String, left: Int, right: Int, line: Int, column: Int) -> Expr:
    return Expr("LOGIC", 0, 0.0, "", op, left, right, List[Int](), "", line, column)


def call_expr(name: String, args: List[Int], line: Int, column: Int) -> Expr:
    return Expr("CALL", 0, 0.0, name, "", -1, -1, args, "", line, column)


def cast_expr(target: String, operand: Int, line: Int, column: Int) -> Expr:
    return Expr("CAST", 0, 0.0, target, "", operand, -1, List[Int](), "", line, column)


# ---------------------------------------------------------------------------
# Statements
# ---------------------------------------------------------------------------
# kind is one of:
#   "RETURN"    expr
#   "IF"        expr (condition), body, else_body (may be empty)
#   "WHILE"     expr (condition), body
#   "VAR"       name, type_name, expr   (var x = ...  /  var x: T = ...)
#   "ASSIGN"    name, expr              (x = ...)
#   "BREAK"
#   "CONTINUE"
#
# `type_name` of a VAR statement is the annotation (or "") after parsing and
# the variable's actual type after checking.
#
# Compound assignment (`x += e`) has no node of its own: the parser turns it
# into `ASSIGN x = (x + e)`.


struct Stmt(Copyable, Movable):
    var kind: String
    var name: String
    var type_name: String
    var expr: Int
    var body: List[Int]
    var else_body: List[Int]
    var line: Int
    var column: Int

    def __init__(
        out self,
        kind: String,
        name: String,
        type_name: String,
        expr: Int,
        body: List[Int],
        else_body: List[Int],
        line: Int,
        column: Int,
    ):
        self.kind = kind
        self.name = name
        self.type_name = type_name
        self.expr = expr
        self.body = body.copy()
        self.else_body = else_body.copy()
        self.line = line
        self.column = column


def return_stmt(expr: Int, line: Int, column: Int) -> Stmt:
    return Stmt("RETURN", "", "", expr, List[Int](), List[Int](), line, column)


def if_stmt(
    condition: Int, body: List[Int], else_body: List[Int], line: Int, column: Int
) -> Stmt:
    return Stmt("IF", "", "", condition, body, else_body, line, column)


def while_stmt(condition: Int, body: List[Int], line: Int, column: Int) -> Stmt:
    return Stmt("WHILE", "", "", condition, body, List[Int](), line, column)


def var_stmt(
    name: String, type_name: String, expr: Int, line: Int, column: Int
) -> Stmt:
    return Stmt("VAR", name, type_name, expr, List[Int](), List[Int](), line, column)


def assign_stmt(name: String, expr: Int, line: Int, column: Int) -> Stmt:
    return Stmt("ASSIGN", name, "", expr, List[Int](), List[Int](), line, column)


def break_stmt(line: Int, column: Int) -> Stmt:
    return Stmt("BREAK", "", "", -1, List[Int](), List[Int](), line, column)


def continue_stmt(line: Int, column: Int) -> Stmt:
    return Stmt("CONTINUE", "", "", -1, List[Int](), List[Int](), line, column)


# ---------------------------------------------------------------------------
# Functions and the module
# ---------------------------------------------------------------------------


struct Function(Copyable, Movable):
    var name: String
    var parameters: List[Parameter]
    var return_type: String
    var body: List[Int]  # indices into Module.stmts
    var line: Int
    var column: Int

    def __init__(
        out self,
        name: String,
        parameters: List[Parameter],
        return_type: String,
        body: List[Int],
        line: Int,
        column: Int,
    ):
        self.name = name
        self.parameters = parameters.copy()
        self.return_type = return_type
        self.body = body.copy()
        self.line = line
        self.column = column


struct Module(Copyable, Movable):
    """A whole source file: the functions plus the arenas they point into."""

    var functions: List[Function]
    var exprs: List[Expr]
    var stmts: List[Stmt]

    def __init__(out self):
        self.functions = List[Function]()
        self.exprs = List[Expr]()
        self.stmts = List[Stmt]()

    def add_expr(mut self, expr: Expr) -> Int:
        self.exprs.append(expr.copy())
        return len(self.exprs) - 1

    def add_stmt(mut self, stmt: Stmt) -> Int:
        self.stmts.append(stmt.copy())
        return len(self.stmts) - 1

    def find_function(self, name: String) -> Int:
        """Index of the function called `name`, or -1."""
        for i in range(len(self.functions)):
            if self.functions[i].name == name:
                return i
        return -1
