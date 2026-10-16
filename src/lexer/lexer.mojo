from .tokens import Token
from ..util.diagnostics import error_at


def is_letter_or_underscore(c: String) -> Bool:
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"


def is_digit(c: String) -> Bool:
    return c >= "0" and c <= "9"


def keyword_kind(word: String) -> String:
    """Token kind for a reserved word, or "" if `word` is not reserved."""
    if word == "def" or word == "fn":
        return "DEF"
    if word == "raises":
        return "RAISES"
    if word == "for":
        return "FOR"
    if word == "in":
        return "IN"
    if word == "pass":
        return "PASS"
    if word == "alias" or word == "comptime":
        return "ALIAS"
    if word == "None":
        return "NONE"
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
    if word == "and":
        return "AND"
    if word == "or":
        return "OR"
    if word == "not":
        return "NOT"
    if word == "break":
        return "BREAK"
    if word == "continue":
        return "CONTINUE"
    if word == "True":
        return "TRUE"
    if word == "False":
        return "FALSE"
    if word == "Int":
        return "INT"
    if word == "Float64":
        return "FLOAT64"
    if word == "Bool":
        return "BOOL"
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
    if c == "/":
        return "SLASH"
    if c == "%":
        return "PERCENT"
    if c == "<":
        return "LT"
    if c == ">":
        return "GT"
    if c == "=":
        return "ASSIGN"
    return ""


def three_char_kind(triple: String) -> String:
    """Token kind for a three-character token, or "" if there is none."""
    if triple == "//=":
        return "SLASHSLASHEQ"
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
    if pair == "+=":
        return "PLUSEQ"
    if pair == "-=":
        return "MINUSEQ"
    if pair == "*=":
        return "STAREQ"
    if pair == "%=":
        return "PERCENTEQ"
    if pair == "/=":
        return "SLASHEQ"
    return ""


def escape_char(c: String) -> String:
    """The character that an escape such as backslash-n stands for, or ""
    if the escape is unknown."""
    if c == "n":
        return "\n"
    if c == "t":
        return "\t"
    if c == "r":
        return "\r"
    if c == "0":
        return "\0"
    if c == "\\":
        return "\\"
    if c == "\"":
        return "\""
    if c == "'":
        return "'"
    return ""


