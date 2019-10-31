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
    hit_300: Duration
    hit_100: Duration
    hit_50: Duration
  ApproachRate* = float
  OverallDifficulty* = float
  CircleSize* = float

const
  KEYMOD*: Mods = {Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9, KeyCoop}
  FREE_MOD_ALLOWED*: Mods = {NoFail, Easy, Hidden, HardRock, SuddenDeath,
      Flashlight, FadeIn, Relax, Relax2, SpunOut} + KeyMod
  SCORE_INCREASE_MODS*: Mods = {Hidden, HardRock, DoubleTime, Flashlight, FadeIn}
  SCORE_DECREASE_MODS*: Mods = {Easy, NoFail, HalfTime, SpunOut}
  NO_SCORE_MODS*: Mods = {Relax, Relax2, Autoplay}
  DIFFICULTY_CHANGING_MODS*: Mods = {Easy, HardRock, HalfTime, DoubleTime}

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
    KEYMOD,
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
      (SuddenDeath, "sd"),
      (Perfect, "pf"),
      (Flashlight, "fl"),
      (SpunOut, "so"),
      (Key1, "1k"),
      (Key2, "2k"),
      (Key3, "3k"),
      (Key4, "4k"),
      (Key5, "5k"),
      (Key6, "6k"),
      (Key7, "7k"),
      (Key8, "8k"),
      (Key9, "9k"),
    ]
  )
  shortString2Mod = newOrderedTable[string, Mod]()

for m in writeOrder:
  shortString2Mod[mod2ShortString[m]] = m

proc toNum*(m: Mods): int =
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

  for m in ms.toOrderedMods():
    result &= m.toShortString

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc verify*(ms: Mods, gm: GameMode): bool =
  # TODO: add gamemode support
  result = true
  if (Nightcore in ms and DoubleTime notin ms):
    return false

  for s in incompatibleMods:
    if (ms * s).len > 1: return false
