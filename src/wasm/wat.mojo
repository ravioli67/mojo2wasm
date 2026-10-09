"""WebAssembly text format (WAT) output.

Produces the same program as `emitter.mojo`, but as readable text in the
"flat" instruction style, which any WAT tool (wat2wasm, wasm-tools, ...)
accepts. Keep this file in step with the binary emitter: each construct is
lowered the same way.
"""

from ..parser.ast import Module
from .emitter import collect_locals
from .emitter import uses_op


def binary_wat_op(op: String) raises -> String:
    if op == "+":
        return "i64.add"
    if op == "-":
        return "i64.sub"
    if op == "*":
        return "i64.mul"
    if op == "==":
        return "i64.eq"
    if op == "!=":
        return "i64.ne"
    if op == "<":
        return "i64.lt_s"
    if op == ">":
        return "i64.gt_s"
    if op == "<=":
        return "i64.le_s"
    if op == ">=":
        return "i64.ge_s"
    raise Error("Emitter error: unsupported operator '" + op + "'")


def wat_expr(module: Module, mut ins: List[String], index: Int) raises:
    var expr = module.exprs[index].copy()

    if expr.kind == "INT":
        ins.append("i64.const " + String(expr.value))

    elif expr.kind == "VAR":
        ins.append("local.get $" + expr.name)

    elif expr.kind == "NOT":
        wat_expr(module, ins, expr.left)
        ins.append("i32.eqz")

    elif expr.kind == "LOGIC":
        wat_expr(module, ins, expr.left)
        ins.append("if (result i32)")
        if expr.op == "and":
            wat_expr(module, ins, expr.right)
            ins.append("else")
            ins.append("i32.const 0")
        else:
            ins.append("i32.const 1")
            ins.append("else")
            wat_expr(module, ins, expr.right)
        ins.append("end")

    elif expr.kind == "BINARY":
        wat_expr(module, ins, expr.left)
        wat_expr(module, ins, expr.right)
        if expr.op == "//":
            ins.append("call $__floordiv")
        elif expr.op == "%":
            ins.append("call $__floormod")
        else:
            ins.append(binary_wat_op(expr.op))

    else:  # CALL
        for i in range(len(expr.args)):
            wat_expr(module, ins, expr.args[i])
        ins.append("call $" + expr.name)


def wat_block(
    module: Module,
    mut ins: List[String],
    body: List[Int],
    break_label: Int,
    continue_label: Int,
) raises:
    for i in range(len(body)):
        var stmt = module.stmts[body[i]].copy()

        if stmt.kind == "RETURN":
            wat_expr(module, ins, stmt.expr)
            ins.append("return")

        elif stmt.kind == "BREAK":
            ins.append("br " + String(break_label))

        elif stmt.kind == "CONTINUE":
            ins.append("br " + String(continue_label))

        elif stmt.kind == "IF":
            var inner_break = -1
            var inner_continue = -1
            if break_label >= 0:
                inner_break = break_label + 1
                inner_continue = continue_label + 1

            wat_expr(module, ins, stmt.expr)
            ins.append("if")
            wat_block(module, ins, stmt.body, inner_break, inner_continue)
            if len(stmt.else_body) > 0:
                ins.append("else")
                wat_block(
                    module, ins, stmt.else_body, inner_break, inner_continue
                )
            ins.append("end")

        elif stmt.kind == "WHILE":
            ins.append("block")
            ins.append("loop")
            wat_expr(module, ins, stmt.expr)
            ins.append("i32.eqz")
            ins.append("br_if 1")
            wat_block(module, ins, stmt.body, 1, 0)
            ins.append("br 0")
            ins.append("end")
            ins.append("end")

        else:  # VAR and ASSIGN
            wat_expr(module, ins, stmt.expr)
            ins.append("local.set $" + stmt.name)


def opens_block(instruction: String) -> Bool:
    return (
        instruction == "if"
        or instruction == "if (result i32)"
        or instruction == "block"
        or instruction == "loop"
        or instruction == "else"
    )


def format_instructions(ins: List[String], base_indent: Int) -> String:
    """One instruction per line, indented by nesting depth."""
    var out = String()
    var indent = base_indent

    for i in range(len(ins)):
        var instruction = ins[i]

        if instruction == "end" or instruction == "else":
            indent -= 1

        for _ in range(indent):
            out += "  "
        out += instruction + "\n"

        if opens_block(instruction):
            indent += 1

    return out^


def floordiv_wat() -> String:
    return (
        "  (func $__floordiv (param $a i64) (param $b i64) (result i64)\n"
        + "    (local $q i64)\n"
        + "    local.get $a\n"
        + "    local.get $b\n"
        + "    i64.div_s\n"
        + "    local.set $q\n"
        + "    local.get $a\n"
        + "    local.get $b\n"
        + "    i64.rem_s\n"
        + "    i64.const 0\n"
        + "    i64.ne\n"
        + "    local.get $a\n"
        + "    local.get $b\n"
        + "    i64.xor\n"
        + "    i64.const 0\n"
        + "    i64.lt_s\n"
        + "    i32.and\n"
        + "    if (result i64)\n"
        + "      local.get $q\n"
        + "      i64.const 1\n"
        + "      i64.sub\n"
        + "    else\n"
        + "      local.get $q\n"
        + "    end\n"
        + "  )\n"
    )


def floormod_wat() -> String:
    return (
        "  (func $__floormod (param $a i64) (param $b i64) (result i64)\n"
        + "    (local $r i64)\n"
        + "    local.get $a\n"
        + "    local.get $b\n"
        + "    i64.rem_s\n"
        + "    local.set $r\n"
        + "    local.get $r\n"
        + "    i64.const 0\n"
        + "    i64.ne\n"
        + "    local.get $r\n"
        + "    local.get $b\n"
        + "    i64.xor\n"
        + "    i64.const 0\n"
        + "    i64.lt_s\n"
        + "    i32.and\n"
        + "    if (result i64)\n"
        + "      local.get $r\n"
        + "      local.get $b\n"
        + "      i64.add\n"
        + "    else\n"
        + "      local.get $r\n"
        + "    end\n"
        + "  )\n"
    )


def emit_wat(module: Module) raises -> String:
    """Turns a checked Module into WAT text."""
    var out = String("(module\n")

    for f in range(len(module.functions)):
        var function = module.functions[f].copy()

        if f > 0:
            out += "\n"

        var header = String("  (func $") + function.name
        header += " (export \"" + function.name + "\")"
        for p in range(len(function.parameters)):
            header += " (param $" + function.parameters[p].name + " i64)"
        header += " (result i64)\n"
        out += header

        var declared = List[String]()
        collect_locals(module, function.body, declared)
        for d in range(len(declared)):
            out += "    (local $" + declared[d] + " i64)\n"

        var ins = List[String]()
        wat_block(module, ins, function.body, -1, -1)
        ins.append("unreachable")
        out += format_instructions(ins, 2)
        out += "  )\n"

    if uses_op(module, "//"):
        out += "\n" + floordiv_wat()

    if uses_op(module, "%"):
        out += "\n" + floormod_wat()

    out += ")\n"
    return out^
