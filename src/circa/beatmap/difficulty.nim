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

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\

import ../../circa/[units, timing, utils, beatmap, beatmap/hit_objects]

import sequtils, math, algorithm, tables, sugar

import itertools, arraymancer

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

proc linspace(start, stop: SomeNumber, num: int, endpoint: bool = true): seq[float] =
  # LMAO maybe don't use this
  # desperate men use desperately hacked up algorithms
  let times = if endpoint:
    num - 1
  else:
    num

  let delta = (stop - start) / times.float
  var current: float = start.float

  while not (current ~= stop.float) and (if stop > start: current < stop.float else: current > stop.float):
    result.add current
    current += delta

  if endpoint:
    result.add current

  assert result.len == num

proc searchSorted[T](x: openarray[T], value: T, leftSide: static bool = true): int =
  ## Returns the index corresponding to where the input value would be inserted at.
  ## Input must be a sorted 1D seq/array.
  ## In case of exact match, leftSide indicates if we put the value
  ## on the left or the right of the exact match.
  ##
  ## This is equivalent to Numpy and Tensorflow searchsorted
  ## Example
  ##    [0, 3, 9, 9, 10] with value 4 will return 2
  ##    [1, 2, 3, 4, 5]             2 will return 1 if left side, 2 otherwise
  #
  # Note: this will have a proper and faster implementation for tensors in the future

  when leftSide:
    result = x.lowerBound(value)
  else:
    result = x.upperBound(value)

proc searchSorted[T](x: openarray[T], value: openarray[T], leftSide: static bool = true): seq[int] =
  value.mapIt(x.searchSorted(it, leftSide))

proc mapAt[T](
    a: Tensor[T],
    op: proc(a, b: Tensor[T]): Tensor[T],
    indices: seq[seq[int]]
  ): Tensor[T] =
  result = newTensor[T](indices.len, 1)
  for idx, val in indices:
    var val = val
    if val.len == 1:
      val.add a.shape[0]

    if val[0] >= val[1]:
      discard a[val[0]]
    else:
      result[idx, _] = a[val[0]..<val[1]].reduce(op, 0)

proc movingAverageByTime(
    times: Tensor[float],
    data: Tensor[float],
    delta: float,
    num: int
  ): (Tensor[float], Tensor[float]) =
  ## Take the moving average of some values and sample it at regular
  ## frequencies.
  ## Parameters
  ## ----------
  ## times : np.ndarray
  ##     The array of times to use in the average.
  ## data : np.ndarray
  ##     The array of values to take the average of. Each column is averaged
  ##     independently.
  ## delta : int or float
  ##     The length of the leading and trailing window in seconds
  ## num : int
  ##     The number of samples to take.
  ## Returns
  ## -------
  ## times : np.ndarray
  ##     A column vector of the times sampled at.
  ## averages : np.ndarray
  ##     A column array of the averages. 1 column per column in the input

  # take an even sample from 0 to the end time
  let
    outTimes = linspace(
      times[0, 0],
      times[len(toSeq(times))-1, 0],
      num
    ).mapIt(it.floor).toTensor
    delta = delta * 1e9

    # compute the start and stop indices for each sampled window
    windowStartIxs = searchSorted(toSeq(times[_, 0]), outTimes.mapIt(it - delta))
    windowStopIxs = searchSorted(toSeq(times[_, 0]), outTimes.mapIt(it + delta))

    # a 2d array of shape ``(num, 2)`` where each row holds the start and stop
    # index for the window
    # NOTE: basically zip
    windowIxs = stack(windowStartIxs.toTensor, windowStopIxs.toTensor, 1)

    # append a nan to the end of the values so that we can do many slices all
    # the way to the end in reduceat
    values = concat(data, [NaN].repeat(data.shape[1]).toTensor, 0)

    # sum the values in the ranges ``[windowStartIxs, windowStopIxs)``
    windowSums = values.mapAt(arraymancer.`+`, toSeq(chunked(toSeq(windowIxs), 2)))

    windowSizes = block:
      var tempWindowSizes = block:
        var tempTensor = newTensor[float](windowIxs.shape[0], 1)
        for idx in 0..<windowIxs.shape[0]:
          tempTensor[idx, 0] = windowIxs[idx, 1].float - windowIxs[idx, 0].float
        tempTensor
      # convert windowSizes of 0 to 1 (inplace) to prevent division by zero
      tempWindowSizes.applyInline(if x < 1: 1f else: x)
      tempWindowSizes

    outValues = concat(windowSums ./ windowSizes.reshape(windowSizes.shape[0], 1), 0)

  (outTimes.reshape(outTimes.shape[0], 1), outValues)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

