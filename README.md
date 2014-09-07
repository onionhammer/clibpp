clibpp
======

Easy way to 'Mock' C++ interface

Outline the C++ class
---------------------
```nimrod
namespace somelibrary:
	class(test, header: "../test.hpp"):
	    proc multiply[T](value, by: T): int
	    proc output: void {.isstatic.}
	    proc max[T](a, b: T): T
	    var fieldName, notherName: int
```

Use the C++ class
-----------------
```nimrod
# Test interface
test.output()

var item: test
echo item.multiply(5, 9)
echo item.fieldName
echo item.max(2, 10)
echo item.notherName
```