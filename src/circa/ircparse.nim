import strutils
import game_mode, mods

proc toIRCString*(gm: GameMode): string =
  # TODO: "optimize"
  result = case gm:
    of Standard:
      ""
    of Taiko:
      "Taiko"
    of Catch:
      "CatchTheBeat"
    of Mania:
      "osu!mania"

proc IRCtoGameMode*(s: string): GameMode =
  # TODO: "optimize"
  result = case s:
    of "":
      Standard
    of "Taiko":
      Taiko
    of "CatchTheBeat":
      Catch
    of "osu!mania":
      Mania
    else:
      raise newException(Exception, "malformed IRC string for converting to GameMode")

proc toIRCString*(ms: Mods): string =
  var resultSeq: seq[string] = @[]

  for m in ms:
    if m in SCORE_INCREASE_MODS:
      resultSeq.add("+" & $m)
    elif m in SCORE_DECREASE_MODS:
      resultSeq.add("-" & $m)
    elif m in KEYMOD:
      resultSeq.add("|" & m.toShortString & "|")

  result = resultSeq.join(" ")

proc IRCtoMods*(s: string): Mods =
  # TODO: implement
  {}

when isMainModule:
  echo {NoFail, Hidden, HardRock, DoubleTime, Flashlight, SpunOut}.toIRCString
