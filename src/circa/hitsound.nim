type
  HitSoundTypes* {.size: sizeof(cint).} = enum
    Normal, Whistle, Finish, Clap
  HitSound* = set[HitSoundTypes]
  SampleSet* = enum
    AutoSet = 0, NormalSet, SoftSet, DrumSet
