import 'package:flutter/material.dart';

import '../app_data_store.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onRestoreBackup;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onExportBackup,
    required this.onRestoreBackup,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemeMode _themeMode;
  bool _isExportingBackup = false;
  bool _isRestoringBackup = false;
  DateTime? _lastAutoBackupAt;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
    _loadAutoBackupInfo();
  }

  Future<void> _loadAutoBackupInfo() async {
    final lastBackupAt = await AppDataStore.loadLastAutoBackupAt();
    if (!mounted) return;
    setState(() {
      _lastAutoBackupAt = lastBackupAt;
    });
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) {
      return 'non ancora creato';
    }
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
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
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary.withValues(alpha: isDark ? 0.20 : 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.palette,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tema',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Light, dark o automatico di sistema.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.storage,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dati',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Backup locale, ripristino su file e backup auto.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.cloud_done,
                      color: colorScheme.tertiary,
                    ),
                    title: const Text('Backup automatico locale'),
                    subtitle: Text(
                      'Ultimo snapshot: ${_formatDateTime(_lastAutoBackupAt)}',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isExportingBackup || _isRestoringBackup
                        ? null
                        : () =>
                              _runBackupAction(widget.onExportBackup, (value) {
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
                        : () =>
                              _runBackupAction(widget.onRestoreBackup, (value) {
                                setState(() {
                                  _isRestoringBackup = value;
                                });
                              }),
                    icon: const Icon(Icons.restore),
                    label: const Text('Ripristina'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
