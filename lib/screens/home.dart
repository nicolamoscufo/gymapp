import 'dart:convert';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_data_store.dart';
import '../app_preferences.dart';
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

enum _HomeAction {
  templates,
  importCsv,
  exportCsv,
  exportHistoryCsv,
  exportBodyCsv,
  exportBackup,
  restoreBackup,
}

enum _ScheduleMenuAction { toggleArchive, delete }

enum _HistoryRangeFilter { all, last30, last90 }

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
  WorkoutSession? _savedSession;

  int _currentIndex = 0;
  String _searchQuery = '';
  String _historyQuery = '';
  int? _selectedWeekFilter;
  _HistoryRangeFilter _historyRangeFilter = _HistoryRangeFilter.all;
  bool _historyOnlyPr = false;
  bool _showArchived = false;
  final int _defaultRestSeconds = AppPreferences.defaultRestSeconds;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final bundle = await AppDataStore.loadBundle();

    if (!mounted) {
      return;
    }

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
      _sortSchedules();
    });

    if (bundle.recoveredFromCorruption) {
      _showInfo('Alcuni dati corrotti sono stati ignorati per evitare crash.');
    }
  }

  Future<void> _saveSchedules() async {
    await AppDataStore.saveSchedules(schedules);
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

  Exercise _templateExercise(
    String name,
    MuscleGroup group, {
    int sets = 3,
    int reps = 10,
    int? minReps,
    int? maxReps,
  }) {
    return Exercise(
      name: name,
      set: sets,
      reps: reps,
      weight: 0,
      muscleGroup: group,
      targetMinReps: minReps,
      targetMaxReps: maxReps,
      notes: '',
      technique: IntensityTechnique.none,
      restSeconds: _defaultRestSeconds,
    );
  }

  void _addTemplateSchedules(String templateName) {
    final now = DateTime.now();
    final templates = switch (templateName) {
      'PPL' => [
        Schedule(
          title: 'Push',
          week: 1,
          createdAt: now,
          goal: 'Spinta: petto, spalle, tricipiti',
          trainingWeekdays: const [DateTime.monday],
          exercises: [
            _templateExercise(
              'Panca piana',
              MuscleGroup.chest,
              sets: 4,
              reps: 8,
              minReps: 6,
              maxReps: 8,
            ),
            _templateExercise(
              'Military press',
              MuscleGroup.shoulders,
              sets: 3,
              reps: 8,
              minReps: 6,
              maxReps: 10,
            ),
            _templateExercise(
              'Dip / Pushdown',
              MuscleGroup.triceps,
              reps: 12,
              minReps: 10,
              maxReps: 15,
            ),
          ],
        ),
        Schedule(
          title: 'Pull',
          week: 1,
          createdAt: now,
          goal: 'Trazioni: dorso, bicipiti',
          trainingWeekdays: const [DateTime.wednesday],
          exercises: [
            _templateExercise(
              'Lat machine',
              MuscleGroup.back,
              sets: 4,
              reps: 10,
              minReps: 8,
              maxReps: 12,
            ),
            _templateExercise(
              'Rematore',
              MuscleGroup.back,
              sets: 3,
              reps: 10,
              minReps: 8,
              maxReps: 12,
            ),
            _templateExercise(
              'Curl bilanciere',
              MuscleGroup.biceps,
              reps: 10,
              minReps: 8,
              maxReps: 12,
            ),
          ],
        ),
        Schedule(
          title: 'Legs',
          week: 1,
          createdAt: now,
          goal: 'Gambe complete',
          trainingWeekdays: const [DateTime.friday],
          exercises: [
            _templateExercise(
              'Squat',
              MuscleGroup.quadriceps,
              sets: 4,
              reps: 6,
              minReps: 5,
              maxReps: 8,
            ),
            _templateExercise(
              'Romanian deadlift',
              MuscleGroup.hamstrings,
              sets: 3,
              reps: 8,
              minReps: 6,
              maxReps: 10,
            ),
            _templateExercise(
              'Calf raise',
              MuscleGroup.calves,
              reps: 12,
              minReps: 10,
              maxReps: 15,
            ),
          ],
        ),
      ],
      'Upper/Lower' => [
        Schedule(
          title: 'Upper',
          week: 1,
          createdAt: now,
          goal: 'Parte alta completa',
          trainingWeekdays: const [DateTime.monday, DateTime.thursday],
          exercises: [
            _templateExercise(
              'Panca piana',
              MuscleGroup.chest,
              sets: 4,
              reps: 8,
              minReps: 6,
              maxReps: 8,
            ),
            _templateExercise(
              'Lat machine',
              MuscleGroup.back,
              sets: 4,
              reps: 10,
              minReps: 8,
              maxReps: 12,
            ),
            _templateExercise(
              'Alzate laterali',
              MuscleGroup.shoulders,
              reps: 12,
              minReps: 10,
              maxReps: 15,
            ),
          ],
        ),
        Schedule(
          title: 'Lower',
          week: 1,
          createdAt: now,
          goal: 'Parte bassa completa',
          trainingWeekdays: const [DateTime.tuesday, DateTime.friday],
          exercises: [
            _templateExercise(
              'Squat',
              MuscleGroup.quadriceps,
              sets: 4,
              reps: 6,
              minReps: 5,
              maxReps: 8,
            ),
            _templateExercise(
              'Leg curl',
              MuscleGroup.hamstrings,
              reps: 10,
              minReps: 8,
              maxReps: 12,
            ),
            _templateExercise(
              'Addome',
              MuscleGroup.abs,
              reps: 15,
              minReps: 12,
              maxReps: 20,
            ),
          ],
        ),
      ],
      'Full body' => [
        Schedule(
          title: 'Full body',
          week: 1,
          createdAt: now,
          goal: 'Tutto il corpo 3 volte a settimana',
          trainingWeekdays: const [
            DateTime.monday,
            DateTime.wednesday,
            DateTime.friday,
          ],
          exercises: [
            _templateExercise(
              'Squat',
              MuscleGroup.quadriceps,
              sets: 3,
              reps: 8,
              minReps: 6,
              maxReps: 10,
            ),
            _templateExercise(
              'Panca piana',
              MuscleGroup.chest,
              sets: 3,
              reps: 8,
              minReps: 6,
              maxReps: 10,
            ),
            _templateExercise(
              'Rematore',
              MuscleGroup.back,
              sets: 3,
              reps: 10,
              minReps: 8,
              maxReps: 12,
            ),
          ],
        ),
      ],
      _ => [
        Schedule(
          title: 'Forza',
          week: 1,
          createdAt: now,
          goal: 'Progressione carichi base',
          trainingWeekdays: const [DateTime.monday, DateTime.thursday],
          exercises: [
            _templateExercise(
              'Squat',
              MuscleGroup.quadriceps,
              sets: 5,
              reps: 5,
              minReps: 5,
              maxReps: 5,
            ),
            _templateExercise(
              'Panca piana',
              MuscleGroup.chest,
              sets: 5,
              reps: 5,
              minReps: 5,
              maxReps: 5,
            ),
            _templateExercise(
              'Stacco',
              MuscleGroup.back,
              sets: 3,
              reps: 5,
              minReps: 3,
              maxReps: 5,
            ),
          ],
        ),
        Schedule(
          title: 'Ipertrofia',
          week: 1,
          createdAt: now,
          goal: 'Volume controllato e pump',
          trainingWeekdays: const [DateTime.tuesday, DateTime.friday],
          exercises: [
            _templateExercise(
              'Leg press',
              MuscleGroup.quadriceps,
              sets: 4,
              reps: 10,
              minReps: 8,
              maxReps: 12,
            ),
            _templateExercise(
              'Chest press',
              MuscleGroup.chest,
              sets: 4,
              reps: 10,
              minReps: 8,
              maxReps: 12,
            ),
            _templateExercise(
              'Pulley',
              MuscleGroup.back,
              sets: 4,
              reps: 12,
              minReps: 10,
              maxReps: 15,
            ),
          ],
        ),
      ],
    };

    setState(() {
      schedules.addAll(templates);
      _sortSchedules();
    });
    _saveSchedules();
  }

  Future<void> _showTemplatePicker() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Template schede'),
        children: [
          for (final template in const [
            'PPL',
            'Upper/Lower',
            'Full body',
            'Forza + Ipertrofia',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, template),
              child: Text(template),
            ),
        ],
      ),
    );

    if (selected == null || !mounted) {
      return;
    }
    _addTemplateSchedules(selected);
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
            content: SizedBox(
              width: double.maxFinite,
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
                  const SizedBox(height: 12),
                  Flexible(
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
                              Navigator.push(
                                this.context,
                                MaterialPageRoute(
                                  builder: (context) => ScheduleDetailScreen(
                                    schedule: schedule,
                                    history: history,
                                    defaultRestSeconds: _defaultRestSeconds,
                                    onUpdate: () {
                                      setState(() {});
                                      _saveSchedules();
                                    },
                                  ),
                                ),
                              ).then((_) => _loadData());
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
    final targetWeightController = TextEditingController(text: '100');
    final barWeightController = TextEditingController(text: '20');
    final warmupWeightController = TextEditingController(text: '100');
    final warmupRepsController = TextEditingController(text: '8');
    final topSetWeightController = TextEditingController(text: '100');
    final backoffReductionController = TextEditingController(
      text: defaultBackoffReductionPercent.toStringAsFixed(0),
    );
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final targetWeight =
              parseDecimalInput(targetWeightController.text) ?? 0;
          final barWeight = parseDecimalInput(barWeightController.text) ?? 20;
          final perSide = ((targetWeight - barWeight) / 2)
              .clamp(0, 999)
              .toDouble();
          var remaining = perSide;
          final plates = <String>[];
          for (final plate in const [25, 20, 15, 10, 5, 2.5, 1.25]) {
            final count = remaining ~/ plate;
            if (count > 0) {
              plates.add('${count}x ${plate}kg');
              remaining -= count * plate;
            }
          }

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
                          'Plate calculator',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: targetWeightController,
                                decoration: const InputDecoration(
                                  labelText: 'Totale kg',
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setSheetState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: barWeightController,
                                decoration: const InputDecoration(
                                  labelText: 'Bilanciere kg',
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setSheetState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Per lato: ${plates.isEmpty ? 'nessun disco' : plates.join(' + ')}',
                        ),
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
                          'Warm-up calculator',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
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
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: warmupRepsController,
                                decoration: const InputDecoration(
                                  labelText: 'Reps lavoro',
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setSheetState(() {}),
                              ),
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
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
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
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
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
          exercise.restSeconds == candidate.restSeconds &&
          exercise.muscleGroup == candidate.muscleGroup &&
          exercise.equipment == candidate.equipment &&
          exercise.movementPattern == candidate.movementPattern &&
          exercise.targetMinReps == candidate.targetMinReps &&
          exercise.targetMaxReps == candidate.targetMaxReps &&
          exercise.technique == candidate.technique &&
          exercise.weight == candidate.weight &&
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
        'restSeconds',
        'notes',
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
          exercise.restSeconds,
          exercise.notes,
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

  Map<String, dynamic> _buildBackupPayload() {
    return {
      'version': 3,
      'exportedAt': DateTime.now().toIso8601String(),
      'schedules': schedules.map((schedule) => schedule.toJson()).toList(),
      'history': history.map((session) => session.toJson()).toList(),
      'bodyLogs': bodyLogs.map((entry) => entry.toJson()).toList(),
      'currentSession': _savedSession?.toJson(),
    };
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

      int importedCount = 0;
      int skippedInvalidCount = 0;
      int skippedDuplicateCount = 0;

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
        final notes = hasFullSchema
            ? row[19].toString().trim()
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
        final restSeconds = hasFullSchema
            ? parseIntInput(row[18].toString())
            : null;

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
          restSeconds: restSeconds,
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
        dialogTitle: 'Esporta CSV',
        fileName: 'gymapp_schede.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(csvText)),
      );

      if (savedPath == null && !kIsWeb) {
        return;
      }

      await _showInfo('CSV esportato con successo.');
    } catch (e) {
      await _showInfo('Errore durante export CSV: $e');
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
      final backupText = jsonEncode(_buildBackupPayload());
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Esporta backup',
        fileName: 'gymapp_backup.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(backupText)),
      );

      if (savedPath == null && !kIsWeb) {
        return;
      }

      await _showInfo('Backup esportato con successo.');
    } catch (e) {
      await _showInfo('Errore durante export backup: $e');
    }
  }

  Future<void> _restoreBackupJson() async {
    try {
      final confirm =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Ripristinare backup?'),
              content: const Text(
                'Questo sovrascriverà le schede e la cronologia attuali.',
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

      List<Schedule> restoredSchedules = [];
      List<WorkoutSession> restoredHistory = [];
      List<BodyLog> restoredBodyLogs = [];
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

      final previewConfirm =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Confermare ripristino'),
              content: Text(
                'Trovate ${restoredSchedules.length} schede, ${restoredHistory.length} allenamenti, ${restoredBodyLogs.length} misure corpo.',
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

      if (!previewConfirm || !mounted) {
        return;
      }

      setState(() {
        schedules
          ..clear()
          ..addAll(restoredSchedules);
        history
          ..clear()
          ..addAll(restoredHistory);
        bodyLogs
          ..clear()
          ..addAll(restoredBodyLogs);
        _savedSession = restoredCurrentSession;
        _sortSchedules();
      });

      await _saveAllData();
      if (restoredCurrentSession == null) {
        await AppDataStore.clearCurrentSession();
      } else {
        await AppDataStore.saveCurrentSession(restoredCurrentSession);
      }
      _showUndoSnackBar(
        message: 'Backup ripristinato.',
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
        },
      );
    } catch (e) {
      await _showInfo('Errore durante ripristino backup: $e');
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
            restSeconds: exercise.restSeconds,
            supersetGroup: exercise.supersetGroup,
            progressionKgStep: exercise.progressionKgStep,
            progressionRepStep: exercise.progressionRepStep,
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
        ),
      );
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
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Titolo'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: goalController,
                  decoration: const InputDecoration(labelText: 'Obiettivo'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: mesocycleController,
                        decoration: const InputDecoration(
                          labelText: 'Settimane',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: deloadController,
                        decoration: const InputDecoration(
                          labelText: 'Deload ogni',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                const Text('La settimana avanza ogni lunedi.'),
              ],
            ),
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

  Widget _buildSchedulesTab() {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visibleSchedules = _filteredSchedules();
    final availableWeeks = _availableWeeks();
    final selectedWeekValue = availableWeeks.contains(_selectedWeekFilter)
        ? _selectedWeekFilter
        : null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Cerca',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _searchQuery = ''),
                    ),
            ),
          ),
        ),
        if (_savedSession != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                title: Text(
                  'Riprendi allenamento: ${_savedSession!.scheduleTitle}',
                ),
                subtitle: Text(
                  'Iniziato ${_savedSession!.startTime.day}/${_savedSession!.startTime.month}/${_savedSession!.startTime.year}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: () async {
                        final session = _savedSession!;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ActiveWorkoutScreen.resume(
                              resumedSession: session,
                              history: history,
                              defaultRestSeconds: _defaultRestSeconds,
                            ),
                          ),
                        );
                        _loadData();
                      },
                      child: const Text('Riprendi'),
                    ),
                    const SizedBox(width: 8),
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
        Expanded(
          child: visibleSchedules.isEmpty
              ? _emptyState(
                  icon: Icons.list_alt,
                  title: 'Nessuna scheda visibile',
                  subtitle: 'Crea una scheda o modifica i filtri attivi.',
                  action: schedules.isEmpty
                      ? FilledButton.icon(
                          onPressed: _showTemplatePicker,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Scegli template'),
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
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'W',
                                    style: theme.textTheme.labelSmall?.copyWith(
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
                            title: Text(
                              schedule.title,
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
                                '${schedule.exercises.length} esercizi${schedule.isDeloadWeek() ? ' • deload' : ''}${schedule.goal.trim().isNotEmpty ? '\n${schedule.goal}' : ''}${schedule.isArchived ? ' • archiviata' : ''}',
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Duplica',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () => _duplicateSchedule(schedule),
                                ),
                                PopupMenuButton<_ScheduleMenuAction>(
                                  tooltip: 'Azioni',
                                  onSelected: (action) {
                                    switch (action) {
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
                                    PopupMenuItem(
                                      value: _ScheduleMenuAction.toggleArchive,
                                      child: Text(
                                        schedule.isArchived
                                            ? 'Ripristina'
                                            : 'Archivia',
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: _ScheduleMenuAction.delete,
                                      child: Text('Elimina'),
                                    ),
                                  ],
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ScheduleDetailScreen(
                                    schedule: schedule,
                                    history: history,
                                    defaultRestSeconds: _defaultRestSeconds,
                                    onUpdate: () {
                                      setState(() {});
                                      _saveSchedules();
                                    },
                                  ),
                                ),
                              );
                              _loadData();
                            },
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Titolo'),
            ),
            const SizedBox(height: 8),
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
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
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
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: set.weight.toString(),
                            decoration: const InputDecoration(labelText: 'Kg'),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (value) {
                              set.weight = parseDecimalInput(value) ?? 0;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: set.reps.toString(),
                            decoration: const InputDecoration(
                              labelText: 'Reps',
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              set.reps = parseIntInput(value) ?? 0;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: set.rpe?.toString() ?? '',
                            decoration: const InputDecoration(labelText: 'RPE'),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (value) {
                              set.rpe = parseDecimalInput(value);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: set.rir?.toString() ?? '',
                            decoration: const InputDecoration(labelText: 'RIR'),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              set.rir = parseIntInput(value);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: set.notes,
                      decoration: const InputDecoration(labelText: 'Note set'),
                      onChanged: (value) => set.notes = value,
                    ),
                  ],
                );
              },
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

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry == null ? 'Nuova misura corpo' : 'Modifica misura'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bodyWeightController,
                decoration: const InputDecoration(labelText: 'Peso corpo (kg)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: waistController,
                      decoration: const InputDecoration(labelText: 'Vita cm'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: chestController,
                      decoration: const InputDecoration(labelText: 'Torace cm'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: armController,
                      decoration: const InputDecoration(
                        labelText: 'Braccio cm',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: thighController,
                      decoration: const InputDecoration(labelText: 'Coscia cm'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: sleepController,
                      decoration: const InputDecoration(labelText: 'Sonno ore'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: readinessController,
                      decoration: const InputDecoration(
                        labelText: 'Readiness 1-10',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Note recupero/dolori',
                ),
                minLines: 1,
                maxLines: 3,
              ),
            ],
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
                '${latest.bodyWeight?.toStringAsFixed(1) ?? '-'} kg • Readiness ${latest.readiness ?? '-'} • Sonno ${latest.sleepHours ?? '-'}h',
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
                  'Peso ${entry.bodyWeight?.toStringAsFixed(1) ?? '-'} kg • Vita ${entry.waist?.toStringAsFixed(1) ?? '-'} cm • Readiness ${entry.readiness ?? '-'}${entry.notes.trim().isNotEmpty ? '\n${entry.notes}' : ''}',
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gym'),
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
                case _HomeAction.templates:
                  _showTemplatePicker();
                  break;
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
                case _HomeAction.exportBackup:
                  _exportBackupJson();
                  break;
                case _HomeAction.restoreBackup:
                  _restoreBackupJson();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _HomeAction.templates,
                child: ListTile(
                  leading: Icon(Icons.auto_awesome),
                  title: Text('Template schede'),
                ),
              ),
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
                  title: Text('Esporta CSV'),
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
                value: _HomeAction.exportBackup,
                child: ListTile(
                  leading: Icon(Icons.backup),
                  title: Text('Esporta backup'),
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
          child: _currentIndex == 0
              ? _buildSchedulesTab()
              : _currentIndex == 1
              ? _buildHistoryTab()
              : _currentIndex == 2
              ? StatsScreen(history: history)
              : _buildBodyTab(),
        ),
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _showAddScheduleDialog,
              child: const Icon(Icons.add),
            )
          : _currentIndex == 3
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
                unselectedItemColor: colorScheme.onSurfaceVariant,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.list_alt),
                    label: 'Schede',
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
