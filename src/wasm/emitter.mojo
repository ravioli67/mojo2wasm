from ..parser.ast import Module
from ..util.hex import from_hex
from .types import i64_type
from .types import f64_type
from .types import i32_type
from .types import func_type_tag
from .types import block_type_empty
from .types import block_type_i32
from .types import section_type
from .types import section_import
from .types import section_function
from .types import section_memory
from .types import section_export
from .types import section_code
from .types import section_data
from .types import export_kind_function
from .types import op_unreachable
from .types import op_drop
from .types import op_block
from .types import op_loop
from .types import op_if
from .types import op_else
from .types import op_end
from .types import op_br
from .types import op_br_if
from .types import op_return
from .types import op_call
from .types import op_local_get
from .types import op_local_set
from .types import op_i32_const
from .types import op_i64_const
from .types import op_f64_const
from .types import op_i32_eqz
from .types import op_i32_eq
from .types import op_i32_ne
from .types import op_i64_eqz
from .types import op_i64_eq
from .types import op_i64_ne
from .types import op_i64_lt_s
from .types import op_i64_gt_s
from .types import op_i64_le_s
from .types import op_i64_ge_s
from .types import op_i64_add
from .types import op_i64_sub
from .types import op_i64_mul
from .types import op_f64_eq
from .types import op_f64_ne
from .types import op_f64_lt
from .types import op_f64_gt
from .types import op_f64_le
from .types import op_f64_ge
from .types import op_f64_neg
from .types import op_f64_add
from .types import op_f64_sub
from .types import op_f64_mul
from .types import op_f64_div
from .types import op_i64_trunc_f64_s
from .types import op_i64_extend_i32_u
from .types import op_f64_convert_i64_s
from .types import encode_uleb128
from .types import encode_sleb128


# ---- Small byte-building helpers -------------------------------------------


def append_all(mut destination: List[UInt8], source: List[UInt8]):
    for i in range(len(source)):
        destination.append(source[i])


def string_bytes(text: String) -> List[UInt8]:
    var result = List[UInt8]()
    for b in text.as_bytes():
        result.append(b)
    return result^


def make_section(id: UInt8, content: List[UInt8]) -> List[UInt8]:
    """A section is: id, size (LEB128), content."""
    var result = List[UInt8]()
    result.append(id)
    append_all(result, encode_uleb128(len(content)))
    append_all(result, content)
    return result^


def index_of(names: List[String], name: String) raises -> Int:
    for i in range(len(names)):
        if names[i] == name:
            return i
    raise Error("Emitter error: unknown variable '" + name + "'")


def valtype(type_name: String) -> UInt8:
    """The WASM value type for a source type."""
    if type_name == "Float64":
        return f64_type()
    if type_name == "Bool":
        return i32_type()
    return i64_type()


def binary_opcode(op: String, operand_type: String) raises -> UInt8:
    """Opcodes for operators that map to a single WASM instruction.
    (`//` and `%` are not here: they call helper functions, see below.)"""
    if operand_type == "Float64":
        if op == "+":
            return op_f64_add()
        if op == "-":
            return op_f64_sub()
        if op == "*":
            return op_f64_mul()
        if op == "/":
            return op_f64_div()
        if op == "==":
            return op_f64_eq()
        if op == "!=":
            return op_f64_ne()
        if op == "<":
            return op_f64_lt()
        if op == ">":
            return op_f64_gt()
        if op == "<=":
            return op_f64_le()
        if op == ">=":
            return op_f64_ge()

    elif operand_type == "Bool":
        if op == "==":
            return op_i32_eq()
        if op == "!=":
            return op_i32_ne()

    else:
        if op == "+":
            return op_i64_add()
        if op == "-":
            return op_i64_sub()
        if op == "*":
            return op_i64_mul()
        if op == "==":
            return op_i64_eq()
        if op == "!=":
            return op_i64_ne()
        if op == "<":
            return op_i64_lt_s()
        if op == ">":
            return op_i64_gt_s()
        if op == "<=":
            return op_i64_le_s()
        if op == ">=":
            return op_i64_ge_s()

    raise Error(
        "Emitter error: unsupported operator '"
        + op
        + "' for "
        + operand_type
    )


