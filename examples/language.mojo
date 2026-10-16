"""Showcase of the newer language features."""

alias LIMIT = 10
alias TWICE = LIMIT * 2
alias SCALE: Float64 = 2.5


fn sum_to(n: Int) -> Int:
    """Adds 0 + 1 + ... + n."""
    var total = 0
    for i in range(n + 1):
        total += i
    return total


fn count_even(n: Int) -> Int:
    var count = 0
    for i in range(n):
        if i % 2 != 0:
            continue
        count += 1
    return count


fn first_multiple(of: Int, above: Int) -> Int:
    var found = -1
    for i in range(above + 1, above + 1000):
        if i % of == 0:
            found = i
            break
    return found


fn countdown() raises:
    for i in range(5, 0, -1):
        print(i)
    print("liftoff")


fn evens() -> None:
    for i in range(0, 10, 2):
        print(i)


fn two_loops() -> Int:
    var total = 0
    for i in range(3):
        total += i
    for i in range(10, 13):
        total += i
    return total


fn nested(n: Int) -> Int:
    var total = 0
    for i in range(n):
        for j in range(i):
            total += 1
    return total


fn shadowing() -> Int:
    var x = 1
    if True:
        var x = 100
        x += 1
    return x


fn max_of(a: Int, b: Int) -> Int:
    return a if a > b else b


fn abs_float(x: Float64) -> Float64:
    return -x if x < 0.0 else x


fn grade(score: Int) -> Int:
    return 4 if score >= 90 else 3 if score >= 80 else 2 if score >= 70 else 0


fn scaled(x: Float64) -> Float64:
    return x * SCALE


fn limits() -> Int:
    return LIMIT + TWICE


fn noop():
    pass


fn log_and_double(x: Int) -> Int:
    print("doubling", x)
    return x * 2


fn use_result() -> Int:
    var y = log_and_double(21)
    log_and_double(5)
    noop()
    return y


fn fizzbuzz(n: Int):
    for i in range(1, n + 1):
        if i % 15 == 0:
            print("FizzBuzz")
        elif i % 3 == 0:
            print("Fizz")
        elif i % 5 == 0:
            print("Buzz")
        else:
            print(i)


fn early(n: Int):
    if n < 0:
        print("negative")
        return
    print("ok", n)
