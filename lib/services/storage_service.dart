import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Decides where MP3s are saved: the phone's shared Music/Grab folder when
/// possible (visible to music players), otherwise the app's own folder.
class StorageService {
  StorageService._();
  static final instance = StorageService._();

  Directory? _dir;
  int? _sdk;

  Future<int> _sdkInt() async {
    if (_sdk != null) return _sdk!;
    if (!Platform.isAndroid) return _sdk = 0;
    final info = await DeviceInfoPlugin().androidInfo;
    return _sdk = info.version.sdkInt;
  }

  /// Asks for the storage/media permission this Android version needs.
  Future<void> ensurePermission() async {
    if (!Platform.isAndroid) return;
    final sdk = await _sdkInt();
    if (sdk <= 29) {
      await Permission.storage.request();
    } else if (sdk >= 33) {
      // Lets the app list MP3s it saved before a reinstall.
      await Permission.audio.request();
    }
  }

  /// Permission to read music files saved by other apps.
  Future<bool> ensureReadPermission() async {
    if (!Platform.isAndroid) return true;
    final sdk = await _sdkInt();
    final p = sdk >= 33 ? Permission.audio : Permission.storage;
    var status = await p.status;
    if (!status.isGranted) status = await p.request();
    return status.isGranted || status.isLimited;
  }

  Future<bool> hasReadPermission() async {
    if (!Platform.isAndroid) return true;
    final sdk = await _sdkInt();
    final p = sdk >= 33 ? Permission.audio : Permission.storage;
    final status = await p.status;
    return status.isGranted || status.isLimited;
  }

  Future<bool> isReadPermissionPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;
    final sdk = await _sdkInt();
    final p = sdk >= 33 ? Permission.audio : Permission.storage;
    return (await p.status).isPermanentlyDenied;
  }

  Future<Directory> musicDir() async {
    if (_dir != null) return _dir!;
    if (Platform.isAndroid) {
      final shared = Directory('/storage/emulated/0/Music/Grab');
      try {
        await shared.create(recursive: true);
        final probe = File('${shared.path}/.grab_probe.mp3');
        await probe.writeAsBytes(const [0]);
        await probe.delete();
        return _dir = shared;
      } catch (_) {
        // fall through to the app folder
      }
    }
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final own = Directory('${base.path}/Music');
    await own.create(recursive: true);
    return _dir = own;
  }

  /// Human-readable location for the UI.
  Future<String> label() async {
    final dir = await musicDir();
    return dir.path.startsWith('/storage/emulated/0/Music')
        ? 'Music / Grab'
        : 'App folder';
  }

  static String sanitizeFileName(String name) {
    var s = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.toLowerCase().endsWith('.mp3')) s = s.substring(0, s.length - 4);
    if (s.length > 120) s = s.substring(0, 120).trim();
    return s.isEmpty ? 'audio' : s;
  }

  Future<File> uniqueFile(String baseName) async {
    final dir = await musicDir();
    final clean = sanitizeFileName(baseName);
    var file = File('${dir.path}/$clean.mp3');
    var n = 2;
    while (await file.exists()) {
      file = File('${dir.path}/$clean ($n).mp3');
      n++;
    }
    return file;
  }
}
