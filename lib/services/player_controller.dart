import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

import 'audio_fx.dart';
import 'library_service.dart';
import 'playlist_service.dart';
import 'settings_service.dart';
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
    player.positionStream.listen(_applyCrossfade);
    player.currentIndexStream.listen(_onIndexChanged);
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

  /// The equalizer sits in the player's audio pipeline.
  final AudioPlayer player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [AudioFx.equalizer]),
  );

  // --- Crossfade: fade out the end of a song, fade in the next one ----------

  int? _lastIndex;
  Duration _lastPos = Duration.zero;
  bool _fadeIn = false;
  double _volume = 1;

  final _rand = math.Random();

  void _onIndexChanged(int? index) {
    final cf = SettingsService.instance.crossfadeSeconds;
    // Only fade in when the previous song ran to its end (not a manual skip).
    final endedNaturally = _lastIndex != null &&
        index != _lastIndex &&
        cf > 0 &&
        _lastPos > Duration.zero &&
        _lastPosNearEnd;
    _fadeIn = endedNaturally;
    _lastIndex = index;
    if (!_fadeIn) _setVolume(1);
  }

  bool _lastPosNearEnd = false;

  void _applyCrossfade(Duration pos) {
    final cf = SettingsService.instance.crossfadeSeconds;
    final dur = player.duration;
    _lastPos = pos;
    if (cf <= 0 || dur == null || dur.inMilliseconds <= 0) {
      _lastPosNearEnd = false;
      if (_volume != 1) _setVolume(1);
      return;
    }
    final cfMs = cf * 1000;
    final remaining = (dur - pos).inMilliseconds.toDouble();
    _lastPosNearEnd = remaining < 1500;
    final continues = player.hasNext || player.loopMode != LoopMode.off;
    var v = 1.0;
    // Long enough songs only, so short clips aren't swallowed by the fade.
    if (dur.inMilliseconds > cfMs * 3) {
      if (continues && remaining < cfMs) v = (remaining / cfMs).clamp(0.0, 1.0);
      if (_fadeIn) {
        final f = (pos.inMilliseconds / cfMs).clamp(0.0, 1.0);
        if (f >= 1) _fadeIn = false;
        v = v < f ? v : f;
      }
    }
    if ((v - _volume).abs() > 0.02 || (v == 1 && _volume != 1)) _setVolume(v);
  }

  void _setVolume(double v) {
    _volume = v;
    player.setVolume(v < 0.05 ? 0.05 : v);
  }
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
    // Disabled songs (e.g. ringtones) never play.
    final lists = PlaylistService.instance;
    if (lists.isDisabled(path)) return;
    queue = lists.playable(queue);
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
      AudioFx.apply(); // equalizer settings, once the player has loaded
    } catch (_) {
      await stop();
    }
    _changed();
  }

  /// Shake to shuffle: jump to a random (enabled) song. Returns its title.
  Future<String?> shuffleJump() async {
    final lists = PlaylistService.instance;
    final seq = queue;
    final cur = currentIndex;
    final options = [
      for (var i = 0; i < seq.length; i++)
        if (i != cur && !lists.isDisabled(seq[i].id)) i,
    ];
    if (options.isNotEmpty) {
      final i = options[_rand.nextInt(options.length)];
      await jumpTo(i);
      return seq[i].title;
    }
    // Nothing else queued: shuffle the whole library.
    final all = lists.playable(LibraryService.instance.songs.map((s) => s.path));
    if (all.isEmpty) return null;
    final pick = all[_rand.nextInt(all.length)];
    try {
      await player.setShuffleModeEnabled(true);
      await player.setAudioSources([for (final p in all) _source(p)],
          initialIndex: all.indexOf(pick));
      await player.shuffle();
      player.play();
      AudioFx.apply();
    } catch (_) {
      await stop();
    }
    _changed();
    return currentTitle;
  }

  Future<void> shuffleAll(List<String> queue) async {
    queue = PlaylistService.instance.playable(queue);
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
    if (PlaylistService.instance.isDisabled(path)) return;
    final i = currentIndex;
    if (i == null) return play(path, [path]);
    await player.insertAudioSource(i + 1, _source(path));
  }

  /// Adds [path] to the end of the queue (or plays it if nothing is).
  Future<void> addToQueue(String path) async {
    if (PlaylistService.instance.isDisabled(path)) return;
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

  /// After songs are disabled, take them out of the upcoming queue
  /// (the one playing right now finishes normally).
  Future<void> dropDisabled() async {
    final lists = PlaylistService.instance;
    final seq = queue;
    final cur = currentIndex;
    for (var i = seq.length - 1; i >= 0; i--) {
      if (i != cur && lists.isDisabled(seq[i].id)) {
        await player.removeAudioSourceAt(i);
      }
    }
  }

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
