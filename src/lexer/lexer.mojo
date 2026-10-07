from .tokens import Token


def lex(source: String) -> List[Token]:
    var tokens = List[Token]()
    var i = 0

    while i < len(source):
        var c = source[i]

        # Whitespace
        if c == " " or c == "\n" or c == "\t":
            i += 1
            continue

        # def
        if c == "d":
            if source[i:i + 3] == "def":
                tokens.append(Token("DEF", "def"))
                i += 3
                continue

        # return
        if c == "r":
            if source[i:i + 6] == "return":
                tokens.append(Token("RETURN", "return"))
                i += 6
                continue

        # Int
        if c == "I":
            if source[i:i + 3] == "Int":
                tokens.append(Token("INT", "Int"))
                i += 3
                continue

        # Identifier
        if c >= "a" and c <= "z":
            var start = i

            while i < len(source):
                var current = source[i]

                if not (
                    (current >= "a" and current <= "z") or
                    (current >= "A" and current <= "Z") or
                    (current >= "0" and current <= "9") or
                    current == "_"
                ):
                    break

                i += 1

            tokens.append(
                Token("IDENTIFIER", source[start:i])
            )
            continue

        # Integer
        if c >= "0" and c <= "9":
            var start = i

            while i < len(source):
                var current = source[i]

                if current < "0" or current > "9":
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
        if c == "-":
            if i + 1 < len(source) and source[i + 1] == ">":
                tokens.append(Token("ARROW", "->"))
                i += 2
                continue

        # Unknown
        tokens.append(Token("UNKNOWN", source[i]))
        i += 1

    tokens.append(Token("EOF", ""))
    return tokens