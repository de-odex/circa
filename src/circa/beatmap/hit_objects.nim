import ../../circa/[units, utils, curve, timing, hitsound]

import strutils, strformat, sequtils, algorithm, sugar

import unpack, itertools

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

type
  HitObjectAttr* {.size: sizeof(cint).} = enum
    CircleType, SliderType, NewCombo, SpinnerType,
    Color1, Color2, Color3, HoldNoteType
  HitObjectAttrs* = set[HitObjectAttr]

  Addition* = object
    sampleSet*: SampleSet
    additionSet*: SampleSet
    customIndex*: Option[int]
    sampleVolume*: Option[uint8]
    filename*: Option[string]

  HitObject* = ref object of RootObj
    position*: Position
    time*: Duration
    hitSound*: HitSound
    addition*: Addition
    timingPoints*: ref seq[TimingPoint]
  Circle* = ref object of HitObject
  Slider* = ref object of HitObject
    endTime*: Duration
    curves*: LimCurveSeq
    repeat*: int
    pixelLength*: float
    tickCount*: int
    numBeats*: float
    tickRate*: float
    edgeSounds*: seq[HitSound]
    edgeAdditions*: seq[Addition]
  Spinner* = ref object of HitObject
    endTime*: Duration
  HoldNote* = ref object of HitObject

  Tick* = object
    position: Position
    offset: Duration
    parent: HitObject
    isNote: bool

const
  HitObjectType* = {CircleType, SliderType, SpinnerType, HoldNoteType}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc parseHitSound*(data: string): HitSound =
  var hitSound: int
  hitSound <== data
  cast[HitSound](hitSound)

proc parseAddition*(data: string): Addition =
  var
    sampleSetStr, additionSetStr, customIndexStr,
      sampleVolumeStr, filename: string
    customIndex: int
    sampleVolume: uint8

  try:
    [sampleSetStr, additionSetStr, customIndexStr, sampleVolumeStr, filename] <-- data.split(':')
    customIndex <== customIndexStr
    sampleVolume <== sampleVolumeStr
    result.customIndex = some(customIndex)
    result.sampleVolume = some(sampleVolume)
    result.filename = some(filename)
  except IndexError:
    try:
      [sampleSetStr, additionSetStr] <-- data.split(':')
      result.customIndex = none(int)
      result.sampleVolume = none(uint8)
      result.filename = none(string)
    except IndexError:
      raise newException(ValueError, &"not enough elements in line, got \"{data}\"")
  result.sampleSet = sampleSetStr.parseInt.SampleSet
  result.additionSet = additionSetStr.parseInt.SampleSet

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc initTick(position: Position, offset: Duration, parent: HitObject, isNote: bool = false): Tick =
  Tick(
    position: position,
    offset: offset,
    parent: parent,
    isNote: isNote
  )

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc newHitObject*(position: Position,
    time: Duration,
    hitSound: int,
    addition: Addition=Addition()): HitObject =
  new result
  result.position = position
  result.time = time
  result.hitSound = cast[HitSound](hitSound)
  result.addition = addition

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc parseCircle*(position: Position,
    time: Duration,
    hitSound: HitSound,
    restArg: seq[string],
    timingPoints: ref seq[TimingPoint]): Circle =
  new result

  result.timingPoints = timingPoints

  if restArg.len > 1:
    raise newException(ValueError, &"extra data: {restArg}")

  result.position = position
  result.time = time
  result.hitSound = hitSound
  result.addition = parseAddition(restArg[0])

proc parseSlider*(position: Position,
    time: Duration,
    hitSound: HitSound,
    restArg: seq[string],
    timingPoints: ref seq[TimingPoint], # TODO: remove this
    sliderMultiplier, sliderTickRate: float): Slider =
  new result
  var
    rest = restArg
    rawPoints: seq[string]
    group1, sliderType, repeatStr, pixelLengthStr,
      rawEdgeSoundsGroupedStr, rawEdgeAdditionsGroupedStr: string
    rawEdgeSounds, rawEdgeAdditions: seq[string]

    repeat: int
    pixelLength: float

    tp: TimingPoint
    velocityMultiplier: float
    beatDuration: Duration
    pixelsPerBeat: float
    numBeats: float
    duration: Duration

    points = @[position]

  result.timingPoints = timingPoints

  try:
    [group1, *rest] <-- rest
  except IndexError:
    raise newException(ValueError, &"missing required slider data in \"{restArg}\"")

  try:
    [sliderType, *rawPoints] <-- group1.split('|')
  except IndexError:
    raise newException(ValueError,
      &"expected slider type and points in the first element of rest, {rest}",
    )

  for point in rawPoints:
    var
      xStr, yStr: string
      x, y: float64
    try:
        (xStr, yStr) = point.split(':')
    except IndexError:
      raise newException(ValueError,
        &"expected points in the form x:y, got {point}"
      )

    x <== xStr
    y <== yStr
    points.add(newPos(x, y))

  try:
    [repeatStr, *rest] <-- rest
  except IndexError:
    raise newException(ValueError, &"missing repeat in {rest}")
  repeat <== repeatStr
  result.repeat = repeat

  try:
    [pixelLengthStr, *rest] <-- rest
  except IndexError:
    raise newException(ValueError, &"missing pixelLength in {rest}")
  pixelLength <== pixelLengthStr
  result.pixelLength = pixelLength

  try:
    [rawEdgeSoundsGroupedStr, *rest] <-- rest
  except IndexError:
    rawEdgeSoundsGroupedStr = ""

  rawEdgeSounds = rawEdgeSoundsGroupedStr.split('|')
  if rawEdgeSounds != @[""]:
    for rawEdgeSound in rawEdgeSounds:
      result.edgeSounds.add(parseHitSound(rawEdgeSound))

  try:
    [rawEdgeAdditionsGroupedStr, *rest] <-- rest
  except IndexError:
    rawEdgeAdditionsGroupedStr = ""

  rawEdgeAdditions = rawEdgeAdditionsGroupedStr.split('|')
  if rawEdgeAdditions != @[""]:
    for rawEdgeAddition in rawEdgeAdditions:
      result.edgeAdditions.add(parseAddition(rawEdgeAddition))

  if rest.len > 1:
    raise newException(ValueError, &"extra data: {rest}")

  tp = timingPoints[].at(time)

  if tp.parent.isSome:
    velocityMultiplier = tp.parent.get().beatDuration.inFloatMilliseconds() /
      tp.beatDuration.inFloatMilliseconds()
    beatDuration = tp.parent.get().beatDuration
  else:
    velocityMultiplier = 1
    beatDuration = tp.beatDuration

  # TODO: explain how the hell this does what it does
  pixelsPerBeat = slider_multiplier * 100 * velocityMultiplier
  numBeats = (
    round(((pixelLength * repeat.float) / pixelsPerBeat) * 16) / 16
  )
  result.numBeats = numBeats

  duration = initDuration(
    milliseconds=ceil(beatDuration.inFloatMilliseconds * numBeats).int
  )

  # TODO: explain how the hell this does what it does 2: electric boogaloo
  result.tickCount = int(
    (
      (ceil((numBeats - 0.1) / repeat.float * slider_tick_rate) - 1)
    ) *
    repeat.float +
    repeat.float +
    1
  )

  result.position = position
  result.time = time
  result.endTime = time + duration
  result.hitSound = hitSound
  result.curves = fromKindAndPoints(sliderType, points, pixelLength)
  result.tickRate = sliderTickRate
  result.addition = parseAddition(rest[0])

