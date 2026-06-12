import 'dart:convert';
import 'dart:typed_data';

enum AiCoachTask {
  workoutRecap,
  weeklyReport,
  weakPointAnalysis,
  notesSummary,
  suggestedAdjustments,
  bodyPhotoAnalysis,
  freeChat,
}

extension AiCoachTaskLabel on AiCoachTask {
  String get promptName {
    return switch (this) {
      AiCoachTask.workoutRecap => 'workout_recap',
      AiCoachTask.weeklyReport => 'weekly_report',
      AiCoachTask.weakPointAnalysis => 'weak_point_analysis',
      AiCoachTask.notesSummary => 'notes_summary',
      AiCoachTask.suggestedAdjustments => 'suggested_adjustments',
      AiCoachTask.bodyPhotoAnalysis => 'body_photo_analysis',
      AiCoachTask.freeChat => 'free_chat',
    };
  }

  String get title {
    return switch (this) {
      AiCoachTask.workoutRecap => 'Workout Recap',
      AiCoachTask.weeklyReport => 'Weekly Report',
      AiCoachTask.weakPointAnalysis => 'Weak Point Analysis',
      AiCoachTask.notesSummary => 'Notes Summary',
      AiCoachTask.suggestedAdjustments => 'Suggestions',
      AiCoachTask.bodyPhotoAnalysis => 'Physique Photo Analysis',
      AiCoachTask.freeChat => 'Chat',
    };
  }
}

class AiCoachImageInput {
  final String label;
  final Uint8List bytes;

  const AiCoachImageInput({required this.label, required this.bytes});

  Map<String, dynamic> toContextJson() => {
    'label': label,
    'bytes': bytes.length,
  };
}

class AiCoachInsufficientDataException implements Exception {
  final String message;

  const AiCoachInsufficientDataException(this.message);

  @override
  String toString() => message;
}

class WorkoutRecap {
  final String summary;
  final List<String> positivePoints;
  final List<String> negativePoints;
  final String noteSummary;
  final List<String> warnings;
  final List<String> nextSessionFocus;

  const WorkoutRecap({
    required this.summary,
    required this.positivePoints,
    required this.negativePoints,
    required this.noteSummary,
    required this.warnings,
    required this.nextSessionFocus,
  });

  factory WorkoutRecap.fromJson(Map<String, dynamic> json) {
    return WorkoutRecap(
      summary: _string(json['summary']),
      positivePoints: _stringList(json['positive_points']),
      negativePoints: _stringList(json['negative_points']),
      noteSummary: _string(json['note_summary']),
      warnings: _stringList(json['warnings']),
      nextSessionFocus: _stringList(json['next_session_focus']),
    );
  }

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'positive_points': positivePoints,
    'negative_points': negativePoints,
    'note_summary': noteSummary,
    'warnings': warnings,
    'next_session_focus': nextSessionFocus,
  };
}

class WeeklyTrainingReport {
  final String summary;
  final int sessionsCompleted;
  final List<String> mainImprovements;
  final List<String> possibleWeakPoints;
  final List<String> stalledExercises;
  final List<String> bestProgressions;
  final List<String> recoveryNotes;
  final List<String> practicalSuggestions;

  const WeeklyTrainingReport({
    required this.summary,
    required this.sessionsCompleted,
    required this.mainImprovements,
    required this.possibleWeakPoints,
    required this.stalledExercises,
    required this.bestProgressions,
    required this.recoveryNotes,
    required this.practicalSuggestions,
  });

  factory WeeklyTrainingReport.fromJson(Map<String, dynamic> json) {
    return WeeklyTrainingReport(
      summary: _string(json['summary']),
      sessionsCompleted: _integer(json['sessions_completed']),
      mainImprovements: _stringList(json['main_improvements']),
      possibleWeakPoints: _stringList(json['possible_weak_points']),
      stalledExercises: _stringList(json['stalled_exercises']),
      bestProgressions: _stringList(json['best_progressions']),
      recoveryNotes: _stringList(json['recovery_notes']),
      practicalSuggestions: _stringList(json['practical_suggestions']),
    );
  }

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'sessions_completed': sessionsCompleted,
    'main_improvements': mainImprovements,
    'possible_weak_points': possibleWeakPoints,
    'stalled_exercises': stalledExercises,
    'best_progressions': bestProgressions,
    'recovery_notes': recoveryNotes,
    'practical_suggestions': practicalSuggestions,
  };
}

class WeakPointAnalysis {
  final List<WeakPoint> weakPoints;

  const WeakPointAnalysis({required this.weakPoints});

