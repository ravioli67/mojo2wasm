from .compiler import Compiler


def compile(source: String) -> String:
    var compiler = Compiler()             # Here is the entry point for the public API
    return compiler.compile(source)    # The api is quickly changing so I decided to refrain from using all the files to prevent errors