import '../models/workout.dart';
import '../post_workout_debrief.dart';

class AiCoachLaunchContext {
  final String source;
  final String conversationTitle;
  final String userPrompt;
  final Map<String, dynamic> focusContext;

  const AiCoachLaunchContext({
    required this.source,
    required this.conversationTitle,
    required this.userPrompt,
    required this.focusContext,
  });

  factory AiCoachLaunchContext.postWorkout({
    required WorkoutSession session,
    required List<WorkoutSession> history,
    PostWorkoutDebrief? debrief,
  }) {
    final resolvedDebrief =
        debrief ?? buildPostWorkoutDebrief(session: session, history: history);
    final sameScheduleHistory = _sameScheduleHistory(session, history);
    final historyWindow = sameScheduleHistory.length <= 12
        ? sameScheduleHistory
        : sameScheduleHistory.sublist(sameScheduleHistory.length - 12);

    return AiCoachLaunchContext(
      source: 'post_workout_debrief',
      conversationTitle: 'Debrief · ${session.scheduleTitle}',
      userPrompt: 'Analizza questa seduta appena conclusa. Spiegami cosa è migliorato o peggiorato, interpreta volume, densità, e1RM, RIR/RPE e note, verifica le raccomandazioni deterministiche e dammi le 3 priorità più importanti per la prossima seduta. Se un dato non è sufficiente, dillo chiaramente.',
      focusContext: {
        'type': 'post_workout_debrief',
        'target_session_id': session.id,
        'target_session': session.toJson(),
        'deterministic_debrief': resolvedDebrief.toContextJson(),
        'previous_comparable_session': resolvedDebrief.previousComparableSession
            ?.toJson(),
        'same_schedule_history_count': sameScheduleHistory.length,
        'same_schedule_history_window': historyWindow
            .map((entry) => entry.toJson())
            .toList(),
        'context_contract': {
          'target_session_is_authoritative': true,
          'deterministic_metrics_are_authoritative': true,
          'use_broader_training_context_for_explanation': true,
          'never_invent_missing_values': true,
        },
      },
    );
  }
}

List<WorkoutSession> _sameScheduleHistory(
  WorkoutSession session,
  List<WorkoutSession> history,
) {
  final normalizedTitle = session.scheduleTitle.trim().toLowerCase();
  final matches = history.where((candidate) {
    if (candidate.id == session.id ||
        !candidate.endTime.isBefore(session.endTime)) {
      return false;
    }
    if (session.scheduleId != null) {
      return candidate.scheduleId == session.scheduleId;
    }
    return candidate.scheduleId == null &&
        candidate.scheduleTitle.trim().toLowerCase() == normalizedTitle;
  }).toList();
  matches.sort((a, b) => a.endTime.compareTo(b.endTime));
  return matches;
}
