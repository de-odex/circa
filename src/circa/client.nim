import game_mode, mods, utils, units, library, beatmap, game_mode

import json, tables, strutils, strformat, sequtils, md5, httpclient, uri, httpcore

type
  ApprovedState = enum
    ## The state of a beatmap's approval.
    asGraveyard = -2
    asWip = -1
    asPending = 0
    asRanked = 1
    asApproved = 2
    asQualified = 3
    asLoved = 4

  Genre = enum
    ## The genres that appear on the osu! website.
    gAny = 0
    gUnspecified = 1
    gVideoGame = 2
    gAnime = 3
    gRock = 4
    gPop = 5
    gOther = 6
    gNovelty = 7
    # note: there is no 8
    gHipHop = 9
    gElectronic = 10

  Language = enum
    ## The languages that appear on the osu! website.
    lAny = 0
    lOther = 1
    lEnglish = 2
    lJapanese = 3
    lChinese = 4
    lInstrumental = 5
    lKorean = 6
    lFrench = 7
    lGerman = 8
    lSwedish = 9
    lSpanish = 10
    lItalian = 11

  # snake case is used as to make converting from json easy via the to() macro
  # everywhere else will be using camel case
  BeatmapResult = object    ## A beatmap as represented by the osu! API.
    library: Library        ## The library used to store the Beatmap object.
    beatmap: Option[Beatmap]
    title: string           ## The beatmap's title.
    version: string         ## The beatmap's version.
    beatmap_id: int         ## The beatmap_id.
    approved: ApprovedState ## The state of the beatmap's approved.
    approved_date: DateTime ## The date when this map was approved.
    last_update: DateTime   ## The last date when this map was updated.
    star_rating: float      ## The star rating for the song.
    hit_length: Duration    ## The amount of time from the first element to the last, not counting breaks.
    genre: Genre            ## The genre that appears on the osu! website.
    language: Language      ## The language that appears on the osu! website.
    total_length: Duration  ## The amount of time from the first element to the last, counting breaks.
    beatmap_md5: string     ## The md5 hash of the beatmap.
    favourite_count: int    ## The number of times the beatmap has been favorited.
    play_count: int         ## The number of times this beatmap has been played.
    pass_count: int         ## The number of times this beatmap has been passed.
    max_combo: int          ## The maximum combo that could be achieved on this beatmap.

  UserEvent = object     ## Recent events for a user.
    library: Library     ## The library used to store the Beatmap object.
    beatmap: Option[Beatmap]
    display_html: string ## The html to display on the osu! site.
    beatmap_id: int      ## The beatmap_id of the event.
    beatmapset_id: int   ## The beatmapset_id of the event.
    date: DateTime       ## The date of the event.
    epic_factor: int     ## How epic was this event.

  # clients in returned objects don't make sense in Nim
  User = object            ## Information about an osu! user.
    user_id: int           ## The user id.
    user_name: string      ## The user name.
    count_300: int         ## The total number of 300s ever hit.
    count_100: int         ## The total number of 100s ever hit.
    count_50: int          ## The total number of 50s ever hit.
    play_count: int        ## The total number of plays.
    ranked_score: int      ## The user's ranked score.
    total_score: int       ## The user's total score.
    pp_rank: int           ## The user's rank with the PP system.
    level: float           ## The user's level.
    pp_raw: float          ## The user's total unweighted PP.
    accuracy: float        ## The user's ranked accuracy.
    count_ss: int          ## The number of SSs scored.
    count_s: int           ## The number of Ss scored.
    count_a: int           ## The number of As scored.
    country: string        ## The country code for the user's home country.
    pp_country_rank: int   ## The user's rank with the PP system limited to other players in their country.
    events: seq[UserEvent] ## Recent user events.
    game_mode: GameMode    ## The game mode the user information is for.

  HighScore = object ## A high score for a user or beatmap.
    library: Library
    beatmap: Option[Beatmap]
    user: Option[User]
    beatmap_id: int  ## The beatmap_id of the map this is a score for.
    score: int       ## The score earned in this high score.
    max_combo: int   ## The max combo.
    count_300: int   ## The number of 300s in the high score.
    count_100: int   ## The number of 100s in the high score.
    count_50: int    ## The number of 50s in the high score.
    count_miss: int  ## The number of misses in the high score.
    count_katu: int  ## The number of katu in the high score.
    count_geki: int  ## The number of geki in the high score.
    perfect: bool    ## Did the user fc the map?
    mods: Mods       ## The mods used.
    user_id: int     ## The id of the user who earned this high score.
    rank: string     ## The letter rank earned. A suffix ``H`` means hidden or flashlight was used, like a silver S(S).
    pp: float        ## The unweighted PP earned for this high score.

  UnknownBeatmapError = object of ValueError

  # Client[T: HttpClient or AsyncHttpClient] = object ## A client for interacting with the osu! rest API.
  #   httpClient: T
  #   library: Library                                ## The library used to look up or cache beatmap objects.
  #   apiKey: string                                  ## The api key to use.
  #   apiUrl: string                                  ## The api url to use.

  Client = ref object ## A client for interacting with the osu! rest API.
    httpClient: HttpClient
    library: Library  ## The library used to look up or cache beatmap objects.
    apiKey: string    ## The api key to use.
    apiUrl*: string   ## The api url to use.

  # these are done for me to not duplicate functionality everywhere
  UserIdentifierKind = enum
    uikUserName, uikUserId
  UserIdentifier = object
    case kind: UserIdentifierKind
    of uikUserName:
      userName: string
    of uikUserId:
      userId: int
  BeatmapIdentifierKind = enum
    bikBeatmapSetId, bikBeatmapId, bikBeatmapMd5
  BeatmapIdentifier = object
    case kind: BeatmapIdentifierKind
    of bikBeatmapSetId:
      beatmapSetId: int
    of bikBeatmapId:
      beatmapId: int
    of bikBeatmapMd5:
      beatmapMd5: string

