import units, utils

import math, sequtils, strformat

import itertools

#[
  refer to https://osu.ppy.sh/help/wiki/osu!_File_Formats/Osu_(file_format) to understand part of this
]#

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
    reqLength*: float # required length

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
  var old_idx = 0
  for n, pseq in toSeq(inp.windowed(2)):
    if pseq[0] == pseq[1]:
      yield inp[old_idx ..< n + 1]
      old_idx = n + 1

  var tail = inp[old_idx..inp.high]
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

proc binCoeff(n, k: int): float =
  n.fac / (k.fac * (n - k).fac)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

const
  tau = 1 # osu's sliders are centripetal
  catmullMat: Mat4d = mat4(
    vec4d(0, -tau, 2*tau, -tau),
    vec4d(2, 0, tau-6, 4-tau),
    vec4d(0, tau, -2*(tau-3), tau-4),
    vec4d(0, 0, -tau, tau),
  )

method at(curve: Curve, t: float): Position {.base.} =
  # this method should be able to handle a t of over 1
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
    result += binCoeff(n, i) * (1 - t).pow((n - i).float64) * t.pow(i.float64) * p[i]

method at(curve: Linear, t: float): Position =
  # verified/accurate
  let p = curve.points
  p[0] + t * (p[1] - p[0])

method at(curve: Catmull, t: float): Position =
  # not verified to be correct
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
  let p = curve.points
  rotate(p[0], curve.center, curve.angle * t)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc linLength(points: openarray[Position]): float =
  for ps in points.windowed(2):
    result += (ps[1] - ps[0]).length # dunno why but distance() doesn't like me

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

const DETAIL = 50 ## how many times at will be called for trueLength calculation

method trueLength*(curve: Curve): float {.base.} =
  # "true" here means the actual length of the curve, not the "reqLength"
  # this does not mean that it is not approximate, approximate is a given
  # considering computers.
  var points: array[DETAIL, Position]
  for i in 0..DETAIL:
    points[i] = curve.at(i/DETAIL)
  points.linLength

method trueLength*(curve: Linear): float =
  (curve.points[1] - curve.points[0]).length

method trueLength*(curve: Perfect): float =
  # simply radius multiplied by angle in radians
  abs(curve.angle * (curve.points[0] - curve.center).length)

proc totalLength*(curves: seq[Curve]): float =
  for c in curves:
    result += c.trueLength

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

  # normalize so that result._angle is positive
  if endAngle < startAngle:
    endAngle += 2'f64 * PI

  var
    # angle of arc sector that describes slider
    angle = endAngle - startAngle

  let
    # switch angle direction if necessary
    aToC = coordinates[2] - coordinates[0]
    orthoAToC = newPos(aToC[1], -aToC[0])

  if orthoAToC.dot(coordinates[1] - coordinates[0]) < 0:
    angle = -(2 * PI - angle)

  result.add(Perfect(points: points, center: center, angle: angle))

proc newPerfect*(points: seq[Position]): seq[Curve] =
  if points.len != 3:
    raise newException(ValueError, "only three points may be specified for perfect curves")
  newPerfect(points, getCenter(points))
