import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

/// Lyrics found for a song: timed lines (synced) or plain text.
class Lyrics {
  const Lyrics({required this.lines, required this.plain, required this.source});

  final List<LyricLine> lines;
  final String plain;

  /// Where they came from: an .lrc file next to the song, or the MP3's tags.
  final String source;

  bool get synced => lines.length >= 2;

  /// Index of the line being sung at [pos] (-1 before the first line).
  int indexAt(Duration pos) {
    var lo = 0, hi = lines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= pos) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }
}

/// Loads lyrics from the user's own files only:
///   1. `<song name>.lrc` in the same folder as the MP3
///   2. lyrics embedded in the MP3's tags (plain or LRC formatted)
class LyricsService {
  LyricsService._();
  static final instance = LyricsService._();

  final _cache = <String, Lyrics?>{};

  Future<Lyrics?> load(String path) async {
    if (_cache.containsKey(path)) return _cache[path];
    Lyrics? result;
    try {
      result = await Isolate.run(() => _loadLyrics(path));
    } catch (_) {}
    _cache[path] = result;
    return result;
  }

  void forget(String path) => _cache.remove(path);
}

Lyrics? _loadLyrics(String path) {
  final dot = path.lastIndexOf('.');
  final base = dot > 0 ? path.substring(0, dot) : path;
  // 1. A matching .lrc file (any letter case) next to the song.
  try {
    final dir = File(path).parent;
    final want = '${base.split('/').last}.lrc'.toLowerCase();
    for (final e in dir.listSync()) {
      if (e is File && e.path.split('/').last.toLowerCase() == want) {
        final parsed = parseLrc(e.readAsStringSync(), 'LRC file');
        if (parsed != null) return parsed;
      }
    }
  } catch (_) {}
  // 2. Lyrics stored inside the MP3.
  try {
    final meta = readMetadata(File(path));
    final text = meta.lyrics;
    if (text != null && text.trim().isNotEmpty) {
      return parseLrc(text, 'song tags');
    }
  } catch (_) {}
  return null;
}

final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _offsetTag =
    RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);
final _metaTag = RegExp(r'^\[[a-zA-Z#]+:.*\]\s*$');

/// Parses LRC text ("[01:23.45]words"). Text without timestamps becomes
/// plain lyrics.
Lyrics? parseLrc(String raw, String source) {
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final offsetMatch = _offsetTag.firstMatch(text);
  final offsetMs = offsetMatch == null ? 0 : int.parse(offsetMatch.group(1)!);

  final lines = <LyricLine>[];
  final plain = StringBuffer();
  for (final line in text.split('\n')) {
    final stamps = _timeTag.allMatches(line).toList();
    if (stamps.isEmpty) {
      if (!_metaTag.hasMatch(line.trim())) plain.writeln(line.trim());
      continue;
    }
    final words = line.replaceAll(_timeTag, '').trim();
    for (final m in stamps) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final fracStr = m.group(3);
      var frac = 0;
      if (fracStr != null) {
        frac = switch (fracStr.length) {
          1 => int.parse(fracStr) * 100,
          2 => int.parse(fracStr) * 10,
          _ => int.parse(fracStr),
        };
      }
      final ms = min * 60000 + sec * 1000 + frac - offsetMs;
      lines.add(LyricLine(Duration(milliseconds: ms < 0 ? 0 : ms), words));
      plain.writeln(words);
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  final plainText = plain.toString().trim();
  if (lines.length < 2 && plainText.isEmpty) return null;
  return Lyrics(
    lines: lines.length >= 2 ? lines : const [],
    plain: plainText,
    source: source,
  );
}
