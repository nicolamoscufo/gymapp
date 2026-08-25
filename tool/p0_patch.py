from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'anchor not found: {label}')
    return text.replace(old, new, 1)


# Dependencies
pubspec_path = Path('pubspec.yaml')
pubspec = pubspec_path.read_text()
pubspec = replace_once(
    pubspec,
    '  shared_preferences: ^2.5.5\n',
    '  shared_preferences: ^2.5.5\n  sqflite: ^2.4.2\n',
    'sqflite dependency',
)
pubspec = replace_once(
    pubspec,
    '  flutter_launcher_icons: ^0.14.4\n',
    '  flutter_launcher_icons: ^0.14.4\n  sqflite_common_ffi: ^2.3.7+1\n',
    'sqflite ffi test dependency',
)
pubspec_path.write_text(pubspec)

# AI models: preserve explicit plan identifiers.
models_path = Path('lib/ai_coach/ai_coach_models.dart')
models = models_path.read_text()
models = replace_once(
    models,
    "  final String rationale;\n\n  const ProposedPlanAction({\n",
    "  final String rationale;\n  final String scheduleId;\n  final String exerciseId;\n\n  const ProposedPlanAction({\n",
    'action ids fields',
)
models = replace_once(
    models,
    "    required this.rationale,\n  });\n\n  factory ProposedPlanAction.fromJson",
    "    required this.rationale,\n    this.scheduleId = '',\n    this.exerciseId = '',\n  });\n\n  factory ProposedPlanAction.fromJson",
    'action ids constructor',
)
models = replace_once(
    models,
    "      rationale: _string(json['rationale']),\n    );\n  }\n",
    "      rationale: _string(json['rationale']),\n      scheduleId: _string(json['schedule_id']),\n      exerciseId: _string(json['exercise_id']),\n    );\n  }\n",
    'action ids parse',
)
models = replace_once(
    models,
    "    'rationale': rationale,\n  };\n}",
    "    'rationale': rationale,\n    'schedule_id': scheduleId,\n    'exercise_id': exerciseId,\n  };\n}",
    'action ids json',
)
models_path.write_text(models)

# Structured prompt: IDs are mandatory when a concrete plan mutation is proposed.
prompt_path = Path('lib/ai_coach/ai_coach_prompts.dart')
prompt = prompt_path.read_text()
prompt = replace_once(
    prompt,
    "- Suggestions are read-only and require user confirmation.\n",
    "- Suggestions are read-only and require user confirmation.\n- For proposed_actions that mutate a plan, copy schedule_id and exercise_id exactly from active_plans. Never invent identifiers.\n",
    'prompt action ids rule',
)
prompt = replace_once(
    prompt,
    "            'action': 'increase_load|reduce_load|change_volume|change_reps|change_rest|deload|keep',\n            'target': 'exercise_or_plan_name',\n            'field': 'weight|sets|reps|rest_seconds|notes|schedule',\n",
    "            'action': 'increase_load|reduce_load|change_volume|change_reps|change_rest|deload|keep',\n            'target': 'exercise_or_plan_name',\n            'schedule_id': 'exact_schedule_id_from_active_plans',\n            'exercise_id': 'exact_exercise_id_from_active_plans',\n            'field': 'weight|sets|reps|target_min_reps|target_max_reps|rest_seconds|notes',\n",
    'prompt action schema ids',
)
prompt_path.write_text(prompt)

# Critical bug: keep proposedActions instead of dropping them during safety wrapping.
service_path = Path('lib/ai_coach/local_ai_coach_service.dart')
service = service_path.read_text()
service = replace_once(
    service,
    "              requiresUserConfirmation: true,\n            ),\n",
    "              requiresUserConfirmation: true,\n              proposedActions: suggestion.proposedActions,\n            ),\n",
    'preserve proposed actions',
)
service_path.write_text(service)

# Plan action validator/applier.
Path('lib/ai_coach/ai_plan_action_service.dart').write_text(r'''import '../models/exercise.dart';
import '../models/schedule.dart';
import 'ai_coach_models.dart';

class ValidatedPlanAction {
  final ProposedPlanAction source;
  final String suggestionReason;
  final String confidence;
  final String scheduleId;
  final String scheduleTitle;
  final String exerciseId;
  final String exerciseName;
  final String field;
  final String currentValue;
  final String suggestedValue;
  final Object parsedValue;

  const ValidatedPlanAction({
    required this.source,
    required this.suggestionReason,
    required this.confidence,
    required this.scheduleId,
    required this.scheduleTitle,
    required this.exerciseId,
    required this.exerciseName,
    required this.field,
    required this.currentValue,
    required this.suggestedValue,
    required this.parsedValue,
  });

  String get title => '$exerciseName · ${fieldLabel(field)}';

  static String fieldLabel(String field) => switch (field) {
    'weight' => 'Carico',
    'sets' => 'Serie',
    'reps' => 'Ripetizioni',
    'target_min_reps' => 'Reps minime',
    'target_max_reps' => 'Reps massime',
    'rest_seconds' => 'Recupero',
    'notes' => 'Note',
    _ => field,
  };
}

class PlanApplyResult {
  final int applied;
  final int skipped;

  const PlanApplyResult({required this.applied, required this.skipped});
}

class AiPlanActionService {
  const AiPlanActionService();

  List<ValidatedPlanAction> validate(
    SuggestedAdjustmentReport report,
    List<Schedule> schedules,
  ) {
    final result = <ValidatedPlanAction>[];
    final seen = <String>{};

    for (final suggestion in report.suggestions) {
      for (final action in suggestion.proposedActions) {
        if (action.action == 'keep') continue;
        final resolved = _resolveTarget(action, schedules);
        if (resolved == null) continue;
        final schedule = resolved.$1;
        final exercise = resolved.$2;
        final parsed = _parseSuggestedValue(action.field, action.suggestedValue);
        if (parsed == null) continue;
        if (!_isSemanticallyValid(action, exercise, parsed)) continue;

        final key = '${schedule.id}|${exercise.id}|${action.field}';
        if (!seen.add(key)) continue;
        final current = _currentValue(exercise, action.field);
        if (current == null) continue;
        final suggested = _displayValue(action.field, parsed);
        if (current == suggested) continue;

        result.add(
          ValidatedPlanAction(
            source: action,
            suggestionReason: suggestion.reason,
            confidence: suggestion.confidence,
            scheduleId: schedule.id,
            scheduleTitle: schedule.title,
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            field: action.field,
            currentValue: current,
            suggestedValue: suggested,
            parsedValue: parsed,
          ),
        );
      }
    }
    return result;
  }

  PlanApplyResult apply(
    List<Schedule> schedules,
    List<ValidatedPlanAction> actions,
  ) {
    var applied = 0;
    var skipped = 0;

    for (final action in actions) {
      final schedule = schedules.where((s) => s.id == action.scheduleId).firstOrNull;
      final exercise = schedule?.exercises
          .where((e) => e.id == action.exerciseId)
          .firstOrNull;
      if (exercise == null) {
        skipped += 1;
        continue;
      }

      // Optimistic concurrency guard: never apply a stale AI diff silently.
      if (_currentValue(exercise, action.field) != action.currentValue) {
        skipped += 1;
        continue;
      }

      switch (action.field) {
        case 'weight':
          exercise.weight = action.parsedValue as double;
        case 'sets':
          exercise.set = action.parsedValue as int;
        case 'reps':
          exercise.reps = action.parsedValue as int;
        case 'target_min_reps':
          exercise.targetMinReps = action.parsedValue as int;
        case 'target_max_reps':
          exercise.targetMaxReps = action.parsedValue as int;
        case 'rest_seconds':
          exercise.restSeconds = action.parsedValue as int;
        case 'notes':
          exercise.notes = action.parsedValue as String;
        default:
          skipped += 1;
          continue;
      }
      applied += 1;
    }

    return PlanApplyResult(applied: applied, skipped: skipped);
  }

  (Schedule, Exercise)? _resolveTarget(
    ProposedPlanAction action,
    List<Schedule> schedules,
  ) {
    Schedule? schedule;
    if (action.scheduleId.isNotEmpty) {
      schedule = schedules.where((s) => s.id == action.scheduleId).firstOrNull;
      if (schedule == null) return null;
    }

    Exercise? exercise;
    if (action.exerciseId.isNotEmpty) {
      final matches = <(Schedule, Exercise)>[];
      for (final candidateSchedule in schedule == null ? schedules : [schedule]) {
        for (final candidate in candidateSchedule.exercises) {
          if (candidate.id == action.exerciseId) {
            matches.add((candidateSchedule, candidate));
          }
        }
      }
      if (matches.length != 1) return null;
      return matches.single;
    }

    // Backward-compatible fallback for older local-model outputs. Names must be
    // globally unambiguous; otherwise the action is rejected.
    final target = action.target.trim().toLowerCase();
    if (target.isEmpty) return null;
    final matches = <(Schedule, Exercise)>[];
    for (final candidateSchedule in schedule == null ? schedules : [schedule]) {
      for (final candidate in candidateSchedule.exercises) {
        if (candidate.name.trim().toLowerCase() == target) {
          matches.add((candidateSchedule, candidate));
        }
      }
    }
    return matches.length == 1 ? matches.single : null;
  }

  Object? _parseSuggestedValue(String field, String raw) {
    final value = raw.trim();
    switch (field) {
      case 'weight':
        return double.tryParse(value.replaceAll(',', '.'));
      case 'sets':
      case 'reps':
      case 'target_min_reps':
      case 'target_max_reps':
      case 'rest_seconds':
        final numeric = double.tryParse(value.replaceAll(',', '.'));
        return numeric == null ? null : numeric.round();
      case 'notes':
        return value;
      default:
        return null;
    }
  }

  bool _isSemanticallyValid(
    ProposedPlanAction action,
    Exercise exercise,
    Object value,
  ) {
    switch (action.field) {
      case 'weight':
        final weight = value as double;
        if (!weight.isFinite || weight < 0 || weight > 1000) return false;
        if (action.action == 'increase_load' && weight <= exercise.weight) {
          return false;
        }
        if ((action.action == 'reduce_load' || action.action == 'deload') &&
            weight >= exercise.weight) {
          return false;
        }
        return true;
      case 'sets':
        final sets = value as int;
        return sets >= 1 && sets <= 20;
      case 'reps':
      case 'target_min_reps':
      case 'target_max_reps':
        final reps = value as int;
        return reps >= 1 && reps <= 100;
      case 'rest_seconds':
        final seconds = value as int;
        return seconds >= 0 && seconds <= 900;
      case 'notes':
        return (value as String).length <= 500;
      default:
        return false;
    }
  }

  String? _currentValue(Exercise exercise, String field) => switch (field) {
    'weight' => _formatDouble(exercise.weight),
    'sets' => exercise.set.toString(),
    'reps' => exercise.reps.toString(),
    'target_min_reps' => exercise.targetMinReps?.toString() ?? '',
    'target_max_reps' => exercise.targetMaxReps?.toString() ?? '',
    'rest_seconds' => exercise.restSeconds?.toString() ?? '0',
    'notes' => exercise.notes,
    _ => null,
  };

  String _displayValue(String field, Object value) {
    if (field == 'weight') return _formatDouble(value as double);
    return value.toString();
  }

  String _formatDouble(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
''')

