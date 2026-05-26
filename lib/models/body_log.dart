import 'model_id.dart';

class BodyLog {
  final String id;
  DateTime date;
  double? bodyWeight;
  double? waist;
  double? chest;
  double? arm;
  double? thigh;
  int? sleepHours;
  int? readiness;
  String notes;

  BodyLog({
    String? id,
    required this.date,
    this.bodyWeight,
    this.waist,
    this.chest,
    this.arm,
    this.thigh,
    this.sleepHours,
    this.readiness,
    this.notes = '',
  }) : id = id ?? newModelId('body_log');

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'bodyWeight': bodyWeight,
    'waist': waist,
    'chest': chest,
    'arm': arm,
    'thigh': thigh,
    'sleepHours': sleepHours,
    'readiness': readiness,
    'notes': notes,
  };

  factory BodyLog.fromJson(Map<String, dynamic> json) => BodyLog(
    id: json['id'] as String?,
    date: DateTime.parse(json['date'] as String),
    bodyWeight: (json['bodyWeight'] as num?)?.toDouble(),
    waist: (json['waist'] as num?)?.toDouble(),
    chest: (json['chest'] as num?)?.toDouble(),
    arm: (json['arm'] as num?)?.toDouble(),
    thigh: (json['thigh'] as num?)?.toDouble(),
    sleepHours: json['sleepHours'] as int?,
    readiness: json['readiness'] as int?,
    notes: json['notes'] as String? ?? '',
  );
}
