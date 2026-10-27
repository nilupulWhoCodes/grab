import 'package:flutter/material.dart';

import '../services/download_manager.dart';
import '../theme.dart';
import 'browse_view.dart';
import 'downloads_view.dart';

/// Part 2: browse YouTube and save audio as MP3.
class Mp3Page extends StatefulWidget {
  const Mp3Page({super.key});

  @override
  State<Mp3Page> createState() => Mp3PageState();
}

class Mp3PageState extends State<Mp3Page> {
  int _segment = 0;
  final _browseKey = GlobalKey<BrowseViewState>();

  /// Returns true when the back press was handled here.
  Future<bool> handleBack() async {
    if (_segment == 1) {
      setState(() => _segment = 0);
      return true;
    }
    return await _browseKey.currentState?.goBack() ?? false;
  }

  void showDownloads() => setState(() => _segment = 1);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
          child: Row(
            children: [
              Text('Grab', style: displayStyle(26)),
              const Spacer(),
              ListenableBuilder(
                listenable: DownloadManager.instance,
                builder: (context, _) => _Segmented(
                  index: _segment,
                  badge: DownloadManager.instance.tasks
                      .where((t) => t.isActive)
                      .length,
                  onChanged: (i) => setState(() => _segment = i),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _segment,
            children: [
              BrowseView(key: _browseKey, onDownloadStarted: showDownloads),
              const DownloadsView(),
            ],
          ),
        ),
      ],
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.index,
    required this.onChanged,
    required this.badge,
  });

  final int index;
  final int badge;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(int i, String label) {
      final selected = index == i;
      return Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AppColors.bg : AppColors.sub,
                  ),
                ),
                if (i == 1 && badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.bg : AppColors.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.accent : AppColors.bg,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg(0, 'Browse'), const SizedBox(width: 4), seg(1, 'Downloads')],
      ),
    );
  }
}
