import strutils, tables

import game_mode, units

type
  Mod* {.size: sizeof(cint).} = enum
    NoFail
    Easy
    TouchDevice
    Hidden
    HardRock
    SuddenDeath
    DoubleTime
    Relax
    HalfTime
    Nightcore # always used with DoubleTime
    Flashlight
    Autoplay
    SpunOut
    Relax2    # Autopilot
    Perfect
    Key4
    Key5
    Key6
    Key7
    Key8
    FadeIn
    Random
    Cinema    # formerly LastMod?
    TargetPractice
    Key9
    KeyCoop   # Key10
    Key1
    Key3
    Key2
    ScoreV2
    Mirror
  Mods* = set[Mod]
  OrderedMods* = seq[Mod]
  HitWindows* = tuple
    hit300: Duration
    hit100: Duration
    hit50: Duration
  ApproachRate* = distinct float
  OverallDifficulty* = distinct float
  CircleSize* = distinct float

const
  KeyMods*: Mods = {Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9, KeyCoop}
  FreeModAllowed*: Mods = {NoFail, Easy, Hidden, HardRock, SuddenDeath,
      Flashlight, FadeIn, Relax, Relax2, SpunOut} + KeyMods
  ScoreIncreaseMods*: Mods = {Hidden, HardRock, DoubleTime, Flashlight, FadeIn}
  ScoreDecreaseMods*: Mods = {Easy, NoFail, HalfTime, SpunOut}
  NoScoreMods*: Mods = {Relax, Relax2, Autoplay}
  DifficultyChangingMods*: Mods = {Easy, HardRock, HalfTime, DoubleTime}

  # taken from https://github.com/circleguard/circlecore/blob/57465bb7d16cce9846de06fcb248a718b3bff7c4/circleguard/enums.py#L249
  writeOrder = [
    Easy, Hidden,
    HalfTime, DoubleTime, Nightcore,
    Flashlight,
    NoFail,
    SuddenDeath, Perfect,
    Relax, Relax2, SpunOut, Autoplay,
    ScoreV2,

    TouchDevice,
    FadeIn, Random, Cinema, TargetPractice,
    Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9, KeyCoop,
    Mirror
  ]
  incompatibleMods = [
    {Easy, HardRock},
    {HalfTime, DoubleTime},
    {Hidden, FadeIn},
    {Flashlight, FadeIn},
    {Relax, Relax2, Autoplay},
    {Relax2, Autoplay, SpunOut},
    {SuddenDeath, Perfect},
    KeyMods,
  ]

let
  mod2ShortString = newTable(
    [
      (NoFail, "nf"),
      (Hidden, "hd"),
      (FadeIn, "fi"),
      (Easy, "ez"),
      (HardRock, "hr"),
      (HalfTime, "ht"),
      (DoubleTime, "dt"),
      (Nightcore, "nc"),
      (SuddenDeath, "sd"),
      (Perfect, "pf"),
      (Flashlight, "fl"),
      (SpunOut, "so"),
      (Relax, "rx"),
      (Relax2, "ap"),
      (Autoplay, "at"),
      (TargetPractice, "tp"),
      (ScoreV2, "v2"),
      (TouchDevice, "td"),
      (Random, "rd"),
      (Cinema, "cn"),
      (Key1, "1k"),
      (Key2, "2k"),
      (Key3, "3k"),
      (Key4, "4k"),
      (Key5, "5k"),
      (Key6, "6k"),
      (Key7, "7k"),
      (Key8, "8k"),
      (Key9, "9k"),
      (KeyCoop, "co"),
      (Mirror, "mr"),
    ]
  )
  shortString2Mod = newOrderedTable[string, Mod]()

for m in writeOrder:
  shortString2Mod[mod2ShortString[m]] = m

proc toInt*(m: Mods): int =
  cast[cint](m)

proc toMods*(v: int): Mods =
  cast[Mods](v)

proc toMods*(oms: OrderedMods): Mods =
  for m in oms:
    result = result + {m}

proc toOrderedMods*(ms: Mods): OrderedMods =
  for m in writeOrder:
    if m in ms:
      result.add(m)

proc decompose*(ms: Mods): Mods

proc parseShortMods*(v: string): Mods =
  for n in countup(0, v.len - 1, 2):
    if v.toLower[n .. n + 1] in shortString2Mod:
      result = result + {shortString2Mod[v.toLower[n .. n + 1]]}

proc toShortString*(m: Mod): string =
  if m in mod2ShortString:
    result = mod2ShortString[m]

proc toShortString*(ms: Mods): string =
  if ms.len == 0:
    return "nm"

  for m in ms.decompose().toOrderedMods():
    result &= m.toShortString

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc verify*(ms: Mods, gm: GameMode = Standard): bool =
  # TODO: add gamemode support
  result = true
  if (Nightcore in ms and DoubleTime notin ms):
    return false

  for s in incompatibleMods:
    if (ms * s).len > 1: return false

proc decompose*(ms: Mods): Mods =
  # inspired by https://github.com/circleguard/circlecore/blob/57465bb7d16cce9846de06fcb248a718b3bff7c4/circleguard/enums.py#L164
  # ONLY REMOVES "DUPLICATE" MODS
  result = ms

  if Nightcore in ms and DoubleTime in ms:
    result = result - {DoubleTime}

  if Perfect in ms and SuddenDeath in ms:
    result = result - {SuddenDeath}


proc toMS*(ar: ApproachRate): Duration =
  if ar.float >= 5:
    result = initDuration(milliseconds = 1950 - ar.float * 150)
  else:
    result = initDuration(milliseconds = 1800 - ar.float * 120)

proc toAR*(dur: Duration): ApproachRate =
  var ar = (dur.inFloatMilliseconds - 1950) / -150
  if ar < 5:
    ar = (dur.inFloatMilliseconds - 1800) / -120
  result = ar.ApproachRate

proc toRadius*(cs: CircleSize): float =
  result = (512 / 16) * (1 - 0.7 * (cs.float - 5) / 5)

proc toMS*(od: OverallDifficulty): HitWindows =
  result = (
    hit_300: initDuration(milliseconds = (159 - 12 * od.float) / 2),
    hit_100: initDuration(milliseconds = (279 - 16 * od.float) / 2),
    hit_50: initDuration(milliseconds = (399 - 20 * od.float) / 2),
  )

proc toMS300*(od: OverallDifficulty): Duration =
  result = initDuration(milliseconds = 79.5 - 6 * od.float)

proc toOD*(dur: Duration): OverallDifficulty =
  result = ((dur.inFloatMilliseconds - 79.5) / -6).OverallDifficulty
