import math, sequtils, strutils, strformat, macros

import position, utils

#[
  refer to https://osu.ppy.sh/help/wiki/osu!_File_Formats/Osu_(file_format) to understand part of this
]#

type
  CurvePortion = ref object of RootObj
    points: seq[Position]

  Bezier = ref object of CurvePortion
  Linear = ref object of CurvePortion
  Catmull = ref object of CurvePortion
  Perfect = ref object of CurvePortion
    center: Position
    angle: float  # ORIGINAL angle in radians, not modified by any reqLength

  CurveTypes = Bezier | Linear | Catmull | Perfect

  CurveSeq[T: CurveTypes] = object
    curves: seq[T]
    reqLength: float

  Curve* = object
    bezier: CurveSeq[Bezier]
    linear: CurveSeq[Linear]
    catmull: CurveSeq[Catmull]
    perfect: CurveSeq[Perfect]

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# for catmull...
iterator splitToSections(inp: seq[Position]): seq[Position] =
  for n, pseq in inp.slidingWindowPairs:
    let p0 = inp[max(0, n - 1)]
    var p3: Position
    if inp.len - 1 < n + 2:
      p3 = pseq[1] + pseq[1] - pseq[0]
    else:
      p3 = inp[n + 2]
    yield @[p0, pseq[0], pseq[1], p3]

# for bezier...
iterator splitAtDupes(inp: seq[Position]): seq[Position] =
  var old_ix = 0
  for n, pseq in inp.slidingWindowPairs:
    if pseq[0] == pseq[1]:
      yield inp[old_ix ..< n + 1]
      old_ix = n + 1

  var tail = inp[old_ix..inp.high]
  if tail.len > 0:
    yield tail

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc getCenter(a, b, c: Position): Position =
  let squareVec: Position = pos(2)

  let
    aSquared = (b - c).pow(squareVec).arr.sum
    bSquared = (a - c).pow(squareVec).arr.sum
    cSquared = (a - b).pow(squareVec).arr.sum

  if any(@[aSquared, bSquared, cSquared], proc (x: float64): bool = return x ~= 0):
    raise newException(ValueError, &"given points are collinear: {a}, {b}, {c}")

  let
    s = aSquared * (bSquared + cSquared - aSquared)
    t = bSquared * (aSquared + cSquared - bSquared)
    u = cSquared * (aSquared + bSquared - cSquared)
    stuSum = s + t + u

  if stuSum ~= 0:
    raise newException(ValueError, &"given points are collinear: {a}, {b}, {c}")

  (s * a + t * b + u * c) / stuSum

proc getCenter(oa: openarray[Position]): Position = getCenter(oa[0], oa[1], oa[2])

proc rotate(position, center: Position, radians: float): Position =
  var (pX, pY) = (position.x, position.y)
  var (cX, cY) = (center.x, center.y)

  var xDist = pX - cX
  var yDist = pY - cY

  pos(
    (xDist * cos(radians) - yDist * sin(radians)) + cX,
    (xDist * sin(radians) + yDist * cos(radians)) + cY,
  )

proc binCoeff(n, k: int): float =
  n.fac / (k.fac * (n - k).fac)


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

template funcSeq(typ: typedesc, fun: untyped) =
  proc fun(self: typ, ts: openarray[float]): seq[Position] =
    for t in ts:
      result.add(self.fun(t))

proc approxAt(self: Bezier, t: float): Position =
  let
    p = self.points
    n = p.high
  for i in 0..n:
    result += binCoeff(n, i) * (1 - t).pow((n - i).float64) * t.pow(i.float64) * p[i]

proc approxAt(self: Linear, t: float): Position =
  let p = self.points
  p[0] + t * (p[1] - p[0])

const
  tau = 1
  catmullMat: Mat4d = mat4(
    vec4d(0, -tau,      2*tau,  -tau),
    vec4d(2,    0,      tau-6, 4-tau),
    vec4d(0,  tau, -2*(tau-3), tau-4),
    vec4d(0,    0,       -tau,   tau),
  )