  factory WeakPointAnalysis.fromJson(Map<String, dynamic> json) {
    return WeakPointAnalysis(
      weakPoints: (json['weak_points'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => WeakPoint.fromJson(Map<String, dynamic>.from(entry)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'weak_points': weakPoints.map((entry) => entry.toJson()).toList(),
  };
}

class WeakPoint {
  final String area;
  final String reason;
  final List<String> evidence;
  final String suggestion;

  const WeakPoint({
    required this.area,
    required this.reason,
    required this.evidence,
    required this.suggestion,
  });

  factory WeakPoint.fromJson(Map<String, dynamic> json) {
    return WeakPoint(
      area: _string(json['area']),
      reason: _string(json['reason']),
      evidence: _stringList(json['evidence']),
      suggestion: _string(json['suggestion']),
    );
  }

  Map<String, dynamic> toJson() => {
    'area': area,
    'reason': reason,
    'evidence': evidence,
    'suggestion': suggestion,
  };
}

class NotesSummary {
  final String summary;
  final List<String> recurringThemes;
  final List<String> importantNotes;
  final String sentiment;

  const NotesSummary({
    required this.summary,
    required this.recurringThemes,
    required this.importantNotes,
    required this.sentiment,
  });

  factory NotesSummary.fromJson(Map<String, dynamic> json) {
    return NotesSummary(
      summary: _string(json['summary']),
      recurringThemes: _stringList(json['recurring_themes']),
      importantNotes: _stringList(json['important_notes']),
      sentiment: _string(json['sentiment']).isEmpty
          ? 'neutral'
          : _string(json['sentiment']),
    );
  }

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'recurring_themes': recurringThemes,
    'important_notes': importantNotes,
    'sentiment': sentiment,
  };
}

class SuggestedAdjustmentReport {
  final List<SuggestedAdjustment> suggestions;

  const SuggestedAdjustmentReport({required this.suggestions});

  factory SuggestedAdjustmentReport.fromJson(Map<String, dynamic> json) {
    return SuggestedAdjustmentReport(
      suggestions: (json['suggestions'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (entry) =>
                SuggestedAdjustment.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'suggestions': suggestions.map((entry) => entry.toJson()).toList(),
  };
}

class SuggestedAdjustment {
  final String type;
  final String target;
  final String suggestion;
  final String reason;
  final List<String> evidence;
  final String confidence;
  final bool requiresUserConfirmation;
  final List<ProposedPlanAction> proposedActions;

  const SuggestedAdjustment({
    required this.type,
    required this.target,
    required this.suggestion,
    required this.reason,
    required this.evidence,
    required this.confidence,
    required this.requiresUserConfirmation,
    this.proposedActions = const [],
  });

  factory SuggestedAdjustment.fromJson(Map<String, dynamic> json) {
    return SuggestedAdjustment(
      type: _string(json['type']),
      target: _string(json['target']),
      suggestion: _string(json['suggestion']),
      reason: _string(json['reason']),
      evidence: _stringList(json['evidence']),
      confidence: _string(json['confidence']).isEmpty
          ? 'low'
          : _string(json['confidence']),
      requiresUserConfirmation:
          json['requires_user_confirmation'] as bool? ?? true,
      proposedActions: (json['proposed_actions'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (entry) =>
                ProposedPlanAction.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'target': target,
    'suggestion': suggestion,
    'reason': reason,
    'evidence': evidence,
    'confidence': confidence,
    'requires_user_confirmation': requiresUserConfirmation,
    'proposed_actions': proposedActions.map((entry) => entry.toJson()).toList(),
  };
}

class ProposedPlanAction {
  final String action;
  final String target;
  final String field;
  final String currentValue;
  final String suggestedValue;
  final String rationale;

  const ProposedPlanAction({
    required this.action,
    required this.target,
    required this.field,
    required this.currentValue,
    required this.suggestedValue,
    required this.rationale,
  });

  factory ProposedPlanAction.fromJson(Map<String, dynamic> json) {
    return ProposedPlanAction(
      action: _string(json['action']),
      target: _string(json['target']),
      field: _string(json['field']),
      currentValue: _string(json['current_value']),
      suggestedValue: _string(json['suggested_value']),
      rationale: _string(json['rationale']),
    );
  }

  Map<String, dynamic> toJson() => {
    'action': action,
    'target': target,
    'field': field,
    'current_value': currentValue,
    'suggested_value': suggestedValue,
    'rationale': rationale,
  };
}

class BodyPhotoAnalysis {
  final String summary;
  final List<String> visibleChanges;
  final List<String> improvedAreas;
  final List<String> unchangedAreas;
  final List<String> cautions;
  final List<String> evidence;
  final List<String> nextCheckInTips;

  const BodyPhotoAnalysis({
    required this.summary,
    required this.visibleChanges,
    required this.improvedAreas,
    required this.unchangedAreas,
    required this.cautions,
    required this.evidence,
    required this.nextCheckInTips,
  });

  factory BodyPhotoAnalysis.fromJson(Map<String, dynamic> json) {
    return BodyPhotoAnalysis(
      summary: _string(json['summary']),
      visibleChanges: _stringList(json['visible_changes']),
      improvedAreas: _stringList(json['improved_areas']),
      unchangedAreas: _stringList(json['unchanged_areas']),
      cautions: _stringList(json['cautions']),
      evidence: _stringList(json['evidence']),
      nextCheckInTips: _stringList(json['next_checkin_tips']),
    );
  }

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'visible_changes': visibleChanges,
    'improved_areas': improvedAreas,
    'unchanged_areas': unchangedAreas,
    'cautions': cautions,
    'evidence': evidence,
    'next_checkin_tips': nextCheckInTips,
  };
}

Map<String, dynamic> decodeJsonObject(String raw) {
  final trimmed = _extractJsonObject(raw.trim());
  final decoded = jsonDecode(trimmed) as Object?;
  if (decoded is Map) {
    return Map<String, dynamic>.from(decoded);
  }
  throw const FormatException('Expected a JSON object.');
}

String _extractJsonObject(String raw) {
  final withoutFence = raw
      .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();
  if (withoutFence.startsWith('{') && withoutFence.endsWith('}')) {
    return withoutFence;
  }

  final start = withoutFence.indexOf('{');
  final end = withoutFence.lastIndexOf('}');
  if (start >= 0 && end > start) {
    return withoutFence.substring(start, end + 1);
  }
  return withoutFence;
}

String _string(Object? value) => value?.toString().trim() ?? '';

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }
  final single = _string(value);
  return single.isEmpty ? [] : [single];
}
