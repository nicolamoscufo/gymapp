import 'models/schedule.dart';
import 'models/schedule_version.dart';

class ScheduleVersionReconciliation {
  final List<ScheduleVersion> versions;
  final List<ScheduleVersion> created;
  final bool pointersChanged;

  const ScheduleVersionReconciliation({
    required this.versions,
    required this.created,
    required this.pointersChanged,
  });

  bool get changed => created.isNotEmpty || pointersChanged;
}

ScheduleVersionReconciliation reconcileScheduleVersions({
  required List<Schedule> schedules,
  required List<ScheduleVersion> existingVersions,
  required ScheduleVersionSource source,
  String reason = '',
  DateTime Function()? now,
}) {
  final clock = now ?? DateTime.now;
  final versions = List<ScheduleVersion>.from(existingVersions);
  final created = <ScheduleVersion>[];
  var pointersChanged = false;

  for (final schedule in schedules) {
    final scheduleVersions =
        versions.where((version) => version.scheduleId == schedule.id).toList()
          ..sort((a, b) {
            final byNumber = a.versionNumber.compareTo(b.versionNumber);
            if (byNumber != 0) return byNumber;
            return a.createdAt.compareTo(b.createdAt);
          });

    final latest = scheduleVersions.isEmpty ? null : scheduleVersions.last;
    ScheduleVersion effective;
    if (latest == null || !latest.matchesSchedule(schedule)) {
      effective = ScheduleVersion.capture(
        schedule: schedule,
        versionNumber: (latest?.versionNumber ?? 0) + 1,
        createdAt: clock(),
        source: source,
        parentVersionId: latest?.id,
        reason: reason,
      );
      versions.add(effective);
      created.add(effective);
    } else {
      effective = latest;
    }

    if (schedule.currentVersionId != effective.id ||
        schedule.currentVersionNumber != effective.versionNumber) {
      schedule.currentVersionId = effective.id;
      schedule.currentVersionNumber = effective.versionNumber;
      pointersChanged = true;
    }
  }

  versions.sort((a, b) {
    final bySchedule = a.scheduleId.compareTo(b.scheduleId);
    if (bySchedule != 0) return bySchedule;
    final byNumber = a.versionNumber.compareTo(b.versionNumber);
    if (byNumber != 0) return byNumber;
    return a.createdAt.compareTo(b.createdAt);
  });

  return ScheduleVersionReconciliation(
    versions: List.unmodifiable(versions),
    created: List.unmodifiable(created),
    pointersChanged: pointersChanged,
  );
}

/// Combines two historical program timelines without losing stable version IDs.
///
/// Exact version IDs already present locally win over an imported duplicate.
/// For every schedule the surviving versions are ordered chronologically and
/// re-numbered into one deterministic chain. IDs are intentionally preserved:
/// completed workouts may already point at them through `scheduleVersionId`.
List<ScheduleVersion> mergeScheduleVersionHistories({
  required List<ScheduleVersion> current,
  required List<ScheduleVersion> incoming,
}) {
  final byId = <String, ScheduleVersion>{};
  for (final version in current) {
    byId[version.id] = version;
  }
  for (final version in incoming) {
    byId.putIfAbsent(version.id, () => version);
  }

  final grouped = <String, List<ScheduleVersion>>{};
  for (final version in byId.values) {
    grouped.putIfAbsent(version.scheduleId, () => []).add(version);
  }

  final merged = <ScheduleVersion>[];
  final scheduleIds = grouped.keys.toList()..sort();
  for (final scheduleId in scheduleIds) {
    final versions = grouped[scheduleId]!
      ..sort((a, b) {
        final byDate = a.createdAt.compareTo(b.createdAt);
        if (byDate != 0) return byDate;
        final byNumber = a.versionNumber.compareTo(b.versionNumber);
        if (byNumber != 0) return byNumber;
        return a.id.compareTo(b.id);
      });

    String? parentVersionId;
    for (var index = 0; index < versions.length; index += 1) {
      final version = versions[index];
      final normalized = ScheduleVersion(
        id: version.id,
        scheduleId: scheduleId,
        versionNumber: index + 1,
        createdAt: version.createdAt,
        source: version.source,
        parentVersionId: parentVersionId,
        reason: version.reason,
        snapshot: version.snapshot,
      );
      merged.add(normalized);
      parentVersionId = normalized.id;
    }
  }

  return List.unmodifiable(merged);
}

ScheduleVersion? latestScheduleVersion(
  Iterable<ScheduleVersion> versions,
  String scheduleId,
) {
  ScheduleVersion? latest;
  for (final version in versions) {
    if (version.scheduleId != scheduleId) continue;
    if (latest == null ||
        version.versionNumber > latest.versionNumber ||
        (version.versionNumber == latest.versionNumber &&
            version.createdAt.isAfter(latest.createdAt))) {
      latest = version;
    }
  }
  return latest;
}
