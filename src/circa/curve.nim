import units, utils

import math, sequtils, strformat

import itertools

# refer to https://osu.ppy.sh/help/wiki/osu!_File_Formats/Osu_(file_format) to understand part of this
# especially where "slider"s are tackled

type
  Curve* = ref object of RootObj
    # A single curve
    points*: seq[Position]

  Bezier* = ref object of Curve
    # Beziers can have 2 to inf points.
    # 2 points are treated as linear
    # (TODO: automatically convert 2 point bezier curves into linear)
  Linear* = ref object of Curve
    # Linears can only have 2 points (in file)
    # Perhaps when the to-do above is completed, this will not be assumed
  Catmull* = ref object of Curve
    # Catmulls aren't found often anymore, so I'm not able to find much data about them
    # They are documented as Centripetal in the wiki, though
  Perfect* = ref object of Curve
    # Perfects can only have 3 points
    # They are basically circumscribed circles from triangles;
    #   the start is the first vertex, end is last vertex
    center*: Position
    angle*: float # ORIGINAL angle in radians, not modified by any reqLength

  LimCurveSeq* = object
    # Limited Curve Sequence. A seq[Curve] with a limited length
    curves*: seq[Curve] # Can hold any type of curve, as to
                        # accomodate the future to-do about creating Linears
                        # instead of Beziers when the Bezier is 2 points
                        # long.
    reqLength*: float   # required length

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# for catmull...
iterator splitToSections(inp: seq[Position]): seq[Position] =
  # sliding window of 2 positions representing the middle 2 positions returned
  # first and last positions are either right before/after the middle 2 positions
  # or generated according to the below algorithm
  # first pos: either duplicated second pos or pos before second pos
  # fourth pos: either pos after third pos or an interpolation (p2 + p2 - p1)
  # see nim-glm for operators
  for n, pseq in toSeq(inp.windowed(2)):
    let
      p1 = inp[max(0, n - 1)]
      p4 = if inp.len - 1 < n + 2: pseq[1] + pseq[1] - pseq[0] else: inp[n + 2]
    yield @[p1, pseq[0], pseq[1], p4]

# for bezier...
iterator splitAtDupes(inp: seq[Position]): seq[Position] =
  # just yields another list when a duplicate is found; cuts between the duplicate
  # how difficult is that to understand?
  var oldIdx = 0
  for n, pseq in toSeq(inp.windowed(2)):
    if pseq[0] == pseq[1]:
      yield inp[oldIdx ..< n + 1]
      oldIdx = n + 1

  var tail = inp[oldIdx..inp.high]
  if tail.len > 0:
    yield tail

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc getCenter(a, b, c: Position): Position =
  let squareVec: Position = newPos(2)

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

  newPos(
    (xDist * cos(radians) - yDist * sin(radians)) + cX,
    (xDist * sin(radians) + yDist * cos(radians)) + cY,
  )

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

const
  tau = 1 # osu's catmull curves are centripetal
  catmullMat: Mat4d = mat4(
    vec4d(0, -tau, 2*tau, -tau),
    vec4d(2, 0, tau-6, 4-tau),
    vec4d(0, tau, -2*(tau-3), tau-4),
    vec4d(0, 0, -tau, tau),
  )

method at(curve: Curve, t: float): Position {.base.} =
  discard

method at(curve: Curve, ts: openarray[float]): seq[Position] {.base.} =
  for t in ts:
    result.add(curve.at(t))

method at(curve: Bezier, t: float): Position =
  # not verified to be correct
  let
    p = curve.points
    n = p.high # order of curve
               # formula found at https://en.wikipedia.org/wiki/B%C3%A9zier_curve#Explicit_definition
  for i in 0..n:
    result += binom(n, i).float * (1 - t).pow((n - i).float64) * t.pow(i.float64) * p[i]

method at(curve: Linear, t: float): Position =
  # verified/accurate
  (1 - t) * curve.points[0] + t * curve.points[1]

