## Easy way to 'Mock' C++ interface
import macros, parseutils, strutils

when not defined(CPP):
    {.error: "Must be compiled with cpp switch".}

# Types
type TMacroOptions = tuple
    header, importc: PNimrodNode
    className: PNimrodNode
    ns: string
    inheritable: bool


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
            var handled = true
            case opt.kind
            of nnkExprEqExpr, nnkExprColonExpr:
                case ($ opt[0].ident).toLower
                of "header":
                    result.header = opt[1]
                of "importc":
                    result.importc = opt[1]
                of "namespace", "ns":
                    result.ns = $opt[1] & "::"
                else:
                    handled = false
            of nnkIdent:
                case ($ opt.ident).toLower
                of "inheritable":
                    result.inheritable = true
                else:
                    handled = false
            else:
                handled = false

            if not handled:
                echo "Warning, unhandled argument: ", repr(opt)

    if not isNil(result.importc) or isNil(result.ns):
        result.ns = ""
    if not isNil(result.ns):
        result.importc = newStrLitNode(result.ns & $className)

    result.className = className

proc buildStaticAccessor (name,ty, className:NimNode; ns:string): NimNode {.compileTime.} =
    result = newProc(
        name = name,
        procType = nnkProcDef,
        body = newEmptyNode(),
        params = [ty, newIdentDefs(ident"ty", parseExpr("typedesc["& $className &"]"))]
    )
    result.pragma = newNimNode(nnkPragma).add(
        ident"noDecl",
        newNimNode(nnkExprColonExpr).add(
            ident"importcpp",
            newLit(ns & $className & "::" & $name.baseName & "@")))

template use*(ns: string): stmt {.immediate.} =
    {. emit: "using namespace $1;".format(ns) .}


macro namespace*(namespaceName: expr, body: stmt): stmt {.immediate.} =
    result = newStmtList()

    var newNamespace = newNimNode(nnkExprColonExpr).
        add(ident("ns"), namespaceName)

    # Inject new namespace into each class declaration
    for i in body.children:
        if $i[0] == "class":
            i.insert 2, newNamespace

    result.add body

macro class*(className, opts: expr, body: stmt): stmt {.immediate.} =
    ## Defines a C++ class
    result = newStmtList()

    var parent: NimNode
    var className = className
    if className.kind == nnkInfix and className[0].ident == !"of":
        parent = className[2]
        className = className[1]

    var oseq: seq[PNimrodNode] = @[]
    if len(callsite()) > 3:
      # slots 2 .. -2 are arguments
      for i in 2 .. len(callsite())-2:
        oseq.add callsite()[i]
    let opts = parse_opts(className, oseq)

    # Declare a type named `className`, importing from C++
    var newType = parseExpr(
        "type $1* {.header:$2, importcpp$3.} = object".format(
            $ opts.className, repr(opts.header),
            (if opts.importc.isNil: "" else: ":"& repr(opts.importc))))

    var recList = newNimNode(nnkRecList)
    newType[0][2][2] = recList
    if not parent.isNil:
        # Type has a parent
        newType[0][2][1] = newNimNode(nnkOfInherit).add(parent)
    elif opts.inheritable:
        # Add inheritable pragma
        newType[0][0][1].add ident"inheritable"

    # Iterate through statements in class definition
    var body        = callsite()[< callsite().len]
    let classname_s = $ opts.className
    # Fix for nnkDo showing up here
    if body.kind == nnkDo: body = body.body

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
            # Add any var declared in the class to the type
            # create accessors for any static variables
            # proc varname* (ty:typedesc[classtype]): ty{.importcpp:"Class::StaticVar@"}
            var 
                statics: seq[tuple[name,ty: NimNode]] = @[]
                fields : seq[tuple[name,ty: NimNode]] = @[]

            for id_def in children(statement):
                let ty = id_def[id_def.len - 2]

                for i in 0 .. id_def.len - 3:
                    # iterate over the var names, check each for isStatic pragma
                    let this_ident = id_def[i]
                    var isStatic = false
                    if this_ident.kind == nnkPragmaExpr:
                        for prgma in children(this_ident[1]):
                            if prgma.kind == nnkIdent and ($prgma).eqIdent("isStatic"):
                                statics.add((this_ident[0], ty))
                                isStatic = true
                                break
                    if not isStatic: 
                        fields.add((this_ident, ty))

                # recList.add id_def

            for n,ty in items(fields):
                recList.add newIdentDefs(n, ty)
            for n,ty in items(statics):
                result.add buildStaticAccessor(n, ty, opts.className, opts.ns)

        else:
            result.add statement

    # Insert type into resulting statement list
    result.insert 0, newType

    when defined(Debug):
        echo result.repr


when isMainModule:
    {.compile: "test.cpp".}
    const test_h = "../test.hpp"

    when false:
        # Traditional wrapper
        type test {.header: test_h, importcpp.} = object
            fieldName: cint
            notherName: cint

        proc output(this: typedesc[test]) {.header: test_h, importc: "test::output".}
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
        namespace pp:
            class(test, inheritable, header: test_h):
                proc multiply[T](value, by: T): int
                proc output {.isstatic.}
                proc max[T](a, b: T): T
                proc foo(): int
                var fieldName, notherName{.isStatic.}: int
            class(test_sub of test, header: test_h):
                proc childf: int

        # Test interface
        test.output()

        var item: test
        echo item.multiply(5, 9)
        echo item.fieldName
        echo item.max(2, 10)
        #echo item.notherName
        echo test.notherName

        var item2: test_sub
        echo item2.childf
        assert item2 of test