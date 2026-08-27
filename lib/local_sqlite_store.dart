import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'models/body_log.dart';
import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/schedule_version.dart';
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
        version: 3,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
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
        cycle_notes TEXT NOT NULL,
        current_version_id TEXT,
        current_version_number INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE schedule_exercises (
        id TEXT PRIMARY KEY,
        schedule_id TEXT NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        catalog_id TEXT,
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
      CREATE TABLE schedule_versions (
        id TEXT PRIMARY KEY,
        schedule_id TEXT NOT NULL,
        version_number INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        source TEXT NOT NULL,
        parent_version_id TEXT,
        reason TEXT NOT NULL,
        snapshot_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE workout_sessions (
        id TEXT PRIMARY KEY,
        session_kind TEXT NOT NULL,
        position INTEGER NOT NULL,
        schedule_id TEXT,
        schedule_version_id TEXT,
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
        catalog_id TEXT,
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
    await db.execute(
      'CREATE INDEX idx_schedule_exercises_schedule ON schedule_exercises(schedule_id, position)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_schedule_versions_number ON schedule_versions(schedule_id, version_number)',
    );
    await db.execute(
      'CREATE INDEX idx_workout_sessions_kind_time ON workout_sessions(session_kind, start_time)',
    );
    await db.execute(
      'CREATE INDEX idx_workout_exercises_session ON workout_exercises(session_id, position)',
    );
    await db.execute(
      'CREATE INDEX idx_exercise_sets_parent ON exercise_sets(workout_exercise_id, position)',
    );
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE schedules ADD COLUMN current_version_id TEXT',
      );
      await db.execute(
        'ALTER TABLE schedules ADD COLUMN current_version_number INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE workout_sessions ADD COLUMN schedule_version_id TEXT',
      );
      await db.execute('''
        CREATE TABLE schedule_versions (
          id TEXT PRIMARY KEY,
          schedule_id TEXT NOT NULL,
          version_number INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          source TEXT NOT NULL,
          parent_version_id TEXT,
          reason TEXT NOT NULL,
          snapshot_json TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE UNIQUE INDEX idx_schedule_versions_number ON schedule_versions(schedule_id, version_number)',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE schedule_exercises ADD COLUMN catalog_id TEXT',
      );
      await db.execute(
        'ALTER TABLE workout_exercises ADD COLUMN catalog_id TEXT',
      );
    }
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
    await db.insert('meta', {
      'key': 'legacy_migrated_v1',
      'value': '1',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> migrateLegacyData({
    required List<Schedule> schedules,
    required List<WorkoutSession> history,
    required WorkoutSession? currentSession,
    required List<BodyLog> bodyLogs,
    required List<Exercise> customExercises,
    required Set<String> favoriteExerciseIds,
    List<ScheduleVersion> scheduleVersions = const <ScheduleVersion>[],
  }) async {
    await replaceSchedules(schedules);
    await replaceScheduleVersions(scheduleVersions);
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

  Future<void> replaceScheduleState(
    List<Schedule> schedules,
    List<ScheduleVersion> versions,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('schedules');
      for (var i = 0; i < schedules.length; i += 1) {
        await _insertSchedule(txn, schedules[i], i);
      }
      await txn.delete('schedule_versions');
      for (final version in versions) {
        await _insertScheduleVersion(txn, version);
      }
    });
  }

  Future<void> replaceScheduleVersions(List<ScheduleVersion> versions) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('schedule_versions');
      for (final version in versions) {
        await _insertScheduleVersion(txn, version);
      }
    });
  }

  Future<void> _insertScheduleVersion(
    DatabaseExecutor db,
    ScheduleVersion version,
  ) async {
    await db.insert('schedule_versions', {
      'id': version.id,
      'schedule_id': version.scheduleId,
      'version_number': version.versionNumber,
      'created_at': version.createdAt.toIso8601String(),
      'source': version.source.name,
      'parent_version_id': version.parentVersionId,
      'reason': version.reason,
      'snapshot_json': jsonEncode(version.snapshot),
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
      'current_version_id': schedule.currentVersionId,
      'current_version_number': schedule.currentVersionNumber,
    });
    for (var i = 0; i < schedule.exercises.length; i += 1) {
      final exercise = schedule.exercises[i];
      await db.insert('schedule_exercises', {
        'id': exercise.id,
        'schedule_id': schedule.id,
        'position': i,
        'catalog_id': exercise.catalogId,
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
      await txn.delete(
        'workout_sessions',
        where: 'session_kind = ?',
        whereArgs: ['history'],
      );
      for (var i = 0; i < history.length; i += 1) {
        await _insertSession(txn, history[i], 'history', i);
      }
    });
  }

  Future<void> saveCurrentSession(WorkoutSession session) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'workout_sessions',
        where: 'session_kind = ?',
        whereArgs: ['current'],
      );
      await _insertSession(txn, session, 'current', 0);
    });
  }

  Future<void> clearCurrentSession() async {
    final db = await _db;
    await db.delete(
      'workout_sessions',
      where: 'session_kind = ?',
      whereArgs: ['current'],
    );
  }

  Future<void> _insertSession(
    DatabaseExecutor db,
    WorkoutSession session,
    String kind,
    int position,
  ) async {
    // A completed session can have the same id as the last autosaved current
    // session. Remove it first so FK children cannot become stale.
    await db.delete(
      'workout_sessions',
      where: 'id = ?',
      whereArgs: [session.id],
    );
    await db.insert('workout_sessions', {
      'id': session.id,
      'session_kind': kind,
      'position': position,
      'schedule_id': session.scheduleId,
      'schedule_version_id': session.scheduleVersionId,
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
        'catalog_id': exercise.catalogId,
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
        'active_rest_started_at': exercise.activeRestStartedAt
            ?.toIso8601String(),
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

  Future<
    ({
      List<Schedule> schedules,
      List<WorkoutSession> history,
      List<ScheduleVersion> scheduleVersions,
      WorkoutSession? currentSession,
      List<BodyLog> bodyLogs,
      List<Exercise> customExercises,
      Set<String> favoriteExerciseIds,
    })
  >
  loadAll() async {
    final schedules = await loadSchedules();
    final history = await loadHistory();
    final scheduleVersions = await loadScheduleVersions();
    final current = await loadCurrentSession();
    final bodyLogs = await loadBodyLogs();
    final custom = await loadCustomExercises();
    final favorites = await loadFavoriteExerciseIds();
    return (
      schedules: schedules,
      history: history,
      scheduleVersions: scheduleVersions,
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
          trainingWeekdays: (jsonDecode(
            row['training_weekdays_json'] as String,
          ) as List).whereType<num>().map((e) => e.toInt()).toList(),
          programBlock: row['program_block'] as String,
          cycleNumber: row['cycle_number'] as int,
          cycleNotes: row['cycle_notes'] as String,
          currentVersionId: row['current_version_id'] as String?,
          currentVersionNumber: row['current_version_number'] as int? ?? 0,
        ),
      );
    }
    return result;
  }

  Exercise _scheduleExerciseFromRow(Map<String, Object?> row) {
    return Exercise(
      id: row['id'] as String,
      catalogId: row['catalog_id'] as String?,
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
      backoffReductionPercent: (row['backoff_reduction_percent'] as num)
          .toDouble(),
      restSeconds: row['rest_seconds'] as int?,
      supersetGroup: row['superset_group'] as int?,
      progressionKgStep: (row['progression_kg_step'] as num).toDouble(),
      progressionRepStep: row['progression_rep_step'] as int,
      progressionScheme: progressionSchemeFromJson(row['progression_scheme']),
    );
  }

  Future<List<ScheduleVersion>> loadScheduleVersions() async {
    final db = await _db;
    final rows = await db.query(
      'schedule_versions',
      orderBy: 'schedule_id ASC, version_number ASC, created_at ASC',
    );
    return rows.map((row) {
      ScheduleVersionSource source;
      try {
        source = ScheduleVersionSource.values.byName(row['source'] as String);
      } catch (_) {
        source = ScheduleVersionSource.system;
      }
      return ScheduleVersion(
        id: row['id'] as String,
        scheduleId: row['schedule_id'] as String,
        versionNumber: row['version_number'] as int,
        createdAt: DateTime.parse(row['created_at'] as String),
        source: source,
        parentVersionId: row['parent_version_id'] as String?,
        reason: row['reason'] as String,
        snapshot: Map<String, dynamic>.from(
          jsonDecode(row['snapshot_json'] as String) as Map,
        ),
      );
    }).toList();
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
          scheduleVersionId: row['schedule_version_id'] as String?,
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
      catalogId: row['catalog_id'] as String?,
      name: row['name'] as String,
      notes: row['notes'] as String,
      muscleGroup: muscleGroupFromJson(row['muscle_group']),
      equipment: row['equipment'] as String,
      movementPattern: row['movement_pattern'] as String,
      targetMinReps: row['target_min_reps'] as int?,
      targetMaxReps: row['target_max_reps'] as int?,
      technique: _technique(row['technique']),
      backoffReductionPercent: (row['backoff_reduction_percent'] as num)
          .toDouble(),
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
      previousWeights: (jsonDecode(
        row['previous_weights_json'] as String,
      ) as List).whereType<num>().map((e) => e.toDouble()).toList(),
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
