# Package

version       = "0.1.0"
author        = "Justin Kyle Ramos"
description   = "Slider on Nim"
license       = "LGPL-3.0"
srcDir        = "src"

backend       = "c"

# Dependencies

requires "nim >= 1.0.0"
requires "unpack >= 0.4.0"
requires "glm >= 1.1.1"
requires "itertools >= 0.3.0"

import os

task compileTest, "test if all files compile":
  for file in (getPkgDir() / srcDir).walkDirRec:
    if file[^3..^1] == "nim":
      exec "nim check " & file