type
  SkillKind = enum
    standardSpeed
    standardAim

    catchMovement

    maniaIndividual
    maniaOverall

    taikoStrain

  Skill = object
    usedDifficultyHitObjects*: seq[DifficultyHitObject]
    currentStrain*: float
    currentSectionPeak*: float
    strainPeaks*: seq[float]
    case kind: SkillKind
    of standardSpeed:
      discard
    of standardAim:
      discard
    of catchMovement:
      lastPlayerPosition*: Option[float]
      lastDistanceMoved*: float
    of maniaIndividual:
      holdEndTimesI: seq[Duration]
      column*: int
    of maniaOverall:
      holdEndTimesO: seq[Duration]
      columnCount*: int
    of taikoStrain:
      discard

  DifficultyHitObject = object
    modeHitObject: ModeHitObject
    lastModeHitObject: ModeHitObject
    # here, i'd like mode to base on modeHitObject's gameMode
    case pGameMode: GameMode
    of Standard: discard
    of Catch:
      normalizedPosition: float
      lastNormalizedPosition: float
      strainTime: float
    of Mania: discard
    of Taiko: discard
  # DifficultyHitObject = ref object of RootObj
  #   modeHitObject: ModeHitObject
  #   lastModeHitObject: ModeHitObject
  # StandardDifficultyHitObject = ref object of DifficultyHitObject
  # CatchDifficultyHitObject = ref object of DifficultyHitObject
  #   normalizedPosition: float
  #   lastNormalizedPosition: float
  #   strainTime: float
  # ManiaDifficultyHitObject = ref object of DifficultyHitObject
  # TaikoDifficultyHitObject = ref object of DifficultyHitObject

proc holdEndTimes*(skill: Skill): seq[Duration] =
  case skill.kind
  of maniaIndividual:
    skill.holdEndTimesI
  of maniaOverall:
    skill.holdEndTimesO
  else:
    raise newException(ValueError, "")
    # {.fatal: "undeclared field: holdEndTimes for type Skill".}

proc holdEndTimes*(skill: var Skill): var seq[Duration] =
  case skill.kind
  of maniaIndividual:
    result = skill.holdEndTimesI
  of maniaOverall:
    result = skill.holdEndTimesO
  else:
    raise newException(ValueError, "")
    # {.fatal: "undeclared field: holdEndTimes for type Skill".}

  # ─── CONSTS ─────────────────────────────────────────────────────────────────────

const
  strainStep = initDuration(milliseconds = 400)

  # TODO: Figure what game mode these values are used for
  almostDiameter = 90
  streamSpacing = 110
  singleSpacing = 125
  circleSizeBufferThreshold = 30
  starScalingFactor = 0.0675
  extremeScalingFactor = 0.5

  # osu!catch
  absolutePlayerPositioningError = 16.0
  normalizedHitobjectRadius = 41.0
  directionChangeBonus = 12.5

# NOTE: ensure that hit objects are already modified by mods
proc initDifficultyHitObject(current, last: ModeHitObject): DifficultyHitObject =
  result = DifficultyHitObject(pGameMode: current.gameMode)
  result.modeHitObject = current
  result.lastModeHitObject = last
  if result.modeHitObject.gameMode != result.lastModeHitObject.gameMode:
    raise newException(CatchableError, "") # TODO: proper "NotImpl." error

proc initCatchDifficultyHitObject(current, last: ModeHitObject, halfCatcherWidth: float): DifficultyHitObject =
  result = initDifficultyHitObject(current, last)
  # We will scale everything by this factor, so we can assume a uniform CircleSize among beatmaps.
  var scalingFactor = normalizedHitobjectRadius / halfCatcherWidth

  # CatchPlayfield.BASE_WIDTH == 512

  result.normalizedPosition = result.modeHitObject.hitObject.position.x * 512 * scalingFactor
  result.lastNormalizedPosition = result.lastModeHitObject.hitObject.position.x * 512 * scalingFactor

  # Every strain interval is hard capped at the equivalent of 600 BPM streaming speed as a safety measure
  result.strainTime = max(25, (current.hitObject.startTime - last.hitObject.startTime).inFloatMilliseconds)

proc initManiaDifficultyHitObject(current, last: ModeHitObject): DifficultyHitObject =
  initDifficultyHitObject(current, last)

template decayBase(skill: Skill): float =
  case skill.kind
  of standardSpeed:
    0.3
  of standardAim:
    0.15
  of catchMovement:
    0.2
  of maniaIndividual:
    0.125
  of maniaOverall:
    0.15
  of taikoStrain:
    0.3

template decayWeight(skill: Skill): float =
  case skill.kind
  of catchMovement:
    0.94
  else:
    0.9

template weightScaling(skill: Skill): float =
  case skill.kind
  of standardSpeed:
    1400f
  of standardAim:
    26.25
  of catchMovement:
    850
  else:
    1

