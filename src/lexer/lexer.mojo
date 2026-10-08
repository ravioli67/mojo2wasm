from .tokens import Token


def is_letter_or_underscore(c: String) -> Bool:
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"


def is_digit(c: String) -> Bool:
    return c >= "0" and c <= "9"


def keyword_kind(word: String) -> String:
    """Token kind for a reserved word, or "" if `word` is not reserved."""
    if word == "def":
        return "DEF"
    if word == "return":
        return "RETURN"
    if word == "if":
        return "IF"
    if word == "elif":
        return "ELIF"
    if word == "else":
        return "ELSE"
    if word == "while":
        return "WHILE"
    if word == "var":
        return "VAR"
    if word == "Int":
        return "INT"
    return ""


def single_char_kind(c: String) -> String:
    """Token kind for a one-character token, or "" if there is none."""
    if c == "(":
        return "LPAREN"
    if c == ")":
        return "RPAREN"
    if c == ":":
        return "COLON"
    if c == ",":
        return "COMMA"
    if c == "+":
        return "PLUS"
    if c == "-":
        return "MINUS"
    if c == "*":
        return "STAR"
    if c == "%":
        return "PERCENT"
    if c == "<":
        return "LT"
    if c == ">":
        return "GT"
    if c == "=":
        return "ASSIGN"
    return ""


def two_char_kind(pair: String) -> String:
    """Token kind for a two-character token, or "" if there is none."""
    if pair == "->":
        return "ARROW"
    if pair == "<=":
        return "LE"
    if pair == ">=":
        return "GE"
    if pair == "==":
        return "EQ"
    if pair == "!=":
        return "NE"
    if pair == "//":
        return "SLASHSLASH"
    return ""


def lex(source: String) raises -> List[Token]:
    """Turns source text into tokens.

    Like Python, indentation is significant: the lexer emits NEWLINE at the
    end of every logical line and INDENT / DEDENT when the indentation level
    changes. Blank lines and `#` comments are skipped. Newlines inside
    parentheses are ignored.
    """
    var tokens = List[Token]()
    var indents = List[Int]()
    indents.append(0)

    var i = 0
    var line = 1
    var depth = 0  # parenthesis nesting
    var at_line_start = True
    var n = len(source)

    while i < n:
        # ---- Start of a line: measure indentation -------------------------
        if at_line_start and depth == 0:
            var col = 0
            while i < n and (source[i] == " " or source[i] == "\t"):
                if source[i] == "\t":
                    col += 4
                else:
                    col += 1
                i += 1

            if i >= n:
                break

            var first = source[i]

            # Blank line
            if first == "\n":
                i += 1
                line += 1
                continue
            if first == "\r":
                i += 1
                continue

            # Comment-only line
            if first == "#":
                while i < n and source[i] != "\n":
                    i += 1
                continue

            # A real line: compare its indentation with the enclosing blocks.
            var top = indents[len(indents) - 1]
            if col > top:
                indents.append(col)
                tokens.append(Token("INDENT", "", line))
            elif col < top:
                while col < indents[len(indents) - 1]:
                    _ = indents.pop()
                    tokens.append(Token("DEDENT", "", line))
                if col != indents[len(indents) - 1]:
                    raise Error(
                        "Lexer error: inconsistent indentation on line "
                        + String(line)
                    )

            at_line_start = False
            continue

        var c = source[i]

        # ---- Whitespace inside a line -------------------------------------
        if c == " " or c == "\t" or c == "\r":
            i += 1
            continue

        # ---- Comment ------------------------------------------------------
        if c == "#":
            while i < n and source[i] != "\n":
                i += 1
            continue

        # ---- End of line --------------------------------------------------
        if c == "\n":
            i += 1
            line += 1
            if depth == 0:
                tokens.append(Token("NEWLINE", "\\n", line - 1))
                at_line_start = True
            continue

        # ---- Identifier or keyword ----------------------------------------
        # Read the WHOLE word first, then decide whether it is reserved.
        if is_letter_or_underscore(c):
            var start = i
            while i < n:
                var ch = source[i]
                if not (is_letter_or_underscore(ch) or is_digit(ch)):
                    break
                i += 1

            var word = source[start:i]
            var kind = keyword_kind(word)
            if kind != "":
                tokens.append(Token(kind, word, line))
            else:
                tokens.append(Token("IDENTIFIER", word, line))
            continue

        # ---- Integer literal ----------------------------------------------
        if is_digit(c):
            var start = i
            while i < n:
                if not is_digit(source[i]):
                    break
                i += 1
            tokens.append(Token("INTEGER", source[start:i], line))
            continue

        # ---- Two-character operators (checked before one-character ones) --
        if i + 1 < n:
            var pair = source[i : i + 2]
            var pair_kind = two_char_kind(pair)
            if pair_kind != "":
                tokens.append(Token(pair_kind, pair, line))
                i += 2
                continue

        # ---- One-character tokens -----------------------------------------
        var kind = single_char_kind(c)
        if kind != "":
            if c == "(":
                depth += 1
            if c == ")" and depth > 0:
                depth -= 1
            tokens.append(Token(kind, c, line))
            i += 1
            continue

        # ---- Anything we don't understand yet -----------------------------
        tokens.append(Token("UNKNOWN", c, line))
        i += 1

    # The last line may not end with a newline.
    if len(tokens) > 0 and tokens[len(tokens) - 1].kind != "NEWLINE":
        tokens.append(Token("NEWLINE", "\\n", line))

    # Close every block that is still open.
    while len(indents) > 1:
        _ = indents.pop()
        tokens.append(Token("DEDENT", "", line))

    tokens.append(Token("EOF", "", line))

    return tokens^
