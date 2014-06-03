## Easy way to 'Mock' C++ interface
import macros, parseutils, strutils


proc removePragma(statement: PNimrodNode, pname: string): bool {.compiletime.} =
    ## Removes the input pragma and returns whether pragma was removed
    var pragmas = statement.pragma()
    let pname = !pname
    for index in 0 .. < pragmas.len:
        if pragmas[index].kind == nnkIdent and pragmas[index].ident == pname:
            pragmas.del(index)
            return true

    return false


proc makeProcedure(className, ns: string, statement: PNimrodNode): PNimrodNode {.compiletime.} =
    ## Generate an imported procedure definition for the input class name
    var procName = $(statement[0].basename)
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
            .add(newStrLitNode(ns & className & "::" & procName))

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


template use*(ns: string): stmt {.immediate.} =
    {. emit: "using namespace $1;".format(ns) .}


macro class*(className, opts: expr, body: stmt): stmt {.immediate.} =
    ## Defines a C++ class
    result = newStmtList()

    var header, importc: PNimrodNode
    var ns: string

    if opts.kind == nnkStrLit:
        # user passed a header
        header = opts

    else:
        # slots 2 .. -2 are arguments
        for opt_idx in 2 .. len(callsite())-2:
            let opt = callsite()[opt_idx]

            case opt.kind
            of nnkExprEqExpr, nnkExprColonExpr:
                case ($ opt[0].ident).tolower
                of "header":
                    header = opt[1]
                of "importc":
                    importc = opt[1]
                of "namespace", "ns":
                    ns = $opt[1] & "::"

            else:
                echo "Warning, Unhandled argument: ", repr(opt)

    if not isNil(importc) or isNil(ns):
        ns = ""
    if not isNil(ns):
        importc = parseExpr("\"" & ns & $className & "\"")

    # Declare a type named `className`, importing from C++
    var newType = parseExpr(
        "type $1* {.header:$2, importc$3.} = object".format(
            $className, repr(header),
            (if importc.isNil: "" else: ":"& repr(importc))))


    var recList = newNimNode(nnkRecList)
    newType[0][2][2] = recList

    # Iterate through statements in class definition
    let body = callsite()[< callsite().len]

    for statement in body.children:
        case statement.kind:
        of nnkProcDef:
            # Add procs with header pragma
            var headerPragma = newNimNode(nnkExprColonExpr).add(
                ident("header"),
                header.copyNimNode)
            var member = makeProcedure($className, ns, statement)
            member.pragma.add headerPragma
            result.add member

        of nnkVarSection:
            # Add any fields declared in the class to the type
            for id_def in children(statement):
              recList.add id_def

        else:
            result.add statement

    # Insert type into resulting statement list
    result.insert 0, newType

    when defined(Debug):
        echo result.repr


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
        class(test, ns: pp, header: "../test.hpp"):
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