def lex(source: String) raises -> List[Token]:
    """Turns source text into tokens.

    Like Python, indentation is significant: the lexer emits NEWLINE at the
    end of every logical line and INDENT / DEDENT when the indentation level
    changes. Blank lines and `#` comments are skipped. Newlines inside
    parentheses are ignored. Every token records its line and column.
    """
    var tokens = List[Token]()
    var indents = List[Int]()
    indents.append(0)

    # Positions of the '(' characters that are still open.
    var paren_lines = List[Int]()
    var paren_columns = List[Int]()

    var i = 0
    var line = 1
    var line_start = 0  # index of the first character of the current line
    var at_line_start = True
    var n = len(source)

    while i < n:
        # ---- Start of a line: measure indentation -------------------------
        if at_line_start and len(paren_lines) == 0:
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
                line_start = i
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
            var first_column = i - line_start + 1
            var top = indents[len(indents) - 1]
            if col > top:
                indents.append(col)
                tokens.append(Token("INDENT", "", line, first_column))
            elif col < top:
                while col < indents[len(indents) - 1]:
                    _ = indents.pop()
                    tokens.append(Token("DEDENT", "", line, first_column))
                if col != indents[len(indents) - 1]:
                    raise Error(
                        error_at(
                            "Lexer",
                            line,
                            first_column,
                            (
                                "inconsistent indentation: this line does not"
                                " line up with any enclosing block"
                            ),
                        )
                    )

            at_line_start = False
            continue

        var c = source[i]
        var column = i - line_start + 1

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
            if len(paren_lines) == 0:
                tokens.append(Token("NEWLINE", "\\n", line, column))
                at_line_start = True
            i += 1
            line += 1
            line_start = i
            continue

        # ---- String literal: "text", 'text' or """text""" -----------------
        if c == "\"" or c == "'":
            var quote = c
            var triple = (
                i + 2 < n
                and source[i + 1] == quote
                and source[i + 2] == quote
            )
            var start_line = line
            var start_column = column
            var j = i + 1
            if triple:
                j = i + 3
            var text = String("")

            while True:
                if j >= n:
                    raise Error(
                        error_at(
                            "Lexer",
                            start_line,
                            start_column,
                            "this string is never closed",
                        )
                    )

                var ch = source[j]

                if (
                    triple
                    and ch == quote
                    and j + 2 < n
                    and source[j + 1] == quote
                    and source[j + 2] == quote
                ):
                    j += 3
                    break
                if (not triple) and ch == quote:
                    j += 1
                    break
                if (not triple) and ch == "\n":
                    raise Error(
                        error_at(
                            "Lexer",
                            start_line,
                            start_column,
                            (
                                "this string is never closed (use triple quotes"
                                " for strings that span lines)"
                            ),
                        )
                    )

                if ch == "\\":
                    var escaped = String("")
                    if j + 1 < n:
                        escaped = source[j + 1]
                    var replacement = escape_char(escaped)
                    if escaped == "" or replacement == "":
                        raise Error(
                            error_at(
                                "Lexer",
                                line,
                                j - line_start + 1,
                                "unknown escape sequence '\\" + escaped + "'",
                            )
                        )
                    text += replacement
                    j += 2
                    continue

                if ch == "\n":
                    line += 1
                    line_start = j + 1
                text += ch
                j += 1

            tokens.append(Token("STRING", text, start_line, start_column))
            i = j
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
                tokens.append(Token(kind, word, line, column))
            else:
                tokens.append(Token("IDENTIFIER", word, line, column))
            continue

        # ---- Number: 42 or 3.14 -------------------------------------------
        if is_digit(c):
            var start = i
            while i < n:
                if not is_digit(source[i]):
                    break
                i += 1

            if i + 1 < n and source[i] == "." and is_digit(source[i + 1]):
                i += 1
                while i < n:
                    if not is_digit(source[i]):
                        break
                    i += 1
                tokens.append(Token("FLOAT", source[start:i], line, column))
            else:
                tokens.append(Token("INTEGER", source[start:i], line, column))
            continue

        # ---- Longer operators are checked before shorter ones -------------
        if i + 2 < n:
            var triple = source[i : i + 3]
            var triple_kind = three_char_kind(triple)
            if triple_kind != "":
                tokens.append(Token(triple_kind, triple, line, column))
                i += 3
                continue

        if i + 1 < n:
            var pair = source[i : i + 2]
            var pair_kind = two_char_kind(pair)
            if pair_kind != "":
                tokens.append(Token(pair_kind, pair, line, column))
                i += 2
                continue

        # ---- One-character tokens -----------------------------------------
        var single = single_char_kind(c)
        if single != "":
            if c == "(":
                paren_lines.append(line)
                paren_columns.append(column)
            if c == ")":
                if len(paren_lines) == 0:
                    raise Error(
                        error_at(
                            "Lexer",
                            line,
                            column,
                            "this ')' has no matching '('",
                        )
                    )
                _ = paren_lines.pop()
                _ = paren_columns.pop()
            tokens.append(Token(single, c, line, column))
            i += 1
            continue

        # ---- Anything else is an error ------------------------------------
        raise Error(
            error_at("Lexer", line, column, "unexpected character '" + c + "'")
        )

    # A '(' that was never closed.
    if len(paren_lines) > 0:
        var last = len(paren_lines) - 1
        raise Error(
            error_at(
                "Lexer",
                paren_lines[last],
                paren_columns[last],
                "this '(' is never closed",
            )
        )

    var end_column = n - line_start + 1

    # The last line may not end with a newline.
    if len(tokens) > 0 and tokens[len(tokens) - 1].kind != "NEWLINE":
        tokens.append(Token("NEWLINE", "\\n", line, end_column))

    # Close every block that is still open.
    while len(indents) > 1:
        _ = indents.pop()
        tokens.append(Token("DEDENT", "", line, end_column))

    tokens.append(Token("EOF", "", line, end_column))

    return tokens^
