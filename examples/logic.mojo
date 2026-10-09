# Logic, compound assignment, break / continue and floor division.

def is_prime(n: Int) -> Int:
    if n < 2:
        return 0
    var i = 2
    while i * i <= n:
        if n % i == 0:
            return 0
        i += 1
    return 1


def collatz_steps(n: Int) -> Int:
    var steps = 0
    while n != 1:
        if n % 2 == 0:
            n //= 2
        else:
            n = 3 * n + 1
        steps += 1
    return steps


def sum_odd_until(limit: Int) -> Int:
    var total = 0
    var i = 0
    while i < 1000:
        i += 1
        if i % 2 == 0:
            continue
        if total + i > limit:
            break
        total += i
    return total


def in_range(x: Int, lo: Int, hi: Int) -> Int:
    if x >= lo and x <= hi:
        return 1
    return 0


def is_leap(year: Int) -> Int:
    if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0):
        return 1
    return 0


def safe_ratio(n: Int) -> Int:
    # `10 // n` is never evaluated when n == 0 (short-circuit).
    if n > 0 and 10 // n >= 2:
        return 1
    return 0


def not_demo(a: Int, b: Int) -> Int:
    if not a < b:
        return 1
    return 0


def fdiv(a: Int, b: Int) -> Int:
    return a // b


def fmod(a: Int, b: Int) -> Int:
    return a % b


def folded() -> Int:
    return (2 + 3) * 4 - 20 // 3 + -7 % 3