def float_bytes(value: Float64) raises -> List[UInt8]:
    """The 8 little-endian bytes of an IEEE-754 double.

    Computed with plain arithmetic (halving / doubling is exact in binary
    floating point), so no bit-casting is needed:
    value = 1.fraction * 2^exponent, with a 52-bit fraction.
    Literals are never negative zero, so only the sign of non-zero values
    is handled.
    """
    var sign = 0
    var x = value
    if x < 0.0:
        sign = 1
        x = -x

    var result = List[UInt8]()

    if x == 0.0:
        for _ in range(7):
            result.append(0)
        result.append(UInt8(sign * 128))
        return result^

    if x > 1.7976931348623157e308:
        raise Error("Emitter error: floating-point literal is too large")

    var exponent = 0
    while x >= 2.0:
        x = x / 2.0
        exponent += 1
    while x < 1.0:
        x = x * 2.0
        exponent -= 1

    if exponent < -1022:
        raise Error("Emitter error: floating-point literal is too small")

    var fraction = Int((x - 1.0) * 4503599627370496.0)  # 2^52
    var biased = exponent + 1023

    for i in range(6):
        result.append(UInt8((fraction >> (8 * i)) & 255))
    result.append(UInt8(((fraction >> 48) & 15) | ((biased & 15) << 4)))
    result.append(UInt8((sign * 128) | (biased >> 4)))

    return result^


# ---- Floor division helpers ----------------------------------------------------
#
# Mojo's `//` and `%` round toward negative infinity (like Python), but WASM's
# i64.div_s / i64.rem_s truncate toward zero. For example -7 // 2 is -4 in Mojo
# but -3 in WASM. So programs that use `//` or `%` get one small helper
# function appended to the module (after the user's functions):
#
#   floordiv(a, b): q = a / b; if (a % b != 0) and ((a ^ b) < 0): q - 1 else q
#   floormod(a, b): r = a % b; if (r != 0) and ((r ^ b) < 0): r + b   else r


def floordiv_body() raises -> List[UInt8]:
    return from_hex(
        "01 01 7e "  # one local group: 1 x i64   (local 2 = q)
        + "20 00 20 01 7f 21 02 "  # q = a / b
        + "20 00 20 01 81 42 00 52 "  # (a % b) != 0
        + "20 00 20 01 85 42 00 53 "  # (a ^ b) < 0
        + "71 "  # and
        + "04 7e "  # if (result i64)
        + "20 02 42 01 7d "  # q - 1
        + "05 "  # else
        + "20 02 "  # q
        + "0b 0b"  # end if, end function
    )


def floormod_body() raises -> List[UInt8]:
    return from_hex(
        "01 01 7e "  # one local group: 1 x i64   (local 2 = r)
        + "20 00 20 01 81 21 02 "  # r = a % b
        + "20 02 42 00 52 "  # r != 0
        + "20 02 20 01 85 42 00 53 "  # (r ^ b) < 0
        + "71 "  # and
        + "04 7e "  # if (result i64)
        + "20 02 20 01 7c "  # r + b
        + "05 "  # else
        + "20 02 "  # r
        + "0b 0b"  # end if, end function
    )


# ---- print(): host imports and string literals ---------------------------------
#
# print() is lowered to calls of functions the host provides (module "env"):
#
#   print_i64(Int)   print_f64(Float64)   print_bool(0 | 1)
#   print_str(pointer, length)            -- text read from exported memory
#
# Only the imports a program uses are declared. String literals (and the
# separator " " and the newline "\n") live in a data segment at address 0.


def print_import_for(type_name: String) -> String:
    if type_name == "Float64":
        return "print_f64"
    if type_name == "Bool":
        return "print_bool"
    return "print_i64"


def import_names(module: Module) -> List[String]:
    """The imports the program needs, in a fixed order."""
    var any_print = False
    var need_i64 = False
    var need_f64 = False
    var need_bool = False

    for i in range(len(module.stmts)):
        var stmt = module.stmts[i].copy()
        if stmt.kind != "PRINT":
            continue
        any_print = True
        for a in range(len(stmt.args)):
            var argument = module.exprs[stmt.args[a]].copy()
            if argument.kind == "STRING":
                continue
            if argument.etype == "Float64":
                need_f64 = True
            elif argument.etype == "Bool":
                need_bool = True
            else:
                need_i64 = True

    var names = List[String]()
    if any_print:
        if need_i64:
            names.append("print_i64")
        if need_f64:
            names.append("print_f64")
        if need_bool:
            names.append("print_bool")
        names.append("print_str")
    return names^


