import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.build,
    required this.version,
    required this.notes,
    required this.url,
    required this.size,
  });

  final int build;
  final String version;
  final String notes;
  final Uri url;
  final int size;
}

enum UpdateState { idle, checking, upToDate, available, downloading, error }

/// Checks the repo's GitHub Releases for a newer build and installs it.
class UpdateService extends ChangeNotifier {
  UpdateService._();
  static final instance = UpdateService._();

  static const _repo = 'nilupulWhoCodes/grab';

  /// Set by CI: `--dart-define=GRAB_BUILD=<run number>`.
  static const currentBuild = int.fromEnvironment('GRAB_BUILD');
  static String get currentVersion =>
      currentBuild == 0 ? 'dev build' : '1.0.$currentBuild';

  UpdateState state = UpdateState.idle;
  UpdateInfo? available;
  double progress = 0;
  String? error;
  bool bannerDismissed = false;

  void dismissBanner() {
    bannerDismissed = true;
    notifyListeners();
  }

  void _set(UpdateState s) {
    state = s;
    notifyListeners();
  }

  /// Quiet check a few seconds after launch.
  void checkSoon() {
    if (!Platform.isAndroid || currentBuild == 0) return;
    Timer(const Duration(seconds: 5), () => check(silent: true));
  }

  Future<void> check({bool silent = false}) async {
    if (state == UpdateState.checking || state == UpdateState.downloading) {
      return;
    }
    _set(UpdateState.checking);
    error = null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client
          .getUrl(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'))
          .timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'Grab-app');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) {
        throw Exception('No releases found. Is the repo public?');
      }
      if (res.statusCode != 200) {
        throw Exception('GitHub answered ${res.statusCode}.');
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String? ?? '';
      final build = int.tryParse(tag.split('.').last) ?? 0;
      if (build <= currentBuild) {
        available = null;
        _set(UpdateState.upToDate);
        return;
      }
      final assets = (json['assets'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final wanted = await _assetName();
      final asset = assets.firstWhere(
        (a) => a['name'] == wanted,
        orElse: () => assets.firstWhere(
          (a) => (a['name'] as String).endsWith('.apk'),
          orElse: () => {},
        ),
      );
      if (asset.isEmpty) throw Exception('The new release has no APK.');
      available = UpdateInfo(
        build: build,
        version: tag.startsWith('v') ? tag.substring(1) : tag,
        notes: (json['body'] as String? ?? '').trim(),
        url: Uri.parse(asset['browser_download_url'] as String),
        size: (asset['size'] as num?)?.toInt() ?? 0,
      );
      bannerDismissed = false;
      _set(UpdateState.available);
    } catch (e) {
      error = e is TimeoutException
          ? 'GitHub did not respond.'
          : e.toString().replaceFirst('Exception: ', '');
      _set(silent ? UpdateState.idle : UpdateState.error);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _assetName() async {
    try {
      final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
      if (abis.contains('arm64-v8a')) return 'grab-arm64.apk';
      if (abis.any((a) => a.startsWith('armeabi'))) return 'grab-armv7.apk';
    } catch (_) {}
    return 'grab-arm64.apk';
  }

  /// Downloads the new APK and opens Android's installer.
  Future<void> install() async {
    final info = available;
    if (info == null || state == UpdateState.downloading) return;
    progress = 0;
    error = null;
    _set(UpdateState.downloading);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/grab-update-${info.build}.apk');
      final req = await client.getUrl(info.url).timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.userAgentHeader, 'Grab-app');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw Exception('Download failed (${res.statusCode}).');
      }
      final total = info.size > 0 ? info.size : res.contentLength;
      final sink = file.openWrite();
      var got = 0;
      var last = 0.0;
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          progress = got / total;
          if (progress - last >= 0.01) {
            last = progress;
            notifyListeners();
          }
        }
      }
      await sink.flush();
      await sink.close();
      progress = 1;
      _set(UpdateState.available);
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        throw Exception(result.message.isEmpty
            ? 'Could not open the installer.'
            : result.message);
      }
    } catch (e) {
      error = e is TimeoutException
          ? 'The download stalled. Try again.'
          : e.toString().replaceFirst('Exception: ', '');
      _set(UpdateState.error);
    } finally {
      client.close(force: true);
    }
  }
}
