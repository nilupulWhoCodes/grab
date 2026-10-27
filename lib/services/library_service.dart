import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'storage_service.dart';

class Song {
  const Song({
    required this.path,
    required this.size,
    required this.modified,
    this.tagTitle,
    this.tagArtist,
    this.album,
    this.duration,
    this.artPath,
  });

  final String path;
  final int size;
  final DateTime modified;
  final String? tagTitle;
  final String? tagArtist;
  final String? album;
  final Duration? duration;

  /// Cover art extracted from the file into the app's cache, if it has one.
  final String? artPath;

  String get fileName => path.split('/').last;
  String get folder {
    final parts = path.split('/');
    return parts.length > 1 ? parts[parts.length - 2] : '';
  }

  String get _stem => fileName.toLowerCase().endsWith('.mp3')
      ? fileName.substring(0, fileName.length - 4)
      : fileName;

  /// Tag title, else "Artist - Title.mp3" → Title, else the file name.
  String get title {
    if (tagTitle != null && tagTitle!.trim().isNotEmpty) return tagTitle!.trim();
    final i = _stem.indexOf(' - ');
    return i > 0 ? _stem.substring(i + 3).trim() : _stem;
  }

  /// Tag artist, else "Artist - Title.mp3" → Artist, else the folder name.
  String get artist {
    if (tagArtist != null && tagArtist!.trim().isNotEmpty) {
      return tagArtist!.trim();
    }
    final i = _stem.indexOf(' - ');
    return i > 0 ? _stem.substring(0, i).trim() : folder;
  }
}

enum SortMode { recent, title }

enum LibraryState { idle, scanning, ready, noPermission }

/// Finds MP3 files on the phone's storage and reads their tags/cover art.
class LibraryService extends ChangeNotifier {
  LibraryService._();
  static final instance = LibraryService._();

  List<Song> _songs = [];
  final Map<String, Song> _byPath = {};
  LibraryState state = LibraryState.idle;
  SortMode sort = SortMode.recent;
  String query = '';

  Song? songFor(String path) => _byPath[path];

  /// Every song, unfiltered and unsorted.
  List<Song> get allSongs => List.unmodifiable(_songs);

  List<Song> get songs {
    final q = query.trim().toLowerCase();
    final list = q.isEmpty
        ? List.of(_songs)
        : _songs
            .where((s) =>
                s.title.toLowerCase().contains(q) ||
                s.artist.toLowerCase().contains(q) ||
                (s.album ?? '').toLowerCase().contains(q) ||
                s.folder.toLowerCase().contains(q))
            .toList();
    switch (sort) {
      case SortMode.recent:
        list.sort((a, b) => b.modified.compareTo(a.modified));
      case SortMode.title:
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return list;
  }

  int get total => _songs.length;

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setSort(SortMode m) {
    sort = m;
    notifyListeners();
  }

  void _setSongs(List<Song> songs) {
    _songs = songs;
    _byPath
      ..clear()
      ..addEntries(songs.map((s) => MapEntry(s.path, s)));
  }

  Future<String> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/library');
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> scan({bool askPermission = true}) async {
    if (state == LibraryState.scanning) return;
    final granted = askPermission
        ? await StorageService.instance.ensureReadPermission()
        : await StorageService.instance.hasReadPermission();
    if (!granted) {
      state = LibraryState.noPermission;
      notifyListeners();
      return;
    }
    state = LibraryState.scanning;
    notifyListeners();
    final roots = await _roots();
    final cache = await _cacheDir();
    try {
      final found = await Isolate.run(() => _scanRoots(roots, cache));
      _setSongs(found.map(_fromRecord).toList());
    } catch (_) {
      // keep whatever we had
    }
    state = LibraryState.ready;
    notifyListeners();
  }

  /// Called after a download finishes so the song shows up right away.
  Future<void> addFile(String path) async {
    if (_byPath.containsKey(path) || !File(path).existsSync()) return;
    final cache = await _cacheDir();
    try {
      final rec = await Isolate.run(() => _readOne(path, cache, null));
      if (rec != null) {
        _setSongs([..._songs, _fromRecord(rec)]);
        notifyListeners();
      }
    } catch (_) {}
  }

  void removeFile(String path) {
    _setSongs(_songs.where((s) => s.path != path).toList());
    notifyListeners();
  }

  Future<List<String>> _roots() async {
    if (!Platform.isAndroid) {
      return [(await StorageService.instance.musicDir()).path];
    }
    final roots = <String>['/storage/emulated/0'];
    // SD cards and USB drives show up as /storage/XXXX-XXXX.
    try {
      for (final e in Directory('/storage').listSync()) {
        final name = e.path.split('/').last;
        if (e is Directory && name != 'emulated' && name != 'self') {
          roots.add(e.path);
        }
      }
    } catch (_) {}
    return roots;
  }
}

// ---------------------------------------------------------------------------
// Background isolate work. Records cross the isolate boundary as plain maps.

Song _fromRecord(Map<String, Object?> r) => Song(
      path: r['p']! as String,
      size: r['s']! as int,
      modified: DateTime.fromMillisecondsSinceEpoch(r['m']! as int),
      tagTitle: r['t'] as String?,
      tagArtist: r['a'] as String?,
      album: r['al'] as String?,
      duration: r['d'] == null ? null : Duration(milliseconds: r['d']! as int),
      artPath: r['art'] as String?,
    );

const _skipDirs = {'android', 'notifications', 'ringtones', 'alarms'};

/// Stable 64-bit FNV-1a hash (String.hashCode isn't guaranteed stable).
String _fnv(List<int> bytes) {
  var h = 0xcbf29ce484222325;
  for (final b in bytes) {
    h ^= b;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toUnsigned(64).toRadixString(16);
}

String? _clean(String? s) {
  if (s == null) return null;
  final t = s.replaceAll('\u0000', '').trim();
  return t.isEmpty ? null : t;
}

/// Reads one file's tags (and saves its cover art). Uses [cached] when the
/// file hasn't changed since the last scan.
Map<String, Object?>? _readOne(
    String path, String cacheDir, Map<String, Object?>? cached) {
  final file = File(path);
  final st = file.statSync();
  if (st.type != FileSystemEntityType.file) return null;
  final m = st.modified.millisecondsSinceEpoch;
  if (cached != null && cached['m'] == m && cached['s'] == st.size) {
    final art = cached['art'] as String?;
    if (art == null || File(art).existsSync()) return cached;
  }
  final rec = <String, Object?>{'p': path, 's': st.size, 'm': m};
  try {
    final meta = readMetadata(file, getImage: true);
    rec['t'] = _clean(meta.title);
    rec['a'] = _clean(meta.artist) ?? _clean(meta.albumArtist);
    rec['al'] = _clean(meta.album);
    rec['d'] = meta.duration?.inMilliseconds;
    if (meta.pictures.isNotEmpty) {
      final pic = meta.pictures.first;
      final bytes = pic.bytes;
      if (bytes.isNotEmpty) {
        final sample = bytes.length > 8192 ? bytes.sublist(0, 8192) : bytes;
        final name = '${_fnv([...sample, ...utf8.encode('${bytes.length}')])}'
            '${pic.mimetype.contains('png') ? '.png' : '.jpg'}';
        final out = File('$cacheDir/art/$name');
        if (!out.existsSync()) {
          out.parent.createSync(recursive: true);
          out.writeAsBytesSync(bytes, flush: true);
        }
        rec['art'] = out.path;
      }
    }
  } catch (_) {
    // Unreadable tags: fall back to the file name.
  }
  return rec;
}

List<Map<String, Object?>> _scanRoots(List<String> roots, String cacheDir) {
  // Load the tag cache from the previous scan.
  final cacheFile = File('$cacheDir/tags.json');
  var cache = <String, Map<String, Object?>>{};
  try {
    final raw = jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
    cache = raw.map((k, v) => MapEntry(k, Map<String, Object?>.from(v as Map)));
  } catch (_) {}

  final paths = <String>[];
  final seen = <String>{};

  void walk(Directory dir, int depth) {
    if (depth > 10) return;
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final e in entries) {
      final name = e.path.split('/').last;
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        final lower = name.toLowerCase();
        if (lower == 'android' && depth == 0) continue;
        if (lower != 'android' && _skipDirs.contains(lower)) continue;
        walk(e, depth + 1);
      } else if (e is File && name.toLowerCase().endsWith('.mp3')) {
        try {
          // Skip tiny clips (notification sounds and the like).
          if (e.lengthSync() < 150 * 1024) continue;
          if (seen.add(e.path)) paths.add(e.path);
        } catch (_) {}
      }
    }
  }

  for (final r in roots) {
    walk(Directory(r), 0);
  }

  final out = <Map<String, Object?>>[];
  final newCache = <String, Map<String, Object?>>{};
  for (final p in paths) {
    try {
      final rec = _readOne(p, cacheDir, cache[p]);
      if (rec != null) {
        out.add(rec);
        newCache[p] = rec;
      }
    } catch (_) {}
  }
  try {
    cacheFile.writeAsStringSync(jsonEncode(newCache));
  } catch (_) {}
  return out;
}