def import_index(module: Module, name: String) -> Int:
    var names = import_names(module)
    for i in range(len(names)):
        if names[i] == name:
            return i
    return -1


def import_param_types(name: String) -> List[UInt8]:
    var types = List[UInt8]()
    if name == "print_i64":
        types.append(i64_type())
    elif name == "print_f64":
        types.append(f64_type())
    elif name == "print_bool":
        types.append(i32_type())
    else:  # print_str(pointer, length)
        types.append(i32_type())
        types.append(i32_type())
    return types^


def byte_length(text: String) -> Int:
    return len(string_bytes(text))


def add_unique(mut table: List[String], text: String):
    for i in range(len(table)):
        if table[i] == text:
            return
    table.append(text)


def string_table(module: Module) -> List[String]:
    """Every distinct text print() needs, in order of first use."""
    var table = List[String]()

    for i in range(len(module.stmts)):
        var stmt = module.stmts[i].copy()
        if stmt.kind != "PRINT":
            continue
        for a in range(len(stmt.args)):
            var argument = module.exprs[stmt.args[a]].copy()
            if argument.kind == "STRING":
                add_unique(table, argument.name)
        if len(stmt.args) > 1:
            add_unique(table, " ")
        add_unique(table, "\n")

    return table^


def string_offset(table: List[String], text: String) -> Int:
    """Address of `text` in the data segment."""
    var offset = 0
    for i in range(len(table)):
        if table[i] == text:
            return offset
        offset += byte_length(table[i])
    return -1


def uses_op(module: Module, op: String) -> Bool:
    for i in range(len(module.exprs)):
        if module.exprs[i].kind == "BINARY" and module.exprs[i].op == op:
            return True
    return False


def helper_index(module: Module, op: String) -> Int:
    """Function index of the helper for `//` or `%`, or -1 if not needed.

    Imported functions come first in WASM's function index space, then the
    user's functions, then the helpers: floordiv first (if used), then
    floormod (if used).
    """
    var next_index = len(import_names(module)) + len(module.functions)

    if uses_op(module, "//"):
        if op == "//":
            return next_index
        next_index += 1

    if uses_op(module, "%"):
        if op == "%":
            return next_index

    return -1


def helper_count(module: Module) -> Int:
    var count = 0
    if uses_op(module, "//"):
        count += 1
    if uses_op(module, "%"):
        count += 1
    return count


# ---- Expressions and statements ----------------------------------------------


def emit_expr(module: Module, mut code: List[UInt8], index: Int) raises:
    var expr = module.exprs[index].copy()

    if expr.kind == "INT":
        code.append(op_i64_const())
        append_all(code, encode_sleb128(expr.value))

    elif expr.kind == "FLOAT":
        code.append(op_f64_const())
        append_all(code, float_bytes(expr.fvalue))

    elif expr.kind == "BOOL":
        code.append(op_i32_const())
        append_all(code, encode_sleb128(expr.value))

    elif expr.kind == "ALIAS":
        # An alias is replaced by its value.
        emit_expr(module, code, module.aliases[expr.left].expr)

    elif expr.kind == "VAR":
        code.append(op_local_get())
        append_all(code, encode_uleb128(expr.value))

    elif expr.kind == "NEG":
        if expr.etype == "Int":
            # -x  ->  0 - x
            code.append(op_i64_const())
            append_all(code, encode_sleb128(0))
            emit_expr(module, code, expr.left)
            code.append(op_i64_sub())
        else:
            emit_expr(module, code, expr.left)
            code.append(op_f64_neg())

    elif expr.kind == "NOT":
        emit_expr(module, code, expr.left)
        code.append(op_i32_eqz())

    elif expr.kind == "CAST":
        emit_expr(module, code, expr.left)
        var source_type = module.exprs[expr.left].etype
        if expr.name == "Float64" and source_type == "Int":
            code.append(op_f64_convert_i64_s())
        elif expr.name == "Int" and source_type == "Float64":
            code.append(op_i64_trunc_f64_s())
        elif expr.name == "Int" and source_type == "Bool":
            code.append(op_i64_extend_i32_u())
        elif expr.name == "Bool" and source_type == "Int":
            code.append(op_i64_eqz())  # x == 0
            code.append(op_i32_eqz())  # ... so x != 0

    elif expr.kind == "TERNARY":
        # a if c else b  ->  c ; if (result T) a else b end
        emit_expr(module, code, expr.args[0])
        code.append(op_if())
        code.append(valtype(expr.etype))
        emit_expr(module, code, expr.left)
        code.append(op_else())
        emit_expr(module, code, expr.right)
        code.append(op_end())

    elif expr.kind == "LOGIC":
        # Short-circuit evaluation, so `n > 0 and 10 // n > 1` never divides
        # by zero:
        #   a and b  ->  a ; if (result i32) b else 0 end
        #   a or  b  ->  a ; if (result i32) 1 else b end
        emit_expr(module, code, expr.left)
        code.append(op_if())
        code.append(block_type_i32())
        if expr.op == "and":
            emit_expr(module, code, expr.right)
            code.append(op_else())
            code.append(op_i32_const())
            code.append(0)
        else:
            code.append(op_i32_const())
            code.append(1)
            code.append(op_else())
            emit_expr(module, code, expr.right)
        code.append(op_end())

    elif expr.kind == "BINARY":
        emit_expr(module, code, expr.left)
        emit_expr(module, code, expr.right)
        if expr.op == "//" or expr.op == "%":
            code.append(op_call())
            append_all(
                code, encode_uleb128(helper_index(module, expr.op))
            )
        else:
            code.append(
                binary_opcode(expr.op, module.exprs[expr.left].etype)
            )

    else:  # CALL: push the arguments, then call by function index
        for i in range(len(expr.args)):
            emit_expr(module, code, expr.args[i])
        code.append(op_call())
        append_all(
            code,
            encode_uleb128(
                len(import_names(module)) + module.find_function(expr.name)
            ),
        )


