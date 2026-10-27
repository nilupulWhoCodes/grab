import 'package:flutter/material.dart';

import '../services/art_colors.dart';
import '../services/player_controller.dart';
import '../services/settings_service.dart';
import '../theme.dart';

/// Background that takes on the playing song's cover colours, and shares
/// those colours with everything inside it ([ArtBackdrop.colorsOf]).
class ArtBackdrop extends StatefulWidget {
  const ArtBackdrop({super.key, required this.child});
  final Widget child;

  static ArtColors colorsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ArtScope>()?.colors ??
      ArtColors.fallback;

  @override
  State<ArtBackdrop> createState() => _ArtBackdropState();
}

class _ArtBackdropState extends State<ArtBackdrop> {
  ArtColors _colors = ArtColors.fallback;
  String? _forArt = '\u0000';
  final _p = PlayerController.instance;
  final _s = SettingsService.instance;

  @override
  void initState() {
    super.initState();
    _p.addListener(_refresh);
    _s.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    _p.removeListener(_refresh);
    _s.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    final art = _s.albumColours ? _p.currentArt : null;
    if (art == _forArt) return;
    _forArt = art;
    ArtColors.forArt(art).then((c) {
      if (mounted && _forArt == art) setState(() => _colors = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = _s.albumColours ? _colors.top : AppColors.bg;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, AppColors.bg],
          stops: const [0, 0.85],
        ),
      ),
      child: _ArtScope(
        colors: _s.albumColours ? _colors : ArtColors.fallback,
        child: widget.child,
      ),
    );
  }
}

class _ArtScope extends InheritedWidget {
  const _ArtScope({required this.colors, required super.child});
  final ArtColors colors;

  @override
  bool updateShouldNotify(_ArtScope old) => old.colors != colors;
}
