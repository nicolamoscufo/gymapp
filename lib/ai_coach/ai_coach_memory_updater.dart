import 'ai_coach_memory.dart';

class AiCoachMemoryUpdater {
  final AiCoachMemoryStore store;

  const AiCoachMemoryUpdater({this.store = const AiCoachMemoryStore()});

  static const int _maxEntriesPerBucket = 8;
  static const int _maxEntryLength = 180;

  Future<AiCoachMemory> updateFromUserText(
    String text, {
    AiCoachMemory current = const AiCoachMemory(),
  }) async {
    final hasPersistedMemory = await store.hasStoredValue();
    var memory = hasPersistedMemory ? await store.load() : current;
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) return memory;

    final lower = normalizedText.toLowerCase();
    if (_clearAllMarkers.any(lower.contains)) {
      memory = const AiCoachMemory();
      await store.save(memory);
      return memory;
    }

    final forgetMatch = RegExp(
      r'^(?:dimentica|scorda|rimuovi dalla memoria)\s+(?:che\s+)?(.+)$',
      caseSensitive: false,
    ).firstMatch(normalizedText);
    if (forgetMatch != null) {
      final target = _clean(forgetMatch.group(1) ?? '');
      if (target.isNotEmpty) {
        memory = AiCoachMemory(
          recurringPreferences: _removeMatching(
            memory.recurringPreferences,
            target,
          ),
          recurringLimitations: _removeMatching(
            memory.recurringLimitations,
            target,
          ),
          coachingNotes: _removeMatching(memory.coachingNotes, target),
        );
        await store.save(memory);
      }
      return memory;
    }

    final preferences = [...memory.recurringPreferences];
    final limitations = [...memory.recurringLimitations];
    final notes = [...memory.coachingNotes];

    for (final sentence in _sentences(normalizedText)) {
      final preference = _extract(sentence, _preferencePatterns);
      if (preference != null) _appendUnique(preferences, preference);

      final limitation = _extract(sentence, _limitationPatterns);
      if (limitation != null) _appendUnique(limitations, limitation);

      final explicitNote = _extract(sentence, _explicitMemoryPatterns);
      if (explicitNote != null &&
          preference == null &&
          limitation == null) {
        _appendUnique(notes, explicitNote);
      }
    }

    final updated = AiCoachMemory(
      recurringPreferences: _bounded(preferences),
      recurringLimitations: _bounded(limitations),
      coachingNotes: _bounded(notes),
    );

    if (!_sameMemory(memory, updated)) {
      await store.save(updated);
    }
    return updated;
  }

  Iterable<String> _sentences(String text) sync* {
    // Commas and semicolons are useful clause boundaries for requests such as
    // "Creami una upper/lower, preferisco i manubri". This lets explicit
    // memory declarations be captured without treating the surrounding request
    // as memory.
    for (final raw in text.split(RegExp(r'[\n.!?;,]+'))) {
      final value = _clean(raw);
      if (value.isNotEmpty) yield value;
    }
  }

  String? _extract(String sentence, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(sentence);
      if (match == null) continue;
      final value = _clean(match.group(1) ?? '');
      if (value.length < 3) continue;
      return value;
    }
    return null;
  }

  String _clean(String value) {
    var cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    cleaned = cleaned.replaceFirst(RegExp(r'^[,:;\-\s]+'), '');
    if (cleaned.length > _maxEntryLength) {
      cleaned = cleaned.substring(0, _maxEntryLength).trim();
    }
    return cleaned;
  }

  void _appendUnique(List<String> target, String value) {
    final cleaned = _clean(value);
    if (cleaned.isEmpty) return;
    final key = cleaned.toLowerCase();
    if (target.any((entry) => entry.toLowerCase() == key)) return;
    target.add(cleaned);
  }

  List<String> _bounded(List<String> values) {
    if (values.length <= _maxEntriesPerBucket) return List.of(values);
    return values.sublist(values.length - _maxEntriesPerBucket);
  }

  List<String> _removeMatching(List<String> source, String target) {
    final needle = target.toLowerCase();
    return source
        .where((entry) {
          final haystack = entry.toLowerCase();
          return !haystack.contains(needle) && !needle.contains(haystack);
        })
        .toList();
  }

  bool _sameMemory(AiCoachMemory a, AiCoachMemory b) {
    return _sameList(a.recurringPreferences, b.recurringPreferences) &&
        _sameList(a.recurringLimitations, b.recurringLimitations) &&
        _sameList(a.coachingNotes, b.coachingNotes);
  }

  bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static final List<RegExp> _preferencePatterns = [
    RegExp(r'^(?:io\s+)?preferisco\s+(.+)$', caseSensitive: false),
    RegExp(r'^(?:io\s+)?mi trovo meglio con\s+(.+)$', caseSensitive: false),
    RegExp(r'^(?:io\s+)?mi piace(?:rebbe)?\s+(.+)$', caseSensitive: false),
    RegExp(
      r'^(?:io\s+)?voglio dare priorità\s+((?:a|al|alla|ai|agli|alle)\s+.+)$',
      caseSensitive: false,
    ),
    RegExp(
      r'^(?:io\s+)?voglio dare priorita\s+((?:a|al|alla|ai|agli|alle)\s+.+)$',
      caseSensitive: false,
    ),
  ];

  static final List<RegExp> _limitationPatterns = [
    RegExp(r'^(?:io\s+)?evito\s+(.+)$', caseSensitive: false),
    RegExp(r'^(?:io\s+)?non voglio fare\s+(.+)$', caseSensitive: false),
    RegExp(r'^(?:io\s+)?non posso fare\s+(.+)$', caseSensitive: false),
    RegExp(r'^(?:io\s+)?non mi trovo bene con\s+(.+)$', caseSensitive: false),
  ];

  static final List<RegExp> _explicitMemoryPatterns = [
    RegExp(r'^(?:ricorda|ricordati) che\s+(.+)$', caseSensitive: false),
    RegExp(r'^tieni a mente che\s+(.+)$', caseSensitive: false),
    RegExp(r'^memorizza che\s+(.+)$', caseSensitive: false),
  ];

  static const List<String> _clearAllMarkers = [
    'cancella tutta la memoria del coach',
    'dimentica tutto quello che ricordi',
    'azzera la memoria del coach',
  ];
}
