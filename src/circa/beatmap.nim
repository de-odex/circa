import units, game_mode, timing, beatmap/hit_objects, hitsound, mods

import strutils, strformat, sequtils, math, sugar, tables, macros, sets, streams

import zip/zipfiles

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

proc getAsString(groups: Table[string, Table[string, string]],
    section, field: string, default: string): string =
  getAsString(groups, section, field, some(default))

macro getAs(typ: untyped): untyped =
  let
    typStr = typ.repr
    typStrC = typ.repr.capitalizeAscii
    getAsTyp = ("getAs" & typStrC).ident
    parseTyp = ("parse" & typStrC).ident

  result = quote do:
    proc `getAsTyp`(groups: Table[string, Table[string, string]],
        section, field: string, default = none(`typ`)): `typ` {.used.} =
      let v = if default.isSome:
          getAsString(groups, section, field, some($default.get()))
        else:
          getAsString(groups, section, field, none(string))

      try:
        result = v.`parseTyp`()
      except ValueError:
        raise newException(ValueError,
          "field " & field & " in section " & section & " should be of type " &
          `typStr` &
          ", got " & v,
        )

    proc `getAsTyp`(groups: Table[string, Table[string, string]],
        section, field: string, default: `typ`): `typ` {.used.} =
      `getAsTyp`(groups, section, field, some(default))

getAs int
getAs float
getAs bool

proc getAsIntSeq(groups: Table[string, Table[string, string]],
    section, field: string, default = none(string)): seq[int] =
  let v = getAsString(groups, section, field, default)
  if v != "":
    try:
      for e in v.split(','):
        result.add(e.strip().parseInt())
    except ValueError:
      raise newException(ValueError,
        &"field {field} in section {section} should be of type seq[int], got {v}",
      )

proc getAsIntSeq(groups: Table[string, Table[string, string]],
    section, field: string, default: seq[int]): seq[int] =
  getAsIntSeq(groups, section, field, some(default.join(",")))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

type
  CountdownSpeed* = enum
    NoCountdown = 0
    Normal
    Half
    Double

  GeneralData* = object
    audioFilename*: string
    audioLeadIn*: Duration
    previewTime*: Duration
    countdownSpeed*: CountdownSpeed
    sampleSet*: SampleSet
    stackLeniency*: float
    gameMode*: GameMode
    letterboxInBreaks*: bool
    storyFireInFront*: bool
    skinPreference*: string # TODO: handlers in parseBeatmap
    epilepsyWarning*: bool  # TODO: handlers in parseBeatmap
    countdownOffset*: int   # TODO: handlers in parseBeatmap
    widescreenStoryboard*: bool
    specialStyle*: bool     # TODO: handlers in parseBeatmap
    useSkinSprites*: bool
  EditorData* = object
    bookmarks*: seq[Duration]
    distanceSpacing*: float
    beatDivisor*: int
    gridSize*: int
    timelineZoom*: float
  MetaData* = object
    title*: string
    titleUnicode*: string
    artist*: string
    artistUnicode*: string
    creator*: string
    version*: string
    source*: string
    tags*: seq[string]
    beatmapId*: int
    beatmapSetId*: int
  DifficultyData* = object
    hpDrainRate*: float
    circleSize*: float
    overallDifficulty*: float
    approachRate*: float
    sliderMultiplier*: float
    sliderTickRate*: float
  Event* = ref object of RootObj
    # TODO: set this up
    time*: Duration # TODO: handlers in parseBeatmap

  Beatmap* = ref object of RootObj
    formatVersion*: int
    general*: GeneralData
    editor*: EditorData
    metadata*: MetaData
    difficulty*: DifficultyData
    events*: seq[Event]  # currently, events are ignored and this will be nil or empty
    timingPoints*: ref seq[TimingPoint]
    colors*: seq[string] # TODO: handlers in parseBeatmap
    hitObjects*: seq[HitObject]

  ModeBeatmap* = object
    beatmap*: Beatmap
    modeHitObjects*: seq[ModeHitObject]
    gameMode*: GameMode
    mods*: Mods
  ScoredBeatmap* = object
    modeBeatmap: ModeBeatmap
    accuracy*: float
    combo*: int
    misses*: int
    score*: int

  # NOTE: use these for a more accurate representation of an in-game hit object
  ModeHitObject* = object
    hitObject*: HitObject

    case gameMode*: GameMode
    of Standard: discard
    of Catch:
      distanceToHyperDash*: float
      scale*: float
      pHyperDashTarget: Option[ref ModeHitObject]
    of Mania:
      pColumn: Option[int]
    of Taiko: discard

  # ModeHitObject* = ref object of RootObj
  #   hitObject*: HitObject
  # StandardHitObject* = ref object of ModeHitObject
  # CatchHitObject* = ref object of ModeHitObject
  #   distanceToHyperDash*: float
  #   scale*: float
  #   pHyperDashTarget: Option[CatchHitObject]
  # ManiaHitObject* = ref object of ModeHitObject
  #   pColumn: Option[int]
  # TaikoHitObject* = ref object of ModeHitObject

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# template getSet(name: untyped, fullName: untyped) =
#   proc `name`*(dd: DifficultyData): float = dd.`fullName`
#   proc `name=`*(dd: var DifficultyData, val: float) = dd.`fullName` = val

