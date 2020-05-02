import unittest

import math

import circa/[utils, units, curve]

# Help wanted for creating tests for curve.nim

test "curve at":
  let
    sq: seq[LimCurveSeq] = @[
      initLimCurveSeq(newBezier(@[newPos(512, 228), newPos(482, 216), newPos(482, 216), newPos(428, 224)]), 85),
      initLimCurveSeq(newLinear(@[newPos(0, 0), newPos(1, 1), newPos(2, 3)]), 2),
      initLimCurveSeq(newCatmull(@[newPos(-1, -1), newPos(-1, 1), newPos(1, 1), newPos(1, -1)]), 20),
      #256,192,9571,6,0,P|185:206|139:177,1,104.999996795654
      initLimCurveSeq(newPerfect(@[newPos(256, 192), newPos(185, 206), newPos(139, 177)]), 105)
    ]

  check:
    `~=`(sq[0].at(0.5), newPos(471, 217.5), ep = 0.001)
    `~=`(sq[3].at(0.3333333333333), newPos(224, 207), ep = 0.002)

    initLimCurveSeq(newLinear(@[newPos(0, 0), newPos(1, 1), newPos(2, 0)]), 2*sqrt(2'd)).at(0.5) ~= newPos(1, 1)

test "curve length":
  check:
    initLimCurveSeq(newLinear(@[newPos(0, 0), newPos(1, 1), newPos(2, 0)]),
        2*sqrt(2'd)).length ~= 2*sqrt(2'd)

