import units, game_mode, timing, beatmap/hit_objects

import strutils, strformat, sequtils, algorithm, sugar, tables, macros

import unpack, itertools

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc getAsString(groups: Table[string, Table[string, string]],
    section, field: string, default = none(string)): string =
  var
    sectionTable: Table[string, string]
  try:
    sectionTable = groups[section]
  except KeyError:
    if default == none(string):
      raise newException(ValueError, &"missing section {section}")
    return default.get()

  try:
    result = sectionTable[field]
  except KeyError:
    if default == none(string):
      raise newException(ValueError, &"missing field {field} in section {section}")
    result = default.get()

macro get_as(typ: untyped): untyped =
  let
    typStr = typ.repr
    typStrC = typ.repr.capitalizeAscii
    getAsTyp = ("getAs" & typStrC).ident
    parseTyp = ("parse" & typStrC).ident

  result = quote do:
    proc `getAsTyp`(groups: Table[string, Table[string, string]],
        section, field: string, default = none(string)): `typ` {.used.} =
      let v = getAsString(groups, section, field, default)

      try:
        result = v.`parseTyp`()
      except ValueError:
        raise newException(ValueError,
          "field " & field & " in section " & section & " should be of type " &
          `typStr` &
          ", got " & v,
        )

get_as int
get_as float
get_as bool

proc get_as_int_seq(groups: Table[string, Table[string, string]],
    section, field: string, default = none(string)): seq[int] =
  let v = get_as_string(groups, section, field, default)

  try:
    result = @[]
    for e in v.split(','):
      result.add(e.strip().parseInt())
  except ValueError:
    raise newException(ValueError,
      &"field {field} in section {section} should be of type seq[int], got {v}",
    )

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

type
  CountdownSpeed = enum
    NoCountdown = 0
    Normal
    Half
    Double

  GeneralData = object
    audioFilename: string
    audioLeadIn: Duration
    previewTime: Duration
    countdownSpeed: CountdownSpeed
    sampleSet: string # TODO: figure out if this is a simple enum
    stackLeniency: float
    mode: GameMode
    letterboxInBreaks: bool
    storyFireInFront: bool
    skinPreference: string
    epilepsyWarning: bool
    countdownOffset: int
    widescreenStoryboard: bool
    specialStyle: bool
    useSkinSprites: bool
  EditorData = object
    bookmarks: seq[Duration]
    distanceSpacing: float
    beatDivisor: int
    gridSize: int
    timelineZoom: float
  MetaData = object
    title: string
    titleUnicode: string
    artist: string
    artistUnicode: string
    creator: string
    version: string
    source: string
    tags: seq[string]
    beatmapId: int
    beatmapSetId: int
  DifficultyData = object
    hpDrainRate: float
    circleSize: float
    overallDifficulty: float
    approachRate: float
    sliderMultiplier: float
    sliderTickRate: float
  Event = ref object of RootObj
    # TODO: set this up
    time: Duration

  Beatmap = ref object of RootObj
    general: GeneralData
    editor: EditorData
    metadata: MetaData
    difficulty: DifficultyData
    events: ref seq[Event] # currently, events are ignored and this will be nil or empty
    timingPoints: ref seq[TimingPoint]
    colors: ref seq[string]

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc displayName*(self: Beatmap): string =
  &"{self.metadata.artist} - {self.metadata.title} [{self.metadata.version}]"

proc bpm_min() =
  discard

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

when isMainModule:
  let
    tpsStr = @["6664,264.31718061674,4,2,1,60,1,0",
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
  var tpsRef: ref seq[TimingPoint]
  new tpsRef
  tpsRef[] = parseTimingPoints(tpsStr)

  var
    ho = parseHitObject("191,323,7721,5,0,1:0:0:0:", tpsRef, 1, 1)
    hoc = ho
  ho.time = initDuration(milliseconds = 2)
  echo hoc.time
  echo hoc.timingPoints[]
  # echo parseHitObject("256,192,9571,6,0,P|185:206|139:177,1,104.999996795654,8|0,0:1|0:0,0:0:0:0:", tps, 1, 1).repr