# getSet(hp, hpDrainRate)
# getSet(cs, circleSize)
# getSet(od, overallDifficulty)
# getSet(ar, approachRate)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# let versionRegex = re"^osu file format v(\d+)$"

proc splitLines(s: string, keepEol = false): iterator(): string =
  return iterator(): string =
    for i in splitLines(s, keepEol):
      yield i

let mappingGroups = toHashSet([
  "General",
  "Editor",
  "Metadata",
  "Difficulty"
])

proc findGroups(
    lines: iterator(): string, until: Option[string] = none(string)
  ): Table[string, seq[tuple[key: string, value: string]]] =
  ## Split the input data into the named groups.
  # Parameters
  # ----------
  # lines : iterator[str]
  #     The raw lines from the file.
  # Returns
  # -------
  # groups : dict[str, list[str] or dict[str, str]]
  #     The lines in the section. If the section is a mapping section
  #     the the value will be a dict from key to value.
  var
    currentGroup: string
    groupBuffer: seq[string]

  template commitGroup() =
    var groupResult: seq[tuple[key: string, value: string]]

    # we are currently building a group
    if currentGroup in mappingGroups:
      for line in groupBuffer:
        let split = line.split(':', 1)
        var key, value: string
        try:
          (key, value) = (split[0], split[1])
        except IndexError:
          key = split[0]
          value = ""

        # throw away whitespace
        groupResult.add((key.strip(), value.strip()))
    else:
      for line in groupBuffer:
        # throw away whitespace
        groupResult.add(("", line.strip()))

    result[currentGroup] = groupResult
    groupBuffer.setLen(0)

  while true:
    let line = lines()
    if finished(lines):
      break

    if line.len == 0 or line.startsWith("//"):
      # filter out empty lines and comments
      continue

    if line[0] == '[' and line[^1] == ']':
      # we found a section header, commit the current buffered group
      # and start the new group
      if currentGroup != "":
        commitGroup()
      elif until.isSome and currentGroup == until.get():
        break
      currentGroup = line[1..^2]
    else:
      groupBuffer.add(line)

  # commit the final group
  commitGroup()
  return result

proc findGroups(
    lines: iterator(): string, until: string
  ): Table[string, seq[tuple[key: string, value: string]]] =
  findGroups(lines, some(until))