method at(curve: Catmull, t: float): Position =
  # not verified to be correct
  # formula found at https://andrewhungblog.wordpress.com/2017/03/03/catmull-rom-splines-in-plain-english/
  let
    p = curve.points
    tVec = vec4d(1, t.pow(1), t.pow(2), t.pow(3))
    pXVec = vec4d(p[0].x, p[1].x, p[2].x, p[3].x)
    pYVec = vec4d(p[0].y, p[1].y, p[2].y, p[3].y)
    v = tVec / 2 * catmullMat
  result = newPos(v.dot(pXVec), v.dot(pYVec))

method at(curve: Perfect, t: float): Position =
  # verified/accurate
  # broken for t > 1; should continue linearly at tangent slope of endpoint
  rotate(curve.points[0], curve.center, curve.angle * t)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

method tangent(curve: Curve, t: float): Vec[2, float] {.base.} =
  discard

method tangent(curve: Curve, ts: openarray[float]): seq[Vec[2, float]] {.base.} =
  for t in ts:
    result.add(curve.tangent(t))

method tangent(curve: Bezier, t: float): Vec[2, float] =
  let
    p = curve.points
    n = p.high # order of curve
               # formula found at https://pages.mtu.edu/~shene/COURSES/cs3621/NOTES/spline/Bezier/bezier-der.html
  for i in 0..<n:
    result += binom((n-1), i).float * (1 - t).pow(((n-1) - i).float64) * t.pow(i.float64) * (n.float * (p[i+1] - p[i]))
  result.normalize

method tangent(curve: Linear, t: float): Vec[2, float] =
  (curve.points[1] - curve.points[0]).normalize

method tangent(curve: Catmull, t: float): Vec[2, float] =
  discard
  # not verified to be correct
  # formula found at https://andrewhungblog.wordpress.com/2017/03/03/catmull-rom-splines-in-plain-english/
  # let
  #   p = curve.points
  #   tVec = vec4d(1, t.pow(1), t.pow(2), t.pow(3))
  #   pXVec = vec4d(p[0].x, p[1].x, p[2].x, p[3].x)
  #   pYVec = vec4d(p[0].y, p[1].y, p[2].y, p[3].y)
  #   v = tVec / 2 * catmullMat
  # result = newPos(v.dot(pXVec), v.dot(pYVec))

method tangent(curve: Perfect, t: float): Vec[2, float] =
  # verified/accurate
  # broken for t > 1; should continue linearly at tangent slope of endpoint
  let point = rotate(curve.points[0], curve.center, curve.angle * t)
  let vec = point - curve.center

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc linLength(points: openarray[Position]): float =
  for ps in points.windowed(2):
    result += (ps[1] - ps[0]).length # dunno why but distance() doesn't like me

const DETAIL = 50 ## how many times at will be called for length calculation

method length*(curve: Curve): float {.base.} =
  ## Approximate length of the curve
  var points: array[DETAIL+1, Position]
  for i in 0..DETAIL:
    points[i] = curve.at(i/DETAIL)
  points.linLength

method length*(curve: Linear): float =
  (curve.points[1] - curve.points[0]).length

method length*(curve: Perfect): float =
  # simply radius multiplied by angle in radians
  abs(curve.angle * (curve.points[0] - curve.center).length)

proc totalLength*(curves: seq[Curve]): float =
  for c in curves:
    result += c.length

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc newBezier*(points: seq[Position]): seq[Curve] =
  for ps in points.splitAtDupes:
    # ps is varying in length
    result.add(Bezier(points: ps))

proc newLinear*(points: seq[Position]): seq[Curve] =
  for ps in points.windowed(2):
    # ps is always 2 elements long
    result.add(Linear(points: ps))

proc newCatmull*(points: seq[Position]): seq[Curve] =
  for ps in points.splitToSections:
    # ps is always 4 elements long
    result.add(Catmull(points: ps))