# SQLite primary storage. Normalized workout/session/set tables avoid rewriting
# one giant history JSON blob on every active-session update.
Path('lib/local_sqlite_store.dart').write_text(r'''import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'models/body_log.dart';
import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/workout.dart';

class LocalSqliteStore {
  final DatabaseFactory _factory;
  final String? _databasePath;
  Database? _database;

  LocalSqliteStore({DatabaseFactory? factoryOverride, String? databasePath})
    : _factory = factoryOverride ?? databaseFactory,
      _databasePath = databasePath;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;
    final path = _databasePath ?? await _defaultPath();
    final database = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
      ),
    );
    _database = database;
    return database;
  }

  Future<String> _defaultPath() async {
    final root = await getDatabasesPath();
    final separator = root.endsWith('/') ? '' : '/';
    return '$root${separator}gymapp_v2.db';
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE schedules (
        id TEXT PRIMARY KEY,
        position INTEGER NOT NULL,
        title TEXT NOT NULL,
        week INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        is_archived INTEGER NOT NULL,
        mesocycle_weeks INTEGER NOT NULL,
        deload_every_weeks INTEGER NOT NULL,
        goal TEXT NOT NULL,
        training_weekdays_json TEXT NOT NULL,
        program_block TEXT NOT NULL,
        cycle_number INTEGER NOT NULL,
        cycle_notes TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE schedule_exercises (
        id TEXT PRIMARY KEY,
        schedule_id TEXT NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        name TEXT NOT NULL,
        reps INTEGER NOT NULL,
        sets_count INTEGER NOT NULL,
        notes TEXT NOT NULL,
        weight REAL NOT NULL,
        muscle_group TEXT NOT NULL,
        equipment TEXT NOT NULL,
        movement_pattern TEXT NOT NULL,
        target_min_reps INTEGER,
        target_max_reps INTEGER,
        technique TEXT NOT NULL,
        backoff_reps INTEGER,
        backoff_reduction_percent REAL NOT NULL,
        rest_seconds INTEGER,
        superset_group INTEGER,
        progression_kg_step REAL NOT NULL,
        progression_rep_step INTEGER NOT NULL,
        progression_scheme TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE workout_sessions (
        id TEXT PRIMARY KEY,
        session_kind TEXT NOT NULL,
        position INTEGER NOT NULL,
        schedule_id TEXT,
        schedule_title TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE workout_exercises (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        source_exercise_id TEXT,
        name TEXT NOT NULL,
        notes TEXT NOT NULL,
        muscle_group TEXT NOT NULL,
        equipment TEXT NOT NULL,
        movement_pattern TEXT NOT NULL,
        target_min_reps INTEGER,
        target_max_reps INTEGER,
        technique TEXT NOT NULL,
        backoff_reduction_percent REAL NOT NULL,
        rest_seconds INTEGER,
        active_rest_seconds INTEGER,
        active_rest_started_at TEXT,
        superset_group INTEGER,
        progression_kg_step REAL NOT NULL,
        progression_rep_step INTEGER NOT NULL,
        progression_scheme TEXT NOT NULL,
        previous_weights_json TEXT NOT NULL,
        previous_reps_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE exercise_sets (
        id TEXT PRIMARY KEY,
        workout_exercise_id TEXT NOT NULL REFERENCES workout_exercises(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        weight REAL NOT NULL,
        reps INTEGER NOT NULL,
        is_completed INTEGER NOT NULL,
        set_type TEXT NOT NULL,
        rpe REAL,
        rir INTEGER,
        notes TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE body_logs (
        id TEXT PRIMARY KEY,
        position INTEGER NOT NULL,
        date TEXT NOT NULL,
        body_weight REAL,
        waist REAL,
        chest REAL,
        arm REAL,
        thigh REAL,
        sleep_hours INTEGER,
        readiness INTEGER,
        notes TEXT NOT NULL,
        photo_path TEXT,
        photo_name TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE custom_exercises (
        id TEXT PRIMARY KEY,
        position INTEGER NOT NULL,
        json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE favorite_exercises (
        exercise_id TEXT PRIMARY KEY
      )
    ''');
    await db.execute('CREATE INDEX idx_schedule_exercises_schedule ON schedule_exercises(schedule_id, position)');
    await db.execute('CREATE INDEX idx_workout_sessions_kind_time ON workout_sessions(session_kind, start_time)');
    await db.execute('CREATE INDEX idx_workout_exercises_session ON workout_exercises(session_id, position)');
    await db.execute('CREATE INDEX idx_exercise_sets_parent ON exercise_sets(workout_exercise_id, position)');
  }

  Future<bool> get migrationComplete async {
    final db = await _db;
    final rows = await db.query(
      'meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['legacy_migrated_v1'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['value'] == '1';
  }

  Future<bool> get hasAnyData async {
    final db = await _db;
    for (final table in ['schedules', 'workout_sessions', 'body_logs']) {
      final rows = await db.rawQuery('SELECT 1 FROM $table LIMIT 1');
      if (rows.isNotEmpty) return true;
    }
    return false;
  }

  Future<void> markMigrationComplete() async {
    final db = await _db;
    await db.insert(
      'meta',
      {'key': 'legacy_migrated_v1', 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> migrateLegacyData({
    required List<Schedule> schedules,
    required List<WorkoutSession> history,
    required WorkoutSession? currentSession,
    required List<BodyLog> bodyLogs,
    required List<Exercise> customExercises,
    required Set<String> favoriteExerciseIds,
  }) async {
    await replaceSchedules(schedules);
    await replaceHistory(history);
    await replaceBodyLogs(bodyLogs);
    await replaceCustomExercises(customExercises);
    await replaceFavoriteExerciseIds(favoriteExerciseIds);
    if (currentSession != null) {
      await saveCurrentSession(currentSession);
    }
    await markMigrationComplete();
  }

  Future<void> replaceSchedules(List<Schedule> schedules) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('schedules');
      for (var i = 0; i < schedules.length; i += 1) {
        await _insertSchedule(txn, schedules[i], i);
      }
    });
  }

  Future<void> _insertSchedule(
    DatabaseExecutor db,
    Schedule schedule,
    int position,
  ) async {
    await db.insert('schedules', {
      'id': schedule.id,
      'position': position,
      'title': schedule.title,
      'week': schedule.week,
      'created_at': schedule.createdAt.toIso8601String(),
      'is_archived': schedule.isArchived ? 1 : 0,
      'mesocycle_weeks': schedule.mesocycleWeeks,
      'deload_every_weeks': schedule.deloadEveryWeeks,
      'goal': schedule.goal,
      'training_weekdays_json': jsonEncode(schedule.trainingWeekdays),
      'program_block': schedule.programBlock,
      'cycle_number': schedule.cycleNumber,
      'cycle_notes': schedule.cycleNotes,
    });
    for (var i = 0; i < schedule.exercises.length; i += 1) {
      final exercise = schedule.exercises[i];
      await db.insert('schedule_exercises', {
        'id': exercise.id,
        'schedule_id': schedule.id,
        'position': i,
        'name': exercise.name,
        'reps': exercise.reps,
        'sets_count': exercise.set,
        'notes': exercise.notes,
        'weight': exercise.weight,
        'muscle_group': exercise.muscleGroup.name,
        'equipment': exercise.equipment,
        'movement_pattern': exercise.movementPattern,
        'target_min_reps': exercise.targetMinReps,
        'target_max_reps': exercise.targetMaxReps,
        'technique': exercise.technique.name,
        'backoff_reps': exercise.backoffReps,
        'backoff_reduction_percent': exercise.backoffReductionPercent,
        'rest_seconds': exercise.restSeconds,
        'superset_group': exercise.supersetGroup,
        'progression_kg_step': exercise.progressionKgStep,
        'progression_rep_step': exercise.progressionRepStep,
        'progression_scheme': exercise.progressionScheme.name,
      });
    }
  }

  Future<void> replaceHistory(List<WorkoutSession> history) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('workout_sessions', where: 'session_kind = ?', whereArgs: ['history']);
      for (var i = 0; i < history.length; i += 1) {
        await _insertSession(txn, history[i], 'history', i);
      }
    });
  }

  Future<void> saveCurrentSession(WorkoutSession session) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('workout_sessions', where: 'session_kind = ?', whereArgs: ['current']);
      await _insertSession(txn, session, 'current', 0);
    });
  }

  Future<void> clearCurrentSession() async {
    final db = await _db;
    await db.delete('workout_sessions', where: 'session_kind = ?', whereArgs: ['current']);
  }

  Future<void> _insertSession(
    DatabaseExecutor db,
    WorkoutSession session,
    String kind,
    int position,
  ) async {
    // A completed session can have the same id as the last autosaved current
    // session. Remove it first so FK children cannot become stale.
    await db.delete('workout_sessions', where: 'id = ?', whereArgs: [session.id]);
    await db.insert('workout_sessions', {
      'id': session.id,
      'session_kind': kind,
      'position': position,
      'schedule_id': session.scheduleId,
      'schedule_title': session.scheduleTitle,
      'start_time': session.startTime.toIso8601String(),
      'end_time': session.endTime.toIso8601String(),
    });
    for (var i = 0; i < session.exercises.length; i += 1) {
      final exercise = session.exercises[i];
      await db.insert('workout_exercises', {
        'id': exercise.id,
        'session_id': session.id,
        'position': i,
        'source_exercise_id': exercise.sourceExerciseId,
        'name': exercise.name,
        'notes': exercise.notes,
        'muscle_group': exercise.muscleGroup.name,
        'equipment': exercise.equipment,
        'movement_pattern': exercise.movementPattern,
        'target_min_reps': exercise.targetMinReps,
        'target_max_reps': exercise.targetMaxReps,
        'technique': exercise.technique.name,
        'backoff_reduction_percent': exercise.backoffReductionPercent,
        'rest_seconds': exercise.restSeconds,
        'active_rest_seconds': exercise.activeRestSeconds,
        'active_rest_started_at': exercise.activeRestStartedAt?.toIso8601String(),
        'superset_group': exercise.supersetGroup,
        'progression_kg_step': exercise.progressionKgStep,
        'progression_rep_step': exercise.progressionRepStep,
        'progression_scheme': exercise.progressionScheme.name,
        'previous_weights_json': jsonEncode(exercise.previousWeights),
        'previous_reps_json': jsonEncode(exercise.previousReps),
      });
      for (var setIndex = 0; setIndex < exercise.sets.length; setIndex += 1) {
        final set = exercise.sets[setIndex];
        await db.insert('exercise_sets', {
          'id': set.id,
          'workout_exercise_id': exercise.id,
          'position': setIndex,
          'weight': set.weight,
          'reps': set.reps,
          'is_completed': set.isCompleted ? 1 : 0,
          'set_type': set.type.name,
          'rpe': set.rpe,
          'rir': set.rir,
          'notes': set.notes,
        });
      }
    }
  }

  Future<void> replaceBodyLogs(List<BodyLog> logs) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('body_logs');
      for (var i = 0; i < logs.length; i += 1) {
        final log = logs[i];
        await txn.insert('body_logs', {
          'id': log.id,
          'position': i,
          'date': log.date.toIso8601String(),
          'body_weight': log.bodyWeight,
          'waist': log.waist,
          'chest': log.chest,
          'arm': log.arm,
          'thigh': log.thigh,
          'sleep_hours': log.sleepHours,
          'readiness': log.readiness,
          'notes': log.notes,
          'photo_path': log.photoPath,
          'photo_name': log.photoName,
        });
      }
    });
  }

  Future<void> replaceCustomExercises(List<Exercise> exercises) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('custom_exercises');
      for (var i = 0; i < exercises.length; i += 1) {
        final exercise = exercises[i];
        await txn.insert('custom_exercises', {
          'id': exercise.id,
          'position': i,
          'json': jsonEncode(exercise.toJson()),
        });
      }
    });
  }

  Future<void> replaceFavoriteExerciseIds(Set<String> ids) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('favorite_exercises');
      for (final id in ids) {
        await txn.insert('favorite_exercises', {'exercise_id': id});
      }
    });
  }

  Future<({
    List<Schedule> schedules,
    List<WorkoutSession> history,
    WorkoutSession? currentSession,
    List<BodyLog> bodyLogs,
    List<Exercise> customExercises,
    Set<String> favoriteExerciseIds,
  })> loadAll() async {
    final schedules = await loadSchedules();
    final history = await loadHistory();
    final current = await loadCurrentSession();
    final bodyLogs = await loadBodyLogs();
    final custom = await loadCustomExercises();
    final favorites = await loadFavoriteExerciseIds();
    return (
      schedules: schedules,
      history: history,
      currentSession: current,
      bodyLogs: bodyLogs,
      customExercises: custom,
      favoriteExerciseIds: favorites,
    );
  }

  Future<List<Schedule>> loadSchedules() async {
    final db = await _db;
    final rows = await db.query('schedules', orderBy: 'position ASC');
    final result = <Schedule>[];
    for (final row in rows) {
      final exerciseRows = await db.query(
        'schedule_exercises',
        where: 'schedule_id = ?',
        whereArgs: [row['id']],
        orderBy: 'position ASC',
      );
      result.add(
        Schedule(
          id: row['id'] as String,
          title: row['title'] as String,
          week: row['week'] as int,
          createdAt: DateTime.parse(row['created_at'] as String),
          exercises: exerciseRows.map(_scheduleExerciseFromRow).toList(),
          isArchived: (row['is_archived'] as int) == 1,
          mesocycleWeeks: row['mesocycle_weeks'] as int,
          deloadEveryWeeks: row['deload_every_weeks'] as int,
          goal: row['goal'] as String,
          trainingWeekdays: (jsonDecode(row['training_weekdays_json'] as String) as List)
              .whereType<num>()
              .map((e) => e.toInt())
              .toList(),
          programBlock: row['program_block'] as String,
          cycleNumber: row['cycle_number'] as int,
          cycleNotes: row['cycle_notes'] as String,
        ),
      );
    }
    return result;
  }

  Exercise _scheduleExerciseFromRow(Map<String, Object?> row) {
    return Exercise(
      id: row['id'] as String,
      name: row['name'] as String,
      reps: row['reps'] as int,
      set: row['sets_count'] as int,
      notes: row['notes'] as String,
      weight: (row['weight'] as num).toDouble(),
      muscleGroup: muscleGroupFromJson(row['muscle_group']),
      equipment: row['equipment'] as String,
      movementPattern: row['movement_pattern'] as String,
      targetMinReps: row['target_min_reps'] as int?,
      targetMaxReps: row['target_max_reps'] as int?,
      technique: _technique(row['technique']),
      backoffReps: row['backoff_reps'] as int?,
      backoffReductionPercent: (row['backoff_reduction_percent'] as num).toDouble(),
      restSeconds: row['rest_seconds'] as int?,
      supersetGroup: row['superset_group'] as int?,
      progressionKgStep: (row['progression_kg_step'] as num).toDouble(),
      progressionRepStep: row['progression_rep_step'] as int,
      progressionScheme: progressionSchemeFromJson(row['progression_scheme']),
    );
  }

  Future<List<WorkoutSession>> loadHistory() => _loadSessions('history');

  Future<WorkoutSession?> loadCurrentSession() async {
    final sessions = await _loadSessions('current');
    return sessions.isEmpty ? null : sessions.first;
  }

  Future<List<WorkoutSession>> _loadSessions(String kind) async {
    final db = await _db;
    final rows = await db.query(
      'workout_sessions',
      where: 'session_kind = ?',
      whereArgs: [kind],
      orderBy: 'position ASC',
    );
    final result = <WorkoutSession>[];
    for (final row in rows) {
      final exerciseRows = await db.query(
        'workout_exercises',
        where: 'session_id = ?',
        whereArgs: [row['id']],
        orderBy: 'position ASC',
      );
      final exercises = <WorkoutExercise>[];
      for (final exerciseRow in exerciseRows) {
        final setRows = await db.query(
          'exercise_sets',
          where: 'workout_exercise_id = ?',
          whereArgs: [exerciseRow['id']],
          orderBy: 'position ASC',
        );
        exercises.add(_workoutExerciseFromRow(exerciseRow, setRows));
      }
      result.add(
        WorkoutSession(
          id: row['id'] as String,
          scheduleId: row['schedule_id'] as String?,
          scheduleTitle: row['schedule_title'] as String,
          startTime: DateTime.parse(row['start_time'] as String),
          endTime: DateTime.parse(row['end_time'] as String),
          exercises: exercises,
        ),
      );
    }
    return result;
  }

  WorkoutExercise _workoutExerciseFromRow(
    Map<String, Object?> row,
    List<Map<String, Object?>> sets,
  ) {
    return WorkoutExercise(
      id: row['id'] as String,
      sourceExerciseId: row['source_exercise_id'] as String?,
      name: row['name'] as String,
      notes: row['notes'] as String,
      muscleGroup: muscleGroupFromJson(row['muscle_group']),
      equipment: row['equipment'] as String,
      movementPattern: row['movement_pattern'] as String,
      targetMinReps: row['target_min_reps'] as int?,
      targetMaxReps: row['target_max_reps'] as int?,
      technique: _technique(row['technique']),
      backoffReductionPercent: (row['backoff_reduction_percent'] as num).toDouble(),
      restSeconds: row['rest_seconds'] as int?,
      activeRestSeconds: row['active_rest_seconds'] as int?,
      activeRestStartedAt: row['active_rest_started_at'] == null
          ? null
          : DateTime.tryParse(row['active_rest_started_at'] as String),
      supersetGroup: row['superset_group'] as int?,
      progressionKgStep: (row['progression_kg_step'] as num).toDouble(),
      progressionRepStep: row['progression_rep_step'] as int,
      progressionScheme: progressionSchemeFromJson(row['progression_scheme']),
      sets: sets.map(_setFromRow).toList(),
      previousWeights: (jsonDecode(row['previous_weights_json'] as String) as List)
          .whereType<num>()
          .map((e) => e.toDouble())
          .toList(),
      previousReps: (jsonDecode(row['previous_reps_json'] as String) as List)
          .whereType<num>()
          .map((e) => e.toInt())
          .toList(),
    );
  }

  ExerciseSet _setFromRow(Map<String, Object?> row) {
    SetType type;
    try {
      type = SetType.values.byName(row['set_type'] as String);
    } catch (_) {
      type = SetType.normal;
    }
    return ExerciseSet(
      id: row['id'] as String,
      weight: (row['weight'] as num).toDouble(),
      reps: row['reps'] as int,
      isCompleted: (row['is_completed'] as int) == 1,
      type: type,
      rpe: (row['rpe'] as num?)?.toDouble(),
      rir: row['rir'] as int?,
      notes: row['notes'] as String,
    );
  }

  Future<List<BodyLog>> loadBodyLogs() async {
    final db = await _db;
    final rows = await db.query('body_logs', orderBy: 'position ASC');
    return rows
        .map(
          (row) => BodyLog(
            id: row['id'] as String,
            date: DateTime.parse(row['date'] as String),
            bodyWeight: (row['body_weight'] as num?)?.toDouble(),
            waist: (row['waist'] as num?)?.toDouble(),
            chest: (row['chest'] as num?)?.toDouble(),
            arm: (row['arm'] as num?)?.toDouble(),
            thigh: (row['thigh'] as num?)?.toDouble(),
            sleepHours: row['sleep_hours'] as int?,
            readiness: row['readiness'] as int?,
            notes: row['notes'] as String,
            photoPath: row['photo_path'] as String?,
            photoName: row['photo_name'] as String?,
          ),
        )
        .toList();
  }

  Future<List<Exercise>> loadCustomExercises() async {
    final db = await _db;
    final rows = await db.query('custom_exercises', orderBy: 'position ASC');
    return rows
        .map(
          (row) => Exercise.fromJson(
            Map<String, dynamic>.from(jsonDecode(row['json'] as String) as Map),
          ),
        )
        .toList();
  }

  Future<Set<String>> loadFavoriteExerciseIds() async {
    final db = await _db;
    final rows = await db.query('favorite_exercises');
    return rows.map((row) => row['exercise_id'] as String).toSet();
  }

  IntensityTechnique _technique(Object? raw) {
    try {
      return IntensityTechnique.values.byName(raw.toString());
    } catch (_) {
      return IntensityTechnique.none;
    }
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }
}
''')

# Replace AppDataStore with a SQLite-first facade plus legacy migration/fallback.
Path('lib/app_data_store.dart').write_text(r'''import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_sqlite_store.dart';
import 'models/body_log.dart';
import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/workout.dart';

