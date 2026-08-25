import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AiCoachUserProfile {
  final int? age;
  final double? heightCm;
  final String sex;
  final String experienceLevel;
  final String primaryGoal;
  final int? daysAvailable;
  final int? sessionMinutes;
  final String equipment;
  final String preferredExercises;
  final String avoidedExercises;
  final String limitations;
  final String notes;

  const AiCoachUserProfile({
    this.age,
    this.heightCm,
    this.sex = '',
    this.experienceLevel = '',
    this.primaryGoal = '',
    this.daysAvailable,
    this.sessionMinutes,
    this.equipment = '',
    this.preferredExercises = '',
    this.avoidedExercises = '',
    this.limitations = '',
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
    'age': age,
    'height_cm': heightCm,
    'sex': sex,
    'experience_level': experienceLevel,
    'primary_goal': primaryGoal,
    'days_available': daysAvailable,
    'session_minutes': sessionMinutes,
    'equipment': equipment,
    'preferred_exercises': preferredExercises,
    'avoided_exercises': avoidedExercises,
    'limitations': limitations,
    'notes': notes,
  };

  factory AiCoachUserProfile.fromJson(Map<String, dynamic> json) =>
      AiCoachUserProfile(
        age: (json['age'] as num?)?.toInt(),
        heightCm: (json['height_cm'] as num?)?.toDouble(),
        sex: json['sex']?.toString() ?? '',
        experienceLevel: json['experience_level']?.toString() ?? '',
        primaryGoal: json['primary_goal']?.toString() ?? '',
        daysAvailable: (json['days_available'] as num?)?.toInt(),
        sessionMinutes: (json['session_minutes'] as num?)?.toInt(),
        equipment: json['equipment']?.toString() ?? '',
        preferredExercises: json['preferred_exercises']?.toString() ?? '',
        avoidedExercises: json['avoided_exercises']?.toString() ?? '',
        limitations: json['limitations']?.toString() ?? '',
        notes: json['notes']?.toString() ?? '',
      );
}

class AiCoachProfileStore {
  static const _key = 'ai_coach_user_profile_v1';

  const AiCoachProfileStore();

  Future<AiCoachUserProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const AiCoachUserProfile();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? AiCoachUserProfile.fromJson(Map<String, dynamic>.from(decoded))
          : const AiCoachUserProfile();
    } catch (_) {
      return const AiCoachUserProfile();
    }
  }

  Future<void> save(AiCoachUserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(profile.toJson()));
  }
}
