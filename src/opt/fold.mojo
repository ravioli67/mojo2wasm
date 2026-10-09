from ..parser.ast import Module
from ..parser.ast import int_expr


def fold_constants(mut module: Module):
    """Replaces arithmetic on two integer literals with the result.

    `2 + 3 * 4` becomes `14`, and `-5` (parsed as `0 - 5`) becomes `-5`.

    The parser always creates a node's children before the node itself, so
    walking the arena in index order folds bottom-up in a single pass.

    `//` and `%` use Mojo's floor semantics (the same as the runtime helpers
    in the emitter), and are left alone when dividing by zero so the program
    still traps at runtime instead of failing to compile.
    """
    for i in range(len(module.exprs)):
        var expr = module.exprs[i].copy()

        if expr.kind != "BINARY":
            continue

        var op = expr.op
        if not (
            op == "+" or op == "-" or op == "*" or op == "//" or op == "%"
        ):
            continue

        var left = module.exprs[expr.left].copy()
        var right = module.exprs[expr.right].copy()

        if left.kind != "INT" or right.kind != "INT":
            continue

        var a = left.value
        var b = right.value
        var result = 0

        if op == "+":
            result = a + b
        elif op == "-":
            result = a - b
        elif op == "*":
            result = a * b
        elif b == 0:
            continue  # division by zero: leave it for runtime
        elif op == "//":
            result = a // b
        else:
            result = a % b

        module.exprs[i] = int_expr(result, expr.line)