class AppDataKeys {
  static const schedules = 'schedules';
  static const history = 'history';
  static const currentSession = 'current_session';
  static const bodyLogs = 'body_logs';
  static const favoriteExerciseIds = 'favorite_exercise_ids';
  static const customExercises = 'custom_exercises';
  static const scheduledReminderNotificationIds = 'scheduled_reminder_notification_ids';
  static const autoBackupJson = 'auto_backup_json';
  static const lastAutoBackupAt = 'last_auto_backup_at';
}

class AppDataBundle {
  final List<Schedule> schedules;
  final List<WorkoutSession> history;
  final WorkoutSession? currentSession;
  final List<BodyLog> bodyLogs;
  final List<Exercise> customExercises;
  final Set<String> favoriteExerciseIds;
  final bool recoveredFromCorruption;

  const AppDataBundle({
    required this.schedules,
    required this.history,
    required this.currentSession,
    required this.bodyLogs,
    this.customExercises = const [],
    this.favoriteExerciseIds = const <String>{},
    required this.recoveredFromCorruption,
  });
}

class AppDataStore {
  static LocalSqliteStore? _sqlite;

  static bool get _sqliteSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static LocalSqliteStore get _sqliteStore => _sqlite ??= LocalSqliteStore();

  static dynamic _decodeJsonOr(
    SharedPreferences prefs,
    String key,
    dynamic fallback,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return fallback;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return fallback;
    }
  }

  static List<T> _safeLegacyList<T>(
    SharedPreferences prefs,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map>()
          .map((entry) => fromJson(Map<String, dynamic>.from(entry)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static WorkoutSession? _safeLegacyCurrentSession(SharedPreferences prefs) {
    final raw = prefs.getString(AppDataKeys.currentSession);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return WorkoutSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Set<String> _legacyFavoriteIds(SharedPreferences prefs) {
    final raw = prefs.getString(AppDataKeys.favoriteExerciseIds);
    if (raw == null || raw.trim().isEmpty) return <String>{};
    try {
      return (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static AppDataBundle _loadLegacyBundle(SharedPreferences prefs) {
    var recovered = false;

    List<T> checkedList<T>(String key, T Function(Map<String, dynamic>) parser) {
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) return [];
      try {
        return (jsonDecode(raw) as List<dynamic>)
            .whereType<Map>()
            .map((entry) => parser(Map<String, dynamic>.from(entry)))
            .toList();
      } catch (_) {
        recovered = true;
        return [];
      }
    }

    WorkoutSession? current;
    final rawCurrent = prefs.getString(AppDataKeys.currentSession);
    if (rawCurrent != null && rawCurrent.trim().isNotEmpty) {
      try {
        current = WorkoutSession.fromJson(
          Map<String, dynamic>.from(jsonDecode(rawCurrent) as Map),
        );
      } catch (_) {
        recovered = true;
      }
    }

    final bundle = AppDataBundle(
      schedules: checkedList(AppDataKeys.schedules, Schedule.fromJson),
      history: checkedList(AppDataKeys.history, WorkoutSession.fromJson),
      currentSession: current,
      bodyLogs: checkedList(AppDataKeys.bodyLogs, BodyLog.fromJson),
      customExercises: checkedList(AppDataKeys.customExercises, Exercise.fromJson),
      favoriteExerciseIds: _legacyFavoriteIds(prefs),
      recoveredFromCorruption: recovered,
    );
    if (!recovered) return bundle;
    return _bundleFromAutoBackup(prefs) ?? bundle;
  }

  static AppDataBundle? _bundleFromAutoBackup(SharedPreferences prefs) {
    final rawBackup = prefs.getString(AppDataKeys.autoBackupJson);
    if (rawBackup == null || rawBackup.trim().isEmpty) return null;
    try {
      final backupMap = Map<String, dynamic>.from(jsonDecode(rawBackup) as Map);
      return AppDataBundle(
        schedules: (backupMap['schedules'] as List? ?? [])
            .whereType<Map>()
            .map((entry) => Schedule.fromJson(Map<String, dynamic>.from(entry)))
            .toList(),
        history: (backupMap['history'] as List? ?? [])
            .whereType<Map>()
            .map((entry) => WorkoutSession.fromJson(Map<String, dynamic>.from(entry)))
            .toList(),
        currentSession: backupMap['currentSession'] == null
            ? null
            : WorkoutSession.fromJson(
                Map<String, dynamic>.from(backupMap['currentSession'] as Map),
              ),
        bodyLogs: (backupMap['bodyLogs'] as List? ?? [])
            .whereType<Map>()
            .map((entry) => BodyLog.fromJson(Map<String, dynamic>.from(entry)))
            .toList(),
        customExercises: (backupMap['customExercises'] as List? ?? [])
            .whereType<Map>()
            .map((entry) => Exercise.fromJson(Map<String, dynamic>.from(entry)))
            .toList(),
        favoriteExerciseIds: (backupMap['favoriteExerciseIds'] as List? ?? [])
            .map((entry) => entry.toString())
            .toSet(),
        recoveredFromCorruption: true,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeLegacyAutoBackupSnapshot(SharedPreferences prefs) async {
    final payload = {
      'version': 6,
      'auto': true,
      'exportedAt': DateTime.now().toIso8601String(),
      'schedules': _decodeJsonOr(prefs, AppDataKeys.schedules, []),
      'history': _decodeJsonOr(prefs, AppDataKeys.history, []),
      'bodyLogs': _decodeJsonOr(prefs, AppDataKeys.bodyLogs, []),
      'currentSession': prefs.getString(AppDataKeys.currentSession) == null
          ? null
          : _decodeJsonOr(prefs, AppDataKeys.currentSession, null),
      'customExercises': _decodeJsonOr(prefs, AppDataKeys.customExercises, []),
      'favoriteExerciseIds': _decodeJsonOr(prefs, AppDataKeys.favoriteExerciseIds, []),
    };
    await prefs.setString(AppDataKeys.autoBackupJson, jsonEncode(payload));
    await prefs.setString(AppDataKeys.lastAutoBackupAt, DateTime.now().toIso8601String());
  }

  static Future<void> _writeSqliteAutoBackup({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      final last = DateTime.tryParse(prefs.getString(AppDataKeys.lastAutoBackupAt) ?? '');
      if (last != null && DateTime.now().difference(last) < const Duration(minutes: 5)) {
        return;
      }
    }
    final snapshot = await _sqliteStore.loadAll();
    final payload = {
      'version': 6,
      'auto': true,
      'storage': 'sqlite',
      'exportedAt': DateTime.now().toIso8601String(),
      'schedules': snapshot.schedules.map((e) => e.toJson()).toList(),
      'history': snapshot.history.map((e) => e.toJson()).toList(),
      'bodyLogs': snapshot.bodyLogs.map((e) => e.toJson()).toList(),
      'currentSession': snapshot.currentSession?.toJson(),
      'customExercises': snapshot.customExercises.map((e) => e.toJson()).toList(),
      'favoriteExerciseIds': snapshot.favoriteExerciseIds.toList(),
    };
    await prefs.setString(AppDataKeys.autoBackupJson, jsonEncode(payload));
    await prefs.setString(AppDataKeys.lastAutoBackupAt, DateTime.now().toIso8601String());
  }

  static Future<void> _ensureSqliteMigration() async {
    final store = _sqliteStore;
    if (await store.migrationComplete) return;
    if (await store.hasAnyData) {
      await store.markMigrationComplete();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = _loadLegacyBundle(prefs);
    await store.migrateLegacyData(
      schedules: legacy.schedules,
      history: legacy.history,
      currentSession: legacy.currentSession,
      bodyLogs: legacy.bodyLogs,
      customExercises: legacy.customExercises,
      favoriteExerciseIds: legacy.favoriteExerciseIds,
    );
  }

  static Future<AppDataBundle> loadBundle() async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        final data = await _sqliteStore.loadAll();
        return AppDataBundle(
          schedules: data.schedules,
          history: data.history,
          currentSession: data.currentSession,
          bodyLogs: data.bodyLogs,
          customExercises: data.customExercises,
          favoriteExerciseIds: data.favoriteExerciseIds,
          recoveredFromCorruption: false,
        );
      } catch (_) {
        final prefs = await SharedPreferences.getInstance();
        return _bundleFromAutoBackup(prefs) ?? _loadLegacyBundle(prefs);
      }
    }
    return _loadLegacyBundle(await SharedPreferences.getInstance());
  }

  static Future<List<WorkoutSession>> loadHistory() async => (await loadBundle()).history;

  static Future<void> saveSchedules(List<Schedule> schedules) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.replaceSchedules(schedules);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppDataKeys.schedules, jsonEncode(schedules.map((e) => e.toJson()).toList()));
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<void> saveHistory(List<WorkoutSession> history) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.replaceHistory(history);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppDataKeys.history, jsonEncode(history.map((e) => e.toJson()).toList()));
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<void> saveBodyLogs(List<BodyLog> bodyLogs) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.replaceBodyLogs(bodyLogs);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppDataKeys.bodyLogs, jsonEncode(bodyLogs.map((e) => e.toJson()).toList()));
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<void> saveCurrentSession(WorkoutSession session) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.saveCurrentSession(session);
        await _writeSqliteAutoBackup();
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppDataKeys.currentSession, jsonEncode(session.toJson()));
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<void> clearCurrentSession() async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.clearCurrentSession();
        await _writeSqliteAutoBackup();
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppDataKeys.currentSession);
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<Set<String>> loadFavoriteExerciseIds() async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        return await _sqliteStore.loadFavoriteExerciseIds();
      } catch (_) {}
    }
    return _legacyFavoriteIds(await SharedPreferences.getInstance());
  }

  static Future<void> saveFavoriteExerciseIds(Set<String> ids) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.replaceFavoriteExerciseIds(ids);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppDataKeys.favoriteExerciseIds, jsonEncode(ids.toList()));
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<List<Exercise>> loadCustomExercises() async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        return await _sqliteStore.loadCustomExercises();
      } catch (_) {}
    }
    return _safeLegacyList(await SharedPreferences.getInstance(), AppDataKeys.customExercises, Exercise.fromJson);
  }

  static Future<void> saveCustomExercises(List<Exercise> exercises) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.replaceCustomExercises(exercises);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppDataKeys.customExercises, jsonEncode(exercises.map((e) => e.toJson()).toList()));
    await _writeLegacyAutoBackupSnapshot(prefs);
  }

  static Future<void> addCustomExercise(Exercise exercise) async {
    final exercises = await loadCustomExercises();
    final normalizedName = exercise.name.trim().toLowerCase();
    final index = exercises.indexWhere((e) => e.name.trim().toLowerCase() == normalizedName);
    final template = Exercise.fromJson(exercise.toJson());
    if (index == -1) {
      exercises.add(template);
    } else {
      exercises[index] = template;
    }
    exercises.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await saveCustomExercises(exercises);
  }

  static Future<Set<int>> loadScheduledReminderNotificationIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppDataKeys.scheduledReminderNotificationIds);
    if (raw == null || raw.trim().isEmpty) return <int>{};
    try {
      return (jsonDecode(raw) as List<dynamic>).whereType<num>().map((e) => e.toInt()).toSet();
    } catch (_) {
      return <int>{};
    }
  }

  static Future<void> saveScheduledReminderNotificationIds(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppDataKeys.scheduledReminderNotificationIds, jsonEncode(ids.toList()));
  }

  static Future<DateTime?> loadLastAutoBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(AppDataKeys.lastAutoBackupAt) ?? '');
  }

  static Future<AppDataBundle?> loadAutoBackupBundle() async {
    return _bundleFromAutoBackup(await SharedPreferences.getInstance());
  }

  static Future<Map<String, dynamic>> buildExportPayload({
    required List<Schedule> schedules,
    required List<WorkoutSession> history,
    required List<BodyLog> bodyLogs,
    WorkoutSession? currentSession,
  }) async {
    final favoriteExerciseIds = (await loadFavoriteExerciseIds()).toList()..sort();
    final customExercises = await loadCustomExercises();
    return {
      'version': 6,
      'exportedAt': DateTime.now().toIso8601String(),
      'schedules': schedules.map((e) => e.toJson()).toList(),
      'history': history.map((e) => e.toJson()).toList(),
      'bodyLogs': bodyLogs.map((e) => e.toJson()).toList(),
      'currentSession': currentSession?.toJson(),
      'customExercises': customExercises.map((e) => e.toJson()).toList(),
      'favoriteExerciseIds': favoriteExerciseIds,
    };
  }

  static Future<void> saveAll({
    required List<Schedule> schedules,
    required List<WorkoutSession> history,
    required List<BodyLog> bodyLogs,
  }) async {
    if (_sqliteSupported) {
      try {
        await _ensureSqliteMigration();
        await _sqliteStore.replaceSchedules(schedules);
        await _sqliteStore.replaceHistory(history);
        await _sqliteStore.replaceBodyLogs(bodyLogs);
        await _writeSqliteAutoBackup(force: true);
        return;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppDataKeys.schedules, jsonEncode(schedules.map((e) => e.toJson()).toList()));
    await prefs.setString(AppDataKeys.history, jsonEncode(history.map((e) => e.toJson()).toList()));
    await prefs.setString(AppDataKeys.bodyLogs, jsonEncode(bodyLogs.map((e) => e.toJson()).toList()));
    await _writeLegacyAutoBackupSnapshot(prefs);
  }
}
''')

# AI Coach UI: structured review/diff with explicit user confirmation.
ai_screen_path = Path('lib/screens/ai_coach.dart')
ai = ai_screen_path.read_text()
ai = replace_once(
    ai,
    "import '../ai_coach/ai_coach_memory.dart';\n",
    "import '../ai_coach/ai_coach_memory.dart';\nimport '../ai_coach/ai_plan_action_service.dart';\nimport '../app_data_store.dart';\n",
    'ai screen imports',
)
ai = replace_once(
    ai,
    "  final AiCoachModelInstaller modelInstaller;\n",
    "  final AiCoachModelInstaller modelInstaller;\n  final AiPlanActionService planActionService;\n",
    'ai screen plan service field',
)
ai = replace_once(
    ai,
    "    this.modelInstaller = const FlutterGemmaAiCoachModelInstaller(),\n  });\n",
    "    this.modelInstaller = const FlutterGemmaAiCoachModelInstaller(),\n    this.planActionService = const AiPlanActionService(),\n  });\n",
    'ai screen plan service constructor',
)
ai = replace_once(
    ai,
    "  bool _isRunning = false;\n",
    "  bool _isRunning = false;\n  bool _isAnalyzingPlan = false;\n",
    'ai screen analyzing state',
)
ai = replace_once(
    ai,
    "  Future<void> _handleSuggestionTap(String suggestion) async {\n    _textController.text = suggestion;\n    await _sendMessage();\n  }\n\n  @override\n",
    r'''  Future<void> _handleSuggestionTap(String suggestion) async {
    _textController.text = suggestion;
    await _sendMessage();
  }

  Future<void> _reviewPlanAdjustments() async {
    if (_isAnalyzingPlan || _isRunning) return;
    if (!_isModelInstalled) {
      setState(() => _errorMessage = 'Scarica il modello locale prima di analizzare la scheda.');
      return;
    }
    setState(() {
      _isAnalyzingPlan = true;
      _errorMessage = null;
    });
    try {
      final report = await widget.service.suggestWorkoutAdjustments(
        history: widget.history,
        schedules: widget.schedules,
        bodyLogs: widget.bodyLogs,
        profile: _profile,
        memory: _memory,
      );
      final actions = widget.planActionService.validate(report, widget.schedules);
      if (!mounted) return;
      if (actions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessuna modifica strutturata applicabile in sicurezza.')),
        );
        return;
      }
      final selected = await showModalBottomSheet<List<ValidatedPlanAction>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => _PlanActionsReviewSheet(actions: actions),
      );
      if (!mounted || selected == null || selected.isEmpty) return;
      final result = widget.planActionService.apply(widget.schedules, selected);
      if (result.applied > 0) {
        await AppDataStore.saveSchedules(widget.schedules);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.skipped == 0
                ? '${result.applied} modifiche applicate alla scheda.'
                : '${result.applied} applicate, ${result.skipped} saltate perché i dati erano cambiati.',
          ),
        ),
      );
    } on AiCoachInsufficientDataException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Impossibile generare modifiche sicure alla scheda.');
    } finally {
      if (mounted) setState(() => _isAnalyzingPlan = false);
    }
  }

  @override
