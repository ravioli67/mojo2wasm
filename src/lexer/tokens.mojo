struct Token:
    var kind: String
    var lexeme: String

    def __init__(out self, kind: String, lexeme: String):
        self.kind = kind
        self.lexeme = lexeme