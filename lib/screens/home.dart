import 'dart:convert';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_data_store.dart';
import '../app_preferences.dart';
import '../dialog_form.dart';
import '../local_notifications.dart';
import '../models/body_log.dart';
import '../models/exercise.dart';
import '../models/schedule.dart';
import '../models/workout.dart';
import '../number_input.dart';
import '../top_set_backoff.dart';
import 'schedule_detail.dart';
import 'settings.dart';
import 'stats.dart';
import 'active_workout.dart';
import 'exercise_detail.dart';
import 'calendar_screen.dart';

enum _HomeAction {
  importCsv,
  exportCsv,
  exportHistoryCsv,
  exportBodyCsv,
  exportAllJson,
  restoreBackup,
}

enum _ScheduleMenuAction { rename, duplicate, toggleArchive, delete }

enum _HistoryRangeFilter { all, last30, last90 }

enum _BackupImportMode { merge, replace }

class HomePage extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  const HomePage({
    super.key,
    this.themeMode = AppPreferences.defaultThemeMode,
    this.onThemeModeChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Schedule> schedules = [];
  final List<WorkoutSession> history = [];
  final List<BodyLog> bodyLogs = [];
  final TextEditingController _searchController = TextEditingController();
  WorkoutSession? _savedSession;

  int _currentIndex = 0;
  String _searchQuery = '';
  String _historyQuery = '';
  int? _selectedWeekFilter;
  _HistoryRangeFilter _historyRangeFilter = _HistoryRangeFilter.all;
  bool _historyOnlyPr = false;
  bool _showArchived = false;
  final int _defaultRestSeconds = AppPreferences.defaultRestSeconds;
  double _defaultBackoffReductionPercent =
      AppPreferences.defaultBackoffReductionPercent;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final bundle = await AppDataStore.loadBundle();
    final defaultBackoffReductionPercent =
        await AppPreferences.loadDefaultBackoffReductionPercent();

    if (!mounted) {
      return;
    }

    var backoffDataChanged = false;

    setState(() {
      schedules
        ..clear()
        ..addAll(bundle.schedules);
      history
        ..clear()
        ..addAll(bundle.history);
      bodyLogs
        ..clear()
        ..addAll(bundle.bodyLogs);
      _savedSession = bundle.currentSession;
      _defaultBackoffReductionPercent = defaultBackoffReductionPercent;
      backoffDataChanged =
          _applyBackoffReductionToSchedules(defaultBackoffReductionPercent) |
          _applyBackoffReductionToHistory(defaultBackoffReductionPercent) |
          _applyBackoffReductionToSession(
            _savedSession,
            defaultBackoffReductionPercent,
          );
      _sortSchedules();
    });

    if (backoffDataChanged) {
      await _saveAllData();
      if (_savedSession != null) {
        await AppDataStore.saveCurrentSession(_savedSession!);
      }
    }

    if (bundle.recoveredFromCorruption) {
      _showInfo('Alcuni dati corrotti sono stati ignorati per evitare crash.');
    }
    _refreshWorkoutReminders();
  }

  Future<void> _saveSchedules() async {
    await AppDataStore.saveSchedules(schedules);
    await _refreshWorkoutReminders();
  }

  Future<void> _saveHistory() async {
    await AppDataStore.saveHistory(history);
  }

  Future<void> _saveBodyLogs() async {
    await AppDataStore.saveBodyLogs(bodyLogs);
  }

  Future<void> _saveAllData() async {
    await AppDataStore.saveAll(
      schedules: schedules,
      history: history,
      bodyLogs: bodyLogs,
    );
    await _refreshWorkoutReminders();
  }

  bool _applyBackoffReductionToExercises(
    List<Exercise> exercises,
    double reductionPercent,
  ) {
    var changed = false;
    final normalized = AppPreferences.normalizeBackoffReductionPercent(
      reductionPercent,
    );
    for (final exercise in exercises) {
      if (exercise.backoffReductionPercent != normalized) {
        exercise.backoffReductionPercent = normalized;
        changed = true;
      }
    }
    return changed;
  }

  bool _applyBackoffReductionToSchedules(double reductionPercent) {
    var changed = false;
    for (final schedule in schedules) {
      changed |= _applyBackoffReductionToExercises(
        schedule.exercises,
        reductionPercent,
      );
    }
    return changed;
  }

  bool _applyBackoffReductionToWorkoutExercises(
    List<WorkoutExercise> exercises,
    double reductionPercent,
  ) {
    var changed = false;
    final normalized = AppPreferences.normalizeBackoffReductionPercent(
      reductionPercent,
    );
    for (final exercise in exercises) {
      if (exercise.backoffReductionPercent != normalized) {
        exercise.backoffReductionPercent = normalized;
        changed = true;
      }
    }
    return changed;
  }

  bool _applyBackoffReductionToSession(
    WorkoutSession? session,
    double reductionPercent,
  ) {
    if (session == null) {
      return false;
    }
    return _applyBackoffReductionToWorkoutExercises(
      session.exercises,
      reductionPercent,
    );
  }

  bool _applyBackoffReductionToHistory(double reductionPercent) {
    var changed = false;
    for (final session in history) {
      changed |= _applyBackoffReductionToSession(session, reductionPercent);
    }
    return changed;
  }

  Future<void> _saveBackoffReductionPercent(double reductionPercent) async {
    final normalized = AppPreferences.normalizeBackoffReductionPercent(
      reductionPercent,
    );
    setState(() {
      _defaultBackoffReductionPercent = normalized;
      _applyBackoffReductionToSchedules(normalized);
      _applyBackoffReductionToHistory(normalized);
      _applyBackoffReductionToSession(_savedSession, normalized);
    });
    await AppPreferences.saveDefaultBackoffReductionPercent(normalized);
    await _saveAllData();
    if (_savedSession != null) {
      await AppDataStore.saveCurrentSession(_savedSession!);
    }

    final customExercises = await AppDataStore.loadCustomExercises();
    if (_applyBackoffReductionToExercises(customExercises, normalized)) {
      await AppDataStore.saveCustomExercises(customExercises);
    }
  }

  Future<void> _refreshWorkoutReminders() async {
    final reminderSettings = await AppPreferences.loadWorkoutReminderSettings();
    await LocalNotificationService.scheduleWorkoutReminders(
      schedules: schedules,
      enabled: reminderSettings.enabled,
      hour: reminderSettings.hour,
      minute: reminderSettings.minute,
    );
  }

  Future<void> _discardSavedSession() async {
    await AppDataStore.clearCurrentSession();
    if (!mounted) return;
    setState(() {
      _savedSession = null;
    });
  }

  void _showUndoSnackBar({
    required String message,
    required VoidCallback onUndo,
  }) {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'ANNULLA', onPressed: onUndo),
      ),
    );
  }

  void _sortSchedules() {
    schedules.sort((a, b) {
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
      }

      final weekCompare = a.currentWeek().compareTo(b.currentWeek());
      if (weekCompare != 0) {
        return weekCompare;
      }

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  }

  Future<void> _deleteHistory(int index) async {
    if (index < 0 || index >= history.length) {
      return;
    }

    final deletedSession = history[index];
    setState(() {
      history.removeAt(index);
    });
    await _saveHistory();

    _showUndoSnackBar(
      message: 'Allenamento eliminato.',
      onUndo: () {
        if (!mounted || history.contains(deletedSession)) {
          return;
        }

        setState(() {
          final restoreIndex = index > history.length ? history.length : index;
          history.insert(restoreIndex, deletedSession);
        });
        _saveHistory();
      },
    );
  }

  Future<void> _showInfo(String message) async {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showExerciseDetail(String exerciseName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ExerciseDetailScreen(exerciseName: exerciseName, history: history),
      ),
    );
  }

  Future<void> _openScheduleDetail(Schedule schedule) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduleDetailScreen(
          schedule: schedule,
          history: history,
          defaultRestSeconds: _defaultRestSeconds,
          defaultBackoffReductionPercent: _defaultBackoffReductionPercent,
          onUpdate: () {
            setState(() {});
            _saveSchedules();
          },
        ),
      ),
    );
    _loadData();
  }

  String _weekdayLabel(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'Lun',
      DateTime.tuesday => 'Mar',
      DateTime.wednesday => 'Mer',
      DateTime.thursday => 'Gio',
      DateTime.friday => 'Ven',
      DateTime.saturday => 'Sab',
      DateTime.sunday => 'Dom',
      _ => '?',
    };
  }

  void _showGlobalSearch() {
    var query = '';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalized = query.trim().toLowerCase();
          final matchingSchedules = normalized.isEmpty
              ? const <Schedule>[]
              : schedules
                    .where((schedule) {
                      return schedule.title.toLowerCase().contains(
                            normalized,
                          ) ||
                          schedule.exercises.any(
                            (exercise) => exercise.name.toLowerCase().contains(
                              normalized,
                            ),
                          );
                    })
                    .take(8)
                    .toList();
          final matchingExercises = normalized.isEmpty
              ? const <String>[]
              : history
                    .expand((session) => session.exercises)
                    .map((exercise) => exercise.name)
                    .where((name) => name.toLowerCase().contains(normalized))
                    .toSet()
                    .take(8)
                    .toList();

          return AlertDialog(
            title: const Text('Ricerca globale'),
            content: AppDialogFrame(
              maxWidth: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Schede, esercizi, storico',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  appDialogFieldGap,
                  SizedBox(
                    height: math.min(
                      420.0,
                      MediaQuery.sizeOf(context).height * 0.46,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ...matchingSchedules.map(
                          (schedule) => ListTile(
                            leading: const Icon(Icons.list_alt),
                            title: Text(schedule.title),
                            subtitle: Text(
                              '${schedule.exercises.length} esercizi',
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _openScheduleDetail(schedule);
                            },
                          ),
                        ),
                        ...matchingExercises.map(
                          (name) => ListTile(
                            leading: const Icon(Icons.show_chart),
                            title: Text(name),
                            subtitle: const Text('Storico esercizio'),
                            onTap: () {
                              Navigator.pop(context);
                              _showExerciseDetail(name);
                            },
                          ),
                        ),
                        if (normalized.isNotEmpty &&
                            matchingSchedules.isEmpty &&
                            matchingExercises.isEmpty)
                          const ListTile(title: Text('Nessun risultato.')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Chiudi'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showToolsSheet() {
    final warmupWeightController = TextEditingController(text: '100');
    final warmupRepsController = TextEditingController(text: '8');
    final topSetWeightController = TextEditingController(text: '100');
    final backoffReductionController = TextEditingController(
      text: formatDecimal(_defaultBackoffReductionPercent),
    );
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final warmupWeight =
              parseDecimalInput(warmupWeightController.text) ?? 0;
          final warmupReps = parseIntInput(warmupRepsController.text) ?? 8;
          final warmupSets = [
            '40% x ${math.max(5, warmupReps + 2)} reps = ${(warmupWeight * 0.40).toStringAsFixed(1)} kg',
            '60% x ${math.max(3, warmupReps)} reps = ${(warmupWeight * 0.60).toStringAsFixed(1)} kg',
            '75% x ${math.max(2, warmupReps - 2)} reps = ${(warmupWeight * 0.75).toStringAsFixed(1)} kg',
            '85% x 1-2 reps = ${(warmupWeight * 0.85).toStringAsFixed(1)} kg',
          ];
          final topSetWeight =
              parseDecimalInput(topSetWeightController.text) ?? 0;
          final backoffReduction =
              parseDecimalInput(backoffReductionController.text) ??
              defaultBackoffReductionPercent;
          final displayBackoffReduction = backoffReduction
              .clamp(0, 100)
              .toDouble();
          final backoffWeight = recommendedBackoffWeight(
            topSetWeight,
            reductionPercent: backoffReduction,
          );

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Strumenti rapidi',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Warm-up calculator',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        AppFieldRow(
                          children: [
                            TextField(
                              controller: warmupWeightController,
                              decoration: const InputDecoration(
                                labelText: 'Serie lavoro kg',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setSheetState(() {}),
                            ),
                            TextField(
                              controller: warmupRepsController,
                              decoration: const InputDecoration(
                                labelText: 'Reps lavoro',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setSheetState(() {}),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...warmupSets.map((line) => Text(line)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Top set / back off',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        AppFieldRow(
                          children: [
                            TextField(
                              controller: topSetWeightController,
                              decoration: const InputDecoration(
                                labelText: 'Top set kg',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setSheetState(() {}),
                            ),
                            TextField(
                              controller: backoffReductionController,
                              decoration: const InputDecoration(
                                labelText: 'Riduzione %',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setSheetState(() {}),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Back off consigliato: ${formatDecimal(backoffWeight)} kg (-${formatDecimal(displayBackoffReduction)}%)',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<String> _readPickedTextFile(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Il file selezionato non contiene dati leggibili.');
    }

    return utf8.decode(bytes);
  }

  String _normalizeText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\uFEFF', '');
  }

  bool _looksLikeCsvHeader(List<dynamic> row) {
    if (row.length < 7) {
      return false;
    }

    final first = row[0].toString().trim().toLowerCase();
    final second = row[1].toString().trim().toLowerCase();
    final third = row[2].toString().trim().toLowerCase();

    return first.contains('title') ||
        first.contains('titolo') ||
        second.contains('week') ||
        second.contains('settimana') ||
        third.contains('exercise') ||
        third.contains('eserc');
  }

  List<List<dynamic>> _decodeCsv(String rawText) {
    final normalizedText = _normalizeText(rawText);
    List<List<dynamic>> rows = const CsvToListConverter(
      eol: '\n',
    ).convert(normalizedText);

    if (rows.isNotEmpty &&
        rows.first.length < 7 &&
        normalizedText.contains(';')) {
      rows = const CsvToListConverter(
        fieldDelimiter: ';',
        eol: '\n',
      ).convert(normalizedText);
    }

    if (rows.isNotEmpty && _looksLikeCsvHeader(rows.first)) {
      rows = rows.skip(1).toList();
    }

    return rows;
  }

  bool _parseBoolCell(Object? value) {
    final normalized = value.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'si';
  }

  DateTime _parseDateCell(Object? value) {
    return DateTime.tryParse(value.toString().trim()) ?? DateTime.now();
  }

  IntensityTechnique _parseTechnique(String value) {
    try {
      return IntensityTechnique.values.byName(value.trim());
    } catch (_) {
      return IntensityTechnique.none;
    }
  }

  bool _exerciseAlreadyExists(Schedule schedule, Exercise candidate) {
    return schedule.exercises.any((exercise) {
      return exercise.name == candidate.name &&
          exercise.set == candidate.set &&
          exercise.reps == candidate.reps &&
          exercise.backoffReps == candidate.backoffReps &&
          exercise.backoffReductionPercent ==
              candidate.backoffReductionPercent &&
          exercise.restSeconds == candidate.restSeconds &&
          exercise.muscleGroup == candidate.muscleGroup &&
          exercise.equipment == candidate.equipment &&
          exercise.movementPattern == candidate.movementPattern &&
          exercise.targetMinReps == candidate.targetMinReps &&
          exercise.targetMaxReps == candidate.targetMaxReps &&
          exercise.technique == candidate.technique &&
          exercise.weight == candidate.weight &&
          exercise.supersetGroup == candidate.supersetGroup &&
          exercise.progressionKgStep == candidate.progressionKgStep &&
          exercise.progressionRepStep == candidate.progressionRepStep &&
          exercise.progressionScheme == candidate.progressionScheme &&
          exercise.notes.trim() == candidate.notes.trim();
    });
  }

  String _buildSchedulesCsv() {
    final rows = <List<dynamic>>[
      [
        'scheduleTitle',
        'week',
        'createdAt',
        'goal',
        'mesocycleWeeks',
        'deloadEveryWeeks',
        'isArchived',
        'exerciseName',
        'sets',
        'reps',
        'targetMinReps',
        'targetMaxReps',
        'weight',
        'muscleGroup',
        'equipment',
        'movementPattern',
        'technique',
        'backoffReps',
        'backoffReductionPercent',
        'restSeconds',
        'notes',
        'supersetGroup',
        'progressionKgStep',
        'progressionRepStep',
        'progressionScheme',
      ],
    ];

    for (final schedule in schedules) {
      for (final exercise in schedule.exercises) {
        rows.add([
          schedule.title,
          schedule.week,
          schedule.createdAt.toIso8601String(),
          schedule.goal,
          schedule.mesocycleWeeks,
          schedule.deloadEveryWeeks,
          schedule.isArchived,
          exercise.name,
          exercise.set,
          exercise.reps,
          exercise.targetMinReps,
          exercise.targetMaxReps,
          exercise.weight,
          exercise.muscleGroup.label,
          exercise.equipment,
          exercise.movementPattern,
          exercise.technique.name,
          exercise.backoffReps,
          exercise.backoffReductionPercent,
          exercise.restSeconds,
          exercise.notes,
          exercise.supersetGroup,
          exercise.progressionKgStep,
          exercise.progressionRepStep,
          exercise.progressionScheme.name,
        ]);
      }
    }

    if (rows.length == 1) {
      return '';
    }

    return const ListToCsvConverter(
      fieldDelimiter: ',',
      eol: '\n',
    ).convert(rows);
  }

  String _buildHistoryCsv() {
    final rows = <List<dynamic>>[
      [
        'sessionTitle',
        'startTime',
        'endTime',
        'exercise',
        'muscleGroup',
        'setIndex',
        'isWarmup',
        'isCompleted',
        'weight',
        'reps',
        'rpe',
        'rir',
        'setNotes',
      ],
    ];

    for (final session in history) {
      for (final exercise in session.exercises) {
        for (var index = 0; index < exercise.sets.length; index++) {
          final set = exercise.sets[index];
          rows.add([
            session.scheduleTitle,
            session.startTime.toIso8601String(),
            session.endTime.toIso8601String(),
            exercise.name,
            exercise.muscleGroup.label,
            index + 1,
            set.isWarmup,
            set.isCompleted,
            set.weight,
            set.reps,
            set.rpe,
            set.rir,
            set.notes,
          ]);
        }
      }
    }

    if (rows.length == 1) {
      return '';
    }

    return const ListToCsvConverter(
      fieldDelimiter: ',',
      eol: '\n',
    ).convert(rows);
  }

  String _buildBodyCsv() {
    final rows = <List<dynamic>>[
      [
        'date',
        'bodyWeight',
        'waist',
        'chest',
        'arm',
        'thigh',
        'sleepHours',
        'readiness',
        'photoName',
        'photoPath',
        'notes',
      ],
      ...bodyLogs.map(
        (entry) => [
          entry.date.toIso8601String(),
          entry.bodyWeight,
          entry.waist,
          entry.chest,
          entry.arm,
          entry.thigh,
          entry.sleepHours,
          entry.readiness,
          entry.photoName,
          entry.photoPath,
          entry.notes,
        ],
      ),
    ];

    if (rows.length == 1) {
      return '';
    }

    return const ListToCsvConverter(
      fieldDelimiter: ',',
      eol: '\n',
    ).convert(rows);
  }

  List<Schedule> _cloneSchedules(List<Schedule> source) {
    return source
        .map((schedule) => Schedule.fromJson(schedule.toJson()))
        .toList();
  }

  List<WorkoutSession> _cloneHistory(List<WorkoutSession> source) {
    return source
        .map((session) => WorkoutSession.fromJson(session.toJson()))
        .toList();
  }

  List<BodyLog> _cloneBodyLogs(List<BodyLog> source) {
    return source.map((entry) => BodyLog.fromJson(entry.toJson())).toList();
  }

  WorkoutSession? _cloneSession(WorkoutSession? source) {
    return source == null ? null : WorkoutSession.fromJson(source.toJson());
  }

  int _matchingScheduleIndex(List<Schedule> source, Schedule candidate) {
    return source.indexWhere((schedule) {
      final sameId = schedule.id == candidate.id;
      final sameTitleWeek =
          schedule.title.trim().toLowerCase() ==
              candidate.title.trim().toLowerCase() &&
          schedule.week == candidate.week;
      return sameId || sameTitleWeek;
    });
  }

  bool _sameSession(WorkoutSession a, WorkoutSession b) {
    return a.id == b.id ||
        (a.scheduleTitle.trim().toLowerCase() ==
                b.scheduleTitle.trim().toLowerCase() &&
            a.startTime == b.startTime &&
            a.endTime == b.endTime);
  }

  bool _sameBodyLog(BodyLog a, BodyLog b) {
    return a.id == b.id || _dateOnly(a.date) == _dateOnly(b.date);
  }

  void _mergeScheduleMetadata(Schedule target, Schedule incoming) {
    if (target.goal.trim().isEmpty) target.goal = incoming.goal;
    if (target.programBlock.trim().isEmpty) {
      target.programBlock = incoming.programBlock;
    }
    if (target.cycleNotes.trim().isEmpty) {
      target.cycleNotes = incoming.cycleNotes;
    }
    target.mesocycleWeeks = math.max(
      target.mesocycleWeeks,
      incoming.mesocycleWeeks,
    );
    target.deloadEveryWeeks = incoming.deloadEveryWeeks > 0
        ? incoming.deloadEveryWeeks
        : target.deloadEveryWeeks;
    target.cycleNumber = math.max(target.cycleNumber, incoming.cycleNumber);
    target.trainingWeekdays = {
      ...target.trainingWeekdays,
      ...incoming.trainingWeekdays,
    }.toList()..sort();
  }

  _BackupMergeResult _mergeBackupData({
    required List<Schedule> incomingSchedules,
    required List<WorkoutSession> incomingHistory,
    required List<BodyLog> incomingBodyLogs,
    required WorkoutSession? incomingCurrentSession,
  }) {
    final mergedSchedules = _cloneSchedules(schedules);
    final mergedHistory = _cloneHistory(history);
    final mergedBodyLogs = _cloneBodyLogs(bodyLogs);
    var addedSchedules = 0;
    var mergedScheduleCount = 0;
    var addedExercises = 0;
    var skippedExercises = 0;
    var addedHistory = 0;
    var skippedHistory = 0;
    var addedBodyLogs = 0;
    var skippedBodyLogs = 0;

    for (final incomingSchedule in incomingSchedules) {
      final targetIndex = _matchingScheduleIndex(
        mergedSchedules,
        incomingSchedule,
      );
      if (targetIndex == -1) {
        final clone = Schedule.fromJson(incomingSchedule.toJson());
        mergedSchedules.add(clone);
        addedSchedules++;
        addedExercises += clone.exercises.length;
        continue;
      }

      final target = mergedSchedules[targetIndex];
      _mergeScheduleMetadata(target, incomingSchedule);
      mergedScheduleCount++;
      for (final incomingExercise in incomingSchedule.exercises) {
        final exerciseClone = Exercise.fromJson(incomingExercise.toJson());
        if (_exerciseAlreadyExists(target, exerciseClone)) {
          skippedExercises++;
        } else {
          target.exercises.add(exerciseClone);
          addedExercises++;
        }
      }
    }

    for (final incomingSession in incomingHistory) {
      if (mergedHistory.any(
        (session) => _sameSession(session, incomingSession),
      )) {
        skippedHistory++;
      } else {
        mergedHistory.add(WorkoutSession.fromJson(incomingSession.toJson()));
        addedHistory++;
      }
    }

    for (final incomingBodyLog in incomingBodyLogs) {
      if (mergedBodyLogs.any((entry) => _sameBodyLog(entry, incomingBodyLog))) {
        skippedBodyLogs++;
      } else {
        mergedBodyLogs.add(BodyLog.fromJson(incomingBodyLog.toJson()));
        addedBodyLogs++;
      }
    }

    mergedBodyLogs.sort((a, b) => b.date.compareTo(a.date));
    mergedHistory.sort((a, b) => a.endTime.compareTo(b.endTime));
    return _BackupMergeResult(
      schedules: mergedSchedules,
      history: mergedHistory,
      bodyLogs: mergedBodyLogs,
      currentSession: _savedSession ?? _cloneSession(incomingCurrentSession),
      addedSchedules: addedSchedules,
      mergedSchedules: mergedScheduleCount,
      addedExercises: addedExercises,
      skippedExercises: skippedExercises,
      addedHistory: addedHistory,
      skippedHistory: skippedHistory,
      addedBodyLogs: addedBodyLogs,
      skippedBodyLogs: skippedBodyLogs,
    );
  }

  List<Exercise> _mergeCustomExerciseTemplates(
    List<Exercise> current,
    List<Exercise> incoming,
  ) {
    final merged = current
        .map((exercise) => Exercise.fromJson(exercise.toJson()))
        .toList();
    for (final exercise in incoming) {
      final normalizedName = exercise.name.trim().toLowerCase();
      final existingIndex = merged.indexWhere(
        (entry) => entry.name.trim().toLowerCase() == normalizedName,
      );
      final clone = Exercise.fromJson(exercise.toJson());
      if (existingIndex == -1) {
        merged.add(clone);
      } else {
        merged[existingIndex] = clone;
      }
    }
    merged.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return merged;
  }

  Future<void> _importCsv() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final pickedFile = result.files.single;
      if (!pickedFile.name.toLowerCase().endsWith('.csv')) {
        await _showInfo('Seleziona un file CSV valido.');
        return;
      }

      final inputString = await _readPickedTextFile(pickedFile);
      final rows = _decodeCsv(inputString);
      if (!mounted) {
        return;
      }

      int importedCount = 0;
      int skippedInvalidCount = 0;
      int skippedDuplicateCount = 0;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importare CSV?'),
          content: Text(
            'Verranno lette ${rows.length} righe in modalità merge. Gli esercizi già presenti verranno saltati.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importa'),
            ),
          ],
        ),
      );
      if (confirm != true) {
        return;
      }

      for (final row in rows) {
        if (row.length < 7) {
          skippedInvalidCount++;
          continue;
        }

        final hasFullSchema = row.length >= 20;
        final scheduleTitle = row[0].toString().trim();
        final week = parseIntInput(row[1].toString());
        final createdAt = hasFullSchema
            ? _parseDateCell(row[2])
            : DateTime.now();
        final goal = hasFullSchema ? row[3].toString().trim() : '';
        final mesocycleWeeks = hasFullSchema
            ? (parseIntInput(row[4].toString()) ?? 8)
            : 8;
        final deloadEveryWeeks = hasFullSchema
            ? (parseIntInput(row[5].toString()) ?? 4)
            : 4;
        final isArchived = hasFullSchema ? _parseBoolCell(row[6]) : false;
        final offset = hasFullSchema ? 7 : 0;
        final exerciseName = row[offset + 2].toString().trim();
        final sets = parseIntInput(row[offset + 3].toString());
        final reps = parseIntInput(row[offset + 4].toString());
        final targetMinReps = hasFullSchema
            ? parseIntInput(row[10].toString())
            : null;
        final targetMaxReps = hasFullSchema
            ? parseIntInput(row[11].toString())
            : null;
        final weight = parseDecimalInput(
          row[hasFullSchema ? 12 : 5].toString(),
        );
        final hasBackoffReductionColumn = hasFullSchema && row.length > 24;
        final notesIndex = hasBackoffReductionColumn ? 20 : 19;
        final restSecondsIndex = hasBackoffReductionColumn ? 19 : 18;
        final supersetGroupIndex = hasBackoffReductionColumn ? 21 : 20;
        final progressionKgStepIndex = hasBackoffReductionColumn ? 22 : 21;
        final progressionRepStepIndex = hasBackoffReductionColumn ? 23 : 22;
        final progressionSchemeIndex = hasBackoffReductionColumn ? 24 : 23;
        final notes = hasFullSchema
            ? row[notesIndex].toString().trim()
            : row[6].toString().trim();
        final muscleGroup = row.length > (hasFullSchema ? 13 : 7)
            ? muscleGroupFromJson(row[hasFullSchema ? 13 : 7])
            : MuscleGroup.unassigned;
        final equipment = hasFullSchema ? row[14].toString().trim() : '';
        final movementPattern = hasFullSchema ? row[15].toString().trim() : '';
        final technique = hasFullSchema
            ? _parseTechnique(row[16].toString())
            : IntensityTechnique.none;
        final backoffReps = hasFullSchema
            ? parseIntInput(row[17].toString())
            : null;
        final backoffReductionPercent = hasBackoffReductionColumn
            ? (parseDecimalInput(row[18].toString()) ??
                  _defaultBackoffReductionPercent)
            : _defaultBackoffReductionPercent;
        final restSeconds = hasFullSchema
            ? parseIntInput(row[restSecondsIndex].toString())
            : null;
        final supersetGroup = hasFullSchema && row.length > supersetGroupIndex
            ? parseIntInput(row[supersetGroupIndex].toString())
            : null;
        final progressionKgStep =
            hasFullSchema && row.length > progressionKgStepIndex
            ? (parseDecimalInput(row[progressionKgStepIndex].toString()) ?? 2.5)
            : 2.5;
        final progressionRepStep =
            hasFullSchema && row.length > progressionRepStepIndex
            ? (parseIntInput(row[progressionRepStepIndex].toString()) ?? 1)
            : 1;
        final progressionScheme =
            hasFullSchema && row.length > progressionSchemeIndex
            ? progressionSchemeFromJson(row[progressionSchemeIndex])
            : ProgressionScheme.doubleProgression;

        if (scheduleTitle.isEmpty ||
            week == null ||
            exerciseName.isEmpty ||
            sets == null ||
            reps == null ||
            weight == null) {
          skippedInvalidCount++;
          continue;
        }

        final candidate = Exercise(
          name: exerciseName,
          set: sets,
          reps: reps,
          weight: weight,
          muscleGroup: muscleGroup,
          equipment: equipment,
          movementPattern: movementPattern,
          targetMinReps: targetMinReps,
          targetMaxReps: targetMaxReps,
          notes: notes,
          technique: technique,
          backoffReps: backoffReps,
          backoffReductionPercent: backoffReductionPercent,
          restSeconds: restSeconds,
          supersetGroup: supersetGroup,
          progressionKgStep: progressionKgStep,
          progressionRepStep: progressionRepStep,
          progressionScheme: progressionScheme,
        );

        final scheduleIndex = schedules.indexWhere(
          (s) => s.title == scheduleTitle && s.week == week,
        );
        final schedule = scheduleIndex != -1
            ? schedules[scheduleIndex]
            : Schedule(
                title: scheduleTitle,
                week: week,
                createdAt: createdAt,
                exercises: [],
                isArchived: isArchived,
                mesocycleWeeks: mesocycleWeeks,
                deloadEveryWeeks: deloadEveryWeeks,
                goal: goal,
              );

        if (scheduleIndex == -1) {
          schedules.add(schedule);
        } else {
          schedule.isArchived = false;
          if (hasFullSchema) {
            schedule.goal = goal;
            schedule.mesocycleWeeks = mesocycleWeeks;
            schedule.deloadEveryWeeks = deloadEveryWeeks;
          }
        }

        if (_exerciseAlreadyExists(schedule, candidate)) {
          skippedDuplicateCount++;
          continue;
        }

        schedule.exercises.add(candidate);
        importedCount++;
      }

      _sortSchedules();
      setState(() {});
      await _saveSchedules();
      await _showInfo(
        'Importati $importedCount esercizi. Righe ignorate: $skippedInvalidCount. Duplicati saltati: $skippedDuplicateCount.',
      );
    } catch (e) {
      await _showInfo('Errore durante importazione: $e');
    }
  }

  Future<void> _exportSchedulesCsv() async {
    try {
      final csvText = _buildSchedulesCsv();
      if (csvText.isEmpty) {
        await _showInfo('Non ci sono schede da esportare in CSV.');
        return;
      }

      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Esporta schede CSV',
        fileName: 'gymapp_schede.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(csvText)),
      );

      if (savedPath == null && !kIsWeb) {
        return;
      }

      await _showInfo('Schede esportate in CSV con successo.');
    } catch (e) {
      await _showInfo('Errore durante export schede CSV: $e');
    }
  }

  Future<void> _exportHistoryCsv() async {
    try {
      final csvText = _buildHistoryCsv();
      if (csvText.isEmpty) {
        await _showInfo('Non ci sono allenamenti da esportare.');
        return;
      }

      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Esporta cronologia CSV',
        fileName: 'gymapp_cronologia.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(csvText)),
      );

      if (savedPath == null && !kIsWeb) {
        return;
      }

      await _showInfo('Cronologia esportata con successo.');
    } catch (e) {
      await _showInfo('Errore durante export cronologia: $e');
    }
  }

  Future<void> _exportBodyCsv() async {
    try {
      final csvText = _buildBodyCsv();
      if (csvText.isEmpty) {
        await _showInfo('Non ci sono misure corpo da esportare.');
        return;
      }

      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Esporta corpo CSV',
        fileName: 'gymapp_corpo.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(csvText)),
      );

      if (savedPath == null && !kIsWeb) {
        return;
      }

      await _showInfo('Misure corpo esportate con successo.');
    } catch (e) {
      await _showInfo('Errore durante export corpo: $e');
    }
  }

  Future<void> _exportBackupJson() async {
    try {
      final payload = await AppDataStore.buildExportPayload(
        schedules: schedules,
        history: history,
        bodyLogs: bodyLogs,
        currentSession: _savedSession,
      );
      final backupText = const JsonEncoder.withIndent('  ').convert(payload);
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Esporta tutto (JSON)',
        fileName: 'gymapp_export_completo.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(backupText)),
      );

      if (savedPath == null && !kIsWeb) {
        return;
      }

      await _showInfo(
        'Export completo: ${schedules.length} schede, ${history.length} allenamenti, ${bodyLogs.length} misure corpo.',
      );
    } catch (e) {
      await _showInfo('Errore durante export completo: $e');
    }
  }

  Future<void> _restoreBackupJson() async {
    try {
      final confirm =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Importare backup JSON?'),
              content: const Text(
                'Dopo il file potrai scegliere merge dedup o sostituzione completa.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annulla'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Scegli file'),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirm) {
        return;
      }

      final result = await FilePicker.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final pickedFile = result.files.single;
      if (!pickedFile.name.toLowerCase().endsWith('.json')) {
        await _showInfo('Seleziona un file JSON valido.');
        return;
      }

      final rawText = await _readPickedTextFile(pickedFile);
      final decoded = jsonDecode(_normalizeText(rawText));
      final previousSchedules = _cloneSchedules(schedules);
      final previousHistory = _cloneHistory(history);
      final previousBodyLogs = _cloneBodyLogs(bodyLogs);
      final previousCurrentSession = _savedSession == null
          ? null
          : WorkoutSession.fromJson(_savedSession!.toJson());
      final previousCustomExercises = await AppDataStore.loadCustomExercises();
      final previousFavoriteExerciseIds =
          await AppDataStore.loadFavoriteExerciseIds();

      List<Schedule> restoredSchedules = [];
      List<WorkoutSession> restoredHistory = [];
      List<BodyLog> restoredBodyLogs = [];
      List<Exercise>? restoredCustomExercises;
      Set<String>? restoredFavoriteExerciseIds;
      WorkoutSession? restoredCurrentSession;

      if (decoded is Map) {
        final backupMap = Map<String, dynamic>.from(decoded);
        restoredSchedules = (backupMap['schedules'] as List? ?? [])
            .map((e) => Schedule.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        restoredHistory = (backupMap['history'] as List? ?? [])
            .map(
              (e) =>
                  WorkoutSession.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        restoredBodyLogs = (backupMap['bodyLogs'] as List? ?? [])
            .map((e) => BodyLog.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (backupMap.containsKey('customExercises')) {
          restoredCustomExercises =
              (backupMap['customExercises'] as List? ?? [])
                  .map(
                    (e) =>
                        Exercise.fromJson(Map<String, dynamic>.from(e as Map)),
                  )
                  .toList();
        }
        if (backupMap.containsKey('favoriteExerciseIds')) {
          restoredFavoriteExerciseIds =
              (backupMap['favoriteExerciseIds'] as List? ?? [])
                  .map((entry) => entry.toString())
                  .toSet();
        }
        restoredCurrentSession = backupMap['currentSession'] == null
            ? null
            : WorkoutSession.fromJson(
                Map<String, dynamic>.from(backupMap['currentSession'] as Map),
              );
      } else if (decoded is List) {
        restoredSchedules = decoded
            .map((e) => Schedule.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } else {
        throw Exception('Formato backup non supportato.');
      }

      if (!mounted) {
        return;
      }

      final mergePreview = _mergeBackupData(
        incomingSchedules: restoredSchedules,
        incomingHistory: restoredHistory,
        incomingBodyLogs: restoredBodyLogs,
        incomingCurrentSession: restoredCurrentSession,
      );

      final importMode = await showDialog<_BackupImportMode>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Come importare?'),
          content: Text(
            'File: ${restoredSchedules.length} schede, ${restoredHistory.length} allenamenti, ${restoredBodyLogs.length} misure corpo, ${restoredCustomExercises?.length ?? 0} esercizi custom, ${restoredFavoriteExerciseIds?.length ?? 0} preferiti esercizi.\n\nMerge dedup: +${mergePreview.addedSchedules} schede, ${mergePreview.mergedSchedules} schede unite, +${mergePreview.addedExercises} esercizi, ${mergePreview.skippedExercises} esercizi duplicati saltati, +${mergePreview.addedHistory} allenamenti, ${mergePreview.skippedHistory} allenamenti duplicati, +${mergePreview.addedBodyLogs} misure, ${mergePreview.skippedBodyLogs} misure duplicate.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.pop(context, _BackupImportMode.replace),
              child: const Text('Sostituisci'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, _BackupImportMode.merge),
              child: const Text('Unisci dedup'),
            ),
          ],
        ),
      );

      if (importMode == null || !mounted) {
        return;
      }

      final appliedSchedules = importMode == _BackupImportMode.merge
          ? mergePreview.schedules
          : restoredSchedules;
      final appliedHistory = importMode == _BackupImportMode.merge
          ? mergePreview.history
          : restoredHistory;
      final appliedBodyLogs = importMode == _BackupImportMode.merge
          ? mergePreview.bodyLogs
          : restoredBodyLogs;
      final appliedCurrentSession = importMode == _BackupImportMode.merge
          ? mergePreview.currentSession
          : restoredCurrentSession;
      final appliedCustomExercises = restoredCustomExercises == null
          ? previousCustomExercises
          : importMode == _BackupImportMode.merge
          ? _mergeCustomExerciseTemplates(
              previousCustomExercises,
              restoredCustomExercises,
            )
          : restoredCustomExercises;
      final appliedFavoriteExerciseIds = restoredFavoriteExerciseIds == null
          ? previousFavoriteExerciseIds
          : importMode == _BackupImportMode.merge
          ? {...previousFavoriteExerciseIds, ...restoredFavoriteExerciseIds}
          : restoredFavoriteExerciseIds;

      setState(() {
        schedules
          ..clear()
          ..addAll(appliedSchedules);
        history
          ..clear()
          ..addAll(appliedHistory);
        bodyLogs
          ..clear()
          ..addAll(appliedBodyLogs);
        _savedSession = appliedCurrentSession;
        _sortSchedules();
      });

      await _saveAllData();
      if (appliedCurrentSession == null) {
        await AppDataStore.clearCurrentSession();
      } else {
        await AppDataStore.saveCurrentSession(appliedCurrentSession);
      }
      await AppDataStore.saveCustomExercises(appliedCustomExercises);
      await AppDataStore.saveFavoriteExerciseIds(appliedFavoriteExerciseIds);
      _showUndoSnackBar(
        message: importMode == _BackupImportMode.merge
            ? 'Backup unito.'
            : 'Backup ripristinato.',
        onUndo: () {
          if (!mounted) {
            return;
          }

          setState(() {
            schedules
              ..clear()
              ..addAll(_cloneSchedules(previousSchedules));
            history
              ..clear()
              ..addAll(_cloneHistory(previousHistory));
            bodyLogs
              ..clear()
              ..addAll(_cloneBodyLogs(previousBodyLogs));
            _savedSession = previousCurrentSession;
            _sortSchedules();
          });
          _saveAllData();
          if (previousCurrentSession == null) {
            AppDataStore.clearCurrentSession();
          } else {
            AppDataStore.saveCurrentSession(previousCurrentSession);
          }
          AppDataStore.saveCustomExercises(previousCustomExercises);
          AppDataStore.saveFavoriteExerciseIds(previousFavoriteExerciseIds);
        },
      );
    } catch (e) {
      await _showInfo('Errore durante ripristino backup: $e');
    }
  }

  Future<void> _restoreAutoBackupSnapshot() async {
    try {
      final backupBundle = await AppDataStore.loadAutoBackupBundle();
      if (backupBundle == null) {
        await _showInfo('Nessun auto-backup disponibile.');
        return;
      }
      if (!mounted) {
        return;
      }

      final confirm =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Ripristinare auto-backup?'),
              content: Text(
                'Verranno ripristinate ${backupBundle.schedules.length} schede, ${backupBundle.history.length} allenamenti, ${backupBundle.bodyLogs.length} misure corpo, ${backupBundle.customExercises.length} esercizi custom e ${backupBundle.favoriteExerciseIds.length} preferiti dall\'ultimo snapshot locale.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annulla'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Ripristina'),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirm || !mounted) {
        return;
      }

      setState(() {
        schedules
          ..clear()
          ..addAll(_cloneSchedules(backupBundle.schedules));
        history
          ..clear()
          ..addAll(_cloneHistory(backupBundle.history));
        bodyLogs
          ..clear()
          ..addAll(_cloneBodyLogs(backupBundle.bodyLogs));
        _savedSession = backupBundle.currentSession;
        _sortSchedules();
      });

      await _saveAllData();
      if (_savedSession == null) {
        await AppDataStore.clearCurrentSession();
      } else {
        await AppDataStore.saveCurrentSession(_savedSession!);
      }
      await AppDataStore.saveCustomExercises(backupBundle.customExercises);
      await AppDataStore.saveFavoriteExerciseIds(
        backupBundle.favoriteExerciseIds,
      );
      await _showInfo('Auto-backup ripristinato.');
    } catch (e) {
      await _showInfo('Errore ripristino auto-backup: $e');
    }
  }

  void _deleteSchedule(int index) {
    if (index < 0 || index >= schedules.length) {
      return;
    }

    final deletedSchedule = schedules[index];
    setState(() {
      schedules.removeAt(index);
    });
    _saveSchedules();

    _showUndoSnackBar(
      message: 'Scheda eliminata.',
      onUndo: () {
        if (!mounted || schedules.contains(deletedSchedule)) {
          return;
        }

        setState(() {
          final restoreIndex = index > schedules.length
              ? schedules.length
              : index;
          schedules.insert(restoreIndex, deletedSchedule);
          _sortSchedules();
        });
        _saveSchedules();
      },
    );
  }

  void _addSchedule(
    String title, {
    String goal = '',
    int mesocycleWeeks = 8,
    int deloadEveryWeeks = 4,
    List<int> trainingWeekdays = const [],
  }) {
    setState(() {
      schedules.add(
        Schedule(
          title: title,
          week: 1,
          createdAt: DateTime.now(),
          exercises: [],
          goal: goal,
          mesocycleWeeks: mesocycleWeeks,
          deloadEveryWeeks: deloadEveryWeeks,
          trainingWeekdays: trainingWeekdays,
        ),
      );
      _sortSchedules();
    });
    _saveSchedules();
  }

  void _duplicateSchedule(Schedule schedule) {
    final copiedExercises = schedule.exercises
        .map(
          (exercise) => Exercise(
            name: exercise.name,
            set: exercise.set,
            reps: exercise.reps,
            weight: exercise.weight,
            muscleGroup: exercise.muscleGroup,
            equipment: exercise.equipment,
            movementPattern: exercise.movementPattern,
            targetMinReps: exercise.targetMinReps,
            targetMaxReps: exercise.targetMaxReps,
            notes: exercise.notes,
            technique: exercise.technique,
            backoffReps: exercise.backoffReps,
            backoffReductionPercent: exercise.backoffReductionPercent,
            restSeconds: exercise.restSeconds,
            supersetGroup: exercise.supersetGroup,
            progressionKgStep: exercise.progressionKgStep,
            progressionRepStep: exercise.progressionRepStep,
            progressionScheme: exercise.progressionScheme,
          ),
        )
        .toList();

    setState(() {
      schedules.add(
        Schedule(
          title: '${schedule.title} (copia)',
          week: schedule.currentWeek(),
          createdAt: DateTime.now(),
          exercises: copiedExercises,
          mesocycleWeeks: schedule.mesocycleWeeks,
          deloadEveryWeeks: schedule.deloadEveryWeeks,
          goal: schedule.goal,
          trainingWeekdays: List<int>.from(schedule.trainingWeekdays),
          programBlock: schedule.programBlock,
          cycleNumber: schedule.cycleNumber,
          cycleNotes: schedule.cycleNotes,
        ),
      );
      _sortSchedules();
    });
    _saveSchedules();
  }

  Future<void> _renameSchedule(Schedule schedule) async {
    final titleController = TextEditingController(text: schedule.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rinomina scheda'),
        content: AppDialogContent(
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Titolo'),
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                final title = value.trim();
                if (title.isNotEmpty) {
                  Navigator.pop(context, title);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isNotEmpty) {
                Navigator.pop(context, title);
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );

    if (!mounted || newTitle == null || newTitle == schedule.title) {
      return;
    }

    setState(() {
      schedule.title = newTitle;
      _sortSchedules();
    });
    _saveSchedules();
  }

  void _toggleArchiveSchedule(Schedule schedule) {
    setState(() {
      schedule.isArchived = !schedule.isArchived;
      _sortSchedules();
    });
    _saveSchedules();
  }

  List<int> _availableWeeks() {
    final weeks = schedules
        .map((schedule) => schedule.currentWeek())
        .toSet()
        .toList();
    weeks.sort();
    return weeks;
  }

  List<Schedule> _filteredSchedules() {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = schedules.where((schedule) {
      if (!_showArchived && schedule.isArchived) {
        return false;
      }

      if (_selectedWeekFilter != null &&
          schedule.currentWeek() != _selectedWeekFilter) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final matchesTitle = schedule.title.toLowerCase().contains(query);
      final matchesExercise = schedule.exercises.any(
        (exercise) => exercise.name.toLowerCase().contains(query),
      );

      return matchesTitle || matchesExercise;
    }).toList();

    filtered.sort((a, b) {
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
      }

      final weekCompare = a.currentWeek().compareTo(b.currentWeek());
      if (weekCompare != 0) {
        return weekCompare;
      }

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return filtered;
  }

  void _showAddScheduleDialog() {
    final titleController = TextEditingController();
    final goalController = TextEditingController();
    final mesocycleController = TextEditingController(text: '8');
    final deloadController = TextEditingController(text: '4');
    final selectedDays = <int>{};

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuova scheda'),
          content: AppDialogContent(
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Titolo'),
              ),
              appDialogFieldGap,
              TextField(
                controller: goalController,
                decoration: const InputDecoration(labelText: 'Obiettivo'),
              ),
              appDialogFieldGap,
              AppFieldRow(
                children: [
                  TextField(
                    controller: mesocycleController,
                    decoration: const InputDecoration(labelText: 'Settimane'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: deloadController,
                    decoration: const InputDecoration(labelText: 'Deload ogni'),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              appDialogFieldGap,
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Giorni allenamento',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(7, (index) {
                  final weekday = index + 1;
                  return FilterChip(
                    label: Text(_weekdayLabel(weekday)),
                    selected: selectedDays.contains(weekday),
                    onSelected: (selected) => setDialogState(() {
                      if (selected) {
                        selectedDays.add(weekday);
                      } else {
                        selectedDays.remove(weekday);
                      }
                    }),
                  );
                }),
              ),
              appDialogFieldGap,
              const Text('La settimana avanza ogni lunedì.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  _addSchedule(
                    title,
                    goal: goalController.text.trim(),
                    mesocycleWeeks:
                        parseIntInput(mesocycleController.text) ?? 8,
                    deloadEveryWeeks: parseIntInput(deloadController.text) ?? 4,
                    trainingWeekdays: selectedDays.toList()..sort(),
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onExportBackup: _exportBackupJson,
          onRestoreBackup: _restoreBackupJson,
          onRestoreAutoBackup: _restoreAutoBackupSnapshot,
          onBackoffReductionChanged: _saveBackoffReductionPercent,
          schedules: schedules,
        ),
      ),
    );
  }

  Color _accentForIndex(ColorScheme colorScheme, int index) {
    final accents = [
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      colorScheme.error,
    ];
    return accents[index % accents.length];
  }

  Widget _buildDeleteBackground(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Icon(Icons.delete, color: colorScheme.onErrorContainer),
          ),
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Icon(
                icon,
                color: colorScheme.onPrimaryContainer,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action],
          ],
        ),
      ),
    );
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Widget _buildOnboardingTab() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Setup iniziale',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Crea la prima scheda, imposta obiettivo e giorni di allenamento.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _showAddScheduleDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Crea scheda'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _importCsv,
                      icon: const Icon(Icons.file_upload),
                      label: const Text('Importa CSV'),
                    ),
                    TextButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.privacy_tip),
                      label: const Text('Privacy e backup'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.offline_bolt),
            title: Text('Offline by design'),
            subtitle: Text(
              'Nessun account o server: backup JSON per spostare dati.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.trending_up),
            title: Text('Progressione guidata'),
            subtitle: Text(
              'Dopo la prima seduta l\'app suggerisce carico e reps prossime.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarTab() {
    return CalendarScreen(
      schedules: schedules,
      history: history,
      defaultRestSeconds: _defaultRestSeconds,
      defaultBackoffReductionPercent: _defaultBackoffReductionPercent,
      onRefresh: _loadData,
      onSaveSchedules: _saveSchedules,
      showAppBar: false,
    );
  }

  Widget _buildSchedulesTab() {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (schedules.isEmpty) {
      return _buildOnboardingTab();
    }

    final visibleSchedules = _filteredSchedules();
    final availableWeeks = _availableWeeks();
    final selectedWeekValue = availableWeeks.contains(_selectedWeekFilter)
        ? _selectedWeekFilter
        : null;
    return Column(
      children: [
        ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Cerca',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                ),
              ),
            ),
            if (_savedSession != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: ListTile(
                    isThreeLine: true,
                    title: Text(
                      'Riprendi allenamento: ${_savedSession!.scheduleTitle}',
                    ),
                    subtitle: Text(
                      'Iniziato ${_savedSession!.startTime.day}/${_savedSession!.startTime.month}/${_savedSession!.startTime.year}',
                    ),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FilledButton(
                          onPressed: () async {
                            final session = _savedSession!;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ActiveWorkoutScreen.resume(
                                      resumedSession: session,
                                      history: history,
                                      defaultRestSeconds: _defaultRestSeconds,
                                      defaultBackoffReductionPercent:
                                          _defaultBackoffReductionPercent,
                                    ),
                              ),
                            );
                            _loadData();
                          },
                          child: const Text('Riprendi'),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: _discardSavedSession,
                          child: const Text('Scarta'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<int?>(
                      initialValue: selectedWeekValue,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Week'),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Tutte'),
                        ),
                        ...availableWeeks.map(
                          (week) => DropdownMenuItem<int?>(
                            value: week,
                            child: Text('W$week'),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedWeekFilter = value),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Archiviate'),
                    selected: _showArchived,
                    onSelected: (selected) =>
                        setState(() => _showArchived = selected),
                  ),
                  if (_searchQuery.isNotEmpty ||
                      _selectedWeekFilter != null ||
                      _showArchived)
                    IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _selectedWeekFilter = null;
                          _showArchived = false;
                        });
                      },
                      tooltip: 'Reset filtri',
                      icon: const Icon(Icons.refresh),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        Expanded(
          child: visibleSchedules.isEmpty
              ? _emptyState(
                  icon: Icons.list_alt,
                  title: 'Nessuna scheda visibile',
                  subtitle: 'Crea una scheda o modifica i filtri attivi.',
                  action: schedules.isEmpty
                      ? FilledButton.icon(
                          onPressed: _showAddScheduleDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Crea scheda'),
                        )
                      : null,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: visibleSchedules.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final schedule = visibleSchedules[index];
                    final currentWeek = schedule.currentWeek();
                    final actualIndex = schedules.indexOf(schedule);
                    final accent = _accentForIndex(colorScheme, index);

                    return Dismissible(
                      key: ValueKey(schedule.id),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) {
                        if (actualIndex != -1) {
                          _deleteSchedule(actualIndex);
                        }
                      },
                      background: _buildDeleteBackground(colorScheme),
                      child: Card(
                        color: schedule.isArchived
                            ? colorScheme.surfaceContainerHighest
                            : null,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: schedule.isArchived
                                ? null
                                : LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      accent.withValues(
                                        alpha: isDark ? 0.18 : 0.10,
                                      ),
                                      colorScheme.surface.withValues(
                                        alpha: 0.0,
                                      ),
                                    ],
                                  ),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: accent.withValues(
                                  alpha: isDark ? 0.20 : 0.12,
                                ),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'W',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: accent,
                                            fontWeight: FontWeight.w900,
                                            height: 1,
                                          ),
                                    ),
                                    Text(
                                      '$currentWeek',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            color: accent,
                                            fontWeight: FontWeight.w900,
                                            height: 1,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            title: Text(
                              schedule.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: schedule.isArchived
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.onSurface,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${schedule.exercises.length} esercizi${schedule.isDeloadWeek() ? ' • deload' : ''} • Ciclo ${schedule.cycleNumber}${schedule.programBlock.trim().isEmpty ? '' : ' • ${schedule.programBlock}'}${schedule.goal.trim().isNotEmpty ? '\n${schedule.goal}' : ''}${schedule.isArchived ? ' • archiviata' : ''}',
                                softWrap: true,
                              ),
                            ),
                            trailing: PopupMenuButton<_ScheduleMenuAction>(
                              tooltip: 'Azioni',
                              onSelected: (action) {
                                switch (action) {
                                  case _ScheduleMenuAction.rename:
                                    _renameSchedule(schedule);
                                    break;
                                  case _ScheduleMenuAction.duplicate:
                                    _duplicateSchedule(schedule);
                                    break;
                                  case _ScheduleMenuAction.toggleArchive:
                                    _toggleArchiveSchedule(schedule);
                                    break;
                                  case _ScheduleMenuAction.delete:
                                    if (actualIndex != -1) {
                                      _deleteSchedule(actualIndex);
                                    }
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: _ScheduleMenuAction.rename,
                                  child: ListTile(
                                    leading: Icon(Icons.edit),
                                    title: Text('Rinomina'),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: _ScheduleMenuAction.duplicate,
                                  child: ListTile(
                                    leading: Icon(Icons.copy),
                                    title: Text('Duplica'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: _ScheduleMenuAction.toggleArchive,
                                  child: ListTile(
                                    leading: Icon(
                                      schedule.isArchived
                                          ? Icons.unarchive
                                          : Icons.archive,
                                    ),
                                    title: Text(
                                      schedule.isArchived
                                          ? 'Ripristina'
                                          : 'Archivia',
                                    ),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: _ScheduleMenuAction.delete,
                                  child: ListTile(
                                    leading: Icon(Icons.delete),
                                    title: Text('Elimina'),
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => _openScheduleDetail(schedule),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatHistoryVolume(double volume) {
    return volume % 1 == 0
        ? volume.toStringAsFixed(0)
        : volume.toStringAsFixed(1);
  }

  String _formatSignedVolume(double value) {
    final prefix = value > 0 ? '+' : '';
    return '$prefix${_formatHistoryVolume(value)} kg';
  }

  String _normalizeExerciseName(String name) => name.trim().toLowerCase();

  double _setVolume(ExerciseSet set) => set.weight * set.reps;

  double _exerciseVolume(WorkoutExercise exercise) {
    var volume = 0.0;
    for (final set in exercise.sets) {
      if (set.isCompleted && !set.isWarmup) {
        volume += _setVolume(set);
      }
    }
    return volume;
  }

  double _bestSetVolume(WorkoutExercise exercise) {
    var bestVolume = 0.0;
    for (final set in exercise.sets) {
      if (!set.isCompleted || set.isWarmup) {
        continue;
      }
      final volume = _setVolume(set);
      if (volume > bestVolume) {
        bestVolume = volume;
      }
    }
    return bestVolume;
  }

  int _completedWorkSets(WorkoutExercise exercise) {
    return exercise.sets
        .where((set) => set.isCompleted && !set.isWarmup)
        .length;
  }

  WorkoutExercise? _previousExerciseBefore(
    WorkoutSession session,
    WorkoutExercise exercise,
  ) {
    final exerciseName = _normalizeExerciseName(exercise.name);
    final olderSessions = List<WorkoutSession>.from(history)
      ..sort((a, b) => b.endTime.compareTo(a.endTime));

    for (final candidateSession in olderSessions) {
      if (!candidateSession.endTime.isBefore(session.endTime)) {
        continue;
      }

      for (final candidateExercise in candidateSession.exercises) {
        if (_normalizeExerciseName(candidateExercise.name) == exerciseName &&
            _completedWorkSets(candidateExercise) > 0) {
          return candidateExercise;
        }
      }
    }

    return null;
  }

  bool _exerciseHasPrAtSession(
    WorkoutSession session,
    WorkoutExercise exercise,
  ) {
    final exerciseName = _normalizeExerciseName(exercise.name);
    final previousExercises = history
        .where(
          (candidateSession) =>
              candidateSession.endTime.isBefore(session.endTime),
        )
        .expand((candidateSession) => candidateSession.exercises)
        .where(
          (candidateExercise) =>
              _normalizeExerciseName(candidateExercise.name) == exerciseName,
        )
        .toList();
    if (previousExercises.isEmpty) {
      return false;
    }

    double bestWeight = 0;
    int bestReps = 0;
    double bestSetVolume = 0;
    double bestExerciseVolume = 0;
    for (final previousExercise in previousExercises) {
      bestExerciseVolume = math.max(
        bestExerciseVolume,
        _exerciseVolume(previousExercise),
      );
      for (final set in previousExercise.sets) {
        if (!set.isCompleted || set.isWarmup) {
          continue;
        }
        bestWeight = math.max(bestWeight, set.weight);
        bestReps = math.max(bestReps, set.reps);
        bestSetVolume = math.max(bestSetVolume, _setVolume(set));
      }
    }

    for (final set in exercise.sets) {
      if (!set.isCompleted || set.isWarmup) {
        continue;
      }
      if (set.weight > bestWeight ||
          set.reps > bestReps ||
          _setVolume(set) > bestSetVolume) {
        return true;
      }
    }

    return _exerciseVolume(exercise) > bestExerciseVolume;
  }

  bool _sessionHasPr(WorkoutSession session) {
    return session.exercises.any(
      (exercise) => _exerciseHasPrAtSession(session, exercise),
    );
  }

  List<WorkoutSession> _filteredHistorySessions(
    List<WorkoutSession> sortedHistory,
  ) {
    final now = DateTime.now();
    final minDate = switch (_historyRangeFilter) {
      _HistoryRangeFilter.all => null,
      _HistoryRangeFilter.last30 => now.subtract(const Duration(days: 30)),
      _HistoryRangeFilter.last90 => now.subtract(const Duration(days: 90)),
    };
    final normalizedQuery = _historyQuery.trim().toLowerCase();

    return sortedHistory.where((session) {
      if (minDate != null && session.endTime.isBefore(minDate)) {
        return false;
      }
      if (_historyOnlyPr && !_sessionHasPr(session)) {
        return false;
      }
      if (normalizedQuery.isEmpty) {
        return true;
      }

      return session.scheduleTitle.toLowerCase().contains(normalizedQuery) ||
          session.exercises.any((exercise) {
            return exercise.name.toLowerCase().contains(normalizedQuery) ||
                exercise.muscleGroup.label.toLowerCase().contains(
                  normalizedQuery,
                );
          });
    }).toList();
  }

  List<_PrSummary> _buildRecentPrSummaries() {
    final summaries = <_PrSummary>[];
    final sortedHistory = List<WorkoutSession>.from(history)
      ..sort((a, b) => b.endTime.compareTo(a.endTime));

    for (final session in sortedHistory) {
      for (final exercise in session.exercises) {
        if (_exerciseHasPrAtSession(session, exercise)) {
          summaries.add(
            _PrSummary(
              exerciseName: exercise.name,
              scheduleTitle: session.scheduleTitle,
              date: session.endTime,
            ),
          );
        }
      }
      if (summaries.length >= 8) {
        break;
      }
    }

    return summaries;
  }

  Widget _buildHistoryFilterCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              onChanged: (value) => setState(() => _historyQuery = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cerca storico: esercizio, scheda, gruppo',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Tutto'),
                  selected: _historyRangeFilter == _HistoryRangeFilter.all,
                  onSelected: (_) => setState(
                    () => _historyRangeFilter = _HistoryRangeFilter.all,
                  ),
                ),
                ChoiceChip(
                  label: const Text('30 giorni'),
                  selected: _historyRangeFilter == _HistoryRangeFilter.last30,
                  onSelected: (_) => setState(
                    () => _historyRangeFilter = _HistoryRangeFilter.last30,
                  ),
                ),
                ChoiceChip(
                  label: const Text('90 giorni'),
                  selected: _historyRangeFilter == _HistoryRangeFilter.last90,
                  onSelected: (_) => setState(
                    () => _historyRangeFilter = _HistoryRangeFilter.last90,
                  ),
                ),
                FilterChip(
                  label: const Text('Solo PR'),
                  selected: _historyOnlyPr,
                  onSelected: (selected) =>
                      setState(() => _historyOnlyPr = selected),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrDashboardCard(List<_PrSummary> summaries) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.military_tech),
        title: const Text(
          'Record recenti',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          summaries.isEmpty
              ? 'Nessun PR rilevato con storico precedente.'
              : '${summaries.length} PR recenti',
        ),
        children: summaries.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Completa altre sessioni per sbloccare record.'),
                ),
              ]
            : summaries.map((summary) {
                return ListTile(
                  leading: const Icon(Icons.emoji_events),
                  title: Text(summary.exerciseName),
                  subtitle: Text(summary.scheduleTitle),
                  trailing: Text('${summary.date.day}/${summary.date.month}'),
                  onTap: () => _showExerciseDetail(summary.exerciseName),
                );
              }).toList(),
      ),
    );
  }

  Future<void> _editCompletedWorkout(WorkoutSession session) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ActiveWorkoutScreen.editCompleted(
          session: session,
          history: history,
          defaultRestSeconds: _defaultRestSeconds,
          defaultBackoffReductionPercent: _defaultBackoffReductionPercent,
        ),
      ),
    );
    if (mounted) {
      await _loadData();
    }
  }

  Future<void> _showHistorySessionDialog(WorkoutSession session) async {
    final titleController = TextEditingController(text: session.scheduleTitle);
    final dateController = TextEditingController(
      text:
          '${session.endTime.day}/${session.endTime.month}/${session.endTime.year}',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifica sessione'),
        content: AppDialogContent(
          maxWidth: 480,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Titolo'),
            ),
            appDialogFieldGap,
            TextField(
              controller: dateController,
              decoration: const InputDecoration(
                labelText: 'Data',
                hintText: 'gg/mm/aaaa',
              ),
              keyboardType: TextInputType.datetime,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salva'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) {
      return;
    }

    final parts = dateController.text.split('/');
    DateTime? parsedDate;
    if (parts.length == 3) {
      final day = parseIntInput(parts[0]);
      final month = parseIntInput(parts[1]);
      final year = parseIntInput(parts[2]);
      if (day != null && month != null && year != null) {
        parsedDate = DateTime(year, month, day);
      }
    }

    setState(() {
      session.scheduleTitle = titleController.text.trim().isEmpty
          ? session.scheduleTitle
          : titleController.text.trim();
      if (parsedDate != null) {
        session.startTime = DateTime(
          parsedDate.year,
          parsedDate.month,
          parsedDate.day,
          session.startTime.hour,
          session.startTime.minute,
        );
        session.endTime = DateTime(
          parsedDate.year,
          parsedDate.month,
          parsedDate.day,
          session.endTime.hour,
          session.endTime.minute,
        );
      }
    });
    _saveHistory();
  }

  List<_ExerciseProgressSummary> _buildExerciseProgressSummaries() {
    final occurrencesByExercise = <String, List<_ExerciseOccurrence>>{};
    final sortedHistory = List<WorkoutSession>.from(history)
      ..sort((a, b) => a.endTime.compareTo(b.endTime));

    for (final session in sortedHistory) {
      for (final exercise in session.exercises) {
        if (_completedWorkSets(exercise) == 0) {
          continue;
        }

        final key = _normalizeExerciseName(exercise.name);
        occurrencesByExercise
            .putIfAbsent(key, () => [])
            .add(_ExerciseOccurrence(session: session, exercise: exercise));
      }
    }

    final summaries = <_ExerciseProgressSummary>[];
    for (final occurrences in occurrencesByExercise.values) {
      if (occurrences.length < 2) {
        continue;
      }

      final latest = occurrences.last;
      final previous = occurrences[occurrences.length - 2];
      final latestVolume = _exerciseVolume(latest.exercise);
      final previousVolume = _exerciseVolume(previous.exercise);
      final latestBestSetVolume = _bestSetVolume(latest.exercise);
      final previousBestSetVolume = _bestSetVolume(previous.exercise);
      summaries.add(
        _ExerciseProgressSummary(
          name: latest.exercise.name,
          latestDate: latest.session.endTime,
          latestVolume: latestVolume,
          previousVolume: previousVolume,
          volumeDelta: latestVolume - previousVolume,
          latestBestSetVolume: latestBestSetVolume,
          previousBestSetVolume: previousBestSetVolume,
          bestSetVolumeDelta: latestBestSetVolume - previousBestSetVolume,
        ),
      );
    }

    summaries.sort((a, b) {
      if (a.isImproved != b.isImproved) {
        return a.isImproved ? -1 : 1;
      }
      return b.volumeDelta.compareTo(a.volumeDelta);
    });
    return summaries;
  }

  Widget _buildExerciseProgressCard(
    List<_ExerciseProgressSummary> progressSummaries,
  ) {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visibleSummaries = progressSummaries.take(6).toList();
    final improvedCount = progressSummaries
        .where((entry) => entry.isImproved)
        .length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.tertiary.withValues(alpha: isDark ? 0.20 : 0.12),
              Colors.transparent,
            ],
          ),
        ),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colorScheme.tertiary.withValues(
                  alpha: isDark ? 0.22 : 0.14,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.emoji_events, color: colorScheme.tertiary),
            ),
            title: const Text(
              'Progressi esercizi',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              progressSummaries.isEmpty
                  ? 'Servono almeno 2 allenamenti dello stesso esercizio.'
                  : '$improvedCount miglioramenti recenti',
            ),
            children: visibleSummaries.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nessun confronto disponibile.'),
                    ),
                  ]
                : visibleSummaries.map((summary) {
                    final icon = summary.isImproved
                        ? Icons.emoji_events
                        : summary.volumeDelta < 0
                        ? Icons.trending_down
                        : Icons.trending_flat;
                    final iconColor = summary.isImproved
                        ? colorScheme.tertiary
                        : colorScheme.onSurfaceVariant;

                    return ListTile(
                      leading: Icon(icon, color: iconColor),
                      title: Text(summary.name),
                      subtitle: Text(
                        'Volume ${_formatHistoryVolume(summary.latestVolume)} kg (${_formatSignedVolume(summary.volumeDelta)})\nTop set ${_formatHistoryVolume(summary.latestBestSetVolume)} kg (${_formatSignedVolume(summary.bestSetVolumeDelta)})',
                      ),
                      trailing: Text(
                        '${summary.latestDate.day}/${summary.latestDate.month}',
                        textAlign: TextAlign.right,
                      ),
                      onTap: () => _showExerciseDetail(summary.name),
                    );
                  }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (history.isEmpty) {
      return _emptyState(
        icon: Icons.history,
        title: 'Ancora nessun allenamento completato.',
        subtitle: 'Quando salvi una sessione, la cronologia appare qui.',
      );
    }

    final sortedHistory = List<WorkoutSession>.from(history)
      ..sort((a, b) => b.endTime.compareTo(a.endTime));
    final progressSummaries = _buildExerciseProgressSummaries();
    final prSummaries = _buildRecentPrSummaries();
    final visibleHistory = _filteredHistorySessions(sortedHistory);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHistoryFilterCard(),
        _buildExerciseProgressCard(progressSummaries),
        _buildPrDashboardCard(prSummaries),
        if (visibleHistory.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Nessuna sessione con questi filtri.')),
          ),
        ...List.generate(visibleHistory.length, (sessionIndex) {
          final session = visibleHistory[sessionIndex];
          final duration = session.endTime.difference(session.startTime);
          final String durationStr = '${duration.inMinutes} min';
          final accent = _accentForIndex(colorScheme, sessionIndex + 1);
          final hasSessionPr = _sessionHasPr(session);

          int completedSets = 0;
          double totalVolume = 0;
          for (final ex in session.exercises) {
            for (final s in ex.sets) {
              if (s.isCompleted) {
                completedSets++;
                if (!s.isWarmup) {
                  totalVolume += s.weight * s.reps;
                }
              }
            }
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: isDark ? 0.18 : 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.fitness_center, color: accent),
                  ),
                  title: Text(
                    session.scheduleTitle,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${session.startTime.day}/${session.startTime.month}/${session.startTime.year} • $durationStr\nVolume: ${totalVolume.toStringAsFixed(1)} kg • Set fatti: $completedSets',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasSessionPr)
                        Icon(Icons.emoji_events, color: colorScheme.tertiary),
                      IconButton(
                        tooltip: 'Modifica allenamento',
                        icon: const Icon(Icons.fitness_center),
                        onPressed: () => _editCompletedWorkout(session),
                      ),
                      IconButton(
                        tooltip: 'Modifica sessione',
                        icon: const Icon(Icons.edit_calendar),
                        onPressed: () => _showHistorySessionDialog(session),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: colorScheme.error),
                        onPressed: () =>
                            _deleteHistory(history.indexOf(session)),
                      ),
                    ],
                  ),
                  children: session.exercises.map((ex) {
                    final hasExercisePr = _exerciseHasPrAtSession(session, ex);
                    final setSummary = ex.sets
                        .where((set) => set.isCompleted)
                        .map(
                          (set) =>
                              '${set.isWarmup ? 'W ' : ''}${set.weight}kg x ${set.reps}${set.rpe != null ? ' RPE ${set.rpe}' : ''}${set.rir != null ? ' RIR ${set.rir}' : ''}',
                        )
                        .join(', ');

                    return ListTile(
                      title: Row(
                        children: [
                          Expanded(child: Text(ex.name)),
                          if (hasExercisePr)
                            Chip(
                              avatar: Icon(
                                Icons.emoji_events,
                                color: colorScheme.tertiary,
                                size: 16,
                              ),
                              label: const Text('PR'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      subtitle: Text(
                        setSummary.isEmpty
                            ? 'Nessun set completato'
                            : setSummary,
                      ),
                      trailing: IconButton(
                        tooltip: 'Modifica storico',
                        icon: const Icon(Icons.edit),
                        onPressed: () =>
                            _showHistoryExerciseDialog(session, ex),
                      ),
                      onTap: () => _showHistoryExerciseDialog(session, ex),
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _showHistoryExerciseDialog(
    WorkoutSession session,
    WorkoutExercise exercise,
  ) async {
    final draft = WorkoutExercise.fromJson(exercise.toJson());
    final currentVolume = _exerciseVolume(exercise);
    final currentBestSetVolume = _bestSetVolume(exercise);
    final previousExercise = _previousExerciseBefore(session, exercise);
    final previousVolume = previousExercise == null
        ? null
        : _exerciseVolume(previousExercise);
    final previousBestSetVolume = previousExercise == null
        ? null
        : _bestSetVolume(previousExercise);
    final volumeDelta = previousVolume == null
        ? null
        : currentVolume - previousVolume;
    final bestSetVolumeDelta = previousBestSetVolume == null
        ? null
        : currentBestSetVolume - previousBestSetVolume;
    final isImproved =
        (volumeDelta != null && volumeDelta > 0) ||
        (bestSetVolumeDelta != null && bestSetVolumeDelta > 0);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              if (isImproved) ...[
                Icon(
                  Icons.emoji_events,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(exercise.name)),
            ],
          ),
          content: AppDialogFrame(
            maxWidth: 560,
            child: SizedBox(
              height: math.min(560.0, MediaQuery.sizeOf(context).height * 0.58),
              child: ListView.separated(
                itemCount: draft.sets.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final set = draft.sets[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Set ${index + 1}${set.isWarmup ? ' warm-up' : ''}',
                        ),
                        subtitle: const Text('Completato'),
                        value: set.isCompleted,
                        onChanged: (value) =>
                            setDialogState(() => set.isCompleted = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Warm-up'),
                        value: set.isWarmup,
                        onChanged: (value) =>
                            setDialogState(() => set.isWarmup = value),
                      ),
                      AppFieldRow(
                        children: [
                          TextFormField(
                            initialValue: set.weight.toString(),
                            decoration: const InputDecoration(labelText: 'Kg'),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (value) {
                              set.weight = parseDecimalInput(value) ?? 0;
                            },
                          ),
                          TextFormField(
                            initialValue: set.reps.toString(),
                            decoration: const InputDecoration(
                              labelText: 'Reps',
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              set.reps = parseIntInput(value) ?? 0;
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ActionChip(
                            label: const Text('-2.5 kg'),
                            onPressed: () => setDialogState(() {
                              set.weight = math.max(0, set.weight - 2.5);
                            }),
                          ),
                          ActionChip(
                            label: const Text('+2.5 kg'),
                            onPressed: () => setDialogState(() {
                              set.weight += 2.5;
                            }),
                          ),
                          ActionChip(
                            label: const Text('-1 rep'),
                            onPressed: () => setDialogState(() {
                              set.reps = math.max(0, set.reps - 1);
                            }),
                          ),
                          ActionChip(
                            label: const Text('+1 rep'),
                            onPressed: () => setDialogState(() {
                              set.reps += 1;
                            }),
                          ),
                          for (final rpe in const [7.0, 8.0, 9.0])
                            ActionChip(
                              label: Text('RPE ${rpe.toStringAsFixed(0)}'),
                              onPressed: () => setDialogState(() {
                                set.rpe = rpe;
                              }),
                            ),
                          ActionChip(
                            label: Text(
                              set.isCompleted ? 'Segna non fatto' : 'Completa',
                            ),
                            onPressed: () => setDialogState(() {
                              set.isCompleted = !set.isCompleted;
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Attuale: ${set.weight.toStringAsFixed(1)} kg x ${set.reps}${set.rpe == null ? '' : ' - RPE ${set.rpe}'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      appDialogFieldGap,
                      AppFieldRow(
                        children: [
                          TextFormField(
                            initialValue: set.rpe?.toString() ?? '',
                            decoration: const InputDecoration(labelText: 'RPE'),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (value) {
                              set.rpe = parseDecimalInput(value);
                            },
                          ),
                          TextFormField(
                            initialValue: set.rir?.toString() ?? '',
                            decoration: const InputDecoration(labelText: 'RIR'),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              set.rir = parseIntInput(value);
                            },
                          ),
                        ],
                      ),
                      appDialogFieldGap,
                      TextFormField(
                        initialValue: set.notes,
                        decoration: const InputDecoration(
                          labelText: 'Note set',
                        ),
                        onChanged: (value) => set.notes = value,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      return;
    }

    setState(() {
      exercise.sets = draft.sets;
    });
    await _saveHistory();
    await _showInfo('Allenamento aggiornato.');
  }

  Future<void> _deleteBodyLog(BodyLog entry) async {
    final index = bodyLogs.indexOf(entry);
    if (index == -1) {
      return;
    }

    setState(() {
      bodyLogs.removeAt(index);
    });
    await _saveBodyLogs();

    _showUndoSnackBar(
      message: 'Misura eliminata.',
      onUndo: () {
        if (!mounted || bodyLogs.contains(entry)) {
          return;
        }
        setState(() {
          bodyLogs.insert(
            index > bodyLogs.length ? bodyLogs.length : index,
            entry,
          );
        });
        _saveBodyLogs();
      },
    );
  }

  Future<void> _showBodyLogDialog({BodyLog? entry}) async {
    final bodyWeightController = TextEditingController(
      text: entry?.bodyWeight?.toString() ?? '',
    );
    final waistController = TextEditingController(
      text: entry?.waist?.toString() ?? '',
    );
    final chestController = TextEditingController(
      text: entry?.chest?.toString() ?? '',
    );
    final armController = TextEditingController(
      text: entry?.arm?.toString() ?? '',
    );
    final thighController = TextEditingController(
      text: entry?.thigh?.toString() ?? '',
    );
    final sleepController = TextEditingController(
      text: entry?.sleepHours?.toString() ?? '',
    );
    final readinessController = TextEditingController(
      text: entry?.readiness?.toString() ?? '',
    );
    final notesController = TextEditingController(text: entry?.notes ?? '');
    String? photoPath = entry?.photoPath;
    String? photoName = entry?.photoName;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(entry == null ? 'Nuova misura corpo' : 'Modifica misura'),
          content: AppDialogContent(
            maxWidth: 560,
            children: [
              TextField(
                controller: bodyWeightController,
                decoration: const InputDecoration(labelText: 'Peso corpo (kg)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              appDialogFieldGap,
              AppFieldRow(
                children: [
                  TextField(
                    controller: waistController,
                    decoration: const InputDecoration(labelText: 'Vita cm'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  TextField(
                    controller: chestController,
                    decoration: const InputDecoration(labelText: 'Torace cm'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ),
              appDialogFieldGap,
              AppFieldRow(
                children: [
                  TextField(
                    controller: armController,
                    decoration: const InputDecoration(labelText: 'Braccio cm'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  TextField(
                    controller: thighController,
                    decoration: const InputDecoration(labelText: 'Coscia cm'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ),
              appDialogFieldGap,
              AppFieldRow(
                children: [
                  TextField(
                    controller: sleepController,
                    decoration: const InputDecoration(labelText: 'Sonno ore'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: readinessController,
                    decoration: const InputDecoration(
                      labelText: 'Readiness 1-10',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              appDialogFieldGap,
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Note recupero/dolori',
                ),
                minLines: 1,
                maxLines: 3,
              ),
              appDialogFieldGap,
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_camera),
                title: Text(photoName ?? 'Nessuna foto progresso'),
                subtitle: Text(photoPath ?? 'Aggiungi path immagine locale'),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Scegli foto',
                      icon: const Icon(Icons.add_photo_alternate),
                      onPressed: () async {
                        final result = await FilePicker.pickFiles(
                          type: FileType.image,
                          withData: false,
                        );
                        final picked = result?.files.single;
                        if (picked == null) return;
                        setDialogState(() {
                          photoPath = picked.path;
                          photoName = picked.name;
                        });
                      },
                    ),
                    IconButton(
                      tooltip: 'Rimuovi foto',
                      icon: const Icon(Icons.close),
                      onPressed: photoPath == null && photoName == null
                          ? null
                          : () => setDialogState(() {
                              photoPath = null;
                              photoName = null;
                            }),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      return;
    }

    final updated = entry ?? BodyLog(date: DateTime.now());
    updated.bodyWeight = parseDecimalInput(bodyWeightController.text);
    updated.waist = parseDecimalInput(waistController.text);
    updated.chest = parseDecimalInput(chestController.text);
    updated.arm = parseDecimalInput(armController.text);
    updated.thigh = parseDecimalInput(thighController.text);
    updated.sleepHours = parseIntInput(sleepController.text);
    updated.readiness = parseIntInput(
      readinessController.text,
    )?.clamp(1, 10).toInt();
    updated.notes = notesController.text.trim();
    updated.photoPath = photoPath;
    updated.photoName = photoName;

    setState(() {
      if (entry == null) {
        bodyLogs.add(updated);
      }
      bodyLogs.sort((a, b) => b.date.compareTo(a.date));
    });
    await _saveBodyLogs();
  }

  Widget _buildBodyTab() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (bodyLogs.isEmpty) {
      return _emptyState(
        icon: Icons.monitor_weight,
        title: 'Ancora nessuna misura corpo.',
        subtitle: 'Traccia peso, sonno, readiness e note recupero.',
        action: FilledButton.icon(
          onPressed: () => _showBodyLogDialog(),
          icon: const Icon(Icons.add),
          label: const Text('Aggiungi misura'),
        ),
      );
    }

    final latest = bodyLogs.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.secondary.withValues(alpha: isDark ? 0.20 : 0.12),
                  Colors.transparent,
                ],
              ),
            ),
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.secondary.withValues(
                    alpha: isDark ? 0.22 : 0.14,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.monitor_weight, color: colorScheme.secondary),
              ),
              title: const Text(
                'Ultima misura',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                '${latest.bodyWeight?.toStringAsFixed(1) ?? '-'} kg • Readiness ${latest.readiness ?? '-'} • Sonno ${latest.sleepHours ?? '-'}h${latest.photoName == null ? '' : ' • Foto'}',
              ),
              trailing: FilledButton.icon(
                onPressed: () => _showBodyLogDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Nuova'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...bodyLogs.map((entry) {
          final accent = _accentForIndex(colorScheme, bodyLogs.indexOf(entry));
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: accent.withValues(
                    alpha: isDark ? 0.22 : 0.14,
                  ),
                  foregroundColor: accent,
                  child: Text(
                    '${entry.date.day}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                title: Text(
                  '${entry.date.day}/${entry.date.month}/${entry.date.year}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  'Peso ${entry.bodyWeight?.toStringAsFixed(1) ?? '-'} kg • Vita ${entry.waist?.toStringAsFixed(1) ?? '-'} cm • Readiness ${entry.readiness ?? '-'}${entry.photoName == null ? '' : '\nFoto: ${entry.photoName}'}${entry.notes.trim().isNotEmpty ? '\n${entry.notes}' : ''}',
                ),
                onTap: () => _showBodyLogDialog(entry: entry),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  color: colorScheme.error,
                  onPressed: () => _deleteBodyLog(entry),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final title = switch (_currentIndex) {
      1 => 'Calendario',
      2 => 'Cronologia',
      3 => 'Statistiche',
      4 => 'Corpo',
      _ => 'Gym',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Ricerca globale',
            icon: const Icon(Icons.search),
            onPressed: _showGlobalSearch,
          ),
          IconButton(
            tooltip: 'Strumenti',
            icon: const Icon(Icons.calculate),
            onPressed: _showToolsSheet,
          ),
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
          PopupMenuButton<_HomeAction>(
            tooltip: 'Dati',
            onSelected: (action) {
              switch (action) {
                case _HomeAction.importCsv:
                  _importCsv();
                  break;
                case _HomeAction.exportCsv:
                  _exportSchedulesCsv();
                  break;
                case _HomeAction.exportHistoryCsv:
                  _exportHistoryCsv();
                  break;
                case _HomeAction.exportBodyCsv:
                  _exportBodyCsv();
                  break;
                case _HomeAction.exportAllJson:
                  _exportBackupJson();
                  break;
                case _HomeAction.restoreBackup:
                  _restoreBackupJson();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _HomeAction.importCsv,
                child: ListTile(
                  leading: Icon(Icons.file_upload),
                  title: Text('Importa CSV'),
                ),
              ),
              PopupMenuItem(
                value: _HomeAction.exportCsv,
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('Esporta schede CSV'),
                ),
              ),
              PopupMenuItem(
                value: _HomeAction.exportHistoryCsv,
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Esporta cronologia CSV'),
                ),
              ),
              PopupMenuItem(
                value: _HomeAction.exportBodyCsv,
                child: ListTile(
                  leading: Icon(Icons.monitor_weight),
                  title: Text('Esporta corpo CSV'),
                ),
              ),
              PopupMenuItem(
                value: _HomeAction.exportAllJson,
                child: ListTile(
                  leading: Icon(Icons.inventory_2),
                  title: Text('Esporta tutto (JSON)'),
                ),
              ),
              PopupMenuItem(
                value: _HomeAction.restoreBackup,
                child: ListTile(
                  leading: Icon(Icons.restore),
                  title: Text('Ripristina backup'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: switch (_currentIndex) {
            0 => _buildSchedulesTab(),
            1 => _buildCalendarTab(),
            2 => _buildHistoryTab(),
            3 => StatsScreen(history: history),
            _ => _buildBodyTab(),
          },
        ),
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _showAddScheduleDialog,
              child: const Icon(Icons.add),
            )
          : _currentIndex == 4
          ? FloatingActionButton(
              onPressed: () => _showBodyLogDialog(),
              child: const Icon(Icons.monitor_weight),
            )
          : null,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                currentIndex: _currentIndex,
                onTap: (index) => setState(() => _currentIndex = index),
                backgroundColor: theme.bottomNavigationBarTheme.backgroundColor,
                selectedItemColor: colorScheme.primary,
                showSelectedLabels: false,
                showUnselectedLabels: false,
                unselectedItemColor: colorScheme.onSurfaceVariant,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.list_alt),
                    label: 'Schede',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.calendar_month),
                    label: 'Calendario',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.history),
                    label: 'Cronologia',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.bar_chart),
                    label: 'Statistiche',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.monitor_weight),
                    label: 'Corpo',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseOccurrence {
  final WorkoutSession session;
  final WorkoutExercise exercise;

  const _ExerciseOccurrence({required this.session, required this.exercise});
}

class _ExerciseProgressSummary {
  final String name;
  final DateTime latestDate;
  final double latestVolume;
  final double previousVolume;
  final double volumeDelta;
  final double latestBestSetVolume;
  final double previousBestSetVolume;
  final double bestSetVolumeDelta;

  const _ExerciseProgressSummary({
    required this.name,
    required this.latestDate,
    required this.latestVolume,
    required this.previousVolume,
    required this.volumeDelta,
    required this.latestBestSetVolume,
    required this.previousBestSetVolume,
    required this.bestSetVolumeDelta,
  });

  bool get isImproved => volumeDelta > 0 || bestSetVolumeDelta > 0;
}

class _PrSummary {
  final String exerciseName;
  final String scheduleTitle;
  final DateTime date;

  const _PrSummary({
    required this.exerciseName,
    required this.scheduleTitle,
    required this.date,
  });
}

class _BackupMergeResult {
  final List<Schedule> schedules;
  final List<WorkoutSession> history;
  final List<BodyLog> bodyLogs;
  final WorkoutSession? currentSession;
  final int addedSchedules;
  final int mergedSchedules;
  final int addedExercises;
  final int skippedExercises;
  final int addedHistory;
  final int skippedHistory;
  final int addedBodyLogs;
  final int skippedBodyLogs;

  const _BackupMergeResult({
    required this.schedules,
    required this.history,
    required this.bodyLogs,
    required this.currentSession,
    required this.addedSchedules,
    required this.mergedSchedules,
    required this.addedExercises,
    required this.skippedExercises,
    required this.addedHistory,
    required this.skippedHistory,
    required this.addedBodyLogs,
    required this.skippedBodyLogs,
  });
}
