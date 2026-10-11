# Float64 and Bool.
#
# From JavaScript: Int is a BigInt, Float64 is a number, Bool is 0 or 1.

def circle_area(r: Float64) -> Float64:
    return 3.14159 * r * r


def average(a: Float64, b: Float64) -> Float64:
    return (a + b) / 2.0


def celsius_to_fahrenheit(c: Float64) -> Float64:
    return c * 9.0 / 5.0 + 32.0


def to_float(n: Int) -> Float64:
    return Float64(n)


def truncate(x: Float64) -> Int:
    return Int(x)


def negate(x: Float64) -> Float64:
    return -x


def sqrt_newton(x: Float64) -> Float64:
    # Newton's method; 30 iterations is plenty for doubles.
    if x <= 0.0:
        return 0.0
    var guess = x / 2.0 + 0.5
    var i = 0
    while i < 30:
        guess = (guess + x / guess) / 2.0
        i += 1
    return guess


def mean_of_first(n: Int) -> Float64:
    # 1 + 2 + ... + n, divided by n.
    var total = 0.0
    var i = 1
    while i <= n:
        total += Float64(i)
        i += 1
    return total / Float64(n)


def is_even(n: Int) -> Bool:
    return n % 2 == 0


def is_positive(x: Float64) -> Bool:
    return x > 0.0


def truth() -> Bool:
    return True


def invert(b: Bool) -> Bool:
    return not b


def both(a: Bool, b: Bool) -> Bool:
    return a and b


def either(a: Bool, b: Bool) -> Bool:
    return a or b


def exactly_one(a: Bool, b: Bool) -> Bool:
    return (a or b) and not (a and b)


def same(a: Bool, b: Bool) -> Bool:
    return a == b


def bool_to_int(b: Bool) -> Int:
    return Int(b)


def int_to_bool(n: Int) -> Bool:
    return Bool(n)


def clamp01(x: Float64) -> Float64:
    var below = x < 0.0
    var above = x > 1.0
    if below:
        return 0.0
    if above:
        return 1.0
    return x


def in_unit_range(x: Float64) -> Bool:
    var ok = x >= 0.0 and x <= 1.0
    return ok


def count_primes_below(limit: Int) -> Int:
    var count = 0
    var n = 2
    while n < limit:
        var prime = True
        var d = 2
        while d * d <= n:
            if n % d == 0:
                prime = False
                break
            d += 1
        if prime:
            count += 1
        n += 1
    return count
