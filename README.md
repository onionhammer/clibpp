clibpp
======

Easy way to 'Mock' C++ interface

Usage
-----
```nimrod
    class test, "../test.hpp":
        proc multiply[T](value, by: T): int
        proc output: void {.isstatic.}
        proc max[T](a, b: T): T
        var fieldName, notherName: int
```