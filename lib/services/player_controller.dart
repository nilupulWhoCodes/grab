import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Plays saved MP3s with a simple queue (the current library order).
class PlayerController extends ChangeNotifier {
  PlayerController._() {
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        next();
      }
      notifyListeners();
    });
  }
  static final instance = PlayerController._();

  final AudioPlayer player = AudioPlayer();
  List<String> _queue = [];
  String? currentPath;

  bool get isPlaying => player.playing;

  String? get currentTitle => currentPath == null ? null : titleOf(currentPath!);

  static String titleOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.toLowerCase().endsWith('.mp3')
        ? name.substring(0, name.length - 4)
        : name;
  }

  Future<void> play(String path, List<String> queue) async {
    _queue = queue;
    if (currentPath == path) {
      await toggle();
      return;
    }
    currentPath = path;
    notifyListeners();
    try {
      await player.setFilePath(path);
      player.play();
    } catch (_) {
      currentPath = null;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    if (currentPath == null) return;
    if (player.playing) {
      await player.pause();
    } else {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      player.play();
    }
    notifyListeners();
  }

  Future<void> next() => _step(1);
  Future<void> previous() async {
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }
    await _step(-1);
  }

  Future<void> _step(int delta) async {
    if (currentPath == null || _queue.isEmpty) return;
    final i = _queue.indexOf(currentPath!);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= _queue.length) {
      await player.pause();
      await player.seek(Duration.zero);
      notifyListeners();
      return;
    }
    currentPath = null; // force reload
    await play(_queue[j], _queue);
  }

  /// Stop if the file being removed is playing.
  Future<void> forget(String path) async {
    _queue.remove(path);
    if (currentPath == path) {
      await player.stop();
      currentPath = null;
      notifyListeners();
    }
  }
}
