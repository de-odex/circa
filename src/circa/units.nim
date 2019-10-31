import utils

import times
export times

import glm
export glm

# ~~~~~~~~~~~~~~~~
#     TEMPORAL
# ~~~~~~~~~~~~~~~~
# TODO: refactor this, perhaps?

const
  secondsInMin = 60
  secondsInHour = 60*60
  secondsInDay = 60*60*24

const unitWeights: array[FixedTimeUnit, int64] = [
  1'i64,
  1000,
  1_000_000,
  1e9.int64,
  secondsInMin * 1e9.int64,
  secondsInHour * 1e9.int64,
  secondsInDay * 1e9.int64,
  7 * secondsInDay * 1e9.int64,
]

# TODO: fix? i dont think a fix is possible; floats are floats and floats aren't always precise
proc convert[T: SomeFloat](unitFrom, unitTo: FixedTimeUnit, quantity: T): T
    {.inline.} =
  ## Convert a quantity of some duration unit to another duration unit.
  runnableExamples:
    import utils
    doAssert convert(Days, Hours, 2.5) == 60
    doAssert convert(Days, Weeks, 13) ~= 1.85714285714
    doAssert convert(Seconds, Milliseconds, -1) == -1000
    doAssert convert(Milliseconds, Seconds, 205'f64) == 0.205
  if unitFrom == unitTo:
    quantity
  elif unitFrom < unitTo:
    (quantity / (unitWeights[unitTo] div unitWeights[unitFrom]).T).T
  else:
    ((unitWeights[unitFrom] div unitWeights[unitTo]).T * quantity).T

proc initDuration*(nanoseconds, microseconds, milliseconds,
                   seconds, minutes, hours, days, weeks: float64 = 0): Duration =
  let
    seconds = convert(Weeks, Seconds, weeks) +
      convert(Days, Seconds, days) +
      convert(Minutes, Seconds, minutes) +
      convert(Hours, Seconds, hours) +
      convert(Seconds, Seconds, seconds)
    fSeconds = (seconds - seconds.int64.float64)
    iSeconds = seconds.int64
    nanoseconds = convert(Seconds, Nanoseconds, fSeconds) +
      convert(Milliseconds, Nanoseconds, milliseconds) +
      convert(Microseconds, Nanoseconds, microseconds) +
      convert(Nanoseconds, Nanoseconds, nanoseconds)
  initDuration(seconds=iSeconds, nanoseconds=nanoseconds.int64)  # sadly we cannot retain under nanosecond precision

proc `*`*(x: Duration, y: SomeFloat): Duration =
  initDuration(milliseconds=x.inFloatMilliseconds * y)

proc `*`*(x: SomeFloat, y: Duration): Duration =
  y * x

template inFloat(unitTo: FixedTimeUnit) =
  proc `inFloat unitTo`*(dur: Duration): float64 =
    convert(Nanoseconds, `unitTo`, dur.inNanoseconds.float64)

inFloat(Weeks)
inFloat(Days)
inFloat(Minutes)
inFloat(Hours)
inFloat(Seconds)
inFloat(Milliseconds)
inFloat(Microseconds)

# ~~~~~~~~~~~~~~~~~~
#     POSITIONAL
# ~~~~~~~~~~~~~~~~~~

const
  MAX_POS_X* = 512
  MAX_POS_Y* = 384

type
  Position* = Vec2d

  Point* = ref object
    position: Position
    offset: Duration

proc newPos*(x, y: float64): Vec2[float64] {.inject, inline.} = Vec2[float64](arr: [x,y])
proc newPos*(x: float64)   : Vec2[float64] {.inject, inline.} = Vec2[float64](arr: [x,x])
proc newPos*(a: array[0..1, float64]): Vec2[float64] {.inject, inline.} = Vec2[float64](arr: [a[0], a[1]])

proc `~=`*(x, y: Position, ep=0.00001): bool =
  for index, val in x.arr:
    if not `~=`(x.arr[index], y.arr[index], ep):
      result = false
    else:
      result = true
