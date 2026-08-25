import 'package:flutter/material.dart';

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
    return HomePage(
      themeMode: themeMode,
      onThemeModeChanged: onThemeModeChanged,
      initialIndex: 0,
    );
  }
}
