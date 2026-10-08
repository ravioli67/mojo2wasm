struct Token(Copyable, Movable):
    var kind: String
    var lexeme: String
    var line: Int

    def __init__(out self, kind: String, lexeme: String, line: Int):
        self.kind = kind
        self.lexeme = lexeme
        self.line = line

    def dump(self):
        print(self.line, self.kind, ":", self.lexeme)
