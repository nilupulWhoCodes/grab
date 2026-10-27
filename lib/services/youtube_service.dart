import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class VideoInfo {
  const VideoInfo({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
  });

  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
}

/// Song title/artist guessed from a YouTube title and channel name.
class TagGuess {
  const TagGuess(this.title, this.artist);
  final String title;
  final String artist;

  static final _noise = RegExp(
    r'\s*[\(\[【]\s*(official\s*)?(music\s*|lyrics?\s*|visuali[sz]er\s*|audio\s*|hd\s*|hq\s*|4k\s*|video\s*|mv\s*|m/v\s*|clip\s*officiel\s*)+[\)\]】]',
    caseSensitive: false,
  );

  static String _tidy(String s) => s
      .replaceAll(_noise, '')
      .replaceAll(RegExp(r'\s*\|.*$'), '') // "Song | Album name"
      .replaceAll(RegExp(r'^["“”]+|["“”]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _cleanChannel(String c) => c
      .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
      .replaceAll(RegExp(r'VEVO$'), '')
      .replaceAll(RegExp(r'\s*(Official)?\s*$', caseSensitive: false), '')
      .trim();

  /// "Artist - Song (Official Video)" → (Song, Artist); otherwise the
  /// channel name is used as the artist.
  static TagGuess from(String videoTitle, String channel) {
    final cleaned = _tidy(videoTitle);
    final m = RegExp(r'^(.+?)\s+[-–—]\s+(.+)$').firstMatch(cleaned);
    if (m != null) {
      final artist = m.group(1)!.trim();
      final title = _tidy(m.group(2)!);
      if (artist.isNotEmpty && title.isNotEmpty) return TagGuess(title, artist);
    }
    final artist = _cleanChannel(channel);
    return TagGuess(cleaned.isEmpty ? videoTitle : cleaned,
        artist.isEmpty ? channel : artist);
  }
}

/// One downloadable source for a video's audio.
class AudioCandidate {
  const AudioCandidate({
    required this.url,
    required this.size,
    required this.extension,
    required this.isMuxed,
    required this.clientLabel,
  });

  final Uri url;
  final int size;
  final String extension;

  /// Combined low-quality video+audio stream (audio is extracted by ffmpeg).
  final bool isMuxed;
  final String clientLabel;
}

/// Thin wrapper around youtube_explode_dart: video details + audio sources.
class YoutubeService {
  YoutubeService._();
  static final instance = YoutubeService._();

  YoutubeExplode _yt = YoutubeExplode();
  final _cache = <String, VideoInfo>{};

  static const _timeout = Duration(seconds: 30);

  static final _idPatterns = [
    RegExp(r'[?&]v=([A-Za-z0-9_-]{11})'),
    RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})'),
    RegExp(r'/shorts/([A-Za-z0-9_-]{11})'),
    RegExp(r'/live/([A-Za-z0-9_-]{11})'),
    RegExp(r'/embed/([A-Za-z0-9_-]{11})'),
  ];

  /// Returns the 11-character video id if [url] points at a single video.
  static String? videoIdFrom(String? url) {
    if (url == null) return null;
    final uri = Uri.tryParse(url.trim().startsWith('http')
        ? url.trim()
        : 'https://${url.trim()}');
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    final isYoutube = host == 'youtu.be' ||
        host.endsWith('youtube.com') ||
        host.endsWith('youtube-nocookie.com');
    if (!isYoutube) return null;
    for (final p in _idPatterns) {
      final m = p.firstMatch(uri.toString());
      if (m != null) return m.group(1);
    }
    return null;
  }

  Future<VideoInfo> info(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    final v = await _yt.videos.get(id).timeout(_timeout);
    final info = VideoInfo(
      id: id,
      title: v.title,
      author: v.author,
      duration: v.duration,
      thumbnailUrl: v.thumbnails.mediumResUrl,
    );
    _cache[id] = info;
    return info;
  }

  /// Audio sources to try, best first. Each player client is only asked when
  /// every source from the previous one has failed, because YouTube blocks
  /// different clients/streams at different times:
  ///   1. audio-only streams (best bitrate first)
  ///   2. the combined 360p stream, whose audio ffmpeg extracts
  Stream<AudioCandidate> candidates(String id) async* {
    final clients = <(String, List<YoutubeApiClient>?)>[
      ('default', null), // library default (androidSdkless in 3.x)
      ('android_vr', [YoutubeApiClient.androidVr]),
      ('ios', [YoutubeApiClient.ios]),
    ];
    final seen = <String>{};
    Object? lastError;
    var yielded = 0;

    for (final (label, ytClients) in clients) {
      StreamManifest manifest;
      try {
        manifest = await (ytClients == null
                ? _yt.videos.streamsClient.getManifest(id)
                : _yt.videos.streamsClient.getManifest(id, ytClients: ytClients))
            .timeout(_timeout);
      } catch (e) {
        lastError = e;
        continue;
      }

      final audio = manifest.audioOnly
          .where((s) => s.fragments.isEmpty && s.size.totalBytes > 0)
          .toList()
        ..sort((a, b) =>
            b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
      final muxed = manifest.muxed
          .where((s) => s.fragments.isEmpty && s.size.totalBytes > 0)
          .toList()
        ..sort((a, b) => a.size.totalBytes.compareTo(b.size.totalBytes));

      for (final s in [...audio.take(2), ...muxed.take(1)]) {
        if (!seen.add(s.url.toString())) continue;
        yielded++;
        yield AudioCandidate(
          url: s.url,
          size: s.size.totalBytes,
          extension: s.container.name,
          isMuxed: s is MuxedStreamInfo,
          clientLabel: label,
        );
      }
    }

    if (yielded == 0) {
      throw Exception(lastError == null
          ? 'No downloadable audio found for this video.'
          : _friendly(lastError));
    }
  }

  /// Recreate the client (drops stale sessions after errors).
  void reset() {
    _yt.close();
    _yt = YoutubeExplode();
  }

  static String _friendly(Object e) {
    final s = e.toString();
    final lower = s.toLowerCase();
    if (e is TimeoutException || lower.contains('timeout')) {
      return 'YouTube is not responding. Try again in a bit.';
    }
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup')) {
      return 'No internet connection.';
    }
    if (lower.contains('private')) return 'This video is private.';
    if (lower.contains('age') && lower.contains('restrict')) {
      return 'This video is age-restricted.';
    }
    if (lower.contains('unplayable') || lower.contains('unavailable')) {
      return 'This video is unavailable.';
    }
    return s.replaceFirst('Exception: ', '');
  }

  static String friendlyError(Object e) => _friendly(e);
}