proc genGeneralData(groups: Table[string, Table[string, string]]): GeneralData =
  result.audioFilename = getAsString(groups, "General", "AudioFilename")
  result.audioLeadIn = initDuration(
    milliseconds = getAsInt(groups, "General", "AudioLeadIn", 0)
  )
  result.previewTime = initDuration(
    milliseconds = getAsInt(groups, "General", "PreviewTime")
  )
  result.countdownSpeed = getAsInt(
    groups,
    "General",
    "Countdown",
    0
  ).CountdownSpeed
  result.sampleSet = parseEnum[SampleSet](getAsString(
    groups,
    "General",
    "SampleSet"
  ))
  result.stackLeniency = getAsFloat(
    groups,
    "General",
    "StackLeniency",
    0
  )
  result.gameMode = getAsInt(groups, "General", "Mode", 0).GameMode
  result.letterboxInBreaks = getAsBool(
    groups,
    "General",
    "LetterboxInBreaks",
    false
  )
  result.storyFireInFront = getAsBool(
    groups,
    "General",
    "StoryFireInFront",
    true
  )
  result.useSkinSprites = getAsBool(
    groups,
    "General",
    "StoryFireInFront",
    false
  )
  result.widescreenStoryboard = getAsBool(
    groups,
    "General",
    "WidescreenStoryboard",
    false
  )

proc genEditorData(groups: Table[string, Table[string, string]]): EditorData =
  result.bookmarks = getAsIntSeq(
    groups,
    "Editor",
    "Bookmarks",
    @[]
  ).mapIt(initDuration(milliseconds = it))
  result.distanceSpacing = getAsFloat(
    groups,
    "Editor",
    "DistanceSpacing",
    1
  )
  result.beatDivisor = getAsInt(groups, "Editor", "BeatDivisor", 4)
  result.gridSize = getAsInt(groups, "Editor", "GridSize", 4)
  result.timelineZoom = getAsFloat(groups, "Editor", "TimelineZoom", 1.0)

proc genMetaData(groups: Table[string, Table[string, string]]): MetaData =
  result.title = getAsString(groups, "Metadata", "Title")
  result.titleUnicode = getAsString(
    groups,
    "Metadata",
    "TitleUnicode",
    result.title
  )
  result.artist = getAsString(groups, "Metadata", "Artist")
  result.artistUnicode = getAsString(
    groups,
    "Metadata",
    "ArtistUnicode",
    result.artist
  )
  result.creator = getAsString(groups, "Metadata", "Creator")
  result.version = getAsString(groups, "Metadata", "Version")
  result.source = getAsString(groups, "Metadata", "Source", "")
  # space delimited list
  result.tags = getAsString(groups, "Metadata", "Tags", "").split()
  result.beatmapId = getAsInt(groups, "Metadata", "BeatmapID", -1)
  result.beatmapSetId = getAsInt(
    groups,
    "Metadata",
    "BeatmapSetID",
    -1
  )

proc genDifficultyData(groups: Table[string, Table[string,
    string]]): DifficultyData =
  result.hpDrainRate = getAsFloat(groups, "Difficulty", "HPDrainRate")
  result.circleSize = getAsFloat(groups, "Difficulty", "CircleSize")
  result.overallDifficulty = getAsFloat(
    groups,
    "Difficulty",
    "OverallDifficulty",
  )
  result.approachRate = getAsFloat(
    groups,
    "Difficulty",
    "ApproachRate",
    # old maps didn't have an AR so the OD is used as a default
    result.overallDifficulty
  )
  result.sliderMultiplier = getAsFloat(
    groups,
    "Difficulty",
    "SliderMultiplier",
    1.4, # taken from wiki
  )
  result.sliderTickRate = getAsFloat(
    groups,
    "Difficulty",
    "SliderTickRate",
    1.0, # taken from wiki
  )

proc parseVersion(line: string): int =
  if line.startsWith("osu file format v"):
    return line.split("v")[1].parseInt
  else:
    raise newException(ValueError, &"missing osu file format specifier in: {line}")