const DefaultApiUrl = "https://osu.ppy.sh/api"

proc beatmap(self: var BeatmapResult or var UserEvent or var HighScore, save = false): Beatmap =
  ## Lookup the associated beatmap object.
  result = self.beatmap
  withSome result:
    some beatmap:
      return beatmap
    none:
      self.beatmap = self.library.lookup(
        self.beatmapId,
        download = true,
        shouldSave = save,
      )
      return self.beatmap

# proc initBeatmapResult(
#     library: Library,
#     title: string,
#     version: string,
#     beatmapId: int,
#     approved: ApprovedState,
#     approvedDate: DateTime,
#     lastUpdate: DateTime,
#     starRating: float,
#     hitLength: Duration,
#     genre: Genre,
#     language: Language,
#     totalLength: Duration,
#     beatmapMd5: string,
#     favouriteCount: int,
#     playCount: int,
#     passCount: int,
#     maxCombo: int
#   ): BeatmapResult =
#   BeatmapResult(
#     library: library,
#     beatmap: none Beatmap,

#     title: title,
#     version: version,
#     beatmapId: beatmapId,
#     approved: approved,
#     approvedDate: approvedDate,
#     lastUpdate: lastUpdate,
#     starRating: starRating,
#     hitLength: hitLength,
#     genre: genre,
#     language: language,
#     totalLength: totalLength,
#     beatmapMd5: beatmapMd5,
#     favouriteCount: favouriteCount,
#     playCount: playCount,
#     passCount: passCount,
#     maxCombo: maxCombo
#   )

# proc initUserEvent(
#     library: Library,
#     displayHtml: string,
#     beatmapId: int,
#     beatmapsetId: int,
#     date: DateTime,
#     epicFactor: int
#   ): UserEvent =
#   UserEvent(
#     library: library,

