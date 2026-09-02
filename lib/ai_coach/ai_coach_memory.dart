import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AiCoachMemory {
  final List<String> recurringPreferences;
  final List<String> recurringLimitations;
  final List<String> coachingNotes;

  const AiCoachMemory({
    this.recurringPreferences = const [],
    this.recurringLimitations = const [],
    this.coachingNotes = const [],
  });

  bool get isEmpty =>
      recurringPreferences.isEmpty &&
      recurringLimitations.isEmpty &&
      coachingNotes.isEmpty;

  Map<String, dynamic> toJson() => {
    'recurring_preferences': recurringPreferences,
    'recurring_limitations': recurringLimitations,
    'coaching_notes': coachingNotes,
  };

  factory AiCoachMemory.fromJson(Map<String, dynamic> json) => AiCoachMemory(
    recurringPreferences: _stringList(json['recurring_preferences']),
    recurringLimitations: _stringList(json['recurring_limitations']),
    coachingNotes: _stringList(json['coaching_notes']),
  );
}

class AiCoachMemoryStore {
  static const _key = 'ai_coach_memory_v1';

  const AiCoachMemoryStore();

  Future<bool> hasStoredValue() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key);
  }

  Future<AiCoachMemory> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const AiCoachMemory();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? AiCoachMemory.fromJson(Map<String, dynamic>.from(decoded))
          : const AiCoachMemory();
    } catch (_) {
      return const AiCoachMemory();
    }
  }

  Future<void> save(AiCoachMemory memory) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(memory.toJson()));
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((entry) => entry.toString().trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}