proc parseBeatmap*(data: string): Beatmap =
  let
    data = data.strip(trailing = false)
    lines = data.splitLines()
  var line = lines()
  if line[0..2] == "\239\187\191": # UTF-8 BOM
    line = line[3..^1]
  while line.strip == "":
    line = lines()

  let
    groups = toSeq(findGroups(lines).pairs())
    tableGroups = groups.filterIt(it[0] in mappingGroups)
      .mapIt((it[0], it[1].toTable())).toTable()
    seqGroups = groups.filterIt(it[0] notin mappingGroups)
      .mapIt((it[0], it[1].mapIt(it.value))).toTable()

  new result

  result.formatVersion = parseVersion(line)

  result.general = genGeneralData(tableGroups)
  result.editor = genEditorData(tableGroups)
  result.metadata = genMetaData(tableGroups)
  result.difficulty = genDifficultyData(tableGroups)

  # var timing_points: seq[TimingPoint] = @[]
  # # the parent starts as None because the first timing point should
  # # not be inherited
  # var parent: Option[TimingPoint]
  # for raw_timing_point in groups["TimingPoints"]:
  #     let timing_point = parseTimingPoint(raw_timing_point.value, parent)
  #     if timing_point.parent == none(TimingPoint):
  #         # we have a new parent node, pass that along to the new
  #         # timing points
  #         parent = some(timing_point)
  #     timing_points.add(timing_point)
  new result.timingPoints
  result.timingPoints[] = parseTimingPoints(seqGroups["TimingPoints"])

  result.hitObjects = seqGroups["HitObjects"].mapIt(
    parseHitObject(
      it,
      result.timingPoints,
      result.difficulty.sliderMultiplier,
      result.difficulty.sliderTickRate
    )
  )

proc parseBeatmapMetadata*(data: string): Beatmap =
  let
    data = data.strip(trailing = false)
    lines = data.splitLines()
  var line = lines()
  if line[0..2] == "\239\187\191": # UTF-8 BOM
    line = line[3..^1]
  while line.strip == "":
    line = lines()

  let
    groups = toSeq(findGroups(lines, "Difficulty").pairs())
    tableGroups = groups.filterIt(it[0] in mappingGroups)
      .mapIt((it[0], it[1].toTable())).toTable()

  new result

  result.formatVersion = parseVersion(line)

  result.general = genGeneralData(tableGroups)
  result.editor = genEditorData(tableGroups)
  result.metadata = genMetaData(tableGroups)
  result.difficulty = genDifficultyData(tableGroups)

proc fromOszFile*(file: var ZipArchive): Table[string, Beatmap] =
  for packedFile in file.walkFiles():
    if packedFile.endsWith(".osu"):
      let beatmap = parseBeatmap(file.getStream(packedFile).Stream.readAll())
      result[beatmap.metadata.version] = beatmap

proc fromFile*(file: File): Beatmap =
  parseBeatmap(file.readAll())

proc fromOszPath*(path: string): Table[string, Beatmap] =
  var zf: ZipArchive
  discard open(zf, path)
  result = fromOszFile(zf)
  zf.close()

proc fromPath*(path: string): Beatmap =
  let file = open(path)
  result = fromFile(file)
  file.close()

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc displayName*(bm: Beatmap): string =
  &"{bm.metadata.artist} - {bm.metadata.title} [{bm.metadata.version}]"

proc bpmMin*(sbm: ModeBeatmap): float =
  result = min(sbm.beatmap.timingPoints[].filterIt(not it.inherited).mapIt(it.bpm))
  if DoubleTime in sbm.mods:
    result *= 1.5
  elif HalfTime in sbm.mods:
    result *= 0.75

proc bpmMax*(sbm: ModeBeatmap): float =
  result = max(sbm.beatmap.timingPoints[].filterIt(not it.inherited).mapIt(it.bpm))
  if DoubleTime in sbm.mods:
    result *= 1.5
  elif HalfTime in sbm.mods:
    result *= 0.75

proc hp*(sbm: ModeBeatmap): float =
  result = sbm.beatmap.difficulty.hpDrainRate
  if HardRock in sbm.mods:
    result = min(1.4 * result, 10)
  elif Easy in sbm.mods:
    result /= 2

proc cs*(sbm: ModeBeatmap): float =
  result = sbm.beatmap.difficulty.circleSize
  if HardRock in sbm.mods:
    result = min(1.3 * result, 10)
  elif Easy in sbm.mods:
    result /= 2