proc newPerfect*(points: seq[Position], center: Position): seq[Curve] =
  if points.len != 3:
    raise newException(ValueError, "only three points may be specified for perfect curves")

  var coordinates: seq[Position] = @[]
  for p in points:
    coordinates.add(p - center)

  # angles of 3 points to center
  let
    startAngle = arctan2(coordinates[0].y, coordinates[0].x, )
  var
    endAngle = arctan2(coordinates[2].y, coordinates[2].x, )

  # normalize so that result[0].angle is positive
  if endAngle < startAngle:
    endAngle += 2'f64 * PI

  # angle of arc sector that describes slider
  var
    angle = endAngle - startAngle

  # switch angle direction if necessary
  let
    aToC = coordinates[2] - coordinates[0]
    orthoAToC = newPos(aToC[1], -aToC[0])

  if orthoAToC.dot(coordinates[1] - coordinates[0]) < 0:
    angle = -(2 * PI - angle)

  result.add(Perfect(points: points, center: center, angle: angle))

proc newPerfect*(points: seq[Position]): seq[Curve] =
  if points.len != 3:
    raise newException(
      ValueError, "only three points may be specified for perfect curves"
    )
  newPerfect(points, getCenter(points))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# python bisect_left shim
proc bisectLeft[T](a: seq[T], x: T, lo: int = 0, hi: int = -1): int =
  # Return the index where to insert item x in list a, assuming a is sorted.
  # The return value i is such that all e in a[:i] have e < x, and all e in
  # a[i:] have e >= x.  So if x already appears in the list, a.insert(x) will
  # insert just before the leftmost x already there.
  # Optional args lo (default 0) and hi (default len(a)) bound the
  # slice of a to be searched.
  var
    lo = lo
    hi = hi
  if lo < 0:
    raise newException(ValueError, "lo must be non-negative")
  if hi == -1:
    hi = a.len
  while lo < hi:
    let mid = (lo+hi) div 2
    if a[mid] < x:
      lo = mid+1
    else:
      hi = mid
  return lo

proc length*(curveSeq: LimCurveSeq): float =
  for curve in curveSeq.curves:
    result += curve.length

proc ts(curveSeq: LimCurveSeq): seq[float] =
  let
    lengths = curveSeq.curves.mapIt(it.length)
    length = sum(lengths)
  for i, j in toSeq(accumulate(lengths[0..^2], proc(a, b: float): float = a + b)):
    # self.curves[i].reqLength = lengths[i]
    result.add(j / length)
  # self.curves[^1].reqLength = max(
  #   0,
  #   lengths[-1] - (length - self.req_length),
  # )
  result.add(1)
  return result

# Approximation curve creation
proc at*(curveSeq: LimCurveSeq, t: float): Position =
  let t = t * curveSeq.reqLength / curveSeq.length
  if len(curveSeq.curves) == 1:
    # Special case where we only have one curve
    return curveSeq.curves[0].at(t)
  let
    ts = curveSeq.ts # ts of endpoints of curves
    bi = bisectLeft(ts, t)
  var preT: float # t of start of curve for calculation
  if bi == 0:
    preT = 0
  else:
    preT = ts[bi - 1]
  let postT = ts[bi] # t of end of curve for calculation
  return curveSeq.curves[bi].at((t - preT) / (postT - preT))

proc at*(curveSeq: LimCurveSeq, ts: openarray[float]): seq[Position] =
  for t in ts:
    result.add(curveSeq.at(t))