def emit_string_call(
    module: Module, mut code: List[UInt8], table: List[String], text: String
):
    """print_str(address, length) for a text in the data segment."""
    code.append(op_i32_const())
    append_all(code, encode_sleb128(string_offset(table, text)))
    code.append(op_i32_const())
    append_all(code, encode_sleb128(byte_length(text)))
    code.append(op_call())
    append_all(code, encode_uleb128(import_index(module, "print_str")))


def emit_block(
    module: Module,
    mut code: List[UInt8],
    body: List[Int],
    break_label: Int,
    continue_label: Int,
    table: List[String],
) raises:
    """Emits statements.

    `break_label` / `continue_label` are the WASM branch depths that reach
    the end of / the continue point of the innermost enclosing loop from
    this point (-1 outside a loop). Every `if` entered adds one level.
    """
    for i in range(len(body)):
        var stmt = module.stmts[body[i]].copy()

        if stmt.kind == "RETURN":
            if stmt.expr >= 0:
                emit_expr(module, code, stmt.expr)
            code.append(op_return())

        elif stmt.kind == "PASS":
            pass

        elif stmt.kind == "BREAK":
            code.append(op_br())
            append_all(code, encode_uleb128(break_label))

        elif stmt.kind == "CONTINUE":
            code.append(op_br())
            append_all(code, encode_uleb128(continue_label))

        elif stmt.kind == "EXPR":
            emit_expr(module, code, stmt.expr)
            if module.exprs[stmt.expr].etype != "None":
                code.append(op_drop())  # ignore the result

        elif stmt.kind == "PRINT":
            for a in range(len(stmt.args)):
                if a > 0:
                    emit_string_call(module, code, table, " ")
                var argument = module.exprs[stmt.args[a]].copy()
                if argument.kind == "STRING":
                    emit_string_call(module, code, table, argument.name)
                else:
                    emit_expr(module, code, stmt.args[a])
                    code.append(op_call())
                    append_all(
                        code,
                        encode_uleb128(
                            import_index(
                                module, print_import_for(argument.etype)
                            )
                        ),
                    )
            emit_string_call(module, code, table, "\n")

        elif stmt.kind == "IF":
            var inner_break = -1
            var inner_continue = -1
            if break_label >= 0:
                inner_break = break_label + 1
                inner_continue = continue_label + 1

            emit_expr(module, code, stmt.expr)
            code.append(op_if())
            code.append(block_type_empty())
            emit_block(
                module,
                code,
                stmt.body,
                inner_break,
                inner_continue,
                table,
            )
            if len(stmt.else_body) > 0:
                code.append(op_else())
                emit_block(
                    module,
                    code,
                    stmt.else_body,
                    inner_break,
                    inner_continue,
                    table,
                )
            code.append(op_end())

        elif stmt.kind == "WHILE":
            # block { loop { if !cond break; body; continue } }
            # Inside the body: `br 1` leaves the block (break) and
            # `br 0` jumps back to the loop top (continue).
            code.append(op_block())
            code.append(block_type_empty())
            code.append(op_loop())
            code.append(block_type_empty())
            emit_expr(module, code, stmt.expr)
            code.append(op_i32_eqz())
            code.append(op_br_if())
            code.append(1)  # leave the outer block
            emit_block(module, code, stmt.body, 1, 0, table)
            code.append(op_br())
            code.append(0)  # jump back to the top of the loop
            code.append(op_end())
            code.append(op_end())

        elif stmt.kind == "FOR":
            # counter = start; end = stop
            # block { loop {
            #     if !(counter < end) break          (counter > end if step < 0)
            #     i = counter
            #     block { body }                     <- `continue` leaves this
            #     counter += step
            #     continue
            # } }
            var variable = stmt.slot
            var counter = variable + 1
            var end = variable + 2
            var step = stmt.value

            emit_expr(module, code, stmt.args[0])
            code.append(op_local_set())
            append_all(code, encode_uleb128(counter))
            emit_expr(module, code, stmt.args[1])
            code.append(op_local_set())
            append_all(code, encode_uleb128(end))

            code.append(op_block())
            code.append(block_type_empty())
            code.append(op_loop())
            code.append(block_type_empty())

            code.append(op_local_get())
            append_all(code, encode_uleb128(counter))
            code.append(op_local_get())
            append_all(code, encode_uleb128(end))
            if step > 0:
                code.append(op_i64_lt_s())
            else:
                code.append(op_i64_gt_s())
            code.append(op_i32_eqz())
            code.append(op_br_if())
            code.append(1)  # leave the outer block

            code.append(op_local_get())
            append_all(code, encode_uleb128(counter))
            code.append(op_local_set())
            append_all(code, encode_uleb128(variable))

            code.append(op_block())
            code.append(block_type_empty())
            emit_block(module, code, stmt.body, 2, 0, table)
            code.append(op_end())

            code.append(op_local_get())
            append_all(code, encode_uleb128(counter))
            code.append(op_i64_const())
            append_all(code, encode_sleb128(step))
            code.append(op_i64_add())
            code.append(op_local_set())
            append_all(code, encode_uleb128(counter))

            code.append(op_br())
            code.append(0)
            code.append(op_end())
            code.append(op_end())

        else:  # VAR and ASSIGN both store into a local
            emit_expr(module, code, stmt.expr)
            code.append(op_local_set())
            append_all(code, encode_uleb128(stmt.slot))