proc parseSpinner*(position: Position,
    time: Duration,
    hitSound: HitSound,
    restArg: seq[string],
    timingPoints: ref seq[TimingPoint]): Spinner =
  new result
  var
    rest = restArg
    endTimeStr: string
    endTime: int

  result.timingPoints = timingPoints

  try:
    [endTimeStr, *rest] <-- restArg
  except IndexError:
    raise newException(ValueError, &"missing endTime in {rest}")
  endTime <== endTimeStr
  result.endTime = initDuration(milliseconds=endTime)

  if rest.len > 1:
    raise newException(ValueError, &"extra data: {rest}")


  result.position = position
  result.time = time
  result.hitSound = hitSound
  result.addition = parseAddition(restArg[0])

proc parseHitObject*(data: string,
    timingPoints: ref seq[TimingPoint],
    sliderMultiplier, sliderTickRate: float): HitObject =
  new result
  var
    rest = data.split(",")

  var
    xStr, yStr, timeStr, typeStr, hitSoundStr: string
    x: float
    y: float
    pos: Position
    timeInt: int
    time: Duration
    typeInt: int
    typ: HitObjectAttrs
    hitSoundInt: int
    hitSound: HitSound

  try:
    [xStr, yStr, timeStr, typeStr, hitSoundStr, *rest] <-- rest
  except IndexError:
    raise newException(ValueError, &"not enough elements in line, got \"{data}\"")

  x <== xStr
  y <== yStr
  pos = newPos(x, y)

  timeInt <== timeStr
  time = initDuration(milliseconds=timeInt)
  typeInt <== typeStr
  typ = cast[HitObjectAttrs](typeInt) * HitObjectType
  hitSoundInt <== hitSoundStr
  hitSound = cast[HitSound](hitSoundInt)

  case cast[cint](typ):
    of 1: # CircleType
      result = parseCircle(pos, time, hitSound, rest, timingPoints)
    of 2: # SliderType
      result = parseSlider(pos, time, hitSound, rest, timingPoints, sliderMultiplier, sliderTickRate)
    of 8: # SpinnerType
      result = parseSpinner(pos, time, hitSound, rest, timingPoints)
    of 128: # HoldNoteType
      result = parseCircle(pos, time, hitSound, rest, timingPoints)
    else:
      raise newException(ValueError, &"unknown type code {typeStr}")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

method timingPoint(self: HitObject): TimingPoint {.base.} =
  ## The timing point the HitObject is based on.
  self.timingPoints[].at(self.time)

proc tickPoints*(self: Slider): seq[Tick] =
  ## The position and time of each slider tick.
  ## USE WITH CAUTION: UNTESTED; Test cases needed
  var
    beatsPerRepeat = self.numBeats / self.repeat.float
    ticksPerRepeat = self.tickRate * beatsPerRepeat
    beatsPerTick =  beatsPerRepeat / ticksPerRepeat
    repeatDuration: Duration = beatsPerRepeat * self.timingPoint.beatDuration

    preRepeatTicks: seq[Tick] = @[]

  for t in fcount(beatsPerTick, beatsPerRepeat, beatsPerTick):
    var
      pos = self.curves.at(t / beatsPerRepeat)
      timediff = t * self.timingPoint.beatDuration
    preRepeatTicks.add(initTick(pos, self.time + timediff, self))

  var
    pos = self.curves.at(1)
    timediff = repeatDuration
  preRepeatTicks.add(initTick(pos, self.time + timediff, self, true))

  var repeatTicks: seq[Tick] = @[]
  for (tick, pos) in zip(preRepeatTicks, toSeq(chain(preRepeatTicks[0..^3].reversed.map((x) => x.position), @[self.position]))):
    repeatTicks.add initTick(pos, tick.offset, self, tick.isNote)

  # I don't know why cycle here takes a 2nd parameter but in the docs it doesn't.
  var tickSequences: seq[seq[Tick]] = toSeq(islice(cycle(@[pre_repeat_ticks, repeat_ticks], high(int)), stop=self.repeat))

  var toChain: seq[Tick] = @[]
  for i, tickSequence in tickSequences:
    for p in tickSequence:
      toChain.add(initTick(p.position, p.offset + i * repeatDuration, self, p.isNote))

  result = toSeq(chain(toChain))
