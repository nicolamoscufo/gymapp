import 'package:flutter/material.dart';

import '../app_data_store.dart';
import '../app_preferences.dart';
import '../local_notifications.dart';
import '../models/schedule.dart';
import '../number_input.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onRestoreBackup;
  final Future<void> Function() onRestoreAutoBackup;
  final Future<void> Function(double reductionPercent)
  onBackoffReductionChanged;
  final List<Schedule> schedules;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onExportBackup,
    required this.onRestoreBackup,
    required this.onRestoreAutoBackup,
    required this.onBackoffReductionChanged,
    required this.schedules,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemeMode _themeMode;
  bool _isExportingBackup = false;
  bool _isRestoringBackup = false;
  bool _isRestoringAutoBackup = false;
  bool _isSchedulingReminders = false;
  bool _isSavingBackoffReduction = false;
  bool _remindersEnabled = false;
  int _reminderHour = AppPreferences.defaultWorkoutReminderHour;
  int _reminderMinute = AppPreferences.defaultWorkoutReminderMinute;
  double _backoffReductionPercent =
      AppPreferences.defaultBackoffReductionPercent;
  DateTime? _lastAutoBackupAt;
  final TextEditingController _backoffReductionController =
      TextEditingController(
        text: formatDecimal(AppPreferences.defaultBackoffReductionPercent),
      );

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
    _loadAutoBackupInfo();
    _loadReminderSettings();
    _loadBackoffReductionPercent();
  }

  @override
  void dispose() {
    _backoffReductionController.dispose();
    super.dispose();
  }

  Future<void> _loadAutoBackupInfo() async {
    final lastBackupAt = await AppDataStore.loadLastAutoBackupAt();
    if (!mounted) return;
    setState(() {
      _lastAutoBackupAt = lastBackupAt;
    });
  }

  Future<void> _loadReminderSettings() async {
    final settings = await AppPreferences.loadWorkoutReminderSettings();
    if (!mounted) return;
    setState(() {
      _remindersEnabled = settings.enabled;
      _reminderHour = settings.hour;
      _reminderMinute = settings.minute;
    });
  }

  Future<void> _loadBackoffReductionPercent() async {
    final value = await AppPreferences.loadDefaultBackoffReductionPercent();
    if (!mounted) return;
    setState(() {
      _backoffReductionPercent = value;
      _backoffReductionController.text = formatDecimal(value);
    });
  }

  Future<void> _saveBackoffReductionPercent() async {
    final parsed = parseDecimalInput(_backoffReductionController.text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci una percentuale valida.')),
      );
      return;
    }

    final normalized = AppPreferences.normalizeBackoffReductionPercent(parsed);
    setState(() {
      _isSavingBackoffReduction = true;
      _backoffReductionPercent = normalized;
      _backoffReductionController.text = formatDecimal(normalized);
    });
    await widget.onBackoffReductionChanged(normalized);
    if (!mounted) return;
    setState(() => _isSavingBackoffReduction = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Back off aggiornato su tutte le schede.')),
    );
  }

  Future<void> _saveReminderSettings({
    bool? enabled,
    int? hour,
    int? minute,
  }) async {
    final nextSettings = WorkoutReminderSettings(
      enabled: enabled ?? _remindersEnabled,
      hour: hour ?? _reminderHour,
      minute: minute ?? _reminderMinute,
    );
    setState(() {
      _isSchedulingReminders = true;
      _remindersEnabled = nextSettings.enabled;
      _reminderHour = nextSettings.hour;
      _reminderMinute = nextSettings.minute;
    });
    await AppPreferences.saveWorkoutReminderSettings(nextSettings);
    await LocalNotificationService.scheduleWorkoutReminders(
      schedules: widget.schedules,
      enabled: nextSettings.enabled,
      hour: nextSettings.hour,
      minute: nextSettings.minute,
    );
    if (mounted) {
      setState(() => _isSchedulingReminders = false);
    }
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) {
      return 'non ancora creato';
    }
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
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
        await _loadAutoBackupInfo();
      }
    }
  }

  Future<void> _showPrivacyDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy e dati'),
        content: const Text(
          'Gym App salva schede, storico, misure corpo e backup sul dispositivo. '
          'Non usa backend o account. La rete viene usata solo per scaricare il '
          'modello AI locale quando richiesto; allenamenti, profilo AI, chat e '
          'inferenza restano sul dispositivo. Per spostare i dati usa export/import '
          'backup JSON.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backupBusy =
        _isExportingBackup || _isRestoringBackup || _isRestoringAutoBackup;

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SettingsSection(
            title: 'Aspetto',
            icon: Icons.palette_outlined,
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('Sistema'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Chiaro'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Scuro'),
                ),
              ],
              selected: {_themeMode},
              onSelectionChanged: (selection) {
                final selectedThemeMode = selection.first;
                setState(() => _themeMode = selectedThemeMode);
                widget.onThemeModeChanged?.call(selectedThemeMode);
              },
            ),
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'Allenamento',
            icon: Icons.fitness_center_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _backoffReductionController,
                  decoration: InputDecoration(
                    labelText: 'Riduzione back off',
                    suffixText: '%',
                    helperText:
                        'Attuale: ${formatDecimal(_backoffReductionPercent)}%',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onSubmitted: (_) {
                    if (!_isSavingBackoffReduction) {
                      _saveBackoffReductionPercent();
                    }
                  },
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _isSavingBackoffReduction
                        ? null
                        : _saveBackoffReductionPercent,
                    icon: const Icon(Icons.check),
                    label: const Text('Salva'),
                  ),
                ),
                if (_isSavingBackoffReduction) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'Promemoria',
            icon: Icons.notifications_none,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Notifiche allenamento'),
                  subtitle: Text(
                    'Nei giorni programmati alle '
                    '${_reminderHour.toString().padLeft(2, '0')}:'
                    '${_reminderMinute.toString().padLeft(2, '0')}',
                  ),
                  value: _remindersEnabled,
                  onChanged: _isSchedulingReminders
                      ? null
                      : (value) => _saveReminderSettings(enabled: value),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _reminderHour,
                        decoration: const InputDecoration(labelText: 'Ora'),
                        items: List.generate(
                          24,
                          (hour) => DropdownMenuItem<int>(
                            value: hour,
                            child: Text(hour.toString().padLeft(2, '0')),
                          ),
                        ),
                        onChanged: _isSchedulingReminders
                            ? null
                            : (value) {
                                if (value != null) {
                                  _saveReminderSettings(hour: value);
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _reminderMinute,
                        decoration: const InputDecoration(labelText: 'Minuti'),
                        items: const [0, 15, 30, 45]
                            .map(
                              (minute) => DropdownMenuItem<int>(
                                value: minute,
                                child: Text(
                                  minute.toString().padLeft(2, '0'),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _isSchedulingReminders
                            ? null
                            : (value) {
                                if (value != null) {
                                  _saveReminderSettings(minute: value);
                                }
                              },
                      ),
                    ),
                  ],
                ),
                if (_isSchedulingReminders) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'Dati e backup',
            icon: Icons.storage_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.history_outlined,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ultimo backup automatico: '
                        '${_formatDateTime(_lastAutoBackupAt)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: backupBusy
                      ? null
                      : () => _runBackupAction(widget.onExportBackup, (value) {
                          setState(() => _isExportingBackup = value);
                        }),
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Esporta backup'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: backupBusy
                      ? null
                      : () => _runBackupAction(widget.onRestoreBackup, (value) {
                          setState(() => _isRestoringBackup = value);
                        }),
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Importa backup'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _lastAutoBackupAt == null || backupBusy
                      ? null
                      : () => _runBackupAction(
                          widget.onRestoreAutoBackup,
                          (value) {
                            setState(() => _isRestoringAutoBackup = value);
                          },
                        ),
                  icon: const Icon(Icons.restore),
                  label: const Text('Ripristina auto-backup'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy e dati locali'),
                  subtitle: const Text(
                    'Come vengono salvati dati e inferenza AI.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showPrivacyDialog,
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.verified_outlined),
                  title: Text('Stato app'),
                  subtitle: Text('Backup, responsive e test UI per la release.'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
