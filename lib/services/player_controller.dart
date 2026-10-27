import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

import 'library_service.dart';
import 'playlist_service.dart';
import 'widget_service.dart';

/// One shared player for the whole app (Music and MP3 parts), with an
/// editable queue, shuffle/repeat, lock-screen controls and the home widget.
class PlayerController extends ChangeNotifier {
  PlayerController._() {
    player.currentIndexStream.listen((_) => _changed());
    player.sequenceStream.listen((_) => _changed());
    player.playerStateStream.listen((_) => _changed());
    player.shuffleModeEnabledStream.listen((_) => _changed());
    player.loopModeStream.listen((_) => _changed());
    player.positionStream.listen(_trackPlays);
  }

  // A song counts as played once it has run for 30 s (or half of a short one).
  String? _countKey;
  bool _counted = false;

  void _trackPlays(Duration pos) {
    final path = currentPath;
    if (path == null) return;
    final key = '$path#${player.currentIndex}';
    if (key != _countKey) {
      _countKey = key;
      _counted = false;
    }
    // Replaying the same song (repeat one / seek to start) counts again.
    if (_counted && pos < const Duration(seconds: 2)) _counted = false;
    if (_counted) return;
    final dur = player.duration;
    final threshold = dur != null && dur < const Duration(seconds: 60)
        ? dur ~/ 2
        : const Duration(seconds: 30);
    if (pos >= threshold) {
      _counted = true;
      PlaylistService.instance.countPlay(path);
    }
  }
  static final instance = PlayerController._();

  final AudioPlayer player = AudioPlayer();
  bool _askedNotifications = false;

  void _changed() {
    notifyListeners();
    WidgetService.instance.update(
      title: currentItem?.title,
      artist: currentItem?.artist,
      artPath: currentItem?.artUri?.toFilePath(),
      playing: isPlaying,
    );
  }

  bool get isPlaying => player.playing && currentItem != null;
  bool get shuffle => player.shuffleModeEnabled;
  LoopMode get loopMode => player.loopMode;

  /// The queue in playlist order.
  List<MediaItem> get queue =>
      player.sequence.map((s) => s.tag as MediaItem).toList();

  int? get currentIndex {
    final i = player.currentIndex;
    if (i == null || i < 0 || i >= player.sequence.length) return null;
    return i;
  }

  MediaItem? get currentItem {
    final i = currentIndex;
    return i == null ? null : player.sequence[i].tag as MediaItem;
  }

  String? get currentPath => currentItem?.id;
  String? get currentTitle => currentItem?.title;
  String? get currentArtist => currentItem?.artist;
  String? get currentAlbum => currentItem?.album;
  String? get currentArt => currentItem?.artUri?.toFilePath();

  // --- Names when a file has no tags --------------------------------------

  static String _stem(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.toLowerCase().endsWith('.mp3')
        ? name.substring(0, name.length - 4)
        : name;
  }

  static String titleOf(String path) {
    final song = LibraryService.instance.songFor(path);
    if (song != null) return song.title;
    final s = _stem(path);
    final i = s.indexOf(' - ');
    return i > 0 ? s.substring(i + 3).trim() : s;
  }

  static String artistOf(String path) {
    final song = LibraryService.instance.songFor(path);
    if (song != null) return song.artist;
    final s = _stem(path);
    final i = s.indexOf(' - ');
    if (i > 0) return s.substring(0, i).trim();
    final parts = path.split(Platform.pathSeparator);
    return parts.length > 1 ? parts[parts.length - 2] : '';
  }

  static String? artOf(String path) {
    final art = LibraryService.instance.songFor(path)?.artPath;
    return art != null && File(art).existsSync() ? art : null;
  }

  AudioSource _source(String path) {
    final song = LibraryService.instance.songFor(path);
    final art = artOf(path);
    return AudioSource.file(
      path,
      tag: MediaItem(
        id: path,
        title: titleOf(path),
        artist: artistOf(path),
        album: song?.album ?? 'Grab',
        duration: song?.duration,
        artUri: art == null ? null : Uri.file(art),
      ),
    );
  }

  // --- Playback ------------------------------------------------------------

  /// Plays [path] with [queue] as the playlist. Tapping the current song
  /// toggles play/pause.
  Future<void> play(String path, List<String> queue,
      {bool shuffleAll = false}) async {
    if (!shuffleAll && currentPath == path) {
      await toggle();
      return;
    }
    await _askNotifications();
    if (queue.isEmpty) queue = [path];
    try {
      await player.setShuffleModeEnabled(shuffleAll || player.shuffleModeEnabled);
      await player.setAudioSources(
        [for (final p in queue) _source(p)],
        initialIndex: queue.indexOf(path).clamp(0, queue.length - 1),
      );
      if (shuffleAll) await player.shuffle();
      player.play();
    } catch (_) {
      await stop();
    }
    _changed();
  }

  Future<void> shuffleAll(List<String> queue) async {
    if (queue.isEmpty) return;
    final start = (List.of(queue)..shuffle()).first;
    await play(start, queue, shuffleAll: true);
  }

  Future<void> toggle() async {
    if (currentItem == null) return;
    if (player.playing) {
      await player.pause();
    } else {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero, index: player.effectiveIndices.first);
      }
      player.play();
    }
  }

  /// Stops playback and clears the queue (hides the mini player).
  Future<void> stop() async {
    try {
      await player.stop();
      await player.clearAudioSources();
    } catch (_) {}
    _changed();
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

  // --- Queue editing -------------------------------------------------------

  /// Puts [path] right after the current song (or plays it if nothing is).
  Future<void> playNext(String path) async {
    final i = currentIndex;
    if (i == null) return play(path, [path]);
    await player.insertAudioSource(i + 1, _source(path));
  }

  /// Adds [path] to the end of the queue (or plays it if nothing is).
  Future<void> addToQueue(String path) async {
    if (currentIndex == null) return play(path, [path]);
    await player.addAudioSource(_source(path));
  }

  Future<void> jumpTo(int index) async {
    await player.seek(Duration.zero, index: index);
    if (!player.playing) player.play();
  }

  Future<void> removeAt(int index) async {
    if (player.sequence.length <= 1) return stop();
    await player.removeAudioSourceAt(index);
  }

  Future<void> move(int from, int to) => player.moveAudioSource(from, to);

  /// Removes a deleted file from the queue.
  Future<void> forget(String path) async {
    final seq = queue;
    for (var i = seq.length - 1; i >= 0; i--) {
      if (seq[i].id == path) await removeAt(i);
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
