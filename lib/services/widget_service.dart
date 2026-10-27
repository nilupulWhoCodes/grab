import 'dart:async';
import 'dart:io';

import 'package:home_widget/home_widget.dart';

/// Pushes the now-playing state to the Android home-screen widget.
class WidgetService {
  WidgetService._();
  static final instance = WidgetService._();

  static const _provider = 'com.nilupul.grab.GrabWidgetProvider';

  Timer? _debounce;
  String? _last;

  void update({
    String? title,
    String? artist,
    String? artPath,
    required bool playing,
  }) {
    if (!Platform.isAndroid) return;
    final key = '$title|$artist|$artPath|$playing';
    if (key == _last) return;
    _last = key;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        await HomeWidget.saveWidgetData<String>('title', title ?? 'Not playing');
        await HomeWidget.saveWidgetData<String>(
            'artist', title == null ? 'Tap to open Grab' : (artist ?? ''));
        await HomeWidget.saveWidgetData<String>('art', artPath ?? '');
        await HomeWidget.saveWidgetData<bool>('playing', playing);
        await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
      } catch (_) {
        // No widget placed, or not supported: nothing to do.
      }
    });
  }
}