#     displayHtml: displayHtml,
#     beatmapId: beatmapId,
#     beatmapsetId: beatmapsetId,
#     date: date,
#     epicFactor: epicFactor
#   )

# proc initUser(
#     client: Client,
#     userId: int,
#     userName: string,
#     count300: int,
#     count100: int,
#     count50: int,
#     playCount: int,
#     rankedScore: int,
#     totalScore: int,
#     ppRank: int,
#     level: float,
#     ppRaw: float,
#     accuracy: float,
#     countSs: int,
#     countS: int,
#     countA: int,
#     country: string,
#     ppCountryRank: int,
#     events: seq[UserEvent],
#     gameMode: GameMode
#   ): User =
#   User(
#     userId: userId,
#     userName: userName,
#     count300: count300,
#     count100: count100,
#     count50: count50,
#     playCount: playCount,
#     rankedScore: rankedScore,
#     totalScore: totalScore,
#     ppRank: ppRank,
#     level: level,
#     ppRaw: ppRaw,
#     accuracy: accuracy,
#     countSs: countSs,
#     countS: countS,
#     countA: countA,
#     country: country,
#     ppCountryRank: ppCountryRank,
#     events: events,
#     gameMode: gameMode
#   )

# proc initHighScore(
#     client: Client,
#     beatmapId: int,
#     score: int,
#     maxCombo: int,
#     count300: int,
#     count100: int,
#     count50: int,
#     countMiss: int,
#     countKatu: int,
#     countGeki: int,
#     perfect: bool,
#     mods: Mods,
#     userId: int,
#     rank: string,
#     pp: float,
#     user: Option[User] = none User
#   ): HighScore =
#   HighScore(
#     library: client.library,
#     beatmap: none Beatmap,
#     user: user,

#     beatmapId: beatmapId,
#     score: score,
#     maxCombo: maxCombo,
#     count300: count300,
#     count100: count100,
#     count50: count50,
#     countMiss: countMiss,
#     countKatu: countKatu,
#     countGeki: countGeki,
#     perfect: perfect,
#     mods: mods,
#     userId: userId,
#     rank: rank,
#     pp: pp
#   )

proc initClient(
    httpClient: HttpClient,
    library: Library,
    apiKey: string,
    apiUrl: string = DefaultApiUrl
  ): Client =
  Client(
    httpClient: httpClient,
    library: library,
    apiKey: apiKey,
    apiUrl: apiUrl
  )

proc initClient(
    library: Library,
    apiKey: string,
    apiUrl: string = DefaultApiUrl
  ): Client =
  initClient(
    newHttpClient(),
    library,
    apiKey,
    apiUrl
  )
proc userName(userName: string): UserIdentifier =
  UserIdentifier(kind: uikUserName, userName: userName)
proc userId(userId: int): UserIdentifier =
  UserIdentifier(kind: uikUserId, userId: userId)

proc combine(a: var seq[(string, string)], ui: UserIdentifier) =
  case ui.kind
  of uikUserName:
    a["u"] = $ui.userName
    a["type"] = $"string"
  of uikUserId:
    a["u"] = $ui.userId
    a["type"] = $"id"

proc combine(a: seq[(string, string)], ui: UserIdentifier): seq[(string, string)] =
  result = a
  result.combine ui

proc beatmapSetId(beatmapSetId: int): BeatmapIdentifier =
  BeatmapIdentifier(kind: bikBeatmapSetId, beatmapSetId: beatmapSetId)
proc beatmapId(beatmapId: int): BeatmapIdentifier =
  BeatmapIdentifier(kind: bikBeatmapId, beatmapId: beatmapId)
proc beatmapMd5(beatmapMd5: string): BeatmapIdentifier =
  BeatmapIdentifier(kind: bikBeatmapMd5, beatmapMd5: beatmapMd5)
proc beatmapMd5(beatmapMd5: Md5Digest): BeatmapIdentifier =
  BeatmapIdentifier(kind: bikBeatmapMd5, beatmapMd5: $beatmapMd5)

proc combine(a: var seq[(string, string)], bi: BeatmapIdentifier) =
  case bi.kind
  of bikBeatmapSetId:
    a["s"] = $bi.beatmapSetId
  of bikBeatmapId:
    a["b"] = $bi.beatmapId
  of bikBeatmapMd5:
    a["h"] = $bi.beatmapMd5

proc combine(a: seq[(string, string)], bi: BeatmapIdentifier): seq[(string, string)] =
  result = a
  result.combine bi

# differences in the osu! api names and circa's names
let userEventAliases = static:
  {
    "epicfactor": "epic_factor",
  }.toTable

let beatmapAliases = static:
  {
    "beatmapset_id": "beatmap_set_id",
    "difficultyrating": "star_rating",
    "diff_size": "circle_size",
    "diff_overall": "overall_difficulty",
    "diff_approach": "approach_rate",
    "diff_drain": "health_drain",
    "genre_id": "genre",
    "language_id": "language",
    "file_md5": "beatmap_md5",
    "playcount": "play_count",
    "passcount": "pass_count",
  }.toTable

let userAliases = static:
  {
    "username": "user_name",
    "count300": "count_300",
    "count100": "count_100",
    "count50": "count_50",
    "playcount": "play_count",
    "count_rank_ss": "count_ss",
    "count_rank_s": "count_s",
    "count_rank_a": "count_a",
  }.toTable

let highScoreAliases = static:
  {
    "username": "user_name",
    "maxcombo": "max_combo",
    "count300": "count_300",
    "count100": "count_100",
    "count50": "count_50",
    "countmiss": "count_miss",
    "countkatu": "count_katu",
    "countgeki": "count_geki",
    "enabled_mods": "mods",
  }.toTable

proc initFromJson(dst: var Library; jsonNode: JsonNode; jsonPath: var string) =
  discard # ignore

proc initFromJson(dst: var Beatmap; jsonNode: JsonNode; jsonPath: var string) =
  discard # ignore

proc initFromJson(dst: var Option[Beatmap]; jsonNode: JsonNode; jsonPath: var string) =
  discard # ignore

proc initFromJson(dst: var GameMode; jsonNode: JsonNode; jsonPath: var string) =
  discard # ignore

proc initFromJson(dst: var DateTime; jsonNode: JsonNode; jsonPath: var string) =
  dst = jsonNode.getStr.parse("yyyy-MM-dd hh:mm:ss")

proc initFromJson(dst: var Duration; jsonNode: JsonNode; jsonPath: var string) =
  dst = initDuration(seconds = jsonNode.getStr.parseInt())

proc initFromJson(dst: var Mods; jsonNode: JsonNode; jsonPath: var string) =
  dst = cast[Mods](jsonNode.getInt)

proc initFromJson[T: SomeInteger](dst: var T; jsonNode: JsonNode, jsonPath: var string) =
  # verifyJsonKind(jsonNode, {JInt}, jsonPath)
  if jsonNode.kind == JString:
    dst = jsonNode.getStr.parseInt
  elif jsonNode.kind == JInt:
    dst = T(jsonNode.num)

proc initFromJson[T: SomeFloat](dst: var T; jsonNode: JsonNode; jsonPath: var string) =
  # verifyJsonKind(jsonNode, {JInt, JFloat}, jsonPath)
  if jsonNode.kind == JFloat:
    dst = T(jsonNode.fnum)
  elif jsonNode.kind == JInt:
    dst = T(jsonNode.num)
  elif jsonNode.kind == JString:
    dst = T(jsonNode.str.parseFloat)

proc initFromJson[T: ApprovedState or Genre or Language](
    dst: var T;
    jsonNode: JsonNode;
    jsonPath: var string
  ) =
  dst = jsonNode.getInt.T

