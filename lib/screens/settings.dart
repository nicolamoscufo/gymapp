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
        await _loadAutoBackupInfo();
      }
    }
  }

  Future<void> _showPrivacyDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy e store'),
        content: const Text(
          'Gym App salva schede, storico, misure corpo e backup sul dispositivo. Non usa backend o account. La rete viene usata solo per scaricare il modello AI locale quando richiesto; allenamenti, profilo AI, chat e inferenza restano sul dispositivo. Per spostare i dati usa export/import backup JSON.',
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
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<ThemeMode>(
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
                          color: colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.trending_down,
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Back off',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Riduzione usata nei calcoli top set / back off.',
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
                  TextField(
                    controller: _backoffReductionController,
                    decoration: InputDecoration(
                      labelText: 'Riduzione back off %',
                      helperText:
                          'Valore attuale: ${formatDecimal(_backoffReductionPercent)}%',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onSubmitted: (_) => _isSavingBackoffReduction
                        ? null
                        : _saveBackoffReductionPercent(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _isSavingBackoffReduction
                        ? null
                        : _saveBackoffReductionPercent,
                    icon: const Icon(Icons.save),
                    label: const Text('Salva e aggiorna schede'),
                  ),
                  if (_isSavingBackoffReduction) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ],
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      Icons.notifications_active,
                      color: colorScheme.primary,
                    ),
                    title: const Text('Promemoria allenamento'),
                    subtitle: Text(
                      'Notifica nei giorni programmati alle ${_reminderHour.toString().padLeft(2, '0')}:${_reminderMinute.toString().padLeft(2, '0')}',
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _reminderMinute,
                          decoration: const InputDecoration(
                            labelText: 'Minuti',
                          ),
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
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ],
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
                              'Export completo, ripristino su file e backup auto.',
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
                    onPressed:
                        _isExportingBackup ||
                            _isRestoringBackup ||
                            _isRestoringAutoBackup
                        ? null
                        : () =>
                              _runBackupAction(widget.onExportBackup, (value) {
                                setState(() {
                                  _isExportingBackup = value;
                                });
                              }),
                    icon: const Icon(Icons.inventory_2),
                    label: const Text('Esporta tutto'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        _isExportingBackup ||
                            _isRestoringBackup ||
                            _isRestoringAutoBackup
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
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        _lastAutoBackupAt == null ||
                            _isExportingBackup ||
                            _isRestoringBackup ||
                            _isRestoringAutoBackup
                        ? null
                        : () => _runBackupAction(widget.onRestoreAutoBackup, (
                            value,
                          ) {
                            setState(() {
                              _isRestoringAutoBackup = value;
                            });
                          }),
                    icon: const Icon(Icons.history_toggle_off),
                    label: const Text('Ripristina ultimo auto-backup'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: Icon(Icons.privacy_tip, color: colorScheme.primary),
              title: const Text('Privacy locale'),
              subtitle: const Text(
                'Dati e AI locali: rete solo per il download del modello.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showPrivacyDialog,
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: Icon(Icons.storefront, color: colorScheme.tertiary),
              title: const Text('Checklist pubblicazione'),
              subtitle: const Text(
                'Icona, privacy, backup, responsive e test UI pronti per store.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