''',
    'ai plan review method',
)
ai = replace_once(
    ai,
    "        actions: [\n          IconButton(\n            icon: const Icon(Icons.edit_outlined),\n",
    "        actions: [\n          if (_isModelInstalled)\n            IconButton(\n              key: const ValueKey('ai-plan-actions'),\n              icon: _isAnalyzingPlan\n                  ? const SizedBox.square(\n                      dimension: 20,\n                      child: CircularProgressIndicator(strokeWidth: 2),\n                    )\n                  : const Icon(Icons.auto_awesome_motion_outlined),\n              tooltip: 'Proponi modifiche alla scheda',\n              onPressed: _isAnalyzingPlan ? null : _reviewPlanAdjustments,\n            ),\n          IconButton(\n            icon: const Icon(Icons.edit_outlined),\n",
    'ai plan action appbar button',
)
ai += r'''

class _PlanActionsReviewSheet extends StatefulWidget {
  final List<ValidatedPlanAction> actions;

  const _PlanActionsReviewSheet({required this.actions});

  @override
  State<_PlanActionsReviewSheet> createState() => _PlanActionsReviewSheetState();
}

class _PlanActionsReviewSheetState extends State<_PlanActionsReviewSheet> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.actions.length; i += 1) i,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Modifiche proposte', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Il Coach propone, il validator controlla i valori e nulla cambia finché non confermi.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: widget.actions.length,
                itemBuilder: (context, index) {
                  final action = widget.actions[index];
                  return Card(
                    child: CheckboxListTile(
                      key: ValueKey('plan-action-$index'),
                      value: _selected.contains(index),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selected.add(index);
                          } else {
                            _selected.remove(index);
                          }
                        });
                      },
                      title: Text(action.title),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${action.scheduleTitle}: ${action.currentValue} → ${action.suggestedValue}'),
                            if (action.source.rationale.trim().isNotEmpty)
                              Text(action.source.rationale),
                            if (action.suggestionReason.trim().isNotEmpty)
                              Text('Motivo: ${action.suggestionReason}'),
                            Text('Confidenza: ${action.confidence}'),
                          ],
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Annulla'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('apply-plan-actions'),
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.pop(
                              context,
                              _selected.map((i) => widget.actions[i]).toList(),
                            ),
                      child: Text('Applica ${_selected.length}'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
'''
ai_screen_path.write_text(ai)

# Tests for deterministic action validation and stale-diff protection.
Path('test/ai_plan_action_service_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_coach_models.dart';
import 'package:gymapp/ai_coach/ai_plan_action_service.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';

void main() {
  test('validates and applies id-bound AI plan actions', () {
    final exercise = Exercise(
      id: 'bench',
      name: 'Panca',
      reps: 8,
      set: 3,
      notes: '',
      weight: 80,
      technique: IntensityTechnique.none,
    );
    final schedule = Schedule(
      id: 'push',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: [exercise],
    );
    const report = SuggestedAdjustmentReport(
      suggestions: [
        SuggestedAdjustment(
          type: 'load_progression',
          target: 'Panca',
          suggestion: 'Aumenta il carico',
          reason: 'Progressione deterministica positiva',
          evidence: ['RIR stabile'],
          confidence: 'high',
          requiresUserConfirmation: true,
          proposedActions: [
            ProposedPlanAction(
              action: 'increase_load',
              target: 'Panca',
              field: 'weight',
              currentValue: '999',
              suggestedValue: '82.5',
              rationale: 'Piccolo incremento',
              scheduleId: 'push',
              exerciseId: 'bench',
            ),
          ],
        ),
      ],
    );

    const service = AiPlanActionService();
    final actions = service.validate(report, [schedule]);
    expect(actions, hasLength(1));
    expect(actions.single.currentValue, '80');
    expect(actions.single.suggestedValue, '82.5');

    final result = service.apply([schedule], actions);
    expect(result.applied, 1);
    expect(exercise.weight, 82.5);
  });

  test('rejects ambiguous name-only and unsafe actions', () {
    final schedules = [
      for (final id in ['a', 'b'])
        Schedule(
          id: id,
          title: id,
          week: 1,
          createdAt: DateTime(2026, 8, 1),
          exercises: [
            Exercise(
              name: 'Panca',
              reps: 8,
              set: 3,
              notes: '',
              weight: 80,
              technique: IntensityTechnique.none,
            ),
          ],
        ),
    ];
    const report = SuggestedAdjustmentReport(
      suggestions: [
        SuggestedAdjustment(
          type: 'load_progression',
          target: 'Panca',
          suggestion: '',
          reason: '',
          evidence: [],
          confidence: 'low',
          requiresUserConfirmation: true,
          proposedActions: [
            ProposedPlanAction(
              action: 'increase_load',
              target: 'Panca',
              field: 'weight',
              currentValue: '80',
              suggestedValue: '5000',
              rationale: '',
            ),
          ],
        ),
      ],
    );
    expect(const AiPlanActionService().validate(report, schedules), isEmpty);
  });

  test('stale diff is skipped instead of overwriting a newer edit', () {
    final exercise = Exercise(
      id: 'bench',
      name: 'Panca',
      reps: 8,
      set: 3,
      notes: '',
      weight: 80,
      technique: IntensityTechnique.none,
    );
    final schedule = Schedule(
      id: 'push',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: [exercise],
    );
    const report = SuggestedAdjustmentReport(
      suggestions: [
        SuggestedAdjustment(
          type: 'load_progression',
          target: 'Panca',
          suggestion: '',
          reason: '',
          evidence: [],
          confidence: 'medium',
          requiresUserConfirmation: true,
          proposedActions: [
            ProposedPlanAction(
              action: 'increase_load',
              target: 'Panca',
              field: 'weight',
              currentValue: '80',
              suggestedValue: '82.5',
              rationale: '',
              scheduleId: 'push',
              exerciseId: 'bench',
            ),
          ],
        ),
      ],
    );
    const service = AiPlanActionService();
    final actions = service.validate(report, [schedule]);
    exercise.weight = 81;
    final result = service.apply([schedule], actions);
    expect(result.applied, 0);
    expect(result.skipped, 1);
    expect(exercise.weight, 81);
  });
}
''')

