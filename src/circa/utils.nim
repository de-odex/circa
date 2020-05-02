import fenv, strutils, macros, tables

proc `~=`*[T:SomeFloat](x, y: T, ep=0.00001): bool =
  # taken from https://floating-point-gui.de/errors/comparison/
  let
    ax = abs(x)
    ay = abs(y)
    diff = abs(x - y)
    cmb = ax + ay
  if x == y:
    return true
  elif x == 0 or y == 0 or (cmb < T.minimumPositiveValue):
    return diff < (ep * T.minimumPositiveValue)

  result = diff / min(cmb, T.maximumPositiveValue) < ep

macro `<==`*(lhs, rhs: typed): untyped =
  # TODO: stop using this for god's sake, maybe make a more explicitly named macro for this
  let
    toSet = lhs
    origString = rhs
    typ = getTypeInst(lhs)
  var typStr: string = $typ
  typStr.removeSuffix(Digits)
  let
    excStr = (
      toSet.repr & " should be of type " & typ.repr &
      ", got " & origString.repr
    ).newStrLitNode
  var convertedNode = newDotExpr(origString, ("parse" & (typStr.capitalizeAscii)).ident)
  if $typ != typStr:
    convertedNode = newDotExpr(convertedNode, ($typ).ident)
  # echo convertedNode.repr
  result = quote do:
    try:
      `toSet` = `convertedNode`
    except ValueError:
      raise newException(ValueError, `excStr`)

iterator fcount*[T: SomeFloat](start, stop: T, step: T = 1): T =
  var start = start
  while start < stop:
    yield start
    start += stop

iterator fcount*[T: SomeFloat](start: T): T =
  let
    stop: T = 0
    step: T = 1
  while start < stop:
    yield start
    start += stop
