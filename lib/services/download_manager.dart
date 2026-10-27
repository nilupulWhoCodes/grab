import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'storage_service.dart';
import 'youtube_service.dart';

enum TaskStatus { queued, fetching, downloading, converting, done, failed, cancelled }

class DownloadTask {
  DownloadTask({
    required this.info,
    required this.bitrate,
    required this.fileName,
  });

  final VideoInfo info;
  final int bitrate;
  final String fileName;

  TaskStatus status = TaskStatus.queued;
  double progress = 0; // 0..1
  int received = 0;
  int total = 0;
  String? error;
  String? outputPath;

  bool _cancelled = false;
  StreamSubscription<List<int>>? _sub;
  Completer<void>? _streamDone;
  int? _ffmpegSessionId;

  bool get isActive =>
      status == TaskStatus.queued ||
      status == TaskStatus.fetching ||
      status == TaskStatus.downloading ||
      status == TaskStatus.converting;
}

class _Cancelled implements Exception {}

/// Downloads audio streams one at a time and converts them to MP3 on-device.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final instance = DownloadManager._();

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
  }) {
    tasks.add(DownloadTask(info: info, bitrate: bitrate, fileName: fileName));
    notifyListeners();
    _pump();
  }

  void retry(DownloadTask t) {
    tasks.remove(t);
    enqueue(info: t.info, bitrate: t.bitrate, fileName: t.fileName);
  }

  void dismiss(DownloadTask t) {
    tasks.remove(t);
    notifyListeners();
  }

  Future<void> cancel(DownloadTask t) async {
    t._cancelled = true;
    await t._sub?.cancel();
    if (t._streamDone != null && !t._streamDone!.isCompleted) {
      t._streamDone!.completeError(_Cancelled());
    }
    if (t._ffmpegSessionId != null) {
      await FFmpegKit.cancel(t._ffmpegSessionId);
    }
    if (t.status == TaskStatus.queued) {
      t.status = TaskStatus.cancelled;
      tasks.remove(t);
    }
    notifyListeners();
  }

  Future<void> deleteFile(File f) async {
    try {
      await f.delete();
    } catch (_) {}
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

  Future<void> _run(DownloadTask t) async {
    File? tmp;
    var lastNotified = -1.0;
    void update({bool force = false}) {
      if (force || (t.progress - lastNotified).abs() >= 0.005) {
        lastNotified = t.progress;
        notifyListeners();
      }
    }

    try {
      await StorageService.instance.ensurePermission();

      t.status = TaskStatus.fetching;
      update(force: true);
      final audio = await YoutubeService.instance.bestAudio(t.info.id);
      if (t._cancelled) throw _Cancelled();

      t.total = audio.size.totalBytes;
      t.status = TaskStatus.downloading;
      update(force: true);

      final tmpDir = await getTemporaryDirectory();
      tmp = File('${tmpDir.path}/${t.info.id}.${audio.container.name}');
      final sink = tmp.openWrite();
      t._streamDone = Completer<void>();
      t._sub = YoutubeService.instance.open(audio).listen(
        (chunk) {
          sink.add(chunk);
          t.received += chunk.length;
          if (t.total > 0) t.progress = 0.85 * t.received / t.total;
          update();
        },
        onError: (Object e) {
          if (!t._streamDone!.isCompleted) t._streamDone!.completeError(e);
        },
        onDone: () {
          if (!t._streamDone!.isCompleted) t._streamDone!.complete();
        },
        cancelOnError: true,
      );
      try {
        await t._streamDone!.future;
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (t._cancelled) throw _Cancelled();

      t.status = TaskStatus.converting;
      t.progress = 0.85;
      update(force: true);

      final out = await StorageService.instance.uniqueFile(t.fileName);
      final ok = await _convert(t, tmp, out);
      if (t._cancelled) throw _Cancelled();
      if (!ok) throw Exception('Converting to MP3 failed.');

      t.outputPath = out.path;
      t.progress = 1;
      t.status = TaskStatus.done;
      tasks.remove(t);
      await refreshLibrary();
    } on _Cancelled {
      t.status = TaskStatus.cancelled;
      tasks.remove(t);
    } catch (e) {
      t.status = TaskStatus.failed;
      t.error = YoutubeService.friendlyError(e);
      YoutubeService.instance.reset();
    } finally {
      t._sub = null;
      t._ffmpegSessionId = null;
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<bool> _convert(DownloadTask t, File input, File out) async {
    final done = Completer<bool>();
    final durationMs = t.info.duration?.inMilliseconds ?? 0;
    final args = [
      '-y',
      '-i', input.path,
      '-vn',
      '-c:a', 'libmp3lame',
      '-b:a', '${t.bitrate}k',
      '-id3v2_version', '3',
      '-metadata', 'title=${t.info.title}',
      '-metadata', 'artist=${t.info.author}',
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
        if (durationMs > 0) {
          final frac = (stats.getTime() / durationMs).clamp(0.0, 1.0);
          t.progress = 0.85 + 0.15 * frac;
          notifyListeners();
        }
      },
    );
    t._ffmpegSessionId = session.getSessionId();
    final ok = await done.future;
    if (!ok) {
      try {
        if (await out.exists()) await out.delete();
      } catch (_) {}
    }
    return ok;
  }
}