proc initLimCurveSeq*(curves: seq[Curve], reqLength: float): LimCurveSeq =
  # TODO: handle longer-than-curve reqLengths; see initBezier
  LimCurveSeq(curves: curves, reqLength: reqLength)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc fromKindAndPoints*(kind: string, points: seq[Position],
    reqLength: float): LimCurveSeq =
  case kind:
    of "B":
      result = initLimCurveSeq(newBezier(points), reqLength)
    of "L":
      result = initLimCurveSeq(newLinear(points), reqLength)
    of "C":
      result = initLimCurveSeq(newCatmull(points), reqLength)
    of "P":
      var center: Position
      if points.len != 3:
        return initLimCurveSeq(newBezier(points), reqLength)
      try:
        center = getCenter(points)
        result = initLimCurveSeq(newPerfect(points, center), reqLength)
      except ValueError:
        result = initLimCurveSeq(newBezier(points), reqLength)
    else:
      raise newException(ValueError, &"unknown curve kind: {kind}")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

when isMainModule:
  import gnuplot

  let bezpos: seq[Position] = @[
    newPos(216, 231),
    newPos(216, 135),
    newPos(280, 135),
    newPos(344, 135),
    newPos(344, 199),
    newPos(344, 263),
    newPos(248, 327),
    newPos(248, 327),
    newPos(120, 327),
    newPos(120, 327),
    newPos(56, 39),
    newPos(408, 39),
    newPos(408, 39),
    newPos(472, 150),
    newPos(408, 342)
  ]

  # for i in bezpos.splitAtDupes:
  #   echo i

  # for i in catpos.splitToSections:
  #   echo i

  # echo newPerfect(@[newPos(0, 0), newPos(1, 1), newPos(2, 0)]).repr

  let
    sq: seq[LimCurveSeq] = @[
      initLimCurveSeq(newBezier(bezpos), 1280),
      initLimCurveSeq(newLinear(@[newPos(0, 0), newPos(100, 100), newPos(200, 0)]), 200*sqrt(2'd)),
      initLimCurveSeq(newCatmull(@[newPos(-1, -1), newPos(-1, 1), newPos(1, 1),
          newPos(1, -1)]), 20),
      #256,192,9571,6,0,P|185:206|139:177,1,104.999996795654
      initLimCurveSeq(newPerfect(@[newPos(256, 192), newPos(185, 206), newPos(139,
          177)]), 105)
    ]

  # for i in sq:
  #   echo i.at(0.5)

  # # echo sq[0].at(0.5)
  # # echo sq[3].at(0.3333333333333)

  # assert `~=`(sq[0].at(0.5), newPos(471, 217.5), ep = 0.001)
  # assert `~=`(sq[3].at(0.3333333333333), newPos(224, 207), ep = 0.002)
  # echo sq[3].curves[0].at(@[0.0, 0.5, 1.0])
  # echo sq[3].at(1.5)


  const detail2 = 500
  var pos = sq[0].at(toSeq(0..detail2).mapIt(it / detail2))

  cmd "set xr [0:512]"
  cmd "set yr [384:0]"
  setStyle Dots
  plot pos.mapIt(it.x), pos.mapIt(it.y)

  let
    t = 1f
    curve = sq[0].curves[3]
    pointOfCurve = curve.at(t)
    tangentOfCurve = curve.tangent(t) * 20
  setStyle Points
  plot [pointOfCurve.x], [pointOfCurve.y]
  setStyle Lines
  # plot [pointOfCurve.x - tangentOfCurve.x, pointOfCurve.x + tangentOfCurve.x], [pointOfCurve.y - tangentOfCurve.y, pointOfCurve.y + tangentOfCurve.y]
  plot [pointOfCurve.x, pointOfCurve.x + tangentOfCurve.x], [pointOfCurve.y, pointOfCurve.y + tangentOfCurve.y]

  discard readChar stdin

  # echo cat.curves.trueLength
  # echo cat.curves[0].approxAt([0'f64, 0.5, 1'f64])
  # echo cat.at(0)
  # echo cat.at(0.5)
  # echo cat.at(1)
  # echo initCurve[Catmull](newCatmull(@[newPos(-1, -1), newPos(-1, 1)]), 20).at(1)

  # var cr: LimCurveSeq[Bezier] = initCurve(@[a, b, c], 0)

  # echo a.at(0.5)
