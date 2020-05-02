type
  HitSoundTypes* {.size: sizeof(cint).} = enum
    Normal, Whistle, Finish, Clap
  HitSound* = set[HitSoundTypes]
  SampleSet* = enum
    NoSet = (0, "None")
    NormalSet = "Normal"
    SoftSet = "Soft"
    DrumSet = "Drum"
