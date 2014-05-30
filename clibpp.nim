## Easy way to 'Mock' C++ interface
import macros, parseutils, strutils


proc removePragma(statement: PNimrodNode, pname: string): bool {.compiletime.} =
    ## Removes the input pragma and returns whether pragma was removed
    var index   = 0
    var pragmas = statement.pragma()

    for i in pragmas.children:
        if ($i).toLower() == pname.toLower():
            pragmas.del(index)
            return true
        inc(index)

    return false;


proc makeProcedure(className: string, statement: PNimrodNode): PNimrodNode {.compiletime.} =
    ## Generate an imported procedure definition for the input class name
    var procName = $statement[0]
    var pragmas  = statement.pragma
    var params   = statement.params

    if pragmas.kind == nnkEmpty:
        statement.pragma = newNimNode(nnkPragma)
        pragmas = statement.pragma

    # Add importc (if static) or importcpp pragma
    var importCPragma: PNimrodNode
    var thisNode: PNimrodNode

    # Check if isstatic is set (and remove istatic pragma)
    if statement.removePragma("isstatic"):
        importCPragma = newNimNode(nnkExprColonExpr)
            .add(newIdentNode("importc"))
            .add(newStrLitNode(className & "::" & procName))

        # If static, insert 'this: typedesc[`className`]' param
        thisNode = newNimNode(nnkIdentDefs)
            .add(newIdentNode("this"))
            .add(parseExpr("typedesc[" & className & "]"))
            .add(newNimNode(nnkEmpty))

    else:
        importCPragma = newIdentNode("importcpp")

        # If not static, insert 'this: `className`' param
        thisNode = newNimNode(nnkIdentDefs)
            .add(newIdentNode("this"))
            .add(newIdentNode(className))
            .add(newNimNode(nnkEmpty))

    params.insert(1, thisNode)
    pragmas.add importCPragma

    return statement


proc makeField(statement: PNimrodNode): PNimrodNode {.compiletime.} =
    ## Return only the identdefs
    return statement[0]


macro class*(className, header: expr, body: stmt): stmt {.immediate.} =
    ## Defines a C++ class
    result = newStmtList()

    # Declare a type named `className`, importing from C++
    var newType = parseExpr(
        "type " & $className &
        " {.header:\"" & $header & "\", importcpp.} = object")

    var recList = newNimNode(nnkRecList)
    newType[0][2][2] = recList

    # Iterate through statements in class definition
    for statement in body.children:

        case statement.kind:
        of nnkProcDef:
            # Add procs with header pragma
            var headerPragma = newNimNode(nnkExprColonExpr)
                .add(newIdentNode("header"))
                .add(newStrLitNode($header))

            var member = makeProcedure($className, statement)
            member.pragma.add headerPragma
            result.add member

        of nnkVarSection:
            # Add any fields declared in the class to the type
            var member = makeField(statement)
            recList.add member

        else: discard

    # Insert type into resulting statement list
    result.insert 0, newType


when isMainModule:

    {.link: "test.o".}

    when false:
        # Traditional wrapper
        const test_h = "../test.hpp"
        type test {.header: test_h, importcpp.} = object
            fieldName: cint
            notherName: cint

        proc output(this: typedesc[test]): void {.header: test_h, importc: "test::output".}
        proc multiply(this: test, value, by: cint): cint {.header: test_h, importcpp.}
        proc max[T](this: test, a, b: T): T {.header: test_h, importcpp.}

        # Test interface
        test.output()

        var item: test
        echo item.multiply(4, 6)
        echo item.fieldName
        echo item.max(2, 10)
        echo item.notherName

    else:
        # Import "test" class from C++:
        class test, "../test.hpp":
            proc multiply[T](value, by: T): int
            proc output: void {.isstatic.}
            proc max[T](a, b: T): T
            var fieldName, notherName: int

        # Test interface
        test.output()

        var item: test
        echo item.multiply(5, 9)
        echo item.fieldName
        echo item.max(2, 10)
        echo item.notherName