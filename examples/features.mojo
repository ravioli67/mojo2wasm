def gcd(a: Int, b: Int) -> Int:
    while b != 0:
        var t = b
        b = a % b
        a = t
    return a

def abs(x: Int) -> Int:
    if x < 0:
        return -x
    else:
        return x

def sign(x: Int) -> Int:
    if x < 0:
        return -1
    elif x == 0:
        return 0
    else:
        return 1

def poly(x: Int) -> Int:
    return (x + 2) * 3 - x // 2 * (4 - 1)

def fact(n: Int) -> Int:
    if n <= 1:
        return 1
    return n * fact(n - 1)

def twice(x: Int) -> Int:
    return helper(x) + helper(x)

def helper(y: Int) -> Int:
    return y * 10 + 123456789012