proc to(node: JsonNode; t: typedesc[UserEvent]): UserEvent =
  doAssert node.kind == JObject
  var mutNode = JsonNode(kind: JObject)
  for k, v in node.fields:
    mutNode[userEventAliases.getOrDefault(k, k)] = v

  json.to(mutNode, UserEvent)

proc to(node: JsonNode; t: typedesc[BeatmapResult]): BeatmapResult =
  doAssert node.kind == JObject
  var mutNode = JsonNode(kind: JObject)
  for k, v in node.fields:
    mutNode[beatmapAliases.getOrDefault(k, k)] = v

  json.to(mutNode, BeatmapResult)

proc to(node: JsonNode; t: typedesc[User]): User =
  doAssert node.kind == JObject
  var mutNode = JsonNode(kind: JObject)
  for k, v in node.fields:
    mutNode[userAliases.getOrDefault(k, k)] = v

  json.to(mutNode, User)

proc to(node: JsonNode; t: typedesc[HighScore]): HighScore =
  doAssert node.kind == JObject
  var mutNode = JsonNode(kind: JObject)
  for k, v in node.fields:
    mutNode[highScoreAliases.getOrDefault(k, k)] = v

  mutNode["perfect"] = %mutNode["perfect"].getStr.parseBool

  json.to(mutNode, HighScore)

proc beatmapRequest(
    client: Client,
    beatmapIdentifier: BeatmapIdentifier,
    since: Option[DateTime] = none DateTime,
    userIdentifier: Option[UserIdentifier] = none UserIdentifier,
    gameMode: Option[GameMode] = none GameMode,
    includeConvertedBeatmaps: bool = false,
    limit: range[1..500] = 500,
  ): JsonNode =
  var parameters = @{
    "k": client.apiKey,
    "a": if includeConvertedBeatmaps: $1 else: $0,
    "limit": $limit,
  }

  withSome since:
    some since:
      parameters["since"] = $since.format("yyyy-MM-dd")

  parameters.combine beatmapIdentifier

  withSome userIdentifier:
    some userIdentifier:
      parameters.combine userIdentifier

  withSome gameMode:
    some gameMode:
      parameters["m"] = $gameMode.int

  let response = client.httpClient.get(
    &"{client.apiUrl}/get_beatmaps?" & parameters.encodeQuery
  )
  if not response.code.is2xx:
    raise newException(ValueError, "") # TODO: exception text
  response.body.parseJson

proc beatmap(
    client: Client,
    beatmapId: int,
    since: Option[DateTime] = none DateTime,
    userIdentifier: Option[UserIdentifier] = none UserIdentifier,
    gameMode: Option[GameMode] = none GameMode,
    includeConvertedBeatmaps: bool = false,
    limit: range[1..500] = 500,
  ): BeatmapResult =
  let jsonResponse = beatmapRequest(
    client,
    beatmapId(beatmapId),
    since,
    userIdentifier,
    gameMode,
    includeConvertedBeatmaps,
    limit
  )

  try:
    result = jsonResponse[0].to(BeatmapResult)
    result.library = client.library
  except IndexError:
    raise newException(UnknownBeatmapError, &"no beatmap found that matched id: {beatmapId}")

proc beatmap(
    client: Client,
    beatmapMd5: string,
    since: Option[DateTime] = none DateTime,
    userIdentifier: Option[UserIdentifier] = none UserIdentifier,
    gameMode: Option[GameMode] = none GameMode,
    includeConvertedBeatmaps: bool = false,
    limit: range[1..500] = 500,
  ): BeatmapResult =
  let jsonResponse = beatmapRequest(
    client,
    beatmapMd5(beatmapMd5),
    since,
    userIdentifier,
    gameMode,
    includeConvertedBeatmaps,
    limit
  )

  try:
    result = jsonResponse[0].to(BeatmapResult)
    result.library = client.library
  except IndexError:
    raise newException(UnknownBeatmapError, &"no beatmap found that matched md5: {beatmapMd5}")

proc beatmaps(
    client: Client,
    beatmapSetId: int,
    since: Option[DateTime] = none DateTime,
    userIdentifier: Option[UserIdentifier] = none UserIdentifier,
    gameMode: Option[GameMode] = none GameMode,
    includeConvertedBeatmaps: bool = false,
    limit: range[1..500] = 500,
  ): seq[BeatmapResult] =
  let jsonResponse = beatmapRequest(
    client,
    beatmapSetId(beatmapSetId),
    since,
    userIdentifier,
    gameMode,
    includeConvertedBeatmaps,
    limit
  )

  result = jsonResponse.getElems
    .mapIt(it.to(BeatmapResult))
    .map do (it: BeatmapResult) -> BeatmapResult:
      result = it
      result.library = client.library

proc beatmap*(
    client: Client,
    beatmapId: int,
    since: Option[DateTime] = none DateTime,
    userId: Option[int] = none int,
    gameMode: Option[GameMode] = none GameMode,
    includeConvertedBeatmaps: bool = false,
    limit: range[1..500] = 500,
  ): BeatmapResult =
  ## Retrieve information about a beatmap from the osu! API.
  let userIdentifier = withSome userId:
    some userId:
      some userId(userId)
    none:
      none UserIdentifier
  client.beatmap(
    beatmapId,
    since,
    userIdentifier,
    gameMode,
    includeConvertedBeatmaps,
    limit,
  )

proc beatmap*(
    client: Client,
    beatmapMd5: string,
    since: Option[DateTime] = none DateTime,
    userId: Option[int] = none int,
    gameMode: Option[GameMode] = none GameMode,
    includeConvertedBeatmaps: bool = false,
    limit: range[1..500] = 500,
  ): BeatmapResult =
  ## Retrieve information about a beatmap from the osu! API.
  let userIdentifier = withSome userId:
    some userId:
      some userId(userId)
    none:
      none UserIdentifier
  client.beatmap(
    beatmapMd5,
    since,
    userIdentifier,
    gameMode,
    includeConvertedBeatmaps,
    limit,
  )

proc beatmaps*(
    client: Client,
    beatmapSetId: int,
    since: Option[DateTime] = none DateTime,
    userId: Option[int] = none int,
    gameMode: Option[GameMode] = none GameMode,
    includeConvertedBeatmaps: bool = false,
    limit: range[1..500] = 500,
  ): seq[BeatmapResult] =
  ## Retrieve information about a set of beatmaps from the osu! API.
  let userIdentifier = withSome userId:
    some userId:
      some userId(userId)
    none:
      none UserIdentifier
  client.beatmaps(
    beatmapSetId,
    since,
    userIdentifier,
    gameMode,
    includeConvertedBeatmaps,
    limit,
  )

proc beatmap*(
    client: Client,
    beatmapId: int,
    since: Option[DateTime] = none DateTime,
    userName: Option[string] = none string,
    gameMode: Option[GameMode] = none GameMode,
    includeConvertedBeatmaps: bool = false,
    limit: range[1..500] = 500,
  ): BeatmapResult =
  ## Retrieve information about a beatmap from the osu! API.
  let userIdentifier = withSome userName:
    some userName:
      some userName(userName)
    none:
      none UserIdentifier
  client.beatmap(
    beatmapId,
    since,
    userIdentifier,
    gameMode,
    includeConvertedBeatmaps,
    limit,
  )

proc beatmap*(
    client: Client,
    beatmapMd5: string,
    since: Option[DateTime] = none DateTime,
    userName: Option[string] = none string,
    gameMode: Option[GameMode] = none GameMode,
    includeConvertedBeatmaps: bool = false,
    limit: range[1..500] = 500,
  ): BeatmapResult =
  ## Retrieve information about a beatmap from the osu! API.
  let userIdentifier = withSome userName:
    some userName:
      some userName(userName)
    none:
      none UserIdentifier
  client.beatmap(
    beatmapMd5,
    since,
    userIdentifier,
    gameMode,
    includeConvertedBeatmaps,
    limit,
  )

