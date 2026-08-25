import 'package:flutter/material.dart';

import 'ai_coach_entry.dart';
import 'home.dart';

class HomeAiShell extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  const HomeAiShell({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        HomePage(
          themeMode: themeMode,
          onThemeModeChanged: onThemeModeChanged,
        ),
        Positioned(
          right: 16,
          top: MediaQuery.paddingOf(context).top + 64,
          child: SafeArea(
            child: FloatingActionButton.small(
              heroTag: 'local-ai-coach-launcher',
              tooltip: 'AI Coach locale',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiCoachEntryScreen(),
                  ),
                );
              },
              child: const Icon(Icons.psychology_alt),
            ),
          ),
        ),
      ],
    );
  }
}
