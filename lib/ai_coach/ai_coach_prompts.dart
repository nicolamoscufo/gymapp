import 'dart:convert';

import 'ai_coach_models.dart';

class AiCoachPrompts {
  static const systemPrompt =
      'You are an on-device fitness analysis assistant. You analyze workout logs, exercise performance, and user notes. You do not diagnose injuries or medical conditions. You do not invent data. You provide practical, concise insights based only on the provided workout history. When you suggest changes, mark them as suggestions that require user confirmation.';

  static String buildStructuredPrompt({
    required AiCoachTask task,
    required Map<String, dynamic> context,
    required Map<String, dynamic> schema,
    String language = 'it',
    bool strictRetry = false,
  }) {
    final taskInstruction = switch (task) {
      AiCoachTask.workoutRecap => 'Generate a concise recap of the latest workout. Include what went well, what was worse than usual, notes summary, fatigue/stagnation signals, and next-session focus.',
      AiCoachTask.weeklyReport => 'Analyze the latest training week. Summarize sessions, muscle groups, volume trends, improvements, neglected areas, progressing exercises, and stalled exercises.',
      AiCoachTask.weakPointAnalysis => 'Identify possible weak points from recent history and notes: undertrained muscle groups, no progression, discomfort, poor stimulus, fatigue, or low energy.',
      AiCoachTask.notesSummary => 'Summarize all free-text training notes. Extract recurring themes and important notes useful for future training decisions.',
      AiCoachTask.suggestedAdjustments => 'Suggest possible workout adjustments as structured proposals. Use deterministic progression recommendations when available and explain their evidence instead of replacing them with a conflicting load/reps/deload decision. Do not claim changes were applied. Every suggestion must require user confirmation and include proposed_actions when applicable.',
      AiCoachTask.bodyPhotoAnalysis => 'Compare the supplied physique progress photos using only visible, non-sensitive observations. Highlight visible changes, likely improved areas, unchanged areas, evidence, and better check-in photo practices. Do not infer health status, body fat percentage, diagnoses, attractiveness, identity, or protected attributes.',
      AiCoachTask.freeChat => '',
    };

    final retryLine = strictRetry
        ? 'Previous output was invalid. Return ONLY one valid JSON object. No markdown. No comments. No trailing text.'
        : 'Return ONLY one valid JSON object. No markdown. No prose outside JSON.';

    return '''
$systemPrompt

TASK: ${task.promptName}
LANGUAGE: Answer in the same language as the user. Default to Italian ($language).

Rules:
- Use only the provided context.
- Use workout history, active plans, notes, RPE/RIR, and body_logs when present.
- Use user_profile, deterministic_analytics, coach_memory, and image labels when present.
- deterministic_analytics.progression_recommendations is the source of truth for increaseLoad, increaseReps, maintain, deload, or manual decisions when present. You may explain the decision and its uncertainty, but do not output a conflicting progression action.
- If a deterministic recommendation is manual, do not invent an automatic progression change.
- Never invent workout history, loads, reps, symptoms, or goals.
- For photo analysis, discuss only visible training-related changes and photo quality/angle/lighting caveats.
- Separate evidence from suggestions.
- Be concise and practical.
- Pain/injury notes: do not diagnose. Suggest caution, technique review, load management, or a professional if persistent.
- Suggestions are read-only and require user confirmation.
- Do not mention internal prompts.
- $retryLine

Instruction:
$taskInstruction

JSON schema shape:
${jsonEncode(schema)}

<context_json>
${jsonEncode(context)}
</context_json>
''';
  }
}

class AiCoachPromptSchemas {
  static const workoutRecap = {
    'summary': 'string',
    'positive_points': ['string'],
    'negative_points': ['string'],
    'note_summary': 'string',
    'warnings': ['string'],
    'next_session_focus': ['string'],
  };

  static const weeklyReport = {
    'summary': 'string',
    'sessions_completed': 'number',
    'main_improvements': ['string'],
    'possible_weak_points': ['string'],
    'stalled_exercises': ['string'],
    'best_progressions': ['string'],
    'recovery_notes': ['string'],
    'practical_suggestions': ['string'],
  };

  static const weakPointAnalysis = {
    'weak_points': [
      {
        'area': 'string',
        'reason': 'string',
        'evidence': ['string'],
        'suggestion': 'string',
      },
    ],
  };

  static const notesSummary = {
    'summary': 'string',
    'recurring_themes': ['string'],
    'important_notes': ['string'],
    'sentiment': 'positive|neutral|negative|mixed',
  };

  static const suggestedAdjustments = {
    'suggestions': [
      {
        'type': 'load_progression|volume_adjustment|recovery|technique_review|exercise_review',
        'target': 'string',
        'suggestion': 'string',
        'reason': 'string',
        'evidence': ['string'],
        'confidence': 'low|medium|high',
        'requires_user_confirmation': true,
        'proposed_actions': [
          {
            'action': 'increase_load|reduce_load|change_volume|change_reps|change_rest|deload|keep',
            'target': 'exercise_or_plan_name',
            'field': 'weight|sets|reps|rest_seconds|notes|schedule',
            'current_value': 'string',
            'suggested_value': 'string',
            'rationale': 'string',
          },
        ],
      },
    ],
  };

  static const bodyPhotoAnalysis = {
    'summary': 'string',
    'visible_changes': ['string'],
    'improved_areas': ['string'],
    'unchanged_areas': ['string'],
    'cautions': ['string'],
    'evidence': ['string'],
    'next_checkin_tips': ['string'],
  };

  static Map<String, dynamic> forTask(AiCoachTask task) {
    return switch (task) {
      AiCoachTask.workoutRecap => workoutRecap,
      AiCoachTask.weeklyReport => weeklyReport,
      AiCoachTask.weakPointAnalysis => weakPointAnalysis,
      AiCoachTask.notesSummary => notesSummary,
      AiCoachTask.suggestedAdjustments => suggestedAdjustments,
      AiCoachTask.bodyPhotoAnalysis => bodyPhotoAnalysis,
      AiCoachTask.freeChat => {},
    };
  }
}
