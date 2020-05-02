# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest

import circa, os, sequtils, algorithm, strutils

let testFiles = toSeq(walkDir("./test_suite")).sorted do (x, y: (PathComponent, string)) -> int:
  let xNum = if DirSep in x[1] and Digits in x[1].split(DirSep)[^1]:
    x[1].split(DirSep)[^1].split(".")[0].parseInt
  else:
    0
  let yNum = if DirSep in y[1] and Digits in y[1].split(DirSep)[^1]:
    y[1].split(DirSep)[^1].split(".")[0].parseInt
  else:
    0

  xNum.cmp(yNum)

for file in testFiles:
  echo file

suite "parse":
  for file in testFiles:
    test file.path:
      check parseBeatmap(readFile(file.path)) != Beatmap()

# test "final":
#   for file in walkDir("./test_suite"):
#     check parseBeatmap(readFile(file.path)) != Beatmap()
