import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'library_service.dart';
import 'playlist_service.dart';
import 'storage_service.dart';
import 'youtube_service.dart';

enum TaskStatus { queued, fetching, downloading, converting, done, failed, cancelled }

class DownloadTask {
  DownloadTask({
    required this.info,
    required this.bitrate,
    required this.fileName,
    required this.tagTitle,
    required this.tagArtist,
  });

  final VideoInfo info;
  final int bitrate;
  final String fileName;
  final String tagTitle;
  final String tagArtist;

  TaskStatus status = TaskStatus.queued;
  double progress = 0; // 0..1
  int received = 0;
  int total = 0;
  int attempt = 0; // which source is being tried (1-based)
  String? error;
  String? outputPath;

  bool _cancelled = false;
  HttpClient? _http;
  int? _ffmpegSessionId;

  bool get isActive =>
      status == TaskStatus.queued ||
      status == TaskStatus.fetching ||
      status == TaskStatus.downloading ||
      status == TaskStatus.converting;
}

class _Cancelled implements Exception {}

class _SourceFailed implements Exception {
  _SourceFailed(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Downloads audio one task at a time and converts it to MP3 on-device.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final instance = DownloadManager._();

  /// No bytes for this long = the source is stalled; try the next one.
  static const _idleTimeout = Duration(seconds: 20);
  static const _connectTimeout = Duration(seconds: 15);

  /// YouTube throttles big single requests; fetch in ~10 MB ranges.
  static const _chunk = 10 * 1024 * 1024;

  final List<DownloadTask> tasks = [];
  List<File> library = [];
  bool _running = false;

  List<DownloadTask> get active =>
      tasks.where((t) => t.isActive || t.status == TaskStatus.failed).toList();

  Future<void> refreshLibrary() async {
    try {
      final dir = await StorageService.instance.musicDir();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.mp3'))
          .where((f) => !f.path.split('/').last.startsWith('.'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      library = files;
    } catch (_) {
      library = [];
    }
    notifyListeners();
  }

  void enqueue({
    required VideoInfo info,
    required int bitrate,
    required String fileName,
    required String tagTitle,
    required String tagArtist,
  }) {
    tasks.add(DownloadTask(
      info: info,
      bitrate: bitrate,
      fileName: fileName,
      tagTitle: tagTitle,
      tagArtist: tagArtist,
    ));
    notifyListeners();
    _pump();
  }

  void retry(DownloadTask t) {
    tasks.remove(t);
    enqueue(
      info: t.info,
      bitrate: t.bitrate,
      fileName: t.fileName,
      tagTitle: t.tagTitle,
      tagArtist: t.tagArtist,
    );
  }

  void dismiss(DownloadTask t) {
    tasks.remove(t);
    notifyListeners();
  }

  /// Stops a task right away, whatever it is doing.
  void cancel(DownloadTask t) {
    t._cancelled = true;
    t.status = TaskStatus.cancelled;
    tasks.remove(t);
    notifyListeners();
    // Abort network and conversion without waiting on them.
    try {
      t._http?.close(force: true);
    } catch (_) {}
    final sid = t._ffmpegSessionId;
    if (sid != null) {
      FFmpegKit.cancel(sid).catchError((_) {});
    }
  }

  Future<void> deleteFile(File f) async {
    try {
      await f.delete();
    } catch (_) {}
    LibraryService.instance.removeFile(f.path);
    PlaylistService.instance.forget(f.path);
    await refreshLibrary();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = tasks
            .where((t) => t.status == TaskStatus.queued && !t._cancelled)
            .firstOrNull;
        if (next == null) break;
        await _run(next);
      }
    } finally {
      _running = false;
    }
  }

  void _notifyIfActive(DownloadTask t) {
    if (!t._cancelled) notifyListeners();
  }

  Future<void> _run(DownloadTask t) async {
    File? tmp;
    File? cover;
    try {
      await StorageService.instance.ensurePermission();
      if (t._cancelled) throw _Cancelled();

      t.status = TaskStatus.fetching;
      _notifyIfActive(t);

      final tmpDir = await getTemporaryDirectory();
      String? lastReason;
      var ok = false;

      await for (final source
          in YoutubeService.instance.candidates(t.info.id)) {
        if (t._cancelled) throw _Cancelled();
        t.attempt++;
        t.status = TaskStatus.downloading;
        t.received = 0;
        t.total = source.size;
        t.progress = 0;
        _notifyIfActive(t);

        tmp = File('${tmpDir.path}/${t.info.id}_${t.attempt}.${source.extension}');
        try {
          await _download(t, source, tmp);
          ok = true;
          break;
        } on _Cancelled {
          rethrow;
        } catch (e) {
          if (t._cancelled) throw _Cancelled();
          lastReason = e.toString();
          try {
            if (await tmp.exists()) await tmp.delete();
          } catch (_) {}
          tmp = null;
          t.status = TaskStatus.fetching;
          _notifyIfActive(t);
        }
      }
      if (t._cancelled) throw _Cancelled();
      if (!ok || tmp == null) {
        throw Exception(
            'YouTube refused every audio source${lastReason == null ? '' : ' ($lastReason)'}. '
            'Try again later or update the app.');
      }

      t.status = TaskStatus.converting;
      t.progress = 0.85;
      _notifyIfActive(t);

      final out = await StorageService.instance.uniqueFile(t.fileName);
      cover = await _downloadCover(t, tmpDir);
      var converted = await _convert(t, tmp, out, cover);
      if (!converted && cover != null && !t._cancelled) {
        // Retry without cover art if embedding it was the problem.
        converted = await _convert(t, tmp, out, null);
      }
      if (t._cancelled) throw _Cancelled();
      if (!converted) throw Exception('Converting to MP3 failed.');

      t.outputPath = out.path;
      t.progress = 1;
      t.status = TaskStatus.done;
      tasks.remove(t);
      await refreshLibrary();
      LibraryService.instance.addFile(out.path);
    } on _Cancelled {
      t.status = TaskStatus.cancelled;
      tasks.remove(t);
    } catch (e) {
      if (t._cancelled) {
        t.status = TaskStatus.cancelled;
        tasks.remove(t);
      } else {
        t.status = TaskStatus.failed;
        t.error = YoutubeService.friendlyError(e);
        YoutubeService.instance.reset();
      }
    } finally {
      t._http = null;
      t._ffmpegSessionId = null;
      for (final f in [tmp, cover]) {
        try {
          if (f != null && await f.exists()) await f.delete();
        } catch (_) {}
      }
      notifyListeners();
    }
  }

  /// Best available video thumbnail, used as the MP3's cover art.
  Future<File?> _downloadCover(DownloadTask t, Directory tmpDir) async {
    final id = t.info.id;
    final urls = [
      // 1280×720 and 320×180 are true 16:9 (no black bars, unlike hqdefault).
      'https://i.ytimg.com/vi/$id/maxresdefault.jpg',
      'https://i.ytimg.com/vi/$id/mqdefault.jpg',
      t.info.thumbnailUrl,
    ];
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      for (final u in urls) {
        try {
          final req = await client.getUrl(Uri.parse(u)).timeout(_idleTimeout);
          final res = await req.close().timeout(_idleTimeout);
          if (res.statusCode != 200) {
            res.drain<void>().catchError((_) {});
            continue;
          }
          final bytes = await res
              .fold<List<int>>(<int>[], (a, b) => a..addAll(b))
              .timeout(_idleTimeout);
          if (bytes.length < 2048) continue; // placeholder image
          final f = File('${tmpDir.path}/${id}_cover.jpg');
          await f.writeAsBytes(bytes, flush: true);
          return f;
        } catch (_) {}
      }
    } finally {
      client.close(force: true);
    }
    return null;
  }

