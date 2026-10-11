def error_at(kind: String, line: Int, column: Int, message: String) -> String:
    """Builds the machine-readable message: `Kind error at L:C: text`."""
    return (
        kind
        + " error at "
        + String(line)
        + ":"
        + String(column)
        + ": "
        + message
    )


def is_digit_char(c: String) -> Bool:
    return c >= "0" and c <= "9"


def is_word_char(c: String) -> Bool:
    return (
        (c >= "a" and c <= "z")
        or (c >= "A" and c <= "Z")
        or c == "_"
        or is_digit_char(c)
    )


def is_operator_char(c: String) -> Bool:
    return (
        c == "<"
        or c == ">"
        or c == "="
        or c == "!"
        or c == "/"
        or c == "+"
        or c == "-"
        or c == "*"
        or c == "%"
    )


def find_text(haystack: String, needle: String) -> Int:
    """Index of the first occurrence of `needle`, or -1."""
    var n = len(needle)
    var i = 0
    while i + n <= len(haystack):
        if haystack[i : i + n] == needle:
            return i
        i += 1
    return -1


# part where it says DID YOU MEAN?


def edit_distance(a: String, b: String) -> Int:
    """Number of single-character edits needed to turn `a` into `b`."""
    var previous = List[Int]()
    for j in range(len(b) + 1):
        previous.append(j)

    for i in range(1, len(a) + 1):
        var current = List[Int]()
        current.append(i)

        for j in range(1, len(b) + 1):
            var cost = 1
            if a[i - 1 : i] == b[j - 1 : j]:
                cost = 0

            var best = previous[j] + 1
            if current[j - 1] + 1 < best:
                best = current[j - 1] + 1
            if previous[j - 1] + cost < best:
                best = previous[j - 1] + cost
            current.append(best)

        previous = current^

    return previous[len(b)]


def suggest(name: String, candidates: List[String]) -> String:
    """Returns " Did you mean 'x'?" for a close match, otherwise "".

    A match must be within 1 edit for names up to 3 letters (2 edits for
    longer ones), and always fewer edits than the name has letters.
    """
    var best = String("")
    var best_distance = 99

    for i in range(len(candidates)):
        var distance = edit_distance(name, candidates[i])
        if distance < best_distance:
            best_distance = distance
            best = candidates[i]

    var limit = 2
    if len(name) <= 3:
        limit = 1

    if best != "" and best_distance <= limit and best_distance < len(name):
        return " Did you mean '" + best + "'?"

    return ""


# ---- Source excerpts ----------------------------------------------------------


def get_source_line(source: String, number: Int) -> String:
    """Line `number` (1-based) of `source`, without the line ending."""
    var current = 1
    var start = 0

    for i in range(len(source)):
        if current == number and source[i : i + 1] == "\n":
            var end = i
            if end > start and source[end - 1 : end] == "\r":
                end -= 1
            return source[start:end]

        if source[i : i + 1] == "\n":
            current += 1
            start = i + 1

    if current == number:
        var end = len(source)
        if end > start and source[end - 1 : end] == "\r":
            end -= 1
        return source[start:end]

    return ""


def underline_length(text: String, column: Int) -> Int:
    """How many carets to draw: the width of the word, number or operator
    that starts at `column` (at least 1)."""
    var i = column - 1
    if i < 0 or i >= len(text):
        return 1

    var c = text[i : i + 1]
    var j = i

    if is_word_char(c):
        while j < len(text) and is_word_char(text[j : j + 1]):
            j += 1
        # A decimal number like 3.14 is one word.
        if (
            is_digit_char(c)
            and j + 1 < len(text)
            and text[j : j + 1] == "."
            and is_digit_char(text[j + 1 : j + 2])
        ):
            j += 1
            while j < len(text) and is_digit_char(text[j : j + 1]):
                j += 1
        return j - i

    if is_operator_char(c):
        while j < len(text) and is_operator_char(text[j : j + 1]):
            j += 1
        return j - i

    return 1


def parse_number(text: String, start: Int) -> Int:
    """Reads the digits of `text` beginning at `start`; -1 if there are none."""
    var value = 0
    var i = start
    var found = False
    while i < len(text) and is_digit_char(text[i : i + 1]):
        value = value * 10 + Int(ord(text[i : i + 1]) - ord("0"))
        i += 1
        found = True
    if not found:
        return -1
    return value


def digit_count(text: String, start: Int) -> Int:
    var i = start
    while i < len(text) and is_digit_char(text[i : i + 1]):
        i += 1
    return i - start


def add_source_context(source: String, message: String) -> String:
    """Expands `Kind error at L:C: text` into a message that shows the
    source line with carets. Messages without a location are returned as is."""
    var marker = " error at "
    var position = find_text(message, marker)
    if position < 0:
        return message

    var kind = message[0:position]
    var rest = message[position + len(marker) :]

    # Parse "L:C: text"
    var line = parse_number(rest, 0)
    if line < 0:
        return message
    var i = digit_count(rest, 0)
    if i >= len(rest) or rest[i : i + 1] != ":":
        return message
    i += 1

    var column = parse_number(rest, i)
    if column < 0:
        return message
    i += digit_count(rest, i)
    if i >= len(rest) or rest[i : i + 1] != ":":
        return message
    i += 1
    if i < len(rest) and rest[i : i + 1] == " ":
        i += 1

    var text = rest[i:]
    var source_line = get_source_line(source, line)

    var gutter = String(line)
    var blank = String("")
    for _ in range(len(gutter)):
        blank += " "

    # Pad with tabs where the source has tabs so the carets line up.
    var padding = String("")
    for k in range(column - 1):
        if k < len(source_line) and source_line[k : k + 1] == "\t":
            padding += "\t"
        else:
            padding += " "

    var carets = String("")
    for _ in range(underline_length(source_line, column)):
        carets += "^"

    return (
        kind
        + " error: "
        + text
        + "\n"
        + blank
        + " --> line "
        + String(line)
        + ", column "
        + String(column)
        + "\n"
        + blank
        + " |\n"
        + gutter
        + " | "
        + source_line
        + "\n"
        + blank
        + " | "
        + padding
        + carets
    )
