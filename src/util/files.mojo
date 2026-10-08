def read_file(path: String) raises -> String:
    """Reads a whole text file."""
    var file = open(path, "r")
    var text = file.read()
    file.close()
    return text^


def write_file(path: String, data: List[UInt8]) raises:
    """Writes raw bytes to a file, replacing it if it exists."""
    var file = open(path, "w")
    file.write_bytes(data)
    file.close()
