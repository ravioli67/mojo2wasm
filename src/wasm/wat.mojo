"""WebAssembly text format (WAT) output.

Produces the same program as `emitter.mojo`, but as readable text in the
"flat" instruction style, which any WAT tool (wat2wasm, wasm-tools, ...)
accepts. Keep this file in step with the binary emitter: each construct is
lowered the same way.
"""

from ..parser.ast import Module
from ..parser.ast import Function
from .emitter import uses_op
from .emitter import import_names
from .emitter import string_table
from .emitter import string_offset
from .emitter import byte_length
from .emitter import print_import_for
from .emitter import string_bytes


def wat_type(type_name: String) -> String:
    """The WAT value type for a source type."""
    if type_name == "Float64":
        return "f64"
    if type_name == "Bool":
        return "i32"
    return "i64"


def binary_wat_op(op: String, operand_type: String) raises -> String:
    if operand_type == "Float64":
        if op == "+":
            return "f64.add"
        if op == "-":
            return "f64.sub"
        if op == "*":
            return "f64.mul"
        if op == "/":
            return "f64.div"
        if op == "==":
            return "f64.eq"
        if op == "!=":
            return "f64.ne"
        if op == "<":
            return "f64.lt"
        if op == ">":
            return "f64.gt"
        if op == "<=":
            return "f64.le"
        if op == ">=":
            return "f64.ge"

    elif operand_type == "Bool":
        if op == "==":
            return "i32.eq"
        if op == "!=":
            return "i32.ne"

    else:
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

    raise Error(
        "Emitter error: unsupported operator '"
        + op
        + "' for "
        + operand_type
    )


def import_wat_params(name: String) -> String:
    if name == "print_i64":
        return "i64"
    if name == "print_f64":
        return "f64"
    if name == "print_bool":
        return "i32"
    return "i32 i32"


def unique_names(function: Function) -> List[String]:
    """A distinct WAT name for every local slot: when a source name is
    reused (e.g. two loops over `i`), later ones become `i_2`, `i_3`, ..."""
    var seen_names = List[String]()
    var seen_counts = List[Int]()
    var result = List[String]()

    for slot in range(len(function.slot_names)):
        var name = function.slot_names[slot]
        var found = -1
        for k in range(len(seen_names)):
            if seen_names[k] == name:
                found = k
        if found < 0:
            seen_names.append(name)
            seen_counts.append(1)
            result.append(name)
        else:
            seen_counts[found] += 1
            result.append(name + "_" + String(seen_counts[found]))

    return result^


def wat_escape(text: String) -> String:
    """Escapes a string for a WAT data segment: printable ASCII stays as
    is; everything else (and quotes and backslashes) becomes \\hh."""
    var digits = "0123456789abcdef"
    var out = String()
    for b in text.as_bytes():
        var value = Int(b)
        if value >= 32 and value < 127 and value != 34 and value != 92:
            out += chr(value)
        else:
            var high = value >> 4
            var low = value & 15
            out += "\\" + digits[high : high + 1] + digits[low : low + 1]
    return out^


def wat_string_call(
    module: Module, mut ins: List[String], table: List[String], text: String
):
    ins.append("i32.const " + String(string_offset(table, text)))
    ins.append("i32.const " + String(byte_length(text)))
    ins.append("call $__print_str")


