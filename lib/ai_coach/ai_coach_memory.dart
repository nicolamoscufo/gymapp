import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AiCoachMemory {
  final List<String> preferences;
  final List<String> cautions;
  final String summary;

  const AiCoachMemory({
    this.preferences = const [],
    this.cautions = const [],
    this.summary = '',
  });

  Map<String, dynamic> toJson() => {
    'preferences': preferences,
    'cautions': cautions,
    'summary': summary,
  };

  factory AiCoachMemory.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) =>
        (value as List? ?? const []).map((item) => item.toString()).toList();
    return AiCoachMemory(
      preferences: strings(json['preferences']),
      cautions: strings(json['cautions']),
      summary: json['summary']?.toString() ?? '',
    );
  }
}

class AiCoachMemoryStore {
  static const _key = 'aiCoachMemory';

  const AiCoachMemoryStore();

  Future<AiCoachMemory> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const AiCoachMemory();
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
