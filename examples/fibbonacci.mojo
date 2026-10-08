# Recursive and iterative Fibonacci.

def fib(n: Int) -> Int:
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)


def fib_iter(n: Int) -> Int:
    var a = 0
    var b = 1
    var i = 0
    while i < n:
        var t = a + b
        a = b
        b = t
        i = i + 1
    return a
