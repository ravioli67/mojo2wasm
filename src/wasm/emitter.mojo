from ..parser.ast import Module
from ..util.hex import from_hex
from .types import i64_type
from .types import func_type_tag
from .types import block_type_empty
from .types import block_type_i32
from .types import section_type
from .types import section_function
from .types import section_export
from .types import section_code
from .types import export_kind_function
from .types import op_unreachable
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
from .types import op_i32_eqz
from .types import op_i64_eq
from .types import op_i64_ne
from .types import op_i64_lt_s
from .types import op_i64_gt_s
from .types import op_i64_le_s
from .types import op_i64_ge_s
from .types import op_i64_add
from .types import op_i64_sub
from .types import op_i64_mul
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


def binary_opcode(op: String) raises -> UInt8:
    """Opcodes for operators that map to a single WASM instruction.
    (`//` and `%` are not here: they call helper functions, see below.)"""
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
    raise Error("Emitter error: unsupported operator '" + op + "'")


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


def uses_op(module: Module, op: String) -> Bool:
    for i in range(len(module.exprs)):
        if module.exprs[i].kind == "BINARY" and module.exprs[i].op == op:
            return True
    return False


def helper_index(module: Module, op: String) -> Int:
    """Function index of the helper for `//` or `%`, or -1 if not needed.

    Helpers come right after the user's functions: floordiv first (if used),
    then floormod (if used).
    """
    var next_index = len(module.functions)

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


# ---- Locals ------------------------------------------------------------------


def collect_locals(module: Module, body: List[Int], mut found: List[String]):
    """Finds every `var` declaration (in order) so the function header can
    declare all locals up front. WASM numbers locals after the parameters."""
    for i in range(len(body)):
        var stmt = module.stmts[body[i]].copy()
        if stmt.kind == "VAR":
            found.append(stmt.name)
        collect_locals(module, stmt.body, found)
        collect_locals(module, stmt.else_body, found)


# ---- Expressions and statements ----------------------------------------------


def emit_expr(
    module: Module, mut code: List[UInt8], names: List[String], index: Int
) raises:
    var expr = module.exprs[index].copy()

    if expr.kind == "INT":
        code.append(op_i64_const())
        append_all(code, encode_sleb128(expr.value))

    elif expr.kind == "VAR":
        code.append(op_local_get())
        append_all(code, encode_uleb128(index_of(names, expr.name)))

    elif expr.kind == "NOT":
        emit_expr(module, code, names, expr.left)
        code.append(op_i32_eqz())

    elif expr.kind == "LOGIC":
        # Short-circuit evaluation, so `n > 0 and 10 // n > 1` never divides
        # by zero:
        #   a and b  ->  a ; if (result i32) b else 0 end
        #   a or  b  ->  a ; if (result i32) 1 else b end
        emit_expr(module, code, names, expr.left)
        code.append(op_if())
        code.append(block_type_i32())
        if expr.op == "and":
            emit_expr(module, code, names, expr.right)
            code.append(op_else())
            code.append(op_i32_const())
            code.append(0)
        else:
            code.append(op_i32_const())
            code.append(1)
            code.append(op_else())
            emit_expr(module, code, names, expr.right)
        code.append(op_end())

    elif expr.kind == "BINARY":
        emit_expr(module, code, names, expr.left)
        emit_expr(module, code, names, expr.right)
        if expr.op == "//" or expr.op == "%":
            code.append(op_call())
            append_all(
                code, encode_uleb128(helper_index(module, expr.op))
            )
        else:
            code.append(binary_opcode(expr.op))

    else:  # CALL: push the arguments, then call by function index
        for i in range(len(expr.args)):
            emit_expr(module, code, names, expr.args[i])
        code.append(op_call())
        append_all(code, encode_uleb128(module.find_function(expr.name)))


