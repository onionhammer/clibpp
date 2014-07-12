## Easy way to 'Mock' C++ interface
import macros, parseutils, strutils

when not defined(CPP):
    {.error: "Must be compiled with cpp switch".}

# Types
type TMacroOptions = tuple
    header, importc: PNimrodNode
    className: PNimrodNode
    ns: string


# Procedures
proc removePragma(statement: PNimrodNode, pname: string): bool {.compiletime.} =
    ## Removes the input pragma and returns whether pragma was removed
    var pragmas = statement.pragma()
    let pname = !pname
    for index in 0 .. < pragmas.len:
        if pragmas[index].kind == nnkIdent and pragmas[index].ident == pname:
            pragmas.del(index)
            return true


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


proc parse_opts(className: PNimrodNode; opts: seq[PNimrodNode]): TMacroOptions {.compileTime.} =
    if opts.len == 1 and opts[0].kind == nnkStrLit:
        # user passed a header
        result.header = opts[0]

    else:
        for opt in opts.items:
            case opt.kind
            of nnkExprEqExpr, nnkExprColonExpr:
                case ($ opt[0].ident).tolower
                of "header":
                    result.header = opt[1]
                of "importc":
                    result.importc = opt[1]
                of "namespace", "ns":
                    result.ns = $opt[1] & "::"

            else:
                echo "Warning, Unhandled argument: ", repr(opt)

    if not isNil(result.importc) or isNil(result.ns):
        result.ns = ""
    if not isNil(result.ns):
        result.importc = newStrLitNode(result.ns & $className)

    result.className = className


template use*(ns: string): stmt {.immediate.} =
    {. emit: "using namespace $1;".format(ns) .}


macro class*(className, opts: expr, body: stmt): stmt {.immediate.} =
    ## Defines a C++ class
    result = newStmtList()

    var oseq: seq[PNimrodNode] = @[]
    if len(callsite()) > 3:
      # slots 2 .. -2 are arguments
      for i in 2 .. len(callsite())-2:
        oseq.add callsite()[i]
    let opts = parse_opts(className, oseq)

    # Declare a type named `className`, importing from C++
    var newType = parseExpr(
        "type $1* {.header:$2, importc$3.} = object".format(
            $ opts.className, repr(opts.header),
            (if opts.importc.isNil: "" else: ":"& repr(opts.importc))))


    var recList = newNimNode(nnkRecList)
    newType[0][2][2] = recList

    # Iterate through statements in class definition
    let body        = callsite()[< callsite().len]
    let classname_s = $ opts.className

    for statement in body.children:
        case statement.kind:
        of nnkProcDef:
            # Add procs with header pragma
            var headerPragma = newNimNode(nnkExprColonExpr).add(
                ident("header"),
                opts.header.copyNimNode)
            var member = makeProcedure(classname_s, opts.ns, statement)
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
    {.compile: "test.cpp".}

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