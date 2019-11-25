# import asyncio
# from functools import lru_cache
# from hashlib import md5
# import os
# import pathlib
# import sqlite3
# import sys

# import requests

# from .beatmap import Beatmap
# from .cli import maybe_show_progress

import strutils, os
import db_sqlite

when system.hostOS == "windows":
  proc sanitize_filename*(name: string): string =
    result = name
    for invalid_character in ":*?\"\\/|<>":
      result = result.replace($invalid_character)
elif system.hostOS in ["linux", "macosx"]:
  proc sanitize_filename*(name: string): string =
    result = name.replace("/")
else:
  raise newException(OSError, "unknown operating system")

# if sys.platform.startswith('win'):
#     def sanitize_filename(name):
#         for invalid_character in r':*?"\/|<>':
#             name = name.replace(invalid_character, '')
#         return name
# else:
#     def sanitize_filename(name):
#         return name.replace('/', '')

# sanitize_filename.__doc__ = """\
# Sanitize a filename so that it is safe to write to the filesystem.

# Parameters
# ----------
# name : str
#     The name of the file without the directory.

# Returns
# -------
# sanitized_name : str
#     The name with invalid characters stripped out.
# """

const
  DEFAULT_DOWNLOAD_URL: string = "https://osu.ppy.sh/osu"
  DEFAULT_CACHE_SIZE: int = 2048

type Library = ref object
  path*: string
  cache_size: int
  db: DbConn
  download_url: string

proc newLibrary*(path: string, cache: int = DEFAULT_CACHE_SIZE,
    download_url: string = DEFAULT_DOWNLOAD_URL): Library =

  var fn = path / ".slider.db"
  if not path.dirExists:
    path.createDir

  var db = open(fn, "", "", "")

  db.exec(sql"""CREATE TABLE IF NOT EXISTS beatmaps (
                    md5 BLOB PRIMARY KEY,
                    id INT,
                    path TEXT UNIQUE NOT NULL
                )""")

  result = Library(
    path: path,
    cache_size: cache,
    db: db,
    download_url: download_url
  )

# is this needed???
# method copy*(self: Library): Library {.base.} =
#     result = Library(
#       path: self.path,
#       cache_size: self.cache_size,
#       db: self.db,
#       download_url: self.download_url
#     )

proc finalizer*(self: Library) =
  self.db.close()

proc read_beatmap(self: Library, beatmap_id:int ): int =
  with self._db:
    path_query = self.db.execute(
      sql"SELECT path FROM beatmaps WHERE id = ?",
      (beatmap_id,),
    )
  path = path_query.fetchone()
  if path is nil:
    raise KeyError(key)
  else:
    path, = path

  # Make path relative to the root path. We save paths relative to
  # ``self.path`` so a library can be relocated without requiring a
  # rebuild
  return Beatmap.from_path(self.path / path)

proc read_beatmap(self:Library, beatmap_md5:string): int =
  let path = self.db.getValue(
    sql"SELECT path FROM beatmaps WHERE md5 = ?",
    beatmap_md5,
  )
  if path == "":
    raise newException(KeyError, $beatmap_md5)

  return Beatmap.fromPath(self.path / path)


method lookup_by_id(self: Library, beatmap_id: int, download = false,
    save = false): int =
  try:
    result = self.read_beatmap(self, beatmap_id = beatmap_id)
  except KeyError:
    if not download:
      raise
    result = self.download(beatmap_id, save = save)

proc `[]`*(self: Library): int =
  self.lookup_by_id(item)

if isMainModule:
  var a = newLibrary(r"C:\Users\justin\Documents\#CODE\Nim\circa\osu\")

# class Library:
#     """A library of beatmaps backed by a local directory.

#     Parameters
#     ----------
#     path : path-like
#         The path to a local library directory.
#     cache : int, optional
#         The amount of beatmaps to cache in memory. This uses
#         :func:`functools.lru_cache`, and if set to None will cache everything.
#     download_url : str, optional
#         The default location to download beatmaps from.
#     """
#     DEFAULT_DOWNLOAD_URL = 'https://osu.ppy.sh/osu'
#     DEFAULT_CACHE_SIZE = 2048

#     def __init__(self,
#                  path,
#                  *,
#                  cache=DEFAULT_CACHE_SIZE,
#                  download_url=DEFAULT_DOWNLOAD_URL):
#         self.path = path = pathlib.Path(path)

#         self._cache_size = cache
#         self._read_beatmap = lru_cache(cache)(self._raw_read_beatmap)
#         self._db = db = sqlite3.connect(str(path / '.slider.db'))
#         with db:
#             db.execute(
#                 """\
#                 CREATE TABLE IF NOT EXISTS beatmaps (
#                     md5 BLOB PRIMARY KEY,
#                     id INT,
#                     path TEXT UNIQUE NOT NULL
#                 )
#                 """,
#             )
#         self._download_url = download_url

#     def copy(self):
#         """Create a copy suitable for use in a new thread.

#         Returns
#         -------
#         Library
#             The new copy.
#         """
#         return type(self)(
#             self.path,
#             cache=self._cache_size,
#             download_url=self._download_url,
#         )

#     def close(self):
#         """Close any resources used by this library.
#         """
#         self._read_beatmap.cache_clear()
#         self._db.close()

#     def __del__(self):
#         try:
#             self.close()
#         except AttributeError:
#             # if an error is raised in the constructor
#             pass

#     def __enter__(self):
#         return self

#     def __exit__(self, *exc_info):
#         self.close()

#     def __getitem__(self, item):
#         return self.lookup_by_id(item)

#     @staticmethod
#     def _osu_files(path, recurse):
#         """An iterator of ``.osu`` filepaths in a directory.

#         Parameters
#         ----------
#         path : path-like
#             The directory to search in.
#         recurse : bool
#             Recursively search ``path``?

#         Yields
#         ------
#         path : str
#             The path to a ``.osu`` file.
#         """
#         pattern = "*.osu"
#         if recurse:
#             pattern = "**/" + pattern
#         yield from path.glob(pattern)

#     @staticmethod
#     def _iterate_beatmaps(iter):
#         for path in iter:
#             with open(path, 'rb') as f:
#                 data = f.read()
#             try:
#                 beatmap_id = Beatmap.parse_id(data.decode('utf-8-sig'))
#                 yield (beatmap_id, data, path)
#             except ValueError as e:
#                 raise ValueError(f'failed to parse {path}') from e
#             except ZeroDivisionError:
#                 pass

#     @classmethod
#     def create_db(cls,
#                   path,
#                   *,
#                   recurse=True,
#                   cache=DEFAULT_CACHE_SIZE,
#                   download_url=DEFAULT_DOWNLOAD_URL,
#                   show_progress=False):
#         """Create a Library from a directory of ``.osu`` files.

#         Parameters
#         ----------
#         path : path-like
#             The path to the directory to read.
#         recurse : bool, optional
#             Recursively search for beatmaps?
#         cache : int, optional
#             The amount of beatmaps to cache in memory. This uses
#             :func:`functools.lru_cache`, and if set to None will cache
#             everything.
#         download_url : str, optional
#             The default location to download beatmaps from.
#         show_progress : bool, optional
#             Display a progress bar?

#         Notes
#         -----
#         Moving the underlying ``.osu`` files invalidates the library. If this
#         happens, just re-run ``create_db`` again.
#         """
#         path = pathlib.Path(path)
#         db_path = path / '.slider.db'
#         try:
#             # ensure the db is cleared
#             os.remove(db_path)
#         except FileNotFoundError:
#             pass

#         self = cls(path, cache=cache, download_url=download_url)

#         progress = maybe_show_progress(
#             list(self._osu_files(path, recurse=recurse)),
#             show_progress,
#             desc='Processing beatmaps: ',
#             leave=False,
#             unit='beatmaps',
#             # item_show_func=lambda p: 'Done!' if p is None else str(p.stem),
#         )
#         with progress as iter:
#             self._write_iter_to_db(cls._iterate_beatmaps(iter))

#         return self

#     @staticmethod
#     def _raw_read_beatmap(self, *, beatmap_id=None, beatmap_md5=None):
#         """Function for opening beatmaps from disk.

#         This handles both cases to only require a single lru cache.

#         Notes
#         -----
#         This is a ``staticmethod`` to avoid a cycle from self to the lru_cache
#         back to self.
#         """
#         with self._db:
#             if beatmap_id is not None:
#                 key = beatmap_id
#                 path_query = self._db.execute(
#                     'SELECT path FROM beatmaps WHERE id = ?',
#                     (beatmap_id,),
#                 )
#             else:
#                 key = beatmap_md5
#                 path_query = self._db.execute(
#                     'SELECT path FROM beatmaps WHERE md5 = ?',
#                     (beatmap_md5,),
#                 )

#         path = path_query.fetchone()
#         if path is None:
#             raise KeyError(key)
#         else:
#             path, = path

#         # Make path relative to the root path. We save paths relative to
#         # ``self.path`` so a library can be relocated without requiring a
#         # rebuild
#         return Beatmap.from_path(self.path / path)

#     def lookup_by_id(self, beatmap_id, *, download=False, save=False):
#         """Retrieve a beatmap by its beatmap id.

#         Parameters
#         ----------
#         beatmap_id : int or str
#             The id of the beatmap to lookup.

#         Returns
#         -------
#         beatmap : Beatmap
#             The beatmap with the given id.
#         download : bool. optional
#             Download the map if it doesn't exist.
#         save : bool, optional
#             If the lookup falls back to a download, should the result be saved?

#         Raises
#         ------
#         KeyError
#             Raised when the given id is not in the library.
#         """
#         try:
#             return self._read_beatmap(self, beatmap_id=beatmap_id)
#         except KeyError:
#             if not download:
#                 raise
#             return self.download(beatmap_id, save=save)

#     def lookup_by_md5(self, beatmap_md5):
#         """Retrieve a beatmap by its md5 hash.

#         Parameters
#         ----------
#         beatmap_md5 : bytes
#             The md5 hash of the beatmap to lookup.

#         Returns
#         -------
#         beatmap : Beatmap
#             The beatmap with the given md5 hash.

#         Raises
#         ------
#         KeyError
#             Raised when the given md5 hash is not in the library.
#         """
#         return self._read_beatmap(self, beatmap_md5=beatmap_md5)

#     def save(self, data, *, beatmap=None):
#         """Save raw data for a beatmap at a given location.

#         Parameters
#         ----------
#         data : bytes
#             The unparsed beatmap data.
#         beatmap : Beatmap, optional
#             The parsed beatmap. If not provided, the raw data will be parsed.

#         Returns
#         -------
#         beatmap : Beatmap
#             The parsed beatmap.
#         """
#         if beatmap is None:
#             beatmap = Beatmap.parse(data.decode('utf-8-sig'))

#         path = self.path / sanitize_filename(
#             f'{beatmap.artist} - '
#             f'{beatmap.title} '
#             f'({beatmap.creator})'
#             f'[{beatmap.version}]'
#             f'.osu'
#         )
#         with open(path, 'wb') as f:
#             f.write(data)

#         with self._db:
#             self._write_to_db(beatmap, data, path)
#         return beatmap

#     def delete(self, beatmap, *, remove_file=True):
#         """Remove a beatmap from the library.

#         Parameters
#         ----------
#         beatmap : Beatmap
#             The beatmap to delete.
#         remove_file : bool, optional
#             Remove the .osu file from disk.
#         """
#         with self._db:
#             if remove_file:
#                 paths = self._db.execute(
#                     'SELECT path FROM beatmaps WHERE id = ?',
#                     (beatmap.beatmap_id,),
#                 )
#                 for path, in paths:
#                     os.unlink(path)

#             self._db.execute(
#                 'DELETE FROM beatmaps WHERE id = ?',
#                 (beatmap.beatmap_id,),
#             )

#     def _write_to_db(self, beatmap, data, path):
#         """Write data to the database.

#         Parameters
#         ----------
#         beatmap : Beatmap
#             The beatmap being stored.
#         data : bytes
#             The raw data for the beatmap
#         path : pathlib.Path
#             The path to save
#         """
#         # save paths relative to ``self.path`` so a library can be relocated
#         # without requiring a rebuild
#         path = path.relative_to(self.path)
#         beatmap_md5 = md5(data).hexdigest()
#         beatmap_id = beatmap.beatmap_id

#         try:
#             with self._db:
#                 self._db.execute(
#                     'INSERT INTO beatmaps VALUES (?,?,?)',
#                     (beatmap_md5, beatmap_id, str(path)),
#                 )
#         except sqlite3.IntegrityError:
#             # ignore duplicate beatmaps
#             pass

#     def _write_iter_to_db(self, iterable):
#         """Write data to the database.

#         Parameters
#         ----------
#         iterable : iterable[tuple]
#             An iterable of beatmap-data-path tuples
#         """
#         with self._db:
#             for i in iterable:
#                 try:
#                 # save paths relative to ``self.path`` so a library can be relocated
#                 # without requiring a rebuild
#                     path = i[2].relative_to(self.path)
#                     beatmap_md5 = md5(i[1]).hexdigest()
#                     beatmap_id = getattr(i[0], "beatmap_id", i[0])
#                     self._db.execute(
#                         'INSERT INTO beatmaps VALUES (?,?,?)',
#                         (beatmap_md5, beatmap_id, str(path)),
#                     )
#                 except sqlite3.IntegrityError:
#                     # ignore duplicate beatmaps
#                     pass

#     def download(self, beatmap_id, *, save=False):
#         """Download a beatmap.

#         Parameters
#         ----------
#         beatmap_id : int or str
#             The id of the beatmap to download.
#         save : bool, optional
#             Save the beatmap to disk?

#         Returns
#         -------
#         beatmap : Beatmap
#             The downloaded beatmap.
#         """
#         beatmap_response = requests.get(f'{self._download_url}/{beatmap_id}')
#         beatmap_response.raise_for_status()

#         data = beatmap_response.content
#         beatmap = Beatmap.parse(data.decode('utf-8-sig'))

#         if save:
#             self.save(data, beatmap=beatmap)

#         return beatmap

#     @property
#     def md5s(self):
#         """All of the beatmap hashes that this has downloaded.
#         """
#         return tuple(
#             md5 for md5, in self._db.execute('SELECT md5 FROM beatmaps')
#         )

#     @property
#     def ids(self):
#         """All of the beatmap ids that this has downloaded.
#         """
#         return tuple(
#             int(id_)
#             for id_, in self._db.execute('SELECT id FROM beatmaps')
#             if id_ is not None
#         )