template strainDecay(skill: Skill, ms: float): float =
  pow(skill.decayBase, ms / 1000)

proc strainValueOf(skill: var Skill, dho: DifficultyHitObject): float =
  case skill.kind

  of catchMovement:
    if dho.pGameMode != Catch:
      raise newException(CatchableError, "") # TODO: proper "NotImpl." error
    let last = dho.lastModeHitObject
    if skill.lastPlayerPosition.isNone:
      skill.lastPlayerPosition = some(dho.lastNormalizedPosition)

    var playerPosition = clamp(
      skill.lastPlayerPosition.get(),
      dho.normalizedPosition - (normalizedHitobjectRadius - absolutePlayerPositioningError),
      dho.normalizedPosition + (normalizedHitobjectRadius - absolutePlayerPositioningError)
    )

    var distanceMoved = playerPosition - skill.lastPlayerPosition.get()

    var distanceAddition = pow(abs(distanceMoved), 1.3) / 500
    var sqrtStrain = sqrt(dho.strainTime)

    var bonus = 0f

    # Direction changes give an extra point!
    if abs(distanceMoved) > 0.1:

      if abs(skill.lastDistanceMoved) > 0.1 and sgn(distanceMoved) != sgn(skill.lastDistanceMoved):
        let bonusFactor = min(absolutePlayerPositioningError, abs(distanceMoved)) / absolutePlayerPositioningError

        distanceAddition += directionChangeBonus / sqrtStrain * bonusFactor

        # Bonus for tougher direction switches and "almost" hyperdashes at this point
        if last.distanceToHyperDash <= 10 / 512:
          bonus = 0.3 * bonusFactor

      # Base bonus for every movement, giving some weight to streams.
      distanceAddition += 7.5 * min(abs(distanceMoved), normalizedHitobjectRadius * 2) / (normalized_hitobject_radius * 6) / sqrtStrain

    # Bonus for "almost" hyperdashes at corner points
    if last.distanceToHyperDash <= 10 / 512:
      if not last.hyperDash:
        bonus += 1.0
      else:
        # After a hyperdash we ARE in the correct position. Always!
        playerPosition = dho.normalizedPosition

      distanceAddition *= 1.0 + bonus * ((10 - last.distanceToHyperDash * 512) / 10)

    skill.lastPlayerPosition = some(playerPosition)
    skill.lastDistanceMoved = distanceMoved

    return distanceAddition / dho.strainTime

  of maniaIndividual:
    if dho.pGameMode != Mania:
      raise newException(CatchableError, "") # TODO: proper "NotImpl." error
    let current = dho.modeHitObject
    let endTime = current.hitObject.endTime

    if current.column != skill.column:
      return 0

    result = if skill.holdEndTimes.anyIt(it > endTime): 2.5 else: 2
    skill.holdEndTimes[current.column] = endTime

  of maniaOverall:
    if dho.pGameMode != Mania:
      raise newException(CatchableError, "") # TODO: proper "NotImpl." error
    let current = dho.modeHitObject
    let endTime = current.hitObject.endTime

    # Factor in case something else is held
    var holdFactor = 1f
    # Addition to the current note in case it's a hold and has to be released awkwardly
    var holdAddition = 0f

    for i in 0..skill.columnCount:
      # If there is at least one other overlapping end or note, then we get an addition, buuuuuut...
      if current.hitObject.startTime < skill.holdEndTimes[i] and endTime > skill.holdEndTimes[i]:
        holdAddition = 1

      # ... this addition only is valid if there is _no_ other note with the same ending.
      # Releasing multiple notes at the same time is just as easy as releasing one
      if endTime == skill.holdEndTimes[i]:
        holdAddition = 0

      # We give a slight bonus if something is held meanwhile
      if skill.holdEndTimes[i] > endTime:
        holdFactor = 1.25

  else:
    raise newException(CatchableError, "no implementation") # TODO: proper "NotImpl." error

proc process(skill: var Skill, dho: DifficultyHitObject) =
  ## Process a DifficultyHitObject and update current strain values accordingly.
  skill.currentStrain *= skill.strainDecay(inFloatMilliseconds(dho.modeHitObject.hitObject.startTime - dho.lastModeHitObject.hitObject.startTime))
  skill.currentStrain += skill.strainValueOf(dho) * skill.weightScaling

  skill.currentSectionPeak = max(skill.currentStrain, skill.currentSectionPeak)

  skill.usedDifficultyHitObjects.add(dho)

proc saveCurrentPeak(skill: var Skill) =
  ## Saves the current peak strain level to the list of strain peaks,
  ## which will be used to calculate an overall difficulty.
  if skill.usedDifficultyHitObjects.len > 0:
    skill.strainPeaks.add(skill.currentSectionPeak)