# SQLite round-trip and migration tests on the FFI in-memory backend.
Path('test/local_sqlite_store_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/local_sqlite_store.dart';
import 'package:gymapp/models/body_log.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('normalized sqlite store round-trips the full local data graph', () async {
    final store = LocalSqliteStore(
      factoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);

    final planExercise = Exercise(
      id: 'bench-plan',
      name: 'Panca',
      reps: 8,
      set: 3,
      notes: 'petto',
      weight: 80,
      muscleGroup: MuscleGroup.chest,
      restSeconds: 180,
      technique: IntensityTechnique.none,
    );
    final schedule = Schedule(
      id: 'push',
      title: 'Push',
      week: 2,
      createdAt: DateTime(2026, 8, 1),
      exercises: [planExercise],
      trainingWeekdays: [1, 4],
    );
    final session = WorkoutSession(
      id: 'session-1',
      scheduleId: 'push',
      scheduleTitle: 'Push',
      startTime: DateTime(2026, 8, 25, 18),
      endTime: DateTime(2026, 8, 25, 19),
      exercises: [
        WorkoutExercise(
          id: 'work-bench',
          sourceExerciseId: 'bench-plan',
          name: 'Panca',
          notes: 'bene',
          muscleGroup: MuscleGroup.chest,
          technique: IntensityTechnique.none,
          previousWeights: const [77.5],
          previousReps: const [8],
          sets: [
            ExerciseSet(
              id: 'set-1',
              weight: 80,
              reps: 8,
              isCompleted: true,
              rir: 2,
              rpe: 8,
            ),
          ],
        ),
      ],
    );
    final body = BodyLog(
      id: 'body-1',
      date: DateTime(2026, 8, 25),
      bodyWeight: 79.5,
      sleepHours: 8,
      readiness: 8,
    );

    await store.migrateLegacyData(
      schedules: [schedule],
      history: [session],
      currentSession: session,
      bodyLogs: [body],
      customExercises: [planExercise],
      favoriteExerciseIds: {'bench-plan'},
    );

    final data = await store.loadAll();
    expect(await store.migrationComplete, isTrue);
    expect(data.schedules.single.id, 'push');
    expect(data.schedules.single.exercises.single.restSeconds, 180);
    expect(data.history.single.exercises.single.sets.single.rir, 2);
    expect(data.currentSession?.id, 'session-1');
    expect(data.bodyLogs.single.bodyWeight, 79.5);
    expect(data.customExercises.single.id, 'bench-plan');
    expect(data.favoriteExerciseIds, contains('bench-plan'));
  });

  test('current-session writes do not require rewriting history', () async {
    final store = LocalSqliteStore(
      factoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(store.close);
    final history = _session('history', 70);
    final current = _session('current', 80);
    await store.replaceHistory([history]);
    await store.saveCurrentSession(current);
    await store.saveCurrentSession(_session('current', 82.5));

    expect((await store.loadHistory()).single.id, 'history');
    expect(
      (await store.loadCurrentSession())!.exercises.single.sets.single.weight,
      82.5,
    );
  });
}

