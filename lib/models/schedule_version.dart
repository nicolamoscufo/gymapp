import 'dart:convert';

import 'model_id.dart';
import 'schedule.dart';

enum ScheduleVersionSource { migration, user, aiCoach, import, system }

extension ScheduleVersionSourceLabel on ScheduleVersionSource {
  String get label => switch (this) {
    ScheduleVersionSource.migration => 'Migrazione',
    ScheduleVersionSource.user => 'Utente',
    ScheduleVersionSource.aiCoach => 'AI Coach',
    ScheduleVersionSource.import => 'Import',
    ScheduleVersionSource.system => 'Sistema',
  };
}

class ScheduleVersion {
  final String id;
  final String scheduleId;
  final int versionNumber;
  final DateTime createdAt;
  final ScheduleVersionSource source;
  final String? parentVersionId;
  final String reason;
  final Map<String, dynamic> snapshot;

  ScheduleVersion({
    String? id,
    required this.scheduleId,
    required this.versionNumber,
    required this.createdAt,
    required this.source,
    this.parentVersionId,
    this.reason = '',
    required Map<String, dynamic> snapshot,
  }) : id = id ?? newModelId('schedule_version'),
       snapshot = _deepCopyMap(snapshot);

  factory ScheduleVersion.capture({
    required Schedule schedule,
    required int versionNumber,
    required DateTime createdAt,
    required ScheduleVersionSource source,
    String? parentVersionId,
    String reason = '',
  }) {
    return ScheduleVersion(
      scheduleId: schedule.id,
      versionNumber: versionNumber,
      createdAt: createdAt,
      source: source,
      parentVersionId: parentVersionId,
      reason: reason,
      snapshot: canonicalScheduleSnapshot(schedule),
    );
  }

  bool matchesSchedule(Schedule schedule) {
    if (schedule.id != scheduleId) return false;
    return jsonEncode(snapshot) == jsonEncode(canonicalScheduleSnapshot(schedule));
  }

  Schedule restoreSchedule() => Schedule.fromJson(_deepCopyMap(snapshot));

  Map<String, dynamic> toJson() => {
    'id': id,
    'scheduleId': scheduleId,
    'versionNumber': versionNumber,
    'createdAt': createdAt.toIso8601String(),
    'source': source.name,
    'parentVersionId': parentVersionId,
    'reason': reason,
    'snapshot': _deepCopyMap(snapshot),
  };

  factory ScheduleVersion.fromJson(Map<String, dynamic> json) {
    ScheduleVersionSource source;
    try {
      source = ScheduleVersionSource.values.byName(
        json['source'] as String? ?? ScheduleVersionSource.system.name,
      );
    } catch (_) {
      source = ScheduleVersionSource.system;
    }

    return ScheduleVersion(
      id: json['id'] as String?,
      scheduleId: json['scheduleId'] as String,
      versionNumber: (json['versionNumber'] as num?)?.toInt() ?? 1,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime(1970),
      source: source,
      parentVersionId: json['parentVersionId'] as String?,
      reason: json['reason'] as String? ?? '',
      snapshot: Map<String, dynamic>.from(json['snapshot'] as Map? ?? const {}),
    );
  }
}

Map<String, dynamic> canonicalScheduleSnapshot(Schedule schedule) {
  final snapshot = _deepCopyMap(schedule.toJson());
  snapshot.remove('currentVersionId');
  snapshot.remove('currentVersionNumber');
  return snapshot;
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) {
  return Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map);
}
