import strutils
import os
import asyncdispatch
import md5
import httpclient
import strformat
import db_sqlite

import beatmap

proc sanitizeFilename*(name: string): string =
  ## Sanitize a filename so that it is safe to write to the filesystem.
  when system.hostOS == "windows":
    result = name
    for invalidCharacter in ":*?\"\\/|<>":
      result = result.replace($invalidCharacter)
  elif system.hostOS in ["linux", "macosx"]:
    result = name.replace("/")
  else:
    raise newException(OSError, "unknown operating system")

const
  DEFAULT_DOWNLOAD_URL: string = "https://osu.ppy.sh/osu"
  DEFAULT_CACHE_SIZE: int = 2048

var client = newHttpClient()

type Library = ref object
  path*: string
  cacheSize: int
  db: DbConn
  downloadUrl: string

proc writeToDb(lib: Library, beatmap: Beatmap, data: string, path: string)
proc download*(lib: Library, beatmapId: int, shouldSave=false): Beatmap

proc newLibrary*(path: string, cacheSize: int = DEFAULT_CACHE_SIZE,
    downloadUrl: string = DEFAULT_DOWNLOAD_URL): Library =

  var dbPath = path / ".circa.db"
  if not path.dirExists:
    path.createDir()

  var db = db_sqlite.open(dbPath, "", "", "")

  db.exec(sql"""CREATE TABLE IF NOT EXISTS beatmaps (
            md5 BLOB PRIMARY KEY,
            id INT,
            path TEXT UNIQUE NOT NULL
          )""")

  result = Library(
    path: path,
    cacheSize: cacheSize,
    db: db,
    downloadUrl: downloadUrl
  )

proc copy*(lib: Library): Library =
  result = newLibrary(
    lib.path,
    lib.cacheSize,
    lib.downloadUrl
  )

proc close*(lib: Library) =
  ## Close any resources used by this library.
  lib.db.close()

iterator osuFiles(path: string, recurse: bool): string =
  ## An iterator of ``.osu`` filepaths in a directory.

  if recurse:
    for filename in walkDirRec(path):
      if filename.endsWith(".osu"):
        yield filename
  else:
    for kind, filename in walkDir(path):
      if filename.endsWith(".osu"):
        yield path / filename


proc createDb*(path: string, recurse=true, cacheSize: int = DEFAULT_CACHE_SIZE, downloadUrl: string = DEFAULT_DOWNLOAD_URL): Library =
  ## Create a Library from a directory of ``.osu`` files.
  ##
  ## **Note:** Moving the underlying ``.osu`` files invalidates the library.
  ## If this happens, just re-run ``createDb`` again.

  let dbPath = path / ".circa.db"
  try:
    # ensure the db is cleared
    removeFile(dbPath)
  except: # FileNotFoundError:
    discard

  result = newLibrary(path, cacheSize=cacheSize, downloadUrl=downloadUrl)

  # progress = maybeShowProgress(
  #     osuFiles(path, recurse=recurse),
  #     showProgress,
  #     label="Processing beatmaps: ",
  #     itemShowFunc=lambda p: "Done!" if p is None else str(p.stem),
  # )
  for path in osuFiles(path, recurse=recurse):
    let
      f = open(path, fmRead)
      data = f.readAll()
    f.close()

    var beatmap: Beatmap
    try:
      beatmap = parseBeatmapMetadata(data)
    except ValueError as e:
      raise newException(ValueError, &"failed to parse {path}")

    result.writeToDb(beatmap, data, path)

proc readBeatmap(lib: Library, beatmapId: int): Beatmap =
  ## Function for opening beatmaps from disk.
  let path = lib.db.getValue(
    sql"SELECT path FROM beatmaps WHERE id = ?",
    beatmapId,
  )
  if path == "":
    raise newException(KeyError, $beatmapId)

  # Make path relative to the root path. We save paths relative to
  # ``lib.path`` so a library can be relocated without requiring a
  # rebuild
  # FIXME
  # return Beatmap.fromPath(lib.path / path)

proc readBeatmap(lib: Library, beatmapMd5: string): Beatmap =
  let path = lib.db.getValue(
    sql"SELECT path FROM beatmaps WHERE md5 = ?",
    beatmapMd5,
  )
  if path == "":
    raise newException(KeyError, $beatmapMd5)
  # FIXME
  # return Beatmap.fromPath(lib.path / path)

proc lookup*(lib: Library, beatmapId: int, download = false, shouldSave = false): Beatmap =
  ## Retrieve a beatmap by its beatmap id.
  try:
    result = lib.readBeatmap(beatmapId)
  except KeyError:
    if not download:
      raise
    result = lib.download(beatmapId, shouldSave)

proc lookup*(lib: Library, beatmapMd5: string): Beatmap =
  ## Retrieve a beatmap by its md5 hash.
  return lib.readBeatmap(beatmapMd5)

proc `[]`*(lib: Library, item: int): Beatmap =
  ## Retrieve a beatmap by its beatmap id.
  lib.lookup(item)

proc save*(lib: Library, data: string, beatmap: Beatmap): Beatmap =
  ## Save raw data for a beatmap at a given location.
  let path = lib.path / sanitizeFilename(
    &"{beatmap.metadata.artist} - " &
    &"{beatmap.metadata.title} " &
    &"({beatmap.metadata.creator})" &
    &"[{beatmap.metadata.version}]" &
    ".osu"
  )
  let f = open(path, fmWrite)
  f.write(data)
  f.close()

  lib.writeToDb(beatmap, data, path)
  return beatmap

proc save*(lib: Library, data: string): Beatmap =
  ## Save raw data for a beatmap at a given location.
  let beatmap = parseBeatmap(data)
  lib.save(data, beatmap)

proc delete*(lib: Library, beatmap: Beatmap, shouldDeleteFile=false) =
  ## Remove a beatmap from the library.

  if shouldDeleteFile:
    let paths = lib.db.getAllRows(
      sql"SELECT path FROM beatmaps WHERE id = ?",
      beatmap.metadata.beatmapId
    )
    for path in paths:
      removeFile(path[0])

  lib.db.exec(
    sql"DELETE FROM beatmaps WHERE id = ?",
    beatmap.metadata.beatmapId
  )

proc writeToDb(lib: Library, beatmap: Beatmap, data: string, path: string) =
  ## Write data to the database.

  # save paths relative to ``lib.path`` so a library can be relocated
  # without requiring a rebuild
  let
    path = path.relativePath(lib.path)
    beatmapMd5 = $data.toMD5
    beatmapId = beatmap.metadata.beatmapId

  try:
    lib.db.exec(
      sql"INSERT INTO beatmaps VALUES (?,?,?)",
      beatmapMd5, beatmapId, path
    )
  except: # sqlite3.IntegrityError:
    # ignore duplicate beatmaps
    discard

proc writeToDb(lib: Library, args: varargs[tuple[beatmap: Beatmap, data: string, path: string]]) =
  ## Write data to the database.

  for i in args:
    lib.writeToDb(i[0], i[1], i[2])

proc download*(lib: Library, beatmapId: int, shouldSave=false): Beatmap =
  ## Download a beatmap.
  let
    beatmapResponse = client.get(&"{lib.downloadUrl}/{beatmapId}")
    # beatmapResponse.raiseForStatus()
    data = beatmapResponse.body
    beatmap = parseBeatmap(data)

  if shouldSave:
    discard lib.save(data, beatmap)

  return beatmap

proc md5s*(lib: Library): seq[string] =
  ## All of the beatmap hashes that this has downloaded.

  for md5 in lib.db.getAllRows(sql"SELECT md5 FROM beatmaps"):
    result.add(md5[0])

proc ids*(lib: Library): seq[int] =
  ## All of the beatmap ids that this has downloaded.
  for id in lib.db.getAllRows(sql"SELECT id FROM beatmaps"):
    if id[0] != "":
      result.add(id[0].parseInt())

if isMainModule:
  var a = createDb(r"C:\Users\justin\Documents\#CODE\Nim\circa\osulib\")
  # discard a.lookup(38179, true, true)