def wat_expr(
    module: Module, mut ins: List[String], index: Int, names: List[String]
) raises:
    var expr = module.exprs[index].copy()

    if expr.kind == "INT":
        ins.append("i64.const " + String(expr.value))

    elif expr.kind == "FLOAT":
        ins.append("f64.const " + expr.name)

    elif expr.kind == "BOOL":
        ins.append("i32.const " + String(expr.value))

    elif expr.kind == "ALIAS":
        wat_expr(module, ins, module.aliases[expr.left].expr, names)

    elif expr.kind == "VAR":
        ins.append("local.get $" + names[expr.value])

    elif expr.kind == "NEG":
        if expr.etype == "Int":
            ins.append("i64.const 0")
            wat_expr(module, ins, expr.left, names)
            ins.append("i64.sub")
        else:
            wat_expr(module, ins, expr.left, names)
            ins.append("f64.neg")

    elif expr.kind == "NOT":
        wat_expr(module, ins, expr.left, names)
        ins.append("i32.eqz")

    elif expr.kind == "CAST":
        wat_expr(module, ins, expr.left, names)
        var source_type = module.exprs[expr.left].etype
        if expr.name == "Float64" and source_type == "Int":
            ins.append("f64.convert_i64_s")
        elif expr.name == "Int" and source_type == "Float64":
            ins.append("i64.trunc_f64_s")
        elif expr.name == "Int" and source_type == "Bool":
            ins.append("i64.extend_i32_u")
        elif expr.name == "Bool" and source_type == "Int":
            ins.append("i64.eqz")
            ins.append("i32.eqz")

    elif expr.kind == "TERNARY":
        wat_expr(module, ins, expr.args[0], names)
        ins.append("if (result " + wat_type(expr.etype) + ")")
        wat_expr(module, ins, expr.left, names)
        ins.append("else")
        wat_expr(module, ins, expr.right, names)
        ins.append("end")

    elif expr.kind == "LOGIC":
        wat_expr(module, ins, expr.left, names)
        ins.append("if (result i32)")
        if expr.op == "and":
            wat_expr(module, ins, expr.right, names)
            ins.append("else")
            ins.append("i32.const 0")
        else:
            ins.append("i32.const 1")
            ins.append("else")
            wat_expr(module, ins, expr.right, names)
        ins.append("end")

    elif expr.kind == "BINARY":
        wat_expr(module, ins, expr.left, names)
        wat_expr(module, ins, expr.right, names)
        if expr.op == "//":
            ins.append("call $__floordiv")
        elif expr.op == "%":
            ins.append("call $__floormod")
        else:
            ins.append(
                binary_wat_op(expr.op, module.exprs[expr.left].etype)
            )

    else:  # CALL
        for i in range(len(expr.args)):
            wat_expr(module, ins, expr.args[i], names)
        ins.append("call $" + expr.name)


