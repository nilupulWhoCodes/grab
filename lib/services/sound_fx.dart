import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/services.dart';

import 'library_service.dart';
import 'player_controller.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// Speed, pitch and reverb: live on the player, or rendered into a new MP3.
class SoundFx {
  SoundFx._();

  static const _reverb = MethodChannel('grab/reverb');
  static String? reverbError;
  static StreamSubscription<int?>? _sessionSub;

  static const presets = {
    FxMode.normal: (1.0, ReverbPreset.none),
    FxMode.nightcore: (1.25, ReverbPreset.none),
    FxMode.slowedReverb: (0.8, ReverbPreset.largeHall),
  };

  /// Re-attach reverb whenever the player gets a new audio session.
  static void init() {
    _sessionSub ??= PlayerController.instance.player.androidAudioSessionIdStream
        .listen((_) => _applyReverb());
  }

  static Future<void> apply() async {
    final s = SettingsService.instance;
    final player = PlayerController.instance.player;
    try {
      await player.setSpeed(s.speed);
      await player.setPitch(s.effectivePitch);
    } catch (_) {}
    await _applyReverb();
  }

  static Future<void> setMode(FxMode mode) async {
    final preset = presets[mode];
    SettingsService.instance.update((s) {
      s.fxMode = mode;
      if (preset != null) {
        s.speed = preset.$1;
        s.pitch = preset.$1;
        s.linkPitch = true;
        s.reverb = preset.$2;
      }
    });
    await apply();
  }

  /// Any manual change switches to Custom.
  static Future<void> change(void Function(SettingsService s) edit) async {
    SettingsService.instance.update((s) {
      edit(s);
      s.fxMode = FxMode.custom;
    });
    await apply();
  }

  static Future<void> _applyReverb() async {
    if (!Platform.isAndroid) return;
    final s = SettingsService.instance;
    final session = PlayerController.instance.player.androidAudioSessionId ?? 0;
    try {
      await _reverb.invokeMethod('set', {
        'session': session,
        'preset': s.reverb.index,
      });
      reverbError = null;
    } on PlatformException catch (e) {
      reverbError = s.reverb == ReverbPreset.none
          ? null
          : 'Live reverb isn\'t supported on this phone (${e.message}). '
              '"Save as new MP3" still adds it.';
    } catch (_) {}
  }

  // --- Render to a new MP3 ---------------------------------------------------

  /// ffmpeg echo settings that sound like each reverb preset.
  static String? _echo(ReverbPreset r) => switch (r) {
        ReverbPreset.none => null,
        ReverbPreset.smallRoom => 'aecho=0.8:0.6:20|35:0.35|0.25',
        ReverbPreset.mediumRoom => 'aecho=0.8:0.7:40|70:0.4|0.3',
        ReverbPreset.largeRoom => 'aecho=0.8:0.75:60|110|160:0.4|0.3|0.2',
        ReverbPreset.mediumHall =>
          'aecho=0.8:0.8:80|150|230:0.45|0.32|0.22',
        ReverbPreset.largeHall =>
          'aecho=0.8:0.85:120|220|330|450:0.45|0.35|0.25|0.18',
        ReverbPreset.plate => 'aecho=0.8:0.7:15|30|45:0.35|0.25|0.15',
      };

  /// atempo only accepts 0.5–2.0 per filter, so chain as needed.
  static List<String> _tempo(double t) {
    final out = <String>[];
    while (t > 2.0) {
      out.add('atempo=2.0');
      t /= 2.0;
    }
    while (t < 0.5) {
      out.add('atempo=0.5');
      t /= 0.5;
    }
    if ((t - 1).abs() > 0.001) out.add('atempo=${t.toStringAsFixed(4)}');
    return out;
  }

  static String _suffix(SettingsService s) {
    if (s.fxMode == FxMode.nightcore) return 'nightcore';
    if (s.fxMode == FxMode.slowedReverb) return 'slowed + reverb';
    final parts = [
      if ((s.speed - 1).abs() > 0.001) '${s.speed.toStringAsFixed(2)}x',
      if (!s.linkPitch && (s.pitch - 1).abs() > 0.001)
        'pitch ${s.pitch.toStringAsFixed(2)}',
      if (s.reverb != ReverbPreset.none) 'reverb',
    ];
    return parts.isEmpty ? 'edit' : parts.join(' ');
  }

  /// Renders [path] with the current speed/pitch/reverb into Music/Grab.
  /// [onProgress] gets 0..1. Returns the new file, or throws.
  static Future<File> exportCurrent(String path,
      {void Function(double)? onProgress}) async {
    final s = SettingsService.instance;
    final speed = s.speed;
    final pitch = s.effectivePitch;
    final song = LibraryService.instance.songFor(path);
    final title = PlayerController.titleOf(path);
    final artist = PlayerController.artistOf(path);
    final suffix = _suffix(s);
    final out = await StorageService.instance
        .uniqueFile('${artist.isEmpty ? '' : '$artist - '}$title ($suffix)');

    // Pitch: resample trick; then fix the tempo so speed is what was asked.
    final filters = <String>[
      'aresample=44100',
      if ((pitch - 1).abs() > 0.001) ...[
        'asetrate=${(44100 * pitch).round()}',
        'aresample=44100',
      ],
      ..._tempo(speed / pitch),
      if (_echo(s.reverb) != null) _echo(s.reverb)!,
    ];

    final args = [
      '-y',
      '-i', path,
      '-map', '0:a:0',
      '-map', '0:v?',
      '-af', filters.join(','),
      '-c:a', 'libmp3lame',
      '-b:a', '256k',
      '-c:v', 'copy',
      '-disposition:v', 'attached_pic',
      '-map_metadata', '0',
      '-id3v2_version', '3',
      '-metadata', 'title=$title ($suffix)',
      out.path,
    ];

    final totalMs =
        (song?.duration?.inMilliseconds ?? 0) / (speed <= 0 ? 1 : speed);
    final done = Completer<bool>();
    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        final code = await session.getReturnCode();
        if (!done.isCompleted) done.complete(ReturnCode.isSuccess(code));
      },
      null,
      (stats) {
        if (totalMs > 0) {
          onProgress?.call((stats.getTime() / totalMs).clamp(0.0, 1.0));
        }
      },
    );
    final ok = await done.future;
    if (!ok) {
      try {
        if (await out.exists()) await out.delete();
      } catch (_) {}
      throw Exception('Could not render the new MP3.');
    }
    await LibraryService.instance.addFile(out.path);
    return out;
  }
}
