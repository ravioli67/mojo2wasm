def to_hex(data: List[UInt8]) -> String:
    """Formats bytes as lowercase hex separated by spaces: "00 61 73 6d"."""
    var digits = "0123456789abcdef"
    var out = String()

    for i in range(len(data)):
        if i > 0:
            out += " "
        var byte = Int(data[i])
        var high = byte >> 4
        var low = byte & 15
        out += digits[high : high + 1]
        out += digits[low : low + 1]

    return out^
