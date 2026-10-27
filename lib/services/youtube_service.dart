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

/// Thin wrapper around youtube_explode_dart: video details + audio streams.
class YoutubeService {
  YoutubeService._();
  static final instance = YoutubeService._();

  YoutubeExplode _yt = YoutubeExplode();
  final _cache = <String, VideoInfo>{};

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
    final v = await _yt.videos.get(id);
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

  /// Best audio-only stream. Falls back to alternative player clients when
  /// the default ones fail (YouTube changes these regularly).
  Future<AudioOnlyStreamInfo> bestAudio(String id) async {
    Object? lastError;
    final attempts = <List<YoutubeApiClient>?>[
      null,
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.safari],
    ];
    for (final clients in attempts) {
      try {
        final manifest = clients == null
            ? await _yt.videos.streamsClient.getManifest(id)
            : await _yt.videos.streamsClient
                .getManifest(id, ytClients: clients);
        final audio = manifest.audioOnly;
        if (audio.isNotEmpty) return audio.withHighestBitrate();
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(lastError == null
        ? 'No audio stream found for this video.'
        : _friendly(lastError));
  }

  Stream<List<int>> open(AudioOnlyStreamInfo stream) =>
      _yt.videos.streamsClient.get(stream);

  /// Recreate the client (drops stale sessions after errors).
  void reset() {
    _yt.close();
    _yt = YoutubeExplode();
  }

  static String _friendly(Object e) {
    final s = e.toString();
    final lower = s.toLowerCase();
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
