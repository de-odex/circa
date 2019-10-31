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

let
  writeOrder = [
    NoFail,
    Hidden, FadeIn,
    Easy, HardRock,
    HalfTime, DoubleTime,
    SuddenDeath, Perfect,
    Flashlight,
    SpunOut,
    Key1,
    Key2,
    Key3,
    Key4,
    Key5,
    Key6,
    Key7,
    Key8,
    Key9,
  ]
  mod2String = newTable(
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
  mapping = newOrderedTable[string, Mod]()
  flipMapping = newOrderedTable[Mod, string]()
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

for m in writeOrder:
  mapping[mod2String[m]] = m
  flipMapping[m] = mod2String[m]

proc toNum*(m: Mods): int =
  cast[cint](m)

proc toMods*(v: int): Mods =
  cast[Mods](v)

proc parseShortMods*(v: string): Mods =
  for n in countup(0, v.len - 1, 2):
    if v.toLower[n .. n + 1] in mapping:
      result = result + {mapping[v.toLower[n .. n + 1]]}

proc toShortString*(m: Mod): string =
  if m in flipMapping:
    result = flip_mapping[m]

proc toShortString*(ms: Mods): string =
  if ms.len == 0:
    return "nm"

  for m in ms:
    result &= m.toShortString

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc verify*(ms: Mods, gm: GameMode): bool =
  # TODO: add gamemode support
  result = true
  if (Nightcore in ms and DoubleTime notin ms):
    return false

  for s in incompatibleMods:
    if (ms * s).len > 1: return false