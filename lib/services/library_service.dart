import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'storage_service.dart';

class Song {
  const Song({
    required this.path,
    required this.size,
    required this.modified,
  });

  final String path;
  final int size;
  final DateTime modified;

  String get fileName => path.split('/').last;
  String get folder {
    final parts = path.split('/');
    return parts.length > 1 ? parts[parts.length - 2] : '';
  }

  String get _stem => fileName.toLowerCase().endsWith('.mp3')
      ? fileName.substring(0, fileName.length - 4)
      : fileName;

  /// "Artist - Title.mp3" → Title, otherwise the file name.
  String get title {
    final i = _stem.indexOf(' - ');
    return i > 0 ? _stem.substring(i + 3).trim() : _stem;
  }

  /// "Artist - Title.mp3" → Artist, otherwise the folder name.
  String get artist {
    final i = _stem.indexOf(' - ');
    return i > 0 ? _stem.substring(0, i).trim() : folder;
  }
}

enum SortMode { recent, title }

enum LibraryState { idle, scanning, ready, noPermission }

/// Finds MP3 files on the phone's storage.
class LibraryService extends ChangeNotifier {
  LibraryService._();
  static final instance = LibraryService._();

  List<Song> _songs = [];
  LibraryState state = LibraryState.idle;
  SortMode sort = SortMode.recent;
  String query = '';

  List<Song> get songs {
    final q = query.trim().toLowerCase();
    final list = q.isEmpty
        ? List.of(_songs)
        : _songs
            .where((s) =>
                s.title.toLowerCase().contains(q) ||
                s.artist.toLowerCase().contains(q) ||
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
    try {
      final found = await Isolate.run(() => _scanRoots(roots));
      _songs = [
        for (final r in found)
          Song(
            path: r.$1,
            size: r.$2,
            modified: DateTime.fromMillisecondsSinceEpoch(r.$3),
          ),
      ];
    } catch (_) {
      // keep whatever we had
    }
    state = LibraryState.ready;
    notifyListeners();
  }

  /// Called after a download finishes so the song shows up right away.
  void addFile(String path) {
    final f = File(path);
    if (!f.existsSync() || _songs.any((s) => s.path == path)) return;
    final st = f.statSync();
    _songs.add(Song(path: path, size: st.size, modified: st.modified));
    notifyListeners();
  }

  void removeFile(String path) {
    _songs.removeWhere((s) => s.path == path);
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

const _skipDirs = {'android', 'notifications', 'ringtones', 'alarms'};

/// Runs in a background isolate. Returns (path, size, modifiedMs).
List<(String, int, int)> _scanRoots(List<String> roots) {
  final out = <(String, int, int)>[];
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
        if (depth == 0 && _skipDirs.contains(name.toLowerCase())) continue;
        if (_skipDirs.contains(name.toLowerCase()) && name != 'Android') {
          continue;
        }
        walk(e, depth + 1);
      } else if (e is File && name.toLowerCase().endsWith('.mp3')) {
        try {
          final st = e.statSync();
          // Skip tiny clips (notification sounds and the like).
          if (st.size < 150 * 1024) continue;
          if (seen.add(e.path)) {
            out.add((e.path, st.size, st.modified.millisecondsSinceEpoch));
          }
        } catch (_) {}
      }
    }
  }

  for (final r in roots) {
    walk(Directory(r), 0);
  }
  return out;
}
