import npeg, strutils, tables, times
import npeg/lib/utf8

type
  GeneralData* = object
    audioFilename*: string
    audioLeadIn*: Duration
    previewTime*: Duration
    # countdownSpeed*: CountdownSpeed
    countdownSpeed*: string
    # sampleSet*: SampleSet
    sampleSet*: string
    stackLeniency*: float
    # gameMode*: GameMode
    gameMode*: string
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
    # timingPoints*: ref seq[TimingPoint]
    colors*: seq[string] # TODO: handlers in parseBeatmap
    # hitObjects*: seq[HitObject]

type
  ParserData = object
    tableGroups: Table[string, Table[string, string]]
    seqGroups: Table[string, seq[string]]
    beatmap: Beatmap
    lastSection: string

let beatmapParser = peg("beatmap", pd: ParserData):
  beatmap <- *blankLine * versionLine * +(*blankLine * (eventSection | timingSection | hitObjectSection | section)) * *blankLine * !1

  comment <- *Blank * "//" * +Print
  lineEnding <- ?comment * ?'\r' * '\n'
  blankLine <- *Blank * lineEnding
  word <- +Alpha
  integer <- ?'-' * +Digit
  decimal <- (?'-' * +Digit * '.' * +Digit | integer)
  printNoComma <- +(Print - ',')

  versionLine <- "osu file format v" * >integer * lineEnding:
    pd.beatmap.formatVersion = parseInt($1)

  data <- >(word * ?integer) * ?Blank * ':' * ?Blank * >?(+(utf8.any - '\n')) * lineEnding:
    if pd.lastSection notin pd.tableGroups:
      pd.tableGroups[pd.lastSection] = initTable[string, string]()
    pd.tableGroups[pd.lastSection][$1] = $2
  header <- '[' * >word * ']' * lineEnding:
    pd.lastSection = $1
  section <- header * +(data | blankLine)

  eventBg <- "0,0," * ('"' * +Print * '"' | +(Print - ',')) * ',' * integer * ',' * integer * lineEnding
  eventVideo <- "Video" | '1' * ',' * integer * ',' * integer * ',' * integer * lineEnding
  eventBreak <- "2," * integer * ',' * integer * lineEnding
  # NOT ALL EVENTS ARE HERE, GOD THERE ARE SO MANY
  eventHeader <- "[Events]" * lineEnding
  eventSection <- eventHeader * +(eventBg | eventVideo | eventBreak | blankLine)

  timingPoint <- >decimal * ',' * >(?'-' * decimal) * ',' * >integer * ',' * >{'0'..'3'} * ',' * >integer * ',' * >integer * ',' * >{'0', '1'} * ',' * >integer * lineEnding
  timingHeader <- "[TimingPoints]" * lineEnding
  timingSection <- timingHeader * +(timingPoint | blankLine)

  hitSample <- integer * ':' * integer * ':' * integer * ':' * integer * ':' * *Print
  #          type       ,    hitSound   ,
  circle <- >integer * ',' * integer * ',' * hitSample:
    let typ = ($1).parseInt
    validate (typ and 0b1) != 0
  #          type       ,    hitSound   ,    curveType                 |    curvePoints                   ,    slides     ,    length     ,    edgeSounds                      ,    edgeSets                                                          ,
  slider <- >integer * ',' * integer * ',' * {'B', 'C', 'L', 'P'} * *('|' * (integer * ':' * integer)) * ',' * integer * ',' * decimal * ',' * (integer * *('|' * integer)) * ',' * ((integer * ':' * integer) * *('|' * integer * ':' * integer)) * ',' * hitSample:
    let typ = ($1).parseInt
    validate (typ and 0b10) != 0
  #           type       ,    hitSound   ,    endTime    ,
  spinner <- >integer * ',' * integer * ',' * integer * ',' * hitSample:
    let typ = ($1).parseInt
    validate (typ and 0b1000) != 0
  hitObject <- integer * ',' * integer * ',' * integer * ',' * (circle | slider | spinner) * lineEnding
  hitObjectHeader <- "[HitObjects]" * lineEnding
  hitObjectSection <- hitObjectHeader * +(hitObject | blankLine)

var pd: ParserData
new pd.beatmap
let matches = beatmapParser.matchFile("./sbtest/Yuuka - Girls' Carnival (Shizuku-) [Normal].osu", pd)
doAssert matches.ok
echo pd.beatmap.formatVersion
echo pd.tableGroups
echo matches.captures