# ---- The module ----------------------------------------------------------------


def emit(module: Module) raises -> List[UInt8]:
    """Turns a checked Module into the bytes of a .wasm file.

    Function index space: the imports (for print) come first, then the
    user's functions in source order, then the `//` / `%` helpers. Every
    source function is exported under its own name; helpers are not.
    """
    var imports = import_names(module)
    var import_count = len(imports)
    var user_count = len(module.functions)
    var helpers = helper_count(module)
    var defined = user_count + helpers
    var table = string_table(module)
    var has_memory = len(table) > 0
    var out = List[UInt8]()

    # Header: magic number "\0asm" + version 1
    out.append(0x00)
    out.append(0x61)
    out.append(0x73)
    out.append(0x6D)
    out.append(0x01)
    out.append(0x00)
    out.append(0x00)
    out.append(0x00)

    # ---- Type section: imports, then the user's functions, then helpers ----
    var types = List[UInt8]()
    append_all(types, encode_uleb128(import_count + defined))
    for k in range(import_count):
        var params = import_param_types(imports[k])
        types.append(func_type_tag())
        append_all(types, encode_uleb128(len(params)))
        append_all(types, params)
        types.append(0)  # no results
    for f in range(user_count):
        var parameter_count = len(module.functions[f].parameters)
        types.append(func_type_tag())
        append_all(types, encode_uleb128(parameter_count))
        for p in range(parameter_count):
            types.append(valtype(module.functions[f].parameters[p].type_name))
        if module.functions[f].return_type == "":
            types.append(0)  # no results
        else:
            types.append(1)
            types.append(valtype(module.functions[f].return_type))
    for _ in range(helpers):  # helpers are all (i64, i64) -> i64
        types.append(func_type_tag())
        types.append(2)
        types.append(i64_type())
        types.append(i64_type())
        types.append(1)
        types.append(i64_type())
    append_all(out, make_section(section_type(), types))

    # ---- Import section: module "env" ----
    if import_count > 0:
        var import_bytes = List[UInt8]()
        append_all(import_bytes, encode_uleb128(import_count))
        for k in range(import_count):
            var module_name = string_bytes("env")
            var field_name = string_bytes(imports[k])
            append_all(import_bytes, encode_uleb128(len(module_name)))
            append_all(import_bytes, module_name)
            append_all(import_bytes, encode_uleb128(len(field_name)))
            append_all(import_bytes, field_name)
            import_bytes.append(0x00)  # a function
            append_all(import_bytes, encode_uleb128(k))  # type index
        append_all(out, make_section(section_import(), import_bytes))

    # ---- Function section: defined function i uses type import_count + i ----
    var functions = List[UInt8]()
    append_all(functions, encode_uleb128(defined))
    for i in range(defined):
        append_all(functions, encode_uleb128(import_count + i))
    append_all(out, make_section(section_function(), functions))

    # ---- Memory section: one 64 KiB page, for the string literals ----
    if has_memory:
        var memory = List[UInt8]()
        memory.append(1)  # one memory
        memory.append(0)  # no maximum
        memory.append(1)  # at least one page
        append_all(out, make_section(section_memory(), memory))

    # ---- Export section: the user's functions (and the memory) ----
    var exports = List[UInt8]()
    var export_count = user_count
    if has_memory:
        export_count += 1
    append_all(exports, encode_uleb128(export_count))
    for f in range(user_count):
        var name_bytes = string_bytes(module.functions[f].name)
        append_all(exports, encode_uleb128(len(name_bytes)))
        append_all(exports, name_bytes)
        exports.append(export_kind_function())
        append_all(exports, encode_uleb128(import_count + f))
    if has_memory:
        var memory_name = string_bytes("memory")
        append_all(exports, encode_uleb128(len(memory_name)))
        append_all(exports, memory_name)
        exports.append(2)  # a memory
        exports.append(0)  # memory 0
    append_all(out, make_section(section_export(), exports))

    # ---- Code section: one body per function ----
    var code_section = List[UInt8]()
    append_all(code_section, encode_uleb128(defined))

    for f in range(user_count):
        var function = module.functions[f].copy()
        var parameter_count = len(function.parameters)

        var body = List[UInt8]()

        # Local declarations: consecutive locals of the same type share one
        # group `(count, type)`. Parameters are not declared here.
        var group_counts = List[Int]()
        var group_types = List[String]()
        for slot in range(parameter_count, len(function.slot_types)):
            var last = len(group_types) - 1
            if last >= 0 and group_types[last] == function.slot_types[slot]:
                group_counts[last] += 1
            else:
                group_counts.append(1)
                group_types.append(function.slot_types[slot])

        append_all(body, encode_uleb128(len(group_types)))
        for g in range(len(group_types)):
            append_all(body, encode_uleb128(group_counts[g]))
            body.append(valtype(group_types[g]))

        emit_block(module, body, function.body, -1, -1, table)

        # The checker guarantees a value-returning function returns on every
        # path, but WASM validation still wants the body to end well typed.
        if function.return_type != "":
            body.append(op_unreachable())
        body.append(op_end())

        append_all(code_section, encode_uleb128(len(body)))
        append_all(code_section, body)

    if uses_op(module, "//"):
        var body = floordiv_body()
        append_all(code_section, encode_uleb128(len(body)))
        append_all(code_section, body)

    if uses_op(module, "%"):
        var body = floormod_body()
        append_all(code_section, encode_uleb128(len(body)))
        append_all(code_section, body)

    append_all(out, make_section(section_code(), code_section))

    # ---- Data section: the strings, at address 0 ----
    if has_memory:
        var data = List[UInt8]()
        for t in range(len(table)):
            append_all(data, string_bytes(table[t]))

        var segment = List[UInt8]()
        segment.append(1)  # one segment
        segment.append(0)  # active, memory 0
        segment.append(op_i32_const())
        segment.append(0)  # at address 0
        segment.append(op_end())
        append_all(segment, encode_uleb128(len(data)))
        append_all(segment, data)
        append_all(out, make_section(section_data(), segment))

    return out^