WorkoutSession _session(String id, double weight) {
  return WorkoutSession(
    id: id,
    scheduleTitle: 'Push',
    startTime: DateTime(2026, 8, 25, 18),
    endTime: DateTime(2026, 8, 25, 19),
    exercises: [
      WorkoutExercise(
        name: 'Panca',
        notes: '',
        technique: IntensityTechnique.none,
        sets: [ExerciseSet(weight: weight, reps: 8, isCompleted: true)],
      ),
    ],
  );
}
''')

# Widget-level confirmation test and service preservation test appended to existing suite.
ai_test_path = Path('test/ai_coach_test.dart')
ai_test = ai_test_path.read_text()
ai_test = replace_once(
    ai_test,
    "import 'package:gymapp/ai_coach/ai_coach_prompts.dart';\n",
    "import 'package:gymapp/ai_coach/ai_coach_prompts.dart';\nimport 'package:gymapp/ai_coach/ai_plan_action_service.dart';\n",
    'ai test plan import',
)
ai_test = replace_once(
    ai_test,
    "\n\n}\n\nWorkoutSession _session",
    r'''

  testWidgets('AI plan actions show a diff and apply only after confirmation', (tester) async {
    final exercise = Exercise(
      id: 'bench-plan',
      name: 'Panca',
      reps: 8,
      set: 3,
      notes: '',
      weight: 80,
      technique: IntensityTechnique.none,
    );
    final schedule = Schedule(
      id: 'push-plan',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026, 6, 1),
      exercises: [exercise],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AiCoachScreen(
          history: [
            _session(DateTime(2026, 6, 3), weight: 70),
            _session(DateTime(2026, 6, 10), weight: 80),
          ],
          schedules: [schedule],
          service: const _FakePlanActionService(),
          planActionService: const AiPlanActionService(),
          modelInstaller: const _FakeModelInstaller(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai-plan-actions')));
    await tester.pumpAndSettle();
    expect(find.textContaining('80 → 82.5'), findsOneWidget);
    expect(exercise.weight, 80);

    await tester.tap(find.byKey(const ValueKey('apply-plan-actions')));
    await tester.pumpAndSettle();
    expect(exercise.weight, 82.5);
  });

}

WorkoutSession _session''',
    'ai widget plan test',
)
ai_test += r'''

class _FakePlanActionService extends LocalAiCoachService {
  const _FakePlanActionService();

  @override
  Future<SuggestedAdjustmentReport> suggestWorkoutAdjustments({
    required List<WorkoutSession> history,
    required List<Schedule> schedules,
    List<BodyLog> bodyLogs = const [],
    AiCoachUserProfile profile = const AiCoachUserProfile(),
    AiCoachMemory memory = const AiCoachMemory(),
  }) async {
    return const SuggestedAdjustmentReport(
      suggestions: [
        SuggestedAdjustment(
          type: 'load_progression',
          target: 'Panca',
          suggestion: 'Aumenta di 2.5 kg',
          reason: 'RIR stabile e readiness adeguata',
          evidence: ['deterministic progression'],
          confidence: 'high',
          requiresUserConfirmation: true,
          proposedActions: [
            ProposedPlanAction(
              action: 'increase_load',
              target: 'Panca',
              field: 'weight',
              currentValue: '80',
              suggestedValue: '82.5',
              rationale: 'Piccolo incremento',
              scheduleId: 'push-plan',
              exerciseId: 'bench-plan',
            ),
          ],
        ),
      ],
    );
  }
}
'''
ai_test_path.write_text(ai_test)
