import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

/// One shared player for the whole app (Music and MP3 parts), with a queue,
/// shuffle/repeat and lock-screen controls via just_audio_background.
class PlayerController extends ChangeNotifier {
  PlayerController._() {
    player.currentIndexStream.listen((_) => notifyListeners());
    player.playerStateStream.listen((_) => notifyListeners());
    player.shuffleModeEnabledStream.listen((_) => notifyListeners());
    player.loopModeStream.listen((_) => notifyListeners());
  }
  static final instance = PlayerController._();

  final AudioPlayer player = AudioPlayer();
  List<String> _paths = [];
  bool _askedNotifications = false;

  bool get isPlaying => player.playing;
  bool get shuffle => player.shuffleModeEnabled;
  LoopMode get loopMode => player.loopMode;

  String? get currentPath {
    final i = player.currentIndex;
    if (i == null || i < 0 || i >= _paths.length) return null;
    return _paths[i];
  }

  String? get currentTitle =>
      currentPath == null ? null : titleOf(currentPath!);
  String? get currentArtist =>
      currentPath == null ? null : artistOf(currentPath!);

  static String _stem(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.toLowerCase().endsWith('.mp3')
        ? name.substring(0, name.length - 4)
        : name;
  }

  static String titleOf(String path) {
    final s = _stem(path);
    final i = s.indexOf(' - ');
    return i > 0 ? s.substring(i + 3).trim() : s;
  }

  static String artistOf(String path) {
    final s = _stem(path);
    final i = s.indexOf(' - ');
    if (i > 0) return s.substring(0, i).trim();
    final parts = path.split(Platform.pathSeparator);
    return parts.length > 1 ? parts[parts.length - 2] : '';
  }

  /// Plays [path] with [queue] as the playlist. Tapping the current song
  /// toggles play/pause.
  Future<void> play(String path, List<String> queue,
      {bool shuffleAll = false}) async {
    if (!shuffleAll && currentPath == path) {
      await toggle();
      return;
    }
    await _askNotifications();
    _paths = List.of(queue);
    final sources = [
      for (final p in _paths)
        AudioSource.file(
          p,
          tag: MediaItem(
            id: p,
            title: titleOf(p),
            artist: artistOf(p),
            album: 'Grab',
          ),
        ),
    ];
    try {
      await player.setShuffleModeEnabled(shuffleAll || player.shuffleModeEnabled);
      await player.setAudioSources(
        sources,
        initialIndex: _paths.indexOf(path).clamp(0, _paths.length - 1),
      );
      if (shuffleAll) await player.shuffle();
      player.play();
    } catch (_) {
      _paths = [];
    }
    notifyListeners();
  }

  Future<void> shuffleAll(List<String> queue) async {
    if (queue.isEmpty) return;
    final start = (List.of(queue)..shuffle()).first;
    await play(start, queue, shuffleAll: true);
  }

  Future<void> toggle() async {
    if (currentPath == null) return;
    if (player.playing) {
      await player.pause();
    } else {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero, index: player.effectiveIndices.first);
      }
      player.play();
    }
    notifyListeners();
  }

  Future<void> next() async {
    if (player.hasNext) await player.seekToNext();
  }

  Future<void> previous() async {
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> toggleShuffle() async {
    final on = !player.shuffleModeEnabled;
    if (on) await player.shuffle();
    await player.setShuffleModeEnabled(on);
  }

  Future<void> cycleRepeat() async {
    final next = switch (player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await player.setLoopMode(next);
  }

  /// Stop if the file being removed is playing.
  Future<void> forget(String path) async {
    if (currentPath == path) {
      await player.stop();
      _paths = [];
      notifyListeners();
    }
  }

  Future<void> _askNotifications() async {
    if (_askedNotifications || !Platform.isAndroid) return;
    _askedNotifications = true;
    try {
      await Permission.notification.request();
    } catch (_) {}
  }
}
