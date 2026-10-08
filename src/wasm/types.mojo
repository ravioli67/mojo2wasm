"""WebAssembly binary-format constants and LEB128 helpers.

Constants are functions so they work regardless of Mojo's current
`alias` / `comptime` spelling.
"""

# ---- Value types -----------------------------------------------------------
# Mojo's `Int` is 64-bit, so it maps to WASM `i64`.


def i64_type() -> UInt8:
    return 0x7E


def func_type_tag() -> UInt8:
    return 0x60


def block_type_empty() -> UInt8:
    return 0x40


# ---- Section ids -----------------------------------------------------------


def section_type() -> UInt8:
    return 1


def section_function() -> UInt8:
    return 3


def section_export() -> UInt8:
    return 7


def section_code() -> UInt8:
    return 10


def export_kind_function() -> UInt8:
    return 0x00


# ---- Control-flow opcodes --------------------------------------------------


def op_unreachable() -> UInt8:
    return 0x00


def op_block() -> UInt8:
    return 0x02


def op_loop() -> UInt8:
    return 0x03


def op_if() -> UInt8:
    return 0x04


def op_else() -> UInt8:
    return 0x05


def op_end() -> UInt8:
    return 0x0B


def op_br() -> UInt8:
    return 0x0C


def op_br_if() -> UInt8:
    return 0x0D


def op_return() -> UInt8:
    return 0x0F


def op_call() -> UInt8:
    return 0x10


# ---- Variable opcodes ------------------------------------------------------


def op_local_get() -> UInt8:
    return 0x20


def op_local_set() -> UInt8:
    return 0x21


# ---- Numeric opcodes -------------------------------------------------------


def op_i64_const() -> UInt8:
    return 0x42


def op_i32_eqz() -> UInt8:
    return 0x45


def op_i64_eq() -> UInt8:
    return 0x51


def op_i64_ne() -> UInt8:
    return 0x52


def op_i64_lt_s() -> UInt8:
    return 0x53


def op_i64_gt_s() -> UInt8:
    return 0x55


def op_i64_le_s() -> UInt8:
    return 0x57


def op_i64_ge_s() -> UInt8:
    return 0x59


def op_i64_add() -> UInt8:
    return 0x7C


def op_i64_sub() -> UInt8:
    return 0x7D


def op_i64_mul() -> UInt8:
    return 0x7E


def op_i64_div_s() -> UInt8:
    return 0x7F


def op_i64_rem_s() -> UInt8:
    return 0x81


# ---- LEB128 ----------------------------------------------------------------


def encode_uleb128(value: Int) -> List[UInt8]:
    """Unsigned LEB128: used for sizes, counts and indices."""
    var result = List[UInt8]()
    var v = value

    while True:
        var byte = v & 0x7F
        v = v >> 7
        if v != 0:
            result.append(UInt8(byte | 0x80))
        else:
            result.append(UInt8(byte))
            break

    return result^


def encode_sleb128(value: Int) -> List[UInt8]:
    """Signed LEB128: used for `i64.const` immediates."""
    var result = List[UInt8]()
    var v = value
    var more = True

    while more:
        var byte = v & 0x7F
        v = v >> 7  # arithmetic shift keeps the sign
        var sign_bit_set = (byte & 0x40) != 0

        if (v == 0 and not sign_bit_set) or (v == -1 and sign_bit_set):
            more = False
        else:
            byte = byte | 0x80

        result.append(UInt8(byte))

    return result^