proc od*(sbm: ModeBeatmap): float =
  result = sbm.beatmap.difficulty.overallDifficulty
  if HardRock in sbm.mods:
    result = min(1.4 * result, 10)
  elif Easy in sbm.mods:
    result /= 2
  # NOTE: non-float durations, may have some loss in accuracy
  # nanoseconds is max resolution
  if DoubleTime in sbm.mods:
    result = (2 * result.OverallDifficulty.toMS300 div 3).toOD.float
  elif HalfTime in sbm.mods:
    result = (4 * result.OverallDifficulty.toMS300 div 3).toOD.float

proc ar*(sbm: ModeBeatmap): float =
  result = sbm.beatmap.difficulty.approachRate
  if HardRock in sbm.mods:
    result = min(1.4 * result, 10)
  elif Easy in sbm.mods:
    result /= 2
  # NOTE: non-float durations, may have some loss in accuracy
  # nanoseconds is max resolution
  if DoubleTime in sbm.mods:
    result = (2 * result.ApproachRate.toMS div 3).toAR.float
  elif HalfTime in sbm.mods:
    result = (4 * result.ApproachRate.toMS div 3).toAR.float

proc difficulty*(sbm: ModeBeatmap): DifficultyData =
  result.hpDrainRate = sbm.hp
  result.circleSize = sbm.cs
  result.overallDifficulty = sbm.od
  result.approachRate = sbm.ar

proc maxCombo*(sbm: ModeBeatmap): int =
  # FIXME: untested, needs mode variants
  for hitObject in sbm.beatmap.hitObjects:
    if hitObject of Slider:
      result += hitObject.Slider.tickCount + 1
    else:
      result += 1

proc keyCount*(sbm: ModeBeatmap): int =
  let
    roundedCircleSize = round(sbm.beatmap.difficulty.circleSize).int
    roundedOverallDifficulty = round(sbm.beatmap.difficulty.overallDifficulty).int
  case sbm.beatmap.general.gamemode
  of Standard:
    let percentSliderOrSpinner = sbm.beatmap.hitObjects.filterIt(not (
        it of Circle)).len / sbm.beatmap.hitObjects.len;
    if (percentSliderOrSpinner < 0.2):
      result = 7
    elif (percentSliderOrSpinner < 0.3 or roundedCircleSize >= 5):
      result = if roundedOverallDifficulty > 5: 7 else: 6
    elif (percentSliderOrSpinner > 0.6):
      result = if roundedOverallDifficulty > 4: 5 else: 4
    else:
      result = max(4, min(roundedOverallDifficulty + 1, 7))
  of Mania:
    result = max(roundedCircleSize, 1)
    if result >= 10:
      result = result div 2
  else:
    discard

# TODO: refactor this, make it reliant on a "mho" mania hit object rather than
#       binding it to ModeBeatmap
#       this implies making mode-specific hit objects
# proc column*(sbm: ModeBeatmap, ho: HitObject): int =
#   let localXDivisor = 512 / sbm.keyCount
#   clamp(floor(ho.position.x / localXDivisor).int, 0, sbm.keyCount - 1);

#
# ──────────────────────────────────────────────────────────────────────── I ──────────
#   :::::: M O D E   H I T   O B J E C T S : :  :   :    :     :        :          :
# ──────────────────────────────────────────────────────────────────────────────────
#

# These are here as mode hit objects are reliant on the underlying beatmap data
# ex. what lane theyre on, for osu!mania converts
# and what size they are, for osu!standard and osu!catch

proc applyDefaultsToSelf*(mho: var ModeHitObject, difficulty: DifficultyData) =
  case mho.gameMode

  of Catch:
    mho.scale = 1.0f - 0.7f * (difficulty.circleSize - 5) / 5

  else:
    raise newException(CatchableError, "") # TODO: proper "NotImpl." error

# ─── OSU!CATCH ──────────────────────────────────────────────────────────────────

proc initCatchHitObject*: ModeHitObject =
  result = ModeHitObject(gameMode: Catch)
  result.scale = 1

