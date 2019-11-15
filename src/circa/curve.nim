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
