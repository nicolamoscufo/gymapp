import 'exercise.dart';
import 'model_id.dart';

class Schedule {
  final String id;
  String title;
  int week;
  DateTime createdAt;
  List<Exercise> exercises;
  bool isArchived;
  int mesocycleWeeks;
  int deloadEveryWeeks;
  String goal;
  List<int> trainingWeekdays;
  String programBlock;
  int cycleNumber;
  String cycleNotes;

  Schedule({
    String? id,
    required this.title,
    required this.week,
    required this.createdAt,
    required this.exercises,
    this.isArchived = false,
    this.mesocycleWeeks = 8,
    this.deloadEveryWeeks = 4,
    this.goal = '',
    List<int>? trainingWeekdays,
    this.programBlock = '',
    this.cycleNumber = 1,
    this.cycleNotes = '',
  }) : trainingWeekdays = trainingWeekdays ?? [],
       id = id ?? newModelId('schedule');

  int currentWeek({DateTime? now}) {
    final elapsedDays = _startOfWeek(
      now ?? DateTime.now(),
    ).difference(_startOfWeek(createdAt)).inDays;
    final elapsedWeeks = elapsedDays < 0 ? 0 : elapsedDays ~/ 7;
    final calculatedWeek = week + elapsedWeeks;
    return calculatedWeek < 1 ? 1 : calculatedWeek;
  }

  bool isDeloadWeek({DateTime? now}) {
    if (deloadEveryWeeks <= 0) {
      return false;
    }

    return currentWeek(now: now) % deloadEveryWeeks == 0;
  }

  bool isPlannedOn(DateTime date) {
    return trainingWeekdays.contains(date.weekday);
  }

  void resetCycle({DateTime? now}) {
    week = 1;
    createdAt = now ?? DateTime.now();
  }

  void completeMesocycle({DateTime? now}) {
    cycleNumber = cycleNumber < 1 ? 1 : cycleNumber + 1;
    resetCycle(now: now);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'week': week,
    'createdAt': createdAt.toIso8601String(),
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'isArchived': isArchived,
    'mesocycleWeeks': mesocycleWeeks,
    'deloadEveryWeeks': deloadEveryWeeks,
    'goal': goal,
    'trainingWeekdays': trainingWeekdays,
    'programBlock': programBlock,
    'cycleNumber': cycleNumber,
    'cycleNotes': cycleNotes,
  };

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
    id: json['id'] as String?,
    title: json['title'],
    week: json['week'],
    createdAt: DateTime.parse(json['createdAt']),
    exercises:
        (json['exercises'] as List?)
            ?.map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    isArchived: json['isArchived'] as bool? ?? false,
    mesocycleWeeks: json['mesocycleWeeks'] as int? ?? 8,
    deloadEveryWeeks: json['deloadEveryWeeks'] as int? ?? 4,
    goal: json['goal'] as String? ?? '',
    trainingWeekdays: (json['trainingWeekdays'] as List? ?? const [])
        .whereType<num>()
        .map((day) => day.toInt())
        .where((day) => day >= 1 && day <= 7)
        .toList(),
    programBlock: json['programBlock'] as String? ?? '',
    cycleNumber: json['cycleNumber'] as int? ?? 1,
    cycleNotes: json['cycleNotes'] as String? ?? '',
  );
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _startOfWeek(DateTime date) {
  final normalized = _dateOnly(date);
  return normalized.subtract(Duration(days: normalized.weekday - 1));
}
