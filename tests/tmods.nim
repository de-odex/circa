# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest
import fenv

import circa/[mods, units, utils]

template comm(x, y: float): untyped  =
  check:
    x ~= y
    y ~= x

template notComm(x, y: float): untyped  =
  check:
    not (x ~= y)
    not (y ~= x)

test "almost equals":
  comm 1000000f, 1000001f
  notComm 10000f, 10001f

  comm -1000000f, -1000001f
  notComm -10000f, -10001f

  comm 1.0000001f, 1.0000002f
  notComm 1.0002f, 1.0001f

  comm -1.000001f, -1.000002f
  notComm -1.0001f, -1.0002f

  comm 0.000000001000001f, 0.000000001000002f
  notComm 0.000000000001002f, 0.000000000001001f

  comm -0.000000001000001f, -0.000000001000002f
  notComm -0.000000000001002f, -0.000000000001001f

  comm 0.3f, 0.30000003f
  comm -0.3f, -0.30000003f

  # stopped at Comparisons involving zero, https://floating-point-gui.de/errors/NearlyEqualsTest.java

  check:
    0.1 + 0.2 ~= 0.3
    2.3 + 2.4 ~= 4.7
    0.5 + 0.5 ~= 1
    not (0.1 + 0.4 ~= 0.3)

test "num conversion":
  check {NoFail}.toNum == 1
  check {}.toNum == 0

test "mods conversion":
  check 0.toMods == {}

  check (1 shl 22).toMods == {Cinema}

test "string parsing":
  let s: Mods = {}
  check:
    "ezht".parseShortMods == {Easy, HalfTime}
    {Easy, HalfTime}.toShortString == "ezht"
    s.toShortString == "nm"

test "mod verification":
  check:
    {Easy, HardRock}.verify == false
    {DoubleTime, HalfTime}.verify == false
    {Relax, Relax2}.verify == false
    {Hidden, FadeIn}.verify == false
    {Nightcore}.verify == false

test "ar to ms":
  check:
    toMS(ar = 0) == initDuration(milliseconds=1800)
    toMS(ar = 1) == initDuration(milliseconds=1680)
    toMS(ar = 2) == initDuration(milliseconds=1560)
    toMS(ar = 3) == initDuration(milliseconds=1440)
    toMS(ar = 4) == initDuration(milliseconds=1320)
    toMS(ar = 5) == initDuration(milliseconds=1200)
    toMS(ar = 6) == initDuration(milliseconds=1050)
    toMS(ar = 7) == initDuration(milliseconds=900)
    toMS(ar = 8) == initDuration(milliseconds=750)
    toMS(ar = 9) == initDuration(milliseconds=600)
    toMS(ar = 10) == initDuration(milliseconds=450)

    toMS(ar = 9.8) == initDuration(milliseconds=480)

test "ms to ar":
  check:
    toAR(initDuration(milliseconds=320)) ~= 10.86666666666667
    toAR(initDuration(milliseconds=460)) ~= 9.933333333333334

test "od to ms":
  check:
    (hit_300: initDuration(milliseconds=67.5), hit_100: initDuration(milliseconds=123.5), hit_50: initDuration(milliseconds=179.5)) == toMS(od = 2)