  /// Downloads [source] into [dest] in ranged chunks, failing fast on HTTP
  /// errors or when the connection goes quiet.
  Future<void> _download(DownloadTask t, AudioCandidate source, File dest) async {
    final client = HttpClient()
      ..connectionTimeout = _connectTimeout
      ..idleTimeout = const Duration(seconds: 5);
    t._http = client;
    final sink = dest.openWrite();
    final isAndroidUrl = source.url.queryParameters['c'] == 'ANDROID';
    var pos = 0;
    var lastNotified = -1.0;
    try {
      while (pos < source.size) {
        if (t._cancelled) throw _Cancelled();
        final to = min(pos + _chunk, source.size) - 1;
        final uri = isAndroidUrl
            ? source.url
            : Uri.parse('${source.url}&range=$pos-$to');

        final req = await client.getUrl(uri).timeout(_idleTimeout);
        if (isAndroidUrl) {
          req.headers.set(HttpHeaders.rangeHeader, 'bytes=$pos-$to');
          req.headers.set(HttpHeaders.userAgentHeader,
              'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip');
        }
        final res = await req.close().timeout(_idleTimeout);
        if (res.statusCode >= 400) {
          res.drain<void>().catchError((_) {});
          throw _SourceFailed('HTTP ${res.statusCode}');
        }

        final before = pos;
        await for (final data in res.timeout(_idleTimeout,
            onTimeout: (s) => s.addError(_SourceFailed('stalled')))) {
          if (t._cancelled) throw _Cancelled();
          sink.add(data);
          pos += data.length;
          t.received = pos;
          t.progress = 0.85 * pos / source.size;
          if (t.progress - lastNotified >= 0.005) {
            lastNotified = t.progress;
            _notifyIfActive(t);
          }
        }
        if (pos == before) throw _SourceFailed('empty response');
      }
    } on _Cancelled {
      rethrow;
    } catch (e) {
      if (t._cancelled) throw _Cancelled();
      rethrow;
    } finally {
      await sink.flush().catchError((_) {});
      await sink.close().catchError((_) {});
      client.close(force: true);
      if (identical(t._http, client)) t._http = null;
    }
  }

