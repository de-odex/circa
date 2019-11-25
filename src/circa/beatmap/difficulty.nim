import ../../circa/game_mode

proc accuracy*(gm: GameMode,
    count300: int = 0,
    count100: int = 0,
    count50: int = 0,
    countGeki: int = 0,
    countKatu: int = 0,
    countMiss: int = 1): float =

  var
    pointsOfHits: int
    totalHits: int
  case gm:
    of Standard:
      pointsOfHits = count300 * 300 + count100 * 100 + count50 * 50
      totalHits = (count300 + count100 + count50 + countMiss)
    of Taiko:
      pointsOfHits = count300 * 300 + count100 * 150
      totalHits = count300 + count100 + countMiss
    of Catch:
      pointsOfHits = (count300 + count100 + count50) * 300
      totalHits = count300 + count100 + count50 + countMiss + countKatu
    of Mania:
      pointsOfHits = ((countGeki + count300) * 300 + countKatu * 200 + count100 * 100 + count50 * 50)
      totalHits = (countGeki + count300 + countKatu + count100 + count50)

  return pointsOfHits / (totalHits * 300)
