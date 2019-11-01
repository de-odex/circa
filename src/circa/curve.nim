import units

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
