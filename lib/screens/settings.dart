import 'package:flutter/material.dart';

import '../app_preferences.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final int defaultRestSeconds;
  final ValueChanged<int> onDefaultRestSecondsChanged;
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onRestoreBackup;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.defaultRestSeconds,
    required this.onDefaultRestSecondsChanged,
    required this.onExportBackup,
    required this.onRestoreBackup,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemeMode _themeMode;
  late int _defaultRestSeconds;
  bool _isExportingBackup = false;
  bool _isRestoringBackup = false;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
    _defaultRestSeconds = widget.defaultRestSeconds;
  }

  Future<void> _runBackupAction(
    Future<void> Function() action,
    ValueChanged<bool> setRunning,
  ) async {
    setRunning(true);
    try {
      await action();
    } finally {
      if (mounted) {
        setRunning(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final restMinutes = _defaultRestSeconds ~/ 60;
    final restSeconds = _defaultRestSeconds % 60;
    final restLabel = restMinutes > 0
        ? '${restMinutes}m ${restSeconds.toString().padLeft(2, '0')}s'
        : '${restSeconds}s';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Tema',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('Sistema'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode),
                label: Text('Chiaro'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode),
                label: Text('Scuro'),
              ),
            ],
            selected: {_themeMode},
            onSelectionChanged: (selection) {
              final selectedThemeMode = selection.first;
              setState(() {
                _themeMode = selectedThemeMode;
              });
              widget.onThemeModeChanged?.call(selectedThemeMode);
            },
          ),
          const SizedBox(height: 28),
          Text(
            'Recupero',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.timer, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Default',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(restLabel, style: theme.textTheme.titleMedium),
            ],
          ),
          Slider(
            min: AppPreferences.minRestSeconds.toDouble(),
            max: AppPreferences.maxRestSeconds.toDouble(),
            divisions:
                (AppPreferences.maxRestSeconds -
                    AppPreferences.minRestSeconds) ~/
                15,
            label: restLabel,
            value: _defaultRestSeconds.toDouble(),
            onChanged: (value) {
              final seconds = (value / 15).round() * 15;
              setState(() {
                _defaultRestSeconds = seconds;
              });
              widget.onDefaultRestSecondsChanged(seconds);
            },
          ),
          const SizedBox(height: 28),
          Text(
            'Dati',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isExportingBackup || _isRestoringBackup
                ? null
                : () => _runBackupAction(widget.onExportBackup, (value) {
                    setState(() {
                      _isExportingBackup = value;
                    });
                  }),
            icon: const Icon(Icons.backup),
            label: const Text('Esporta'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isExportingBackup || _isRestoringBackup
                ? null
                : () => _runBackupAction(widget.onRestoreBackup, (value) {
                    setState(() {
                      _isRestoringBackup = value;
                    });
                  }),
            icon: const Icon(Icons.restore),
            label: const Text('Ripristina'),
          ),
        ],
      ),
    );
  }
}
