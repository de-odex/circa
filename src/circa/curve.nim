import units, utils

import math, sequtils, strformat


#[
  refer to https://osu.ppy.sh/help/wiki/osu!_File_Formats/Osu_(file_format) to understand part of this
]#

type
  CurvePortion* = ref object of RootObj
    points*: seq[Position]

  Bezier* = ref object of CurvePortion
  Linear* = ref object of CurvePortion
  Catmull* = ref object of CurvePortion
  Perfect* = ref object of CurvePortion
    center*: Position
    angle*: float  # ORIGINAL angle in radians, not modified by any reqLength

  Curve* = object
    curves*: seq[CurvePortion]
    reqLength*: float

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