proc beatmaps*(
    client: Client,
    beatmapSetId: int,
    since: Option[DateTime] = none DateTime,
    userName: Option[string] = none string,
    gameMode: Option[GameMode] = none GameMode,
    includeConvertedBeatmaps: bool = false,
    limit: range[1..500] = 500,
  ): seq[BeatmapResult] =
  ## Retrieve information about a set of beatmaps from the osu! API.
  let userIdentifier = withSome userName:
    some userName:
      some userName(userName)
    none:
      none UserIdentifier
  client.beatmaps(
    beatmapSetId,
    since,
    userIdentifier,
    gameMode,
    includeConvertedBeatmaps,
    limit,
  )

proc user(
    client: Client,
    userIdentifier: UserIdentifier,
    gameMode: Option[GameMode] = none GameMode,
    eventDays: Option[range[1..31]] = none range[1..31],
  ): User =
  var parameters = @[("k", client.apiKey)].combine userIdentifier

  withSome gameMode:
    some gameMode:
      parameters["m"] = $gameMode.int
  withSome eventDays:
    some eventDays:
      parameters["event_days"] = $eventDays

  let response = client.httpClient.get(
    &"{client.apiUrl}/get_user?" & parameters.encodeQuery
  )
  if not response.code.is2xx:
    raise newException(ValueError, "") # TODO: exception text

  result = response.body.parseJson[0].to(User)
  for event in result.events.mitems:
    event.library = client.library
  withSome gameMode:
    some gameMode:
      result.gameMode = gameMode
    none:
      result.gameMode = Standard

proc user*(
    client: Client,
    userId: int,
    gameMode: Option[GameMode] = none GameMode,
    eventDays: Option[range[1..31]] = none range[1..31],
  ): User =
  ## Retrieve information about a user.
  client.user(userId(userId), gameMode, eventDays)

proc user*(
    client: Client,
    userName: string,
    gameMode: Option[GameMode] = none GameMode,
    eventDays: Option[range[1..31]] = none range[1..31],
  ): User =
  ## Retrieve information about a user.
  client.user(userName(userName), gameMode, eventDays)

proc userBest(
    client: Client,
    userIdentifier: UserIdentifier,
    gameMode: GameMode = Standard,
    limit: range[1..100] = 10,
    userOb: Option[User] = none User
  ): seq[HighScore] =
  ## Retrieve information about a user's best scores.
  var parameters = @{
    "k": client.apiKey,
    "m": $gameMode.int,
    "limit": $limit,
  }.combine userIdentifier

  let response = client.httpClient.get(
    &"{client.apiUrl}/get_user_best?" & parameters.encodeQuery
  )
  if not response.code.is2xx:
    raise newException(ValueError, response.body) # TODO: exception text

  let jsonResponse = response.body.parseJson

  result = jsonResponse.getElems.mapIt(it.to(HighScore))
  result = result.map do (it: HighScore) -> HighScore:
    result = it
    result.user = userOb

proc highScores*(client: Client, user: User, limit: range[1..100] = 10): seq[HighScore] =
  ## Lookup the user's high scores.
  client.userBest(
    userId(user.userId),
    user.gameMode,
    limit,
    some user,
  )

proc user*(client: Client, highscore: HighScore): User =
  withSome highscore.user:
    some user:
      user
    none:
      client.user(highscore.userId)

when false:
  proc accuracy(highscore: HighScore): float =
    accuracy(
      highscore.beatmap. # FIXME: game mode needs to be accessible here
      highscore.count300,
      highscore.count100,
      highscore.count50,
      0,
      0,
      highscore.countMiss,
    )
