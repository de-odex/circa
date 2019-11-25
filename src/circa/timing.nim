import units, utils, hitsound

import options, strutils, strformat, sequtils

import unpack

export options

type
  TimingPoint* = ref object
    offset*: Duration
    beatDuration*: Duration
    meter*: int
    sampleSet*: SampleSet
    sampleIndex*: int
    volume*: uint8
    parent*: Option[TimingPoint]
    kiaiMode*: bool

  Bpm* = distinct float

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc newTimingPoint*(offset: Duration,
    beatDuration: Duration,
    meter: int,
    sampleSet: SampleSet,
    sampleIndex: int,
    volume: uint8,
    parent: Option[TimingPoint],
    kiaiMode: bool): TimingPoint =
  new result
  result.offset = offset
  result.beatDuration = beatDuration
  result.meter = meter
  result.sampleSet = sampleSet
  result.sampleIndex = sampleIndex
  result.volume = volume
  result.parent = parent
  result.kiaiMode = kiaiMode

proc bpm*(self: TimingPoint): Bpm =
  (60 / self.beatDuration.inFloatSeconds).Bpm

# TODO: standardise strings
proc `$`*(self: TimingPoint): string =
  $self[]
  # let p = if self.parent.isSome: "" else: "parent "
  # &"<{$type(self)}: {p}{self.offset.inFloatMilliseconds}ms>"

proc at*(timingPoints: openarray[TimingPoint], time: Duration): TimingPoint =
  timingPoints.filterIt(it.offset <= time)[^1]

proc between*(timingPoints: openarray[TimingPoint],
    s, e: Duration): seq[TimingPoint] =
  timingPoints.filterIt(it.offset > s and it.offset < e)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc parseTimingPoint*(data: string, parent: Option[TimingPoint]=none(TimingPoint)): TimingPoint =
  new result
  var
    rest = data.split(",")

  var
    offsetStr: string
    beatDurationStr: string
    meterStr: string
    sampleSetStr: string
    sampleIndexStr: string
    volumeStr: string
    inheritedStr: string
    kiaiModeStr: string

    offset: int
    beatDuration: float
    sampleSet: int

  try:
    [offsetStr, beatDurationStr, *rest] <-- rest
  except IndexError:
    raise newException(ValueError, &"not enough elements in line, got \"{data}\"")

  offset <== offsetStr
  result.offset = initDuration(milliseconds=offset)
  beatDuration <== beatDurationStr

  try:
    [meterStr, *rest] <-- rest
  except IndexError:
    meterStr = "0"
  result.meter <== meterStr

  try:
    [sampleSetStr, *rest] <-- rest
  except IndexError:
    sampleSetStr = "0"
  sampleSet <== sampleSetStr
  result.sampleSet = sampleSet.SampleSet

  try:
    [sampleIndexStr, *rest] <-- rest
  except IndexError:
    sampleIndexStr = "0"
  result.sampleIndex <== sampleIndexStr

  try:
    [volumeStr, *rest] <-- rest
  except IndexError:
    volumeStr = "1"
  result.volume <== volumeStr

  try:
    [inheritedStr, *rest] <-- rest
  except IndexError:
    inheritedStr = "1"

  try:
    [kiaiModeStr, *rest] <-- rest
  except IndexError:
    kiaiModeStr = "0"
  result.kiaiMode <== kiaiModeStr

  if (not inheritedStr.parseBool) and parent.isSome:
    result.beatDuration = initDuration(
      milliseconds=parent.get().beatDuration.inFloatMilliseconds *
      abs(beatDuration / 100)
    )
  else:
    result.beatDuration = initDuration(milliseconds=beatDuration)
  result.parent = parent

proc parseTimingPoints*(datas: seq[string]): seq[TimingPoint] =
  var parent: TimingPoint
  for v in datas:
    var tp: TimingPoint
    if parent.isNil:
      tp = v.parseTimingPoint
      if tp.beatDuration.inMilliseconds < 0:
        raise newException(ValueError, "missing parent timing point")
    else:
      tp = v.parseTimingPoint(some(parent))
    result.add(tp)
    if tp.parent.isNone:
      parent = tp

proc parseTimingPoints*(data: string): seq[TimingPoint] =
  parseTimingPoints(data.split)

when isMainModule:
  var
    a = @["6664,264.31718061674,4,2,1,60,1,0",
      "7721,-71.4285714285714,4,2,1,60,0,0",
      "11950,-58.8235294117647,4,2,1,70,0,0",
      "20408,-62.5,4,2,1,60,0,0",
      "37324,-83.3333333333333,4,2,1,40,0,0",
      "37589,-83.3333333333333,4,3,1,40,0,0",
      "37655,-83.3333333333333,4,2,1,40,0,0",
      "37853,-83.3333333333333,4,3,1,40,0,0",
      "37919,-83.3333333333333,4,2,1,40,0,0",
      "39703,-83.3333333333333,4,3,1,40,0,0",
      "39769,-83.3333333333333,4,2,1,40,0,0",
      "40496,-83.3333333333333,4,3,1,40,0,0",
      "40562,-83.3333333333333,4,2,1,40,0,0",
      "40760,-83.3333333333333,4,3,1,40,0,0",
      "40826,-83.3333333333333,4,2,1,40,0,0",
      "41818,-83.3333333333333,4,3,1,40,0,0",
      "41884,-83.3333333333333,4,2,1,40,0,0",
      "42875,-83.3333333333333,4,3,1,40,0,0",
      "42941,-83.3333333333333,4,2,1,40,0,0",
      "43139,-83.3333333333333,4,3,1,40,0,0",
      "43205,-83.3333333333333,4,2,1,40,0,0",
      "43932,-83.3333333333333,4,3,1,40,0,0",
      "43998,-83.3333333333333,4,2,1,40,0,0",
      "44197,-83.3333333333333,4,3,1,40,0,0",
      "44263,-83.3333333333333,4,2,1,40,0,0",
      "45650,-62.5,4,2,1,60,0,0",
      "53712,-76.9230769230769,4,2,1,60,0,0",
      "53976,-100,4,2,1,60,0,0",
      "54241,-58.8235294117647,4,2,1,70,0,1",
      "59527,-52.6315789473684,4,2,1,70,0,1",
      "60848,-44.4444444444444,4,2,1,70,0,1",
      "62698,-58.8235294117647,4,2,1,70,0,1",
      "71157,-58.8235294117647,4,2,1,60,0,0"
    ]
    b = parseTimingPoints(a)

  for v in b:
    echo $v

  for v in b.between(initDuration(seconds=40), initDuration(seconds=60)):
    # echo $v.bpm & "  " & $v.parent.get().bpm
    discard