proc startNewSectionFrom(skill: var Skill, offset: float) =
  ## Sets the initial strain level for a new section.
  ## offset: The beginning of the new section in milliseconds.
  # The maximum strain of the new section is not zero by default,
  # strain decays as usual regardless of section boundaries.
  # This means we need to capture the strain level
  # at the beginning of the new section, and use that as the initial peak level.
  if skill.usedDifficultyHitObjects.len > 0:
    skill.currentSectionPeak = skill.currentStrain *
      skill.strainDecay(
        offset - skill.usedDifficultyHitObjects[0].modeHitObject.hitObject.startTime.inFloatMilliseconds
      )

proc flattenOnce[T](a: seq[seq[T]]): seq[T] =
  for b in a:
    for c in b:
      result.add c

# TODO: base on a DifficultyCalculator object to fix...
proc createDifficultyHitObjects(mbm: ModeBeatmap): seq[DifficultyHitObject] =
  discard
  case mbm.gameMode

  of Catch:
    var lastObject: Option[ModeHitObject]
    # In 2B beatmaps, it is possible that a normal Fruit is placed in the middle of a JuiceStream.
    for hitObject in mbm.modeHitObjects.mapIt(if it.catchKind == JuiceStream: it.nestedHitObjects else: @[it]).flattenOnce: # FIXME: no resort done
      if (hitObject.catchKind == BananaShower or (hitObject.catchKind == Droplet and hitObject.isTiny)):
        continue

      if lastObject.isSome:
        result.add initCatchDifficultyHitObject(hitObject, lastObject.get(), halfCatcherWidth) #... this error with halfCatcherWidth undefined

      lastObject = some hitObject

  else:
    raise newException(CatchableError, "") # TODO: proper "NotImpl." error

proc difficultyValue(skill: Skill): float =
  ## Returns the calculated difficulty value
  ## representing all processed DifficultyHitObjects.
  var
    difficulty = 0f
    weight = 1f

  # Difficulty is the weighted sum of the highest strains from every section.
  # We're sorting from highest to lowest strain.
  for strain in skill.strainPeaks.sorted(order = Descending):
    difficulty += strain * weight
    weight *= skill.decayWeight

  return difficulty

proc starRating*(sbm: ModeBeatmap, skills: seq[Skill]): float =
  case sbm.gameMode
  of Catch:
    sqrt(skills[0].difficultyValue()) * 0.145
  else:
    0

#
# ──────────────────────────────────────────────────────────────── I ──────────
#   :::::: C A L C U L A T I O N S : :  :   :    :     :        :          :
# ──────────────────────────────────────────────────────────────────────────
#

# ─── OSU!STANDARD ───────────────────────────────────────────────────────────────

proc baseStrain(strain: float): float =
  ((5 * max(1, strain / 0.0675) - 4) ^ 3) / 100000

iterator handleGroup(group: seq[Duration]): float =
  let inner = 1..<group.len
  for n in 0..<group.len:
    for m in inner:
      if n == m:
        continue

      let a = group[n]
      let b = group[m]

      let ratio = if a > b:
        a.inFloatMilliseconds / b.inFloatMilliseconds
      else:
        b.inFloatMilliseconds / a.inFloatMilliseconds

      let closestPowerOfTwo = 2.pow round(log2(ratio))
      let offset = (
          abs(closestPowerOfTwo - ratio) /
          closestPowerOfTwo
      )
      yield offset ^ 2

# proc calculateDifficulty(self: ScoredBeatmap, strain, difficulty_hit_objects): float =
#   highest_strains = []
#   append_highest_strain = highest_strains.append

#   var
#     strain_step = strain_step
#     interval_end = strain_step
#     max_strain = 0

#   usedDifficultyHitObjects = None
#   for difficulty_hit_object in difficulty_hit_objects:
#       while difficulty_hit_object.hit_object.time > interval_end:
#           append_highest_strain(max_strain)

#           if usedDifficultyHitObjects is None:
#               max_strain = 0
#           else:
#               decay = (
#                   _DifficultyHitObject.decay_base[strain] ** (
#                       interval_end -
#                       usedDifficultyHitObjects.hit_object.time
#                   ).total_seconds()
#               )
#               max_strain = usedDifficultyHitObjects.strains[strain] * decay

#           interval_end += strain_step

#       max_strain = max(max_strain, difficulty_hit_object.strains[strain])
#       usedDifficultyHitObjects = difficulty_hit_object

#   difficulty = 0
#   weight = 1

#   decay_weight = self._decay_weight
#   for strain in sorted(highest_strains, reverse=True):
#       difficulty += weight * strain
#       weight *= decay_weight

#   return difficulty

# ────────────────────────────────────────────────────────────────────────────────