def emit_block(
    module: Module,
    mut code: List[UInt8],
    names: List[String],
    body: List[Int],
    break_label: Int,
    continue_label: Int,
) raises:
    """Emits statements.

    `break_label` / `continue_label` are the WASM branch depths that reach
    the end of / the top of the innermost enclosing loop from this point
    (-1 outside a loop). Every `if` entered adds one level of nesting.
    """
    for i in range(len(body)):
        var stmt = module.stmts[body[i]].copy()

        if stmt.kind == "RETURN":
            emit_expr(module, code, names, stmt.expr)
            code.append(op_return())

        elif stmt.kind == "BREAK":
            code.append(op_br())
            append_all(code, encode_uleb128(break_label))

        elif stmt.kind == "CONTINUE":
            code.append(op_br())
            append_all(code, encode_uleb128(continue_label))

        elif stmt.kind == "IF":
            var inner_break = -1
            var inner_continue = -1
            if break_label >= 0:
                inner_break = break_label + 1
                inner_continue = continue_label + 1

            emit_expr(module, code, names, stmt.expr)
            code.append(op_if())
            code.append(block_type_empty())
            emit_block(
                module, code, names, stmt.body, inner_break, inner_continue
            )
            if len(stmt.else_body) > 0:
                code.append(op_else())
                emit_block(
                    module,
                    code,
                    names,
                    stmt.else_body,
                    inner_break,
                    inner_continue,
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
            emit_expr(module, code, names, stmt.expr)
            code.append(op_i32_eqz())
            code.append(op_br_if())
            code.append(1)  # leave the outer block
            emit_block(module, code, names, stmt.body, 1, 0)
            code.append(op_br())
            code.append(0)  # jump back to the top of the loop
            code.append(op_end())
            code.append(op_end())

        else:  # VAR and ASSIGN both store into a local
            emit_expr(module, code, names, stmt.expr)
            code.append(op_local_set())
            append_all(code, encode_uleb128(index_of(names, stmt.name)))


# ---- The module ----------------------------------------------------------------


def emit(module: Module) raises -> List[UInt8]:
    """Turns a checked Module into the bytes of a .wasm file.

    Function i of the source file becomes WASM function i, and every source
    function is exported under its own name. Helper functions (for `//` and
    `%`) follow the user's functions and are not exported.
    """
    var user_count = len(module.functions)
    var helpers = helper_count(module)
    var total = user_count + helpers
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

    # ---- Type section: one signature (i64 x n) -> i64 per function ----
    var types = List[UInt8]()
    append_all(types, encode_uleb128(total))
    for f in range(user_count):
        var parameter_count = len(module.functions[f].parameters)
        types.append(func_type_tag())
        append_all(types, encode_uleb128(parameter_count))
        for _ in range(parameter_count):
            types.append(i64_type())
        types.append(1)  # one result
        types.append(i64_type())
    for _ in range(helpers):  # helpers are all (i64, i64) -> i64
        types.append(func_type_tag())
        types.append(2)
        types.append(i64_type())
        types.append(i64_type())
        types.append(1)
        types.append(i64_type())
    append_all(out, make_section(section_type(), types))

    # ---- Function section: function f uses type f ----
    var functions = List[UInt8]()
    append_all(functions, encode_uleb128(total))
    for f in range(total):
        append_all(functions, encode_uleb128(f))
    append_all(out, make_section(section_function(), functions))

    # ---- Export section: the user's functions, under their source names ----
    var exports = List[UInt8]()
    append_all(exports, encode_uleb128(user_count))
    for f in range(user_count):
        var name_bytes = string_bytes(module.functions[f].name)
        append_all(exports, encode_uleb128(len(name_bytes)))
        append_all(exports, name_bytes)
        exports.append(export_kind_function())
        append_all(exports, encode_uleb128(f))
    append_all(out, make_section(section_export(), exports))

    # ---- Code section: one body per function ----
    var code_section = List[UInt8]()
    append_all(code_section, encode_uleb128(total))

    for f in range(user_count):
        var function = module.functions[f].copy()

        # Local numbering: parameters first, then `var` declarations.
        var declared = List[String]()
        collect_locals(module, function.body, declared)

        var names = List[String]()
        for p in range(len(function.parameters)):
            names.append(function.parameters[p].name)
        for d in range(len(declared)):
            names.append(declared[d])

        var body = List[UInt8]()

        # Local declarations: one group of `n` i64 locals (or none).
        if len(declared) > 0:
            body.append(1)
            append_all(body, encode_uleb128(len(declared)))
            body.append(i64_type())
        else:
            body.append(0)

        emit_block(module, body, names, function.body, -1, -1)

        # The checker guarantees every path returns, but WASM validation
        # still wants the body to end in a well-typed state.
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

    return out^
