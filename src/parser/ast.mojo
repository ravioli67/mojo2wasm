"""AST definitions.

Mojo structs cannot contain themselves, so the tree is stored in flat lists
(an "arena") inside `Module`. Nodes refer to their children by INDEX:

  * `Expr.left`, `Expr.right`, `Expr.args`  -> indices into `Module.exprs`
  * `Stmt.expr`                             -> index into `Module.exprs`
  * `Stmt.body`, `Stmt.else_body`,
    `Function.body`                         -> indices into `Module.stmts`
"""


struct Parameter(Copyable, Movable):
    var name: String
    var type_name: String

    def __init__(out self, name: String, type_name: String):
        self.name = name
        self.type_name = type_name


# ---------------------------------------------------------------------------
# Expressions
# ---------------------------------------------------------------------------
# kind is one of:
#   "INT"     value
#   "VAR"     name
#   "BINARY"  op, left, right
#   "CALL"    name, args


struct Expr(Copyable, Movable):
    var kind: String
    var value: Int
    var name: String
    var op: String
    var left: Int
    var right: Int
    var args: List[Int]
    var line: Int

    def __init__(
        out self,
        kind: String,
        value: Int,
        name: String,
        op: String,
        left: Int,
        right: Int,
        args: List[Int],
        line: Int,
    ):
        self.kind = kind
        self.value = value
        self.name = name
        self.op = op
        self.left = left
        self.right = right
        self.args = args.copy()
        self.line = line


def int_expr(value: Int, line: Int) -> Expr:
    return Expr("INT", value, "", "", -1, -1, List[Int](), line)


def var_expr(name: String, line: Int) -> Expr:
    return Expr("VAR", 0, name, "", -1, -1, List[Int](), line)


def binary_expr(op: String, left: Int, right: Int, line: Int) -> Expr:
    return Expr("BINARY", 0, "", op, left, right, List[Int](), line)


def call_expr(name: String, args: List[Int], line: Int) -> Expr:
    return Expr("CALL", 0, name, "", -1, -1, args, line)


# ---------------------------------------------------------------------------
# Statements
# ---------------------------------------------------------------------------
# kind is one of:
#   "RETURN"  expr
#   "IF"      expr (condition), body, else_body (may be empty)
#   "WHILE"   expr (condition), body
#   "VAR"     name, expr          (declaration:  var x = ...)
#   "ASSIGN"  name, expr          (assignment:   x = ...)


struct Stmt(Copyable, Movable):
    var kind: String
    var name: String
    var expr: Int
    var body: List[Int]
    var else_body: List[Int]
    var line: Int

    def __init__(
        out self,
        kind: String,
        name: String,
        expr: Int,
        body: List[Int],
        else_body: List[Int],
        line: Int,
    ):
        self.kind = kind
        self.name = name
        self.expr = expr
        self.body = body.copy()
        self.else_body = else_body.copy()
        self.line = line


def return_stmt(expr: Int, line: Int) -> Stmt:
    return Stmt("RETURN", "", expr, List[Int](), List[Int](), line)


def if_stmt(
    condition: Int, body: List[Int], else_body: List[Int], line: Int
) -> Stmt:
    return Stmt("IF", "", condition, body, else_body, line)


def while_stmt(condition: Int, body: List[Int], line: Int) -> Stmt:
    return Stmt("WHILE", "", condition, body, List[Int](), line)


def var_stmt(name: String, expr: Int, line: Int) -> Stmt:
    return Stmt("VAR", name, expr, List[Int](), List[Int](), line)


def assign_stmt(name: String, expr: Int, line: Int) -> Stmt:
    return Stmt("ASSIGN", name, expr, List[Int](), List[Int](), line)


# ---------------------------------------------------------------------------
# Functions and the module
# ---------------------------------------------------------------------------


struct Function(Copyable, Movable):
    var name: String
    var parameters: List[Parameter]
    var return_type: String
    var body: List[Int]  # indices into Module.stmts
    var line: Int

    def __init__(
        out self,
        name: String,
        parameters: List[Parameter],
        return_type: String,
        body: List[Int],
        line: Int,
    ):
        self.name = name
        self.parameters = parameters.copy()
        self.return_type = return_type
        self.body = body.copy()
        self.line = line


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
