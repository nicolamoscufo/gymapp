import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/active_workout_session_builder.dart';
import 'package:gymapp/app_data_store.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/schedule_version.dart';
import 'package:gymapp/schedule_version_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('reconciliation creates versions only for structural changes', () {
    final schedule = _schedule();
    final first = reconcileScheduleVersions(
      schedules: [schedule],
      existingVersions: const [],
      source: ScheduleVersionSource.migration,
      now: () => DateTime(2026, 8, 1),
    );

    expect(first.created.single.versionNumber, 1);
    expect(schedule.currentVersionId, first.created.single.id);
    expect(schedule.currentVersionNumber, 1);

    final unchanged = reconcileScheduleVersions(
      schedules: [schedule],
      existingVersions: first.versions,
      source: ScheduleVersionSource.user,
      now: () => DateTime(2026, 8, 2),
    );
    expect(unchanged.created, isEmpty);

    schedule.exercises.single.weight = 82.5;
    final changed = reconcileScheduleVersions(
      schedules: [schedule],
      existingVersions: first.versions,
      source: ScheduleVersionSource.aiCoach,
      reason: 'Approved coach change',
      now: () => DateTime(2026, 8, 3),
    );
    final second = changed.created.single;
    expect(second.versionNumber, 2);
    expect(second.parentVersionId, first.created.single.id);
    expect(second.source, ScheduleVersionSource.aiCoach);
    expect(second.restoreSchedule().exercises.single.weight, 82.5);
  });

  test(
    'import merge keeps stable version ids and builds one ordered chain',
    () {
      final schedule = _schedule();
      final local = ScheduleVersion.capture(
        schedule: schedule,
        versionNumber: 1,
        createdAt: DateTime(2026, 7, 1),
        source: ScheduleVersionSource.user,
      );
      schedule.exercises.single.weight = 82.5;
      final imported = ScheduleVersion.capture(
        schedule: schedule,
        versionNumber: 1,
        createdAt: DateTime(2026, 8, 1),
        source: ScheduleVersionSource.aiCoach,
      );
      final deletedSchedule = Schedule(
        id: 'old-program',
        title: 'Old',
        week: 1,
        createdAt: DateTime(2026, 5, 1),
        exercises: const [],
      );
      final historicalOnly = ScheduleVersion.capture(
        schedule: deletedSchedule,
        versionNumber: 1,
        createdAt: DateTime(2026, 5, 1),
        source: ScheduleVersionSource.import,
      );

      final merged = mergeScheduleVersionHistories(
        current: [local],
        incoming: [imported, historicalOnly],
      );
      final push = merged.where((entry) => entry.scheduleId == 'push').toList();

      expect(push.map((entry) => entry.id), [local.id, imported.id]);
      expect(push.map((entry) => entry.versionNumber), [1, 2]);
      expect(push.last.parentVersionId, local.id);
      expect(
        merged.any((entry) => entry.id == historicalOnly.id),
        isTrue,
        reason: 'Deleted schedules still belong to long-term program history',
      );
    },
  );

  test('legacy load backfills version one and persists the pointer', () async {
    final schedule = _schedule();
    SharedPreferences.setMockInitialValues({
      AppDataKeys.schedules: jsonEncode([schedule.toJson()]),
      AppDataKeys.history: '[]',
      AppDataKeys.bodyLogs: '[]',
    });

    final bundle = await AppDataStore.loadBundle();
    expect(bundle.scheduleVersions, hasLength(1));
    expect(
      bundle.scheduleVersions.single.source,
      ScheduleVersionSource.migration,
    );
    expect(bundle.schedules.single.currentVersionNumber, 1);
    expect(
      bundle.schedules.single.currentVersionId,
      bundle.scheduleVersions.single.id,
    );

    final prefs = await SharedPreferences.getInstance();
    final persisted =
        jsonDecode(prefs.getString(AppDataKeys.scheduleVersions)!) as List;
    expect(persisted, hasLength(1));
  });

  test(
    'saveSchedules creates v2 once and repeated save is idempotent',
    () async {
      final schedule = _schedule();
      await AppDataStore.saveSchedules([schedule]);
      var versions = await AppDataStore.loadScheduleVersions();
      expect(versions, hasLength(1));

      schedule.exercises.single.reps = 9;
      await AppDataStore.saveSchedules(
        [schedule],
        source: ScheduleVersionSource.aiCoach,
        reason: 'Coach proposal accepted',
      );
      versions = await AppDataStore.loadScheduleVersions();
      expect(versions, hasLength(2));
      expect(versions.last.versionNumber, 2);
      expect(versions.last.source, ScheduleVersionSource.aiCoach);

      await AppDataStore.saveSchedules([schedule]);
      expect(await AppDataStore.loadScheduleVersions(), hasLength(2));
    },
  );

  test('new workout binds to the exact current schedule version', () async {
    final schedule = _schedule();
    await AppDataStore.saveSchedules([schedule]);
    final persisted = (await AppDataStore.loadBundle()).schedules.single;
    final session = ActiveWorkoutSessionBuilder(
      history: const [],
      bodyLogs: const [],
      now: () => DateTime(2026, 8, 26, 18),
    ).buildFromSchedule(persisted);

    expect(session.scheduleVersionId, persisted.currentVersionId);
    expect(session.toJson()['scheduleVersionId'], isNotNull);
  });

  test('export payload includes historical schedule versions', () async {
    final schedule = _schedule();
    await AppDataStore.saveSchedules([schedule]);
    schedule.exercises.single.weight = 85;
    await AppDataStore.saveSchedules([schedule]);

    final payload = await AppDataStore.buildExportPayload(
      schedules: [schedule],
      history: const [],
      bodyLogs: const [],
    );
    expect(payload['version'], 6);
    expect(payload['scheduleVersions'], hasLength(2));
  });
}

Schedule _schedule() {
  return Schedule(
    id: 'push',
    title: 'Push',
    week: 1,
    createdAt: DateTime(2026, 8, 1),
    exercises: [
      Exercise(
        id: 'bench',
        name: 'Panca',
        reps: 8,
        set: 3,
        notes: '',
        weight: 80,
        muscleGroup: MuscleGroup.chest,
        technique: IntensityTechnique.none,
      ),
    ],
  );
}
