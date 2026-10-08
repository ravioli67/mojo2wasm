from .compiler import Compiler


def compile(source: String) raises -> List[UInt8]: # the main function is here (call it)
    """Public entry point: Mojo source in, .wasm bytes out."""
    var compiler = Compiler()
    return compiler.compile(source)