proc approxAt(self: Catmull, t: float): Position =
  let
    p = self.points
    tVec = vec4d(1, t.pow(1), t.pow(2), t.pow(3))
    pXVec: Vec4d = vec4d(p[0].x, p[1].x, p[2].x, p[3].x)
    pYVec: Vec4d = vec4d(p[0].y, p[1].y, p[2].y, p[3].y)
    v = tVec / 2 * catmullMat
  result = pos(v.dot(pXVec), v.dot(pYVec))

proc approxAt(self: Perfect, t: float): Position =
  let p = self.points
  rotate(p[0], self.center, self.angle * t)

funcSeq(Bezier, approxAt)
funcSeq(Linear, approxAt)
funcSeq(Catmull, approxAt)
funcSeq(Perfect, approxAt)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# template expFuncSeq(typ: typedesc, fun, blck: untyped) =
#   proc fun*(self: typ, ts: openarray[float]): seq[Position] =
#     for t in ts:
#       result.add(self.fun(t))

# Approximation curve creation
proc at*(self: CurveSeq, t: float): Position =
  let
    curves = self.curves
    fullCurveLength = curves.trueLength
  var reqLength = self.reqLength

  if reqLength > fullCurveLength:
    reqLength = fullCurveLength
  reqLength = reqLength * t

  if curves.len == 1:
    let lenRatio = reqLength / fullCurveLength
    result = curves[0].approxAt(lenRatio)

  elif curves.len > 1:
    var
      n = curves.high
    while curves[0 .. n].trueLength > reqLength:
      n -= 1

    # curves[0 .. n] is now all curves which are filled by the parameter (no need to get the inbetween)
    # curves[n+1] is the curve we need to parametrize
    if n == curves.high:
      n -= 1

    let
      filledCurvesLength = curves[0 .. n].trueLength
      unfilledCurveLength = curves[n+1].trueLength

    var lenRatio: float
    if (reqLength - filledCurvesLength) ~= unfilledCurveLength:
      lenRatio = 1
    else:
      lenRatio = (reqLength - filledCurvesLength) / unfilledCurveLength

    result = curves[n+1].approxAt(lenRatio)

# funcSeq(Curve, at)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc linLength(points: openarray[Position]): float =
  for ps in points.slidingWindowItems:
    result += (ps[1] - ps[0]).length  # dunno why but distance() doesn't like me

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

const DETAIL = 50

proc trueLength*(self: Bezier): float =
  var points: array[DETAIL, Position]
  for i in 0..<DETAIL:
    points[i] = self.approxAt(i/DETAIL)
  points.linLength

proc trueLength*(self: Linear): float =
  (self.points[1] - self.points[0]).length  # distance() doesn't like me here either

proc trueLength*(self: Catmull): float =
  var points: array[DETAIL, Position]
  for i in 0..<DETAIL:
    points[i] = self.approxAt(i/DETAIL)
  points.linLength

proc trueLength*(self: Perfect): float =
  abs(self.angle * (self.points[0] - self.center).length)

proc trueLength*(curves: seq[CurveTypes]): float =
  for c in curves:
    result += c.trueLength

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc newBezier*(points: seq[Position]): seq[Bezier] =
  for ps in points.splitAtDupes:
    # ps is varying in length
    result.add(Bezier(points: ps))

proc newLinear*(points: seq[Position]): seq[Linear] =
  for ps in points.slidingWindowItems:
    # ps is always 2 elements long
    result.add(Linear(points: ps))

proc newCatmull*(points: seq[Position]): seq[Catmull] =
  for ps in points.splitToSections:
    # ps is always 4 elements long
    result.add(Catmull(points: ps))

proc newPerfect*(points: seq[Position], center: Position): seq[Perfect] =
  if points.len != 3:
    raise newException(ValueError, "e") # TODO: exception

  var coordinates: seq[Position] = @[]
  for p in points:
    coordinates.add(p - center)

  # angles of 3 points to center
  let
    startAngle = arctan2(coordinates[0].y, coordinates[0].x,)
  var
    endAngle = arctan2(coordinates[2].y, coordinates[2].x,)

  # normalize so that self._angle is positive
  if endAngle < startAngle:
    endAngle += 2'f64 * PI

  var
    # angle of arc sector that describes slider
    angle = endAngle - startAngle

  let
    # switch angle direction if necessary
    aToC = coordinates[2] - coordinates[0]
    orthoAToC = pos(aToC[1], -aToC[0])

  if orthoAToC.dot(coordinates[1] - coordinates[0]) < 0:
    angle = -(2 * PI - angle)

  result.add(Perfect(points: points, center: center, angle: angle))

