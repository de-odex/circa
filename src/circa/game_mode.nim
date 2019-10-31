import strutils

type GameMode* = enum
  ## The various game modes in osu!.
  Standard, Taiko, Catch, Mania

proc parseGameMode*(s: string): GameMode =
  result = case s.toLower():
    of "standard", "std", "osu", "o", "0":
      Standard
    of "taiko", "t", "1":
      Taiko
    of "catch", "ctb", "c", "2":
      Catch
    of "mania", "m", "3":
      Mania
    else:
      Standard

proc toNum*(gm: GameMode): int =
  cast[cint](gm)

proc toGameMode*(i: int): GameMode =
  cast[GameMode](i)