  Future<bool> _convert(
      DownloadTask t, File input, File out, File? cover) async {
    final done = Completer<bool>();
    final durationMs = t.info.duration?.inMilliseconds ?? 0;
    final args = [
      '-y',
      '-i', input.path,
      if (cover != null) ...['-i', cover.path],
      '-map', '0:a:0',
      if (cover != null) ...['-map', '1:0'],
      '-c:a', 'libmp3lame',
      '-b:a', '${t.bitrate}k',
      if (cover != null) ...[
        '-c:v', 'copy',
        '-disposition:v', 'attached_pic',
        '-metadata:s:v', 'title=Album cover',
        '-metadata:s:v', 'comment=Cover (front)',
      ],
      '-id3v2_version', '3',
      '-metadata', 'title=${t.tagTitle}',
      '-metadata', 'artist=${t.tagArtist}',
      '-metadata', 'album_artist=${t.tagArtist}',
      '-metadata', 'comment=youtube.com/watch?v=${t.info.id}',
      out.path,
    ];
    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        final code = await session.getReturnCode();
        if (!done.isCompleted) done.complete(ReturnCode.isSuccess(code));
      },
      null,
      (stats) {
        if (durationMs > 0 && !t._cancelled) {
          final frac = (stats.getTime() / durationMs).clamp(0.0, 1.0);
          t.progress = 0.85 + 0.15 * frac;
          notifyListeners();
        }
      },
    );
    t._ffmpegSessionId = session.getSessionId();
    if (t._cancelled) {
      FFmpegKit.cancel(t._ffmpegSessionId).catchError((_) {});
    }
    final ok = await done.future;
    if (!ok) {
      try {
        if (await out.exists()) await out.delete();
      } catch (_) {}
    }
    return ok;
  }
}
