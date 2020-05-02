import units, utils, hitsound

import options, strutils, strformat, sequtils

import unpack

export options

type

  TimingPointEffect* {.size: sizeof(cint).} = enum
    KiaiTime
    BarLineOmit = 4
  TimingPointEffects* = set[TimingPointEffect]
  TimingPoint* = ref object ## A timing point assigns properties to an offset
                            ## into a beatmap.
    offset*: Duration ## When this ``TimingPoint`` takes effect.
    case inherited*: bool ## Whether or not the timing point is inherited.
    of true:
      sliderDurationMultiplier*: float
      parent*: TimingPoint ## The parent of an inherited timing point.
                           ## An inherited timing point differs from a
                           ## normal timing point in that the
                           ## ``ms_per_beat`` value is negative, and
                           ## defines a new ``ms_per_beat`` based on the
                           ## parent timing point. This can be used to
                           ## change volume without affecting offset
                           ## timing, or changing slider speeds. If this
                           ## is not an inherited timing point the parent
                           ## should be ``None``.
    of false:
      beatDuration*: Duration ## The duration of a beat, this is another
                              ## representation of BPM.
    meter*: int ## The number of beats per measure.
    sampleSet*: SampleSet ## The type of hit sound samples that are used. FIXME
    sampleIndex*: int ## The set of hit sound samples that are used. FIXME
    volume*: uint8 ## The volume of hit sounds in the range [0, 100].
                   ## This value will be clipped if outside the range.

    effects*: TimingPointEffects ## Whether or not kiai time effects are active.

  Bpm* = float

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc toInt*(tpe: TimingPointEffects): int =
  cast[cint](tpe)

proc toTimingPointEffects*(v: int): TimingPointEffects =
  cast[TimingPointEffects](v)

proc parseTimingPointEffects*(s: string): TimingPointEffects =
  s.parseInt().toTimingPointEffects()

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc newTimingPoint*(
    offset: Duration,
    beatDuration: Duration,
    meter: int,
    sampleSet: SampleSet,
    sampleIndex: int,
    volume: uint8,
    effects: TimingPointEffects
  ): TimingPoint =
  new result
  result.offset = offset
  result.beatDuration = beatDuration
  result.meter = meter
  result.sampleSet = sampleSet
  result.sampleIndex = sampleIndex
  result.volume = volume
  result.effects = effects

proc newTimingPointInherited*(
    offset: Duration,
    sliderDurationMultiplier: float,
    meter: int,
    sampleSet: SampleSet,
    sampleIndex: int,
    volume: uint8,
    parent: TimingPoint,
    effects: TimingPointEffects
  ): TimingPoint =
  result = TimingPoint(inherited: true)
  result.offset = offset
  result.sliderDurationMultiplier = sliderDurationMultiplier
  result.meter = meter
  result.sampleSet = sampleSet
  result.sampleIndex = sampleIndex
  result.volume = volume
  result.parent = parent
  result.effects = effects

proc bpm*(self: TimingPoint): Bpm =
  60 / self.beatDuration.inFloatSeconds

# TODO: standardise strings
proc `$`*(self: TimingPoint): string =
  $self[]
  # let p = if self.parent.isSome: "" else: "parent "
  # &"<{$type(self)}: {p}{self.offset.inFloatMilliseconds}ms>"

proc at*(timingPoints: openarray[TimingPoint], time: Duration): TimingPoint =
  let timingPointsBefore = timingPoints.filterIt(it.offset <= time)
  if timingPointsBefore.len > 0:
    timingPointsBefore[^1]
  else:
    timingPoints[0]

proc between*(timingPoints: openarray[TimingPoint],
    s, e: Duration): seq[TimingPoint] =
  timingPoints.filterIt(it.offset > s and it.offset < e)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc parseTimingPoint*(data: string, parent: Option[TimingPoint]=none(TimingPoint)): TimingPoint =
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
    effectsStr: string

    offset: float
    beatDuration: float
    sampleSet: int

  try:
    [offsetStr, beatDurationStr, *rest] <-- rest
  except IndexError:
    raise newException(ValueError, &"not enough elements in line, got \"{data}\"")

  try:
    [meterStr, *rest] <-- rest
  except IndexError:
    meterStr = "0"

  try:
    [sampleSetStr, *rest] <-- rest
  except IndexError:
    sampleSetStr = "0"

  try:
    [sampleIndexStr, *rest] <-- rest
  except IndexError:
    sampleIndexStr = "0"

  try:
    [volumeStr, *rest] <-- rest
  except IndexError:
    volumeStr = "1"

  try:
    [inheritedStr, *rest] <-- rest
  except IndexError:
    inheritedStr = "1"

  try:
    [effectsStr, *rest] <-- rest
  except IndexError:
    effectsStr = "0"

  let inherited = not inheritedStr.parseBool
  if parent.isSome:
    result = TimingPoint(inherited: inherited)
  else:
    new result
  offset <== offsetStr
  result.offset = initDuration(milliseconds=offset)
  beatDuration <== beatDurationStr
  result.meter <== meterStr
  sampleSet <== sampleSetStr
  result.sampleSet = sampleSet.SampleSet
  result.sampleIndex <== sampleIndexStr
  result.volume <== volumeStr
  result.effects <== effectsStr
  if inherited and parent.isSome:
    result.sliderDurationMultiplier = -1 * beatDuration / 100
    result.parent = parent.get()
  else:
    result.beatDuration = initDuration(milliseconds=beatDuration)

proc parseTimingPoints*(datas: seq[string]): seq[TimingPoint] =
  var parent: TimingPoint
  for v in datas:
    var tp: TimingPoint
    if parent.isNil:
      tp = v.parseTimingPoint()
      if tp.beatDuration.inMilliseconds < 0:
        raise newException(ValueError, "missing parent timing point")
    else:
      tp = v.parseTimingPoint(some(parent))
    result.add(tp)
    if not tp.inherited:
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
