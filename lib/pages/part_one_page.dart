import 'package:flutter/material.dart';

import '../theme.dart';

/// Placeholder until Part 1 of the app is defined.
class PartOnePage extends StatelessWidget {
  const PartOnePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Text('Grab', style: displayStyle(26)),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.grid_view_rounded,
                    size: 40, color: AppColors.muted),
                const SizedBox(height: 12),
                Text('Part 1',
                    style: displayStyle(22, weight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                  'Space reserved for the first part of the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15, color: AppColors.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