def wat_block(
    module: Module,
    mut ins: List[String],
    body: List[Int],
    break_label: Int,
    continue_label: Int,
    table: List[String],
    names: List[String],
) raises:
    for i in range(len(body)):
        var stmt = module.stmts[body[i]].copy()

        if stmt.kind == "RETURN":
            if stmt.expr >= 0:
                wat_expr(module, ins, stmt.expr, names)
            ins.append("return")

        elif stmt.kind == "PASS":
            pass

        elif stmt.kind == "BREAK":
            ins.append("br " + String(break_label))

        elif stmt.kind == "CONTINUE":
            ins.append("br " + String(continue_label))

        elif stmt.kind == "EXPR":
            wat_expr(module, ins, stmt.expr, names)
            if module.exprs[stmt.expr].etype != "None":
                ins.append("drop")

        elif stmt.kind == "PRINT":
            for a in range(len(stmt.args)):
                if a > 0:
                    wat_string_call(module, ins, table, " ")
                var argument = module.exprs[stmt.args[a]].copy()
                if argument.kind == "STRING":
                    wat_string_call(module, ins, table, argument.name)
                else:
                    wat_expr(module, ins, stmt.args[a], names)
                    ins.append(
                        "call $__" + print_import_for(argument.etype)
                    )
            wat_string_call(module, ins, table, "\n")

        elif stmt.kind == "IF":
            var inner_break = -1
            var inner_continue = -1
            if break_label >= 0:
                inner_break = break_label + 1
                inner_continue = continue_label + 1

            wat_expr(module, ins, stmt.expr, names)
            ins.append("if")
            wat_block(
                module, ins, stmt.body, inner_break, inner_continue, table, names
            )
            if len(stmt.else_body) > 0:
                ins.append("else")
                wat_block(
                    module,
                    ins,
                    stmt.else_body,
                    inner_break,
                    inner_continue,
                    table,
                    names,
                )
            ins.append("end")

        elif stmt.kind == "WHILE":
            ins.append("block")
            ins.append("loop")
            wat_expr(module, ins, stmt.expr, names)
            ins.append("i32.eqz")
            ins.append("br_if 1")
            wat_block(module, ins, stmt.body, 1, 0, table, names)
            ins.append("br 0")
            ins.append("end")
            ins.append("end")

        elif stmt.kind == "FOR":
            var variable = names[stmt.slot]
            var counter = names[stmt.slot + 1]
            var end = names[stmt.slot + 2]

            wat_expr(module, ins, stmt.args[0], names)
            ins.append("local.set $" + counter)
            wat_expr(module, ins, stmt.args[1], names)
            ins.append("local.set $" + end)
            ins.append("block")
            ins.append("loop")
            ins.append("local.get $" + counter)
            ins.append("local.get $" + end)
            if stmt.value > 0:
                ins.append("i64.lt_s")
            else:
                ins.append("i64.gt_s")
            ins.append("i32.eqz")
            ins.append("br_if 1")
            ins.append("local.get $" + counter)
            ins.append("local.set $" + variable)
            ins.append("block")
            wat_block(module, ins, stmt.body, 2, 0, table, names)
            ins.append("end")
            ins.append("local.get $" + counter)
            ins.append("i64.const " + String(stmt.value))
            ins.append("i64.add")
            ins.append("local.set $" + counter)
            ins.append("br 0")
            ins.append("end")
            ins.append("end")

        else:  # VAR and ASSIGN
            wat_expr(module, ins, stmt.expr, names)
            ins.append("local.set $" + names[stmt.slot])


def opens_block(instruction: String) -> Bool:
    return (
        instruction == "if"
        or instruction == "if (result i32)"
        or instruction == "if (result i64)"
        or instruction == "if (result f64)"
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
    var imports = import_names(module)
    var table = string_table(module)
    var out = String("(module\n")

    for k in range(len(imports)):
        out += (
            "  (import \"env\" \""
            + imports[k]
            + "\" (func $__"
            + imports[k]
            + " (param "
            + import_wat_params(imports[k])
            + ")))\n"
        )

    if len(table) > 0:
        out += "  (memory (export \"memory\") 1)\n"
        var data = String("")
        for t in range(len(table)):
            data += wat_escape(table[t])
        out += "  (data (i32.const 0) \"" + data + "\")\n"

    for f in range(len(module.functions)):
        var function = module.functions[f].copy()

        if f > 0 or len(imports) > 0 or len(table) > 0:
            out += "\n"

        var names = unique_names(function)
        var parameter_count = len(function.parameters)

        var header = String("  (func $") + function.name
        header += " (export \"" + function.name + "\")"
        for p in range(parameter_count):
            header += (
                " (param $"
                + names[p]
                + " "
                + wat_type(function.parameters[p].type_name)
                + ")"
            )
        if function.return_type != "":
            header += " (result " + wat_type(function.return_type) + ")"
        out += header + "\n"

        for slot in range(parameter_count, len(names)):
            out += (
                "    (local $"
                + names[slot]
                + " "
                + wat_type(function.slot_types[slot])
                + ")\n"
            )

        var ins = List[String]()
        wat_block(module, ins, function.body, -1, -1, table, names)
        if function.return_type != "":
            ins.append("unreachable")
        out += format_instructions(ins, 2)
        out += "  )\n"

    if uses_op(module, "//"):
        out += "\n" + floordiv_wat()

    if uses_op(module, "%"):
        out += "\n" + floormod_wat()

    out += ")\n"
    return out^