proc newPerfect*(points: seq[Position]): seq[Perfect] =
  if points.len != 3:
    raise newException(ValueError, "e") # TODO: exception
  newPerfect(points, getCenter(points))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

macro curveFactory(curveType: typedesc): untyped =
  let curveName = curveType.repr.toLower.ident
  result = quote do:
    proc initCurve*(curves: seq[`curveType`], reqLength: float): Curve =
      Curve(`curveName`: CurveSeq[`curveType`](curves: curves, reqLength: reqLength))

curveFactory(Bezier)
curveFactory(Linear)
curveFactory(Catmull)
curveFactory(Perfect)

proc at*(self: Curve, t: float): Position =
  if self.bezier.curves.len > 0:
    result = self.bezier.at(t)
  elif self.linear.curves.len > 0:
    result = self.linear.at(t)
  elif self.catmull.curves.len > 0:
    result = self.catmull.at(t)
  elif self.perfect.curves.len > 0:
    result = self.perfect.at(t)

proc at*(self: Curve, ts: openarray[float]): seq[Position] =
  for t in ts:
    result.add(self.at(ts))

proc length*(self: Curve): float =
  var points: array[DETAIL, Position]
  for i in 0..<DETAIL:
    points[i] = self.at(i/DETAIL)
  points.linLength

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc `$`*(t: Bezier): string =
  &"Bezier<points={t.points}>"
proc `$`*(t: Linear): string =
  &"Linear<points={t.points}>"
proc `$`*(t: Catmull): string =
  &"Catmull<points={t.points}>"
proc `$`*(t: Perfect): string =
  &"Perfect<points={t.points}>"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc fromKindAndPoints*(kind: string, points: seq[Position], reqLength: float): Curve =
  case kind:
    of "B":
      result = initCurve(newBezier(points), reqLength)
    of "L":
      result = initCurve(newLinear(points), reqLength)
    of "C":
      result = initCurve(newCatmull(points), reqLength)
    of "P":
      var center: Position
      if points.len != 3:
        result = initCurve(newBezier(points), reqLength)
      try:
        center = getCenter(points)
        result = initCurve(newPerfect(points, center), reqLength)
      except ValueError:
        result = initCurve(newBezier(points), reqLength)
    else:
      raise newException(ValueError, &"unknown curve kind: {kind}")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

when isMainModule:
  let bezpos: seq[Position] = @[
    pos(512, 228),
    pos(482, 216),
    pos(482, 216),
    pos(428, 224)
  ]

  # for i in bezpos.splitAtDupes:
  #   echo i

  # for i in catpos.splitToSections:
  #   echo i

  # echo newPerfect(@[pos(0, 0), pos(1, 1), pos(2, 0)]).repr

  let
    sq: seq[Curve] = @[
      initCurve(newBezier(bezpos), 85),
      initCurve(newLinear(@[pos(0, 0), pos(1, 1), pos(2, 3)]), 2),
      initCurve(newCatmull(@[pos(-1, -1), pos(-1, 1), pos(1, 1), pos(1, -1)]), 20),
      #256,192,9571,6,0,P|185:206|139:177,1,104.999996795654
      initCurve(newPerfect(@[pos(256, 192), pos(185, 206), pos(139, 177)]), 105)
    ]

  for i in sq:
    echo i.at(0.5)

  assert `~=`(sq[0].at(0.5), pos(471, 218), ep=0.001)
  assert `~=`(sq[3].at(0.3333333333333), pos(224, 207), ep=0.002)

  # echo cat.curves.trueLength
  # echo cat.curves[0].approxAt([0'f64, 0.5, 1'f64])
  # echo cat.at(0)
  # echo cat.at(0.5)
  # echo cat.at(1)
  # echo initCurve[Catmull](newCatmull(@[pos(-1, -1), pos(-1, 1)]), 20).at(1)

  # var cr: Curve[Bezier] = initCurve(@[a, b, c], 0)

  # echo a.at(0.5)

