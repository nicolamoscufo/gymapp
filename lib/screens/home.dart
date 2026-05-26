import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_data_store.dart';
import '../app_preferences.dart';
import '../models/body_log.dart';
import '../models/exercise.dart';
import '../models/schedule.dart';
import '../models/workout.dart';
import '../number_input.dart';
import 'schedule_detail.dart';
import 'settings.dart';
import 'stats.dart';
import 'active_workout.dart';

enum _HomeAction {
  importCsv,
  exportCsv,
  exportHistoryCsv,
  exportBodyCsv,
  exportBackup,
  restoreBackup,
}

enum _ScheduleMenuAction { toggleArchive, delete }

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
  int? _selectedWeekFilter;
  bool _showArchived = false;
  int _defaultRestSeconds = AppPreferences.defaultRestSeconds;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadSettings();
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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }

    setState(() {
      _defaultRestSeconds =
          prefs.getInt(AppPreferences.defaultRestSecondsKey) ??
          AppPreferences.defaultRestSeconds;
    });
  }

  Future<void> _setDefaultRestSeconds(int seconds) async {
    final normalizedSeconds = seconds.clamp(
      AppPreferences.minRestSeconds,
      AppPreferences.maxRestSeconds,
    );

    setState(() {
      _defaultRestSeconds = normalizedSeconds;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppPreferences.defaultRestSecondsKey, normalizedSeconds);
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
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'schedules': schedules.map((schedule) => schedule.toJson()).toList(),
      'history': history.map((session) => session.toJson()).toList(),
      'bodyLogs': bodyLogs.map((entry) => entry.toJson()).toList(),
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

      List<Schedule> restoredSchedules = [];
      List<WorkoutSession> restoredHistory = [];
      List<BodyLog> restoredBodyLogs = [];

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
        _sortSchedules();
      });

      await _saveAllData();
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
            _sortSchedules();
          });
          _saveAllData();
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuova Scheda'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Titolo (es. Push Day)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: goalController,
              decoration: const InputDecoration(
                labelText: 'Obiettivo (ipertrofia, forza, deload...)',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: mesocycleController,
                    decoration: const InputDecoration(
                      labelText: 'Settimane mesociclo',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: deloadController,
                    decoration: const InputDecoration(labelText: 'Deload ogni'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.calendar_today),
              title: Text('Settimana automatica'),
              subtitle: Text(
                'La scheda parte da settimana 1 e avanza ogni lunedì.',
              ),
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
              if (titleController.text.isNotEmpty) {
                _addSchedule(
                  titleController.text,
                  goal: goalController.text.trim(),
                  mesocycleWeeks: parseIntInput(mesocycleController.text) ?? 8,
                  deloadEveryWeeks: parseIntInput(deloadController.text) ?? 4,
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Aggiungi'),
          ),
        ],
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
          defaultRestSeconds: _defaultRestSeconds,
          onDefaultRestSecondsChanged: _setDefaultRestSeconds,
          onExportBackup: _exportBackupJson,
          onRestoreBackup: _restoreBackupJson,
        ),
      ),
    );
  }

  Widget _buildSchedulesTab() {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleSchedules = _filteredSchedules();
    final availableWeeks = _availableWeeks();
    final selectedWeekValue = availableWeeks.contains(_selectedWeekFilter)
        ? _selectedWeekFilter
        : null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              labelText: 'Cerca schede o esercizi',
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
                    ElevatedButton(
                      onPressed: () async {
                        final session = _savedSession!;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ActiveWorkoutScreen.resume(
                              resumedSession: session,
                              defaultRestSeconds: _defaultRestSeconds,
                            ),
                          ),
                        );
                        _loadData();
                      },
                      child: const Text('RIPRENDI'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _discardSavedSession,
                      child: const Text('SCARTA'),
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
                  decoration: const InputDecoration(labelText: 'Settimana'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Tutte'),
                    ),
                    ...availableWeeks.map(
                      (week) => DropdownMenuItem<int?>(
                        value: week,
                        child: Text('Settimana $week'),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedWeekFilter = value),
                ),
              ),
              FilterChip(
                label: const Text('Mostra archiviate'),
                selected: _showArchived,
                onSelected: (selected) =>
                    setState(() => _showArchived = selected),
              ),
              if (_searchQuery.isNotEmpty ||
                  _selectedWeekFilter != null ||
                  _showArchived)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                      _selectedWeekFilter = null;
                      _showArchived = false;
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset filtri'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${visibleSchedules.length} schede visibili',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: visibleSchedules.isEmpty
              ? const Center(
                  child: Text('Nessuna scheda corrisponde ai filtri scelti.'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: visibleSchedules.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final schedule = visibleSchedules[index];
                    final currentWeek = schedule.currentWeek();
                    final actualIndex = schedules.indexOf(schedule);

                    return Dismissible(
                      key: ValueKey(schedule.id),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) {
                        if (actualIndex != -1) {
                          _deleteSchedule(actualIndex);
                        }
                      },
                      background: Container(
                        color: colorScheme.error,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: Icon(Icons.delete, color: colorScheme.onError),
                      ),
                      child: Card(
                        elevation: 2,
                        color: schedule.isArchived
                            ? colorScheme.surfaceContainerHighest
                            : null,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: schedule.isArchived
                                ? colorScheme.surfaceContainer
                                : colorScheme.primaryContainer,
                            child: Icon(
                              schedule.isArchived
                                  ? Icons.archive
                                  : Icons.fitness_center,
                              color: schedule.isArchived
                                  ? colorScheme.onSurfaceVariant
                                  : colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            schedule.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: schedule.isArchived
                                  ? colorScheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            'Settimana: $currentWeek (auto)${schedule.isDeloadWeek() ? ' • DELOAD' : ''} • Esercizi: ${schedule.exercises.length}${schedule.goal.trim().isNotEmpty ? '\nObiettivo: ${schedule.goal}' : ''}${schedule.isArchived ? ' • Archiviata' : ''}',
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
                              const Icon(Icons.arrow_forward_ios),
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
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    final colorScheme = Theme.of(context).colorScheme;

    if (history.isEmpty) {
      return const Center(child: Text('Ancora nessun allenamento completato.'));
    }

    final sortedHistory = List<WorkoutSession>.from(history)
      ..sort((a, b) => b.endTime.compareTo(a.endTime));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedHistory.length,
      itemBuilder: (context, index) {
        final session = sortedHistory[index];
        final duration = session.endTime.difference(session.startTime);
        final String durationStr = '${duration.inMinutes} min';

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
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text(
              session.scheduleTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${session.startTime.day}/${session.startTime.month}/${session.startTime.year} • $durationStr\nVolume: ${totalVolume.toStringAsFixed(1)} kg • Set fatti: $completedSets',
            ),
            trailing: IconButton(
              icon: Icon(Icons.delete, color: colorScheme.error),
              onPressed: () => _deleteHistory(history.indexOf(session)),
            ),
            children: session.exercises.map((ex) {
              return ListTile(
                title: Text(ex.name),
                subtitle: Text(
                  ex.sets
                      .where((s) => s.isCompleted)
                      .map(
                        (s) =>
                            '${s.isWarmup ? 'W ' : ''}${s.weight}kg x ${s.reps}${s.rpe != null ? ' RPE ${s.rpe}' : ''}${s.rir != null ? ' RIR ${s.rir}' : ''}',
                      )
                      .join(', '),
                ),
                trailing: IconButton(
                  tooltip: 'Modifica storico',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showHistoryExerciseDialog(session, ex),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _showHistoryExerciseDialog(
    WorkoutSession session,
    WorkoutExercise exercise,
  ) async {
    final draft = WorkoutExercise.fromJson(exercise.toJson());

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Modifica ${exercise.name}'),
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
    if (bodyLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ancora nessuna misura corpo.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _showBodyLogDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi misura'),
            ),
          ],
        ),
      );
    }

    final latest = bodyLogs.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.monitor_weight),
            title: const Text('Ultima misura'),
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
        const SizedBox(height: 12),
        ...bodyLogs.map(
          (entry) => Card(
            child: ListTile(
              title: Text(
                '${entry.date.day}/${entry.date.month}/${entry.date.year}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Peso ${entry.bodyWeight?.toStringAsFixed(1) ?? '-'} kg • Vita ${entry.waist?.toStringAsFixed(1) ?? '-'} cm • Readiness ${entry.readiness ?? '-'}${entry.notes.trim().isNotEmpty ? '\n${entry.notes}' : ''}',
              ),
              onTap: () => _showBodyLogDialog(entry: entry),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => _deleteBodyLog(entry),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/app_icon.png', width: 32, height: 32),
            ),
            const SizedBox(width: 10),
            const Text('GymApp', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
          PopupMenuButton<_HomeAction>(
            tooltip: 'Importa ed esporta',
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
      body: _currentIndex == 0
          ? _buildSchedulesTab()
          : _currentIndex == 1
          ? _buildHistoryTab()
          : _currentIndex == 2
          ? StatsScreen(history: history)
          : _buildBodyTab(),
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
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Schede'),
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
    );
  }
}