proc initCatchHitObject*(difficulty: DifficultyData): ModeHitObject =
  result = ModeHitObject(gameMode: Catch)
  result.applyDefaultsToSelf(difficulty)

proc objectRadius*(mho: ModeHitObject): float =
  case mho.gameMode

  of Catch:
    result = 44

  else:
    raise newException(CatchableError, "") # TODO: proper "NotImpl." error

proc hyperDash*(mho: ModeHitObject): bool =
  if mho.gameMode != Catch:
    raise newException(CatchableError, "") # TODO: proper "NotImpl." error
  mho.pHyperDashTarget.isSome

proc hyperDashTarget*(mho: ModeHitObject): ModeHitObject =
  if mho.gameMode != Catch:
    raise newException(CatchableError, "") # TODO: proper "NotImpl." error
  # if mho.pHyperDashTarget.isSome:
  mho.pHyperDashTarget.get()[]
  # else:
  #   raise newException(ValueError, "hyper dash target is unset")

proc `hyperDashTarget=`*(mho: var ModeHitObject, val: ModeHitObject) =
  if mho.gameMode != Catch:
    raise newException(CatchableError, "") # TODO: proper "NotImpl." error
  # if mho.pHyperDashTarget.isNone:
  let rval = new ModeHitObject
  rval[] = val
  mho.pHyperDashTarget = some(rval)
  # else:
  #   raise newException(ValueError, "hyper dash target was already set")

# ─── OSU!MANIA ──────────────────────────────────────────────────────────────────

proc initManiaHitObject*: ModeHitObject =
  ModeHitObject(gameMode: Mania)

proc column*(mho: ModeHitObject): int =
  if mho.gameMode != Mania:
    raise newException(CatchableError, "") # TODO: proper "NotImpl." error
  # if mho.pColumn.isSome:
  mho.pColumn.get()
  # else:
  #   raise newException(ValueError, "column is unset")

proc `column=`*(mho: var ModeHitObject, val: int) =
  if mho.gameMode != Mania:
    raise newException(CatchableError, "") # TODO: proper "NotImpl." error
  # if mho.pColumn.isNone:
  mho.pColumn = some(val)
  # else:
  #   raise newException(ValueError, "column was already set")
  # do i really need to make re-setting this a runtime error?

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

