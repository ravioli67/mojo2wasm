from ..parser.ast import Module
from .types import i64_type
from .types import func_type_tag
from .types import block_type_empty
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
from .types import op_i64_div_s
from .types import op_i64_rem_s
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
    if op == "+":
        return op_i64_add()
    if op == "-":
        return op_i64_sub()
    if op == "*":
        return op_i64_mul()
    if op == "//":
        return op_i64_div_s()
    if op == "%":
        return op_i64_rem_s()
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

    elif expr.kind == "BINARY":
        emit_expr(module, code, names, expr.left)
        emit_expr(module, code, names, expr.right)
        code.append(binary_opcode(expr.op))

    else:  # CALL: push the arguments, then call by function index
        for i in range(len(expr.args)):
            emit_expr(module, code, names, expr.args[i])
        code.append(op_call())
        append_all(code, encode_uleb128(module.find_function(expr.name)))


def emit_block(
    module: Module, mut code: List[UInt8], names: List[String], body: List[Int]
) raises:
    for i in range(len(body)):
        var stmt = module.stmts[body[i]].copy()

        if stmt.kind == "RETURN":
            emit_expr(module, code, names, stmt.expr)
            code.append(op_return())

        elif stmt.kind == "IF":
            emit_expr(module, code, names, stmt.expr)
            code.append(op_if())
            code.append(block_type_empty())
            emit_block(module, code, names, stmt.body)
            if len(stmt.else_body) > 0:
                code.append(op_else())
                emit_block(module, code, names, stmt.else_body)
            code.append(op_end())

        elif stmt.kind == "WHILE":
            # block { loop { if !cond break; body; continue } }
            code.append(op_block())
            code.append(block_type_empty())
            code.append(op_loop())
            code.append(block_type_empty())
            emit_expr(module, code, names, stmt.expr)
            code.append(op_i32_eqz())
            code.append(op_br_if())
            code.append(1)  # leave the outer block
            emit_block(module, code, names, stmt.body)
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

    Function i of the source file becomes WASM function i, and every
    function is exported under its own name.
    """
    var count = len(module.functions)
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
    append_all(types, encode_uleb128(count))
    for f in range(count):
        var parameter_count = len(module.functions[f].parameters)
        types.append(func_type_tag())
        append_all(types, encode_uleb128(parameter_count))
        for _ in range(parameter_count):
            types.append(i64_type())
        types.append(1)  # one result
        types.append(i64_type())
    append_all(out, make_section(section_type(), types))

    # ---- Function section: function f uses type f ----
    var functions = List[UInt8]()
    append_all(functions, encode_uleb128(count))
    for f in range(count):
        append_all(functions, encode_uleb128(f))
    append_all(out, make_section(section_function(), functions))

    # ---- Export section: every function, under its source name ----
    var exports = List[UInt8]()
    append_all(exports, encode_uleb128(count))
    for f in range(count):
        var name_bytes = string_bytes(module.functions[f].name)
        append_all(exports, encode_uleb128(len(name_bytes)))
        append_all(exports, name_bytes)
        exports.append(export_kind_function())
        append_all(exports, encode_uleb128(f))
    append_all(out, make_section(section_export(), exports))

    # ---- Code section: one body per function ----
    var code_section = List[UInt8]()
    append_all(code_section, encode_uleb128(count))

    for f in range(count):
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

        emit_block(module, body, names, function.body)

        # The checker guarantees every path returns, but WASM validation
        # still wants the body to end in a well-typed state.
        body.append(op_unreachable())
        body.append(op_end())

        append_all(code_section, encode_uleb128(len(body)))
        append_all(code_section, body)

    append_all(out, make_section(section_code(), code_section))

    return out^
