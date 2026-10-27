import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'library_service.dart';

class Playlist {
  Playlist({required this.id, required this.name, List<String>? paths})
      : paths = paths ?? [];

  final String id;
  String name;
  final List<String> paths;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'paths': paths};

  static Playlist fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String,
        paths: (j['paths'] as List).cast<String>(),
      );
}

enum SmartPlaylist { favourites, mostPlayed, recentlyAdded }

extension SmartPlaylistInfo on SmartPlaylist {
  String get label => switch (this) {
        SmartPlaylist.favourites => 'Favourites',
        SmartPlaylist.mostPlayed => 'Most played',
        SmartPlaylist.recentlyAdded => 'Recently added',
      };
}

/// Your playlists, favourites and play counts, saved on the phone.
class PlaylistService extends ChangeNotifier {
  PlaylistService._();
  static final instance = PlaylistService._();

  final List<Playlist> playlists = [];
  final List<String> _favourites = []; // newest first
  final Map<String, int> _plays = {};

  /// Songs the user switched off (e.g. ringtones): still listed, never played.
  final Set<String> _disabled = {};
  final Set<String> _disabledFolders = {};
  bool _loaded = false;
  Timer? _saveTimer;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/playlists.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = jsonDecode(await (await _file()).readAsString())
          as Map<String, dynamic>;
      playlists
        ..clear()
        ..addAll((raw['playlists'] as List? ?? [])
            .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map))));
      _favourites
        ..clear()
        ..addAll((raw['favourites'] as List? ?? []).cast<String>());
      _plays
        ..clear()
        ..addAll(Map<String, dynamic>.from(raw['plays'] as Map? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toInt())));
      _disabled
        ..clear()
        ..addAll((raw['disabled'] as List? ?? []).cast<String>());
      _disabledFolders
        ..clear()
        ..addAll((raw['disabledFolders'] as List? ?? []).cast<String>());
    } catch (_) {
      // First run or unreadable file: start empty.
    }
    notifyListeners();
  }

  void _save() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final f = await _file();
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(jsonEncode({
          'playlists': playlists.map((p) => p.toJson()).toList(),
          'favourites': _favourites,
          'plays': _plays,
          'disabled': _disabled.toList(),
          'disabledFolders': _disabledFolders.toList(),
        }));
        await tmp.rename(f.path);
      } catch (_) {}
    });
  }

  // --- Favourites ------------------------------------------------------------

  bool isFavourite(String path) => _favourites.contains(path);

  void toggleFavourite(String path) {
    if (!_favourites.remove(path)) _favourites.insert(0, path);
    _save();
  }

  // --- Disabled songs ------------------------------------------------------

  static String folderOf(String path) {
    final i = path.lastIndexOf('/');
    return i > 0 ? path.substring(0, i) : path;
  }

  static String folderName(String path) {
    final f = folderOf(path);
    return f.substring(f.lastIndexOf('/') + 1);
  }

  bool isDisabled(String path) =>
      _disabled.contains(path) ||
      _disabledFolders.any((f) => path.startsWith('$f/'));

  /// True when the song is off because its whole folder is.
  bool isFolderDisabled(String path) =>
      _disabledFolders.any((f) => path.startsWith('$f/'));

  void setDisabled(String path, bool off) {
    if (off) {
      _disabled.add(path);
    } else {
      _disabled.remove(path);
      // Enabling one song inside a disabled folder re-enables that folder.
      _disabledFolders.removeWhere((f) => path.startsWith('$f/'));
    }
    _save();
  }

  void setFolderDisabled(String path, bool off) {
    final folder = folderOf(path);
    if (off) {
      _disabledFolders.add(folder);
    } else {
      _disabledFolders.remove(folder);
      _disabled.removeWhere((p) => p.startsWith('$folder/'));
    }
    _save();
  }

  /// Only the songs that are allowed to play.
  List<String> playable(Iterable<String> paths) =>
      paths.where((p) => !isDisabled(p)).toList();

  // --- Play counts -----------------------------------------------------------

  int playsOf(String path) => _plays[path] ?? 0;

  void countPlay(String path) {
    _plays[path] = playsOf(path) + 1;
    _save();
  }

  // --- Your playlists --------------------------------------------------------

  Playlist create(String name) {
    final p = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: name.trim().isEmpty ? 'New playlist' : name.trim(),
    );
    playlists.add(p);
    _save();
    return p;
  }

  void rename(Playlist p, String name) {
    if (name.trim().isEmpty) return;
    p.name = name.trim();
    _save();
  }

  void delete(Playlist p) {
    playlists.remove(p);
    _save();
  }

  /// Returns false if the song was already in the playlist.
  bool addTo(Playlist p, String path) {
    if (p.paths.contains(path)) return false;
    p.paths.add(path);
    _save();
    return true;
  }

  void removeFrom(Playlist p, String path) {
    p.paths.remove(path);
    _save();
  }

  void reorder(Playlist p, int from, int to) {
    if (to > from) to -= 1;
    final item = p.paths.removeAt(from);
    p.paths.insert(to, item);
    _save();
  }

  /// When a file is deleted, drop it everywhere.
  void forget(String path) {
    var changed = _favourites.remove(path);
    changed = (_plays.remove(path) != null) || changed;
    for (final p in playlists) {
      changed = p.paths.remove(path) || changed;
    }
    if (changed) _save();
  }

  // --- Resolving to songs ----------------------------------------------------

  /// Paths that still exist on the phone.
  List<String> _existing(Iterable<String> paths) =>
      paths.where((p) => File(p).existsSync()).toList();

  List<String> pathsFor(Playlist p) => _existing(p.paths);

  List<String> smartPaths(SmartPlaylist s) {
    switch (s) {
      case SmartPlaylist.favourites:
        return _existing(_favourites);
      case SmartPlaylist.mostPlayed:
        final entries = _plays.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return _existing(entries.map((e) => e.key)).take(50).toList();
      case SmartPlaylist.recentlyAdded:
        final songs = List<Song>.of(LibraryService.instance.allSongs)
          ..sort((a, b) => b.modified.compareTo(a.modified));
        final cutoff = DateTime.now().subtract(const Duration(days: 30));
        final recent = songs.where((s) => s.modified.isAfter(cutoff)).toList();
        return (recent.isEmpty ? songs.take(25) : recent.take(100))
            .map((s) => s.path)
            .toList();
    }
  }
}