when isMainModule:
  import os
  import std/monotimes
  # import nimprof

  # for file in walkDir("./test_suite"):
  #   # echo file.path
  #   try:
  #   # writeFile "./out.txt", parseBeatmap(readFile(file.path)).repr
  #     let data = readFile(file.path)
  #     let time0m = getMonoTime()
  #     discard parseBeatmapMetadata(data) # .repr
  #     let time1m = getMonoTime()
  #     let time0r = getMonoTime()
  #     discard parseBeatmap(data) # .repr
  #     let time1r = getMonoTime()
  #     echo time1m - time0m
  #     echo time1r - time0r
  #     echo file.path & ": passed"
  #   except Exception as e:
  #     discard
  #     echo file.path & ": failed"
  #     echo getCurrentExceptionMsg()
  #     echo getStackTrace(e)
  #     break

  # let time0 = getMonoTime()
  # for file in walkDir("./osulib"):
  #   try:
  #     let data = readFile(file.path)
  #     let beatmap = parseBeatmap(data)
  #     for hitObject in beatmap.hitObjects:
  #       echo typeof hitObject
  #       echo hitObject of Circle
  #     break
  #   except Exception as e:
  #     discard
  #     echo file.path & ": failed"
  #     echo getCurrentExceptionMsg()
  #     echo getStackTrace(e).replace("justin", "rika")
  #     # break
  # let time1 = getMonoTime()
  # echo time1 - time0



  # import npeg
  # type
  #   ParserData = object
  #     tableGroups: Table[string, Table[string, string]]
  #     seqGroups: Table[string, seq[string]]
  #     beatmap: Beatmap
  #     lastSection: string

  # let beatmapParser = peg("beatmap", pd: ParserData):
  #   beatmap <- *blankLine * versionLine * +(*blankLine * (eventSection | timingSection | hitObjectSection | section)) * *blankLine * !1

  #   comment <- *Blank * "//" * +Print
  #   lineEnding <- ?comment * ?'\r' * '\n'
  #   blankLine <- *Blank * lineEnding
  #   word <- +Alpha
  #   integer <- ?'-' * +Digit
  #   decimal <- (?'-' * +Digit * '.' * +Digit | integer)
  #   printNoComma <- +(Print - ',')

  #   versionLine <- "osu file format v" * >integer * lineEnding:
  #     pd.beatmap.formatVersion = parseInt($1)

  #   data <- >(word * ?integer) * ?Blank * ':' * ?Blank * >?(+(utf8.any - '\n')) * lineEnding:
  #     if pd.lastSection notin pd.tableGroups:
  #       pd.tableGroups[pd.lastSection] = initTable[string, string]()
  #     pd.tableGroups[pd.lastSection][$1] = $2
  #   header <- '[' * >word * ']' * lineEnding:
  #     pd.lastSection = $1
  #   section <- header * +(data | blankLine)

  #   eventBg <- "0,0," * ('"' * +Print * '"' | +(Print - ',')) * ',' * integer * ',' * integer * lineEnding
  #   eventVideo <- "Video" | '1' * ',' * integer * ',' * integer * ',' * integer * lineEnding
  #   eventBreak <- "2," * integer * ',' * integer * lineEnding
  #   # NOT ALL EVENTS ARE HERE, GOD THERE ARE SO MANY
  #   eventHeader <- "[Events]" * lineEnding
  #   eventSection <- eventHeader * +(eventBg | eventVideo | eventBreak | blankLine)

  #   timingPoint <- >decimal * ',' * >(?'-' * decimal) * ',' * >integer * ',' * >{'0'..'3'} * ',' * >integer * ',' * >integer * ',' * >{'0', '1'} * ',' * >integer * lineEnding
  #   timingHeader <- "[TimingPoints]" * lineEnding
  #   timingSection <- timingHeader * +(timingPoint | blankLine)

  #   hitSample <- integer * ':' * integer * ':' * integer * ':' * integer * ':' * *Print
  #   #          type       ,    hitSound   ,
  #   circle <- >integer * ',' * integer * ',' * hitSample:
  #     let typ = ($1).parseInt
  #     validate (typ and 0b1) != 0
  #   #          type       ,    hitSound   ,    curveType                 |    curvePoints                   ,    slides     ,    length     ,    edgeSounds                      ,    edgeSets                                                          ,
  #   slider <- >integer * ',' * integer * ',' * {'B', 'C', 'L', 'P'} * *('|' * (integer * ':' * integer)) * ',' * integer * ',' * decimal * ',' * (integer * *('|' * integer)) * ',' * ((integer * ':' * integer) * *('|' * integer * ':' * integer)) * ',' * hitSample:
  #     let typ = ($1).parseInt
  #     validate (typ and 0b10) != 0
  #   #           type       ,    hitSound   ,    endTime    ,
  #   spinner <- >integer * ',' * integer * ',' * integer * ',' * hitSample:
  #     let typ = ($1).parseInt
  #     validate (typ and 0b1000) != 0
  #   hitObject <- integer * ',' * integer * ',' * integer * ',' * (circle | slider | spinner) * lineEnding
  #   hitObjectHeader <- "[HitObjects]" * lineEnding
  #   hitObjectSection <- hitObjectHeader * +(hitObject | blankLine)

  # let time0 = getMonoTime()
  # for file in walkDir("./osulib"):
  #   try:
  #     let data = readFile(file.path)
  #     let beatmap = parseBeatmap(data)
  #     for hitObject in beatmap.hitObjects:
  #       echo typeof hitObject
  #       echo hitObject of Circle
  #     break
  #   except Exception as e:
  #     discard
  #     echo file.path & ": failed"
  #     echo getCurrentExceptionMsg()
  #     echo getStackTrace(e).replace("justin", "rika")
  #     # break
  # let time1 = getMonoTime()
  # echo time1 - time0
