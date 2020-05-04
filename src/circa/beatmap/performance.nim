import ../../circa/[beatmap, game_mode, mods]

import math

proc performancePoints*(sbm: ScoredBeatmap): float =
  case sbm.modeBeatmap.gameMode
  of Standard:
    discard

  of Catch:
    let
      stars = 0f # FIXME: star calculation for osu!catch
      maxCombo = sbm.modeBeatmap.maxCombo
      ar = sbm.modeBeatmap.ar
    result = (5 * max(1.0, stars / 0.0049) - 4)^2 / 100000
    result *= 0.95 + 0.4 * min(1.0, max_combo.float / 3000.0) + (block:
      if max_combo > 3000:
        log(max_combo.float / 3000.0, 10) * 0.5
      else:
        0.0
    )
    result *= 0.97 ^ sbm.misses
    result *= pow(sbm.combo / max_combo, 0.8)
    if ar > 9:
      result *= 1 + 0.1 * (ar - 9.0)
    elif ar < 8:
      result *= 1 + 0.025 * (8.0 - ar)
    result *= sbm.accuracy.pow(5.5)

    if Hidden in sbm.modeBeatmap.mods:
      result *= 1.05 + 0.075 * (10.0 - min(10.0, ar))
    elif Flashlight in sbm.modeBeatmap.mods:
      result *= 1.35 * (0.95 + 0.4 * min(1.0, max_combo.float / 3000.0) + (block:
        if max_combo > 3000:
          log(max_combo.float / 3000.0, 10) * 0.5
        else:
          0.0
        )
      )

  of Mania:
    #  Thanks Error- for the formula
    let
      stars = 0f # FIXME: star calculation for osu!mania
      od = sbm.modeBeatmap.od
      object_count = sbm.modeBeatmap.beatmap.hit_objects.len
    var score = sbm.score

    if (KeyMods * sbm.modeBeatmap.mods).len > 0:
      discard
      # score *= beatmap_data.score_multiplier(mods) # TODO: what

    let
      perfect_window = 64 - 3 * od

    # 'Obtain strain difficulty'
    var
      base_strain = pow(5 * max(1.0, stars / 0.2) - 4, 2.2) / 135
    # 'Longer maps are worth more'
    base_strain *= 1 + 0.1 * min(1.0, object_count / 1500)
    base_strain *= (block:
      if score < 500000:
        0f
      elif score < 600000:
        (score - 500000) / 100000 * 0.3
      elif score < 700000:
        (score - 600000) / 100000 * 0.25 + 0.3
      elif score < 800000:
        (score - 700000) / 100000 * 0.2 + 0.55
      elif score < 900000:
        (score - 800000) / 100000 * 0.15 + 0.75
      else:
        (score - 900000) / 100000 * 0.1 + 0.90
    )
    let
      window_factor = max(0.0, 0.2 - ((perfect_window - 34) * 0.006667))
      score_factor = (max(0, score.float - 960000) / 40000).pow(1.1)
      base_acc = window_factor * base_strain * score_factor
      acc_factor = pow(base_acc, 1.1)
      strain_factor = pow(base_strain, 1.1)
    result = pow(acc_factor + strain_factor, 1 / 1.1)
    try:
      if Easy in sbm.modeBeatmap.mods:
        result *= 0.5
      elif NoFail in sbm.modeBeatmap.mods:
        result *= 0.9
      else:
        result *= 0.8
    except:
      result *= 0.8

  of Taiko:
    let
      stars = 0f # FIXME: star calculation for osu!taiko
      od = sbm.modeBeatmap.od
      perfect_hits = (sbm.modeBeatmap.maxCombo - sbm.misses)

      max_od = 20
      min_od = 50
      perfect_window = round((floor(min_od.float + (max_od - min_od).float * od / 10) - 0.5) * 100) / 100

    var
      strain = ((max(1f, stars / 0.0075) * 5 - 4)^2 / 100000) * (min(1f, sbm.maxCombo / 1500) * 0.1 + 1)
    strain *= 0.985 ^ sbm.misses
    strain *= min(perfect_hits.float.pow(0.5) / sbm.modeBeatmap.maxCombo.float.pow(0.5), 1)
    strain *= sbm.accuracy
    var
      acc_factor = (150 / perfect_window).pow(1.1) * sbm.accuracy^15 * 22
    acc_factor *= min(pow(sbm.modeBeatmap.maxCombo.float / 1500, 0.3), 1.15)

    var mod_multiplier = 1.1
    try:
      if Hidden in sbm.modeBeatmap.mods:
        mod_multiplier *= 1.1
        strain *= 1.025
      elif NoFail in sbm.modeBeatmap.mods:
        mod_multiplier *= 0.9
      elif Flashlight in sbm.modeBeatmap.mods:
        strain *= 1.05 * min(1, sbm.modeBeatmap.maxCombo / 1500) * 0.1 + 1
    except:
      discard

    result = (strain.pow(1.1) + acc_factor.pow(1.1)).pow(1 / 1.1) * mod_multiplier
