from .tokens import Token


def lex(source: String) -> List[Token]:
    var tokens = List[Token]()
    var i = 0

    while i < len(source):
        var c = source[i]

        # Whitespace
        if c == " " or c == "\n" or c == "\t" or c == "\r":
            i += 1
            continue

        # def
        if source[i:i + 3] == "def":
            tokens.append(Token("DEF", "def"))
            i += 3
            continue

        # return
        if source[i:i + 6] == "return":
            tokens.append(Token("RETURN", "return"))
            i += 6
            continue

        # Int
        if source[i:i + 3] == "Int":
            tokens.append(Token("INT", "Int"))
            i += 3
            continue

        # Identifier
        if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_":
            var start = i

            while i < len(source):
                var ch = source[i]

                if not (
                    (ch >= "a" and ch <= "z") or
                    (ch >= "A" and ch <= "Z") or
                    (ch >= "0" and ch <= "9") or
                    ch == "_"
                ):
                    break

                i += 1

            tokens.append(
                Token("IDENTIFIER", source[start:i])
            )
            continue

        # Integer literal
        if c >= "0" and c <= "9":
            var start = i

            while i < len(source):
                var ch = source[i]

                if ch < "0" or ch > "9":
                    break

                i += 1

            tokens.append(
                Token("INTEGER", source[start:i])
            )
            continue

        # Punctuation
        if c == "(":
            tokens.append(Token("LPAREN", "("))
            i += 1
            continue

        if c == ")":
            tokens.append(Token("RPAREN", ")"))
            i += 1
            continue

        if c == ":":
            tokens.append(Token("COLON", ":"))
            i += 1
            continue

        if c == ",":
            tokens.append(Token("COMMA", ","))
            i += 1
            continue

        if c == "+":
            tokens.append(Token("PLUS", "+"))
            i += 1
            continue

        # ->
        if c == "-" and i + 1 < len(source):
            if source[i + 1] == ">":
                tokens.append(Token("ARROW", "->"))
                i += 2
                continue

        # Anything we don't understand yet
        tokens.append(Token("UNKNOWN", c))
        i += 1

    tokens.append(Token("EOF", ""))

    return tokens