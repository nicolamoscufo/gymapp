from pathlib import Path

# ---------------------------------------------------------------------------
# Expose the existing deterministic period report builder.
# ---------------------------------------------------------------------------
path = Path('lib/progress_analytics.dart')
text = path.read_text()
anchor = "List<ExerciseProgressSummary> _buildExerciseSummaries(\n"
wrapper = r'''PeriodProgressReport buildPeriodProgressReport({
  required List<WorkoutSession> history,
  required List<PersonalRecordEvent> personalRecords,
  required DateTime start,
  required DateTime endExclusive,
}) {
  final sorted = List<WorkoutSession>.from(history)
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  return _buildPeriodReport(
    sorted,
    personalRecords,
    _dateOnly(start),
    _dateOnly(endExclusive),
  );
}

'''
if wrapper.strip() not in text:
    if anchor not in text:
        raise SystemExit('progress analytics anchor not found')
    text = text.replace(anchor, wrapper + anchor, 1)
path.write_text(text)

# ---------------------------------------------------------------------------
# Period / mesocycle comparison domain model.
# ---------------------------------------------------------------------------
Path('lib/progress_period_comparison.dart').write_text(r'''import 'dart:math' as math;

import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/workout.dart';
import 'progress_analytics.dart';

enum ProgressComparisonRange { fourWeeks, eightWeeks, threeMonths, mesocycle }

extension ProgressComparisonRangeLabel on ProgressComparisonRange {
  String get label => switch (this) {
    ProgressComparisonRange.fourWeeks => '4 settimane',
    ProgressComparisonRange.eightWeeks => '8 settimane',
    ProgressComparisonRange.threeMonths => '3 mesi',
    ProgressComparisonRange.mesocycle => 'Mesociclo',
  };
}

class ProgressComparisonWindow {
  final DateTime start;
  final DateTime endExclusive;

  const ProgressComparisonWindow({
    required this.start,
    required this.endExclusive,
  });

  int get durationDays => math.max(1, endExclusive.difference(start).inDays);
  double get durationWeeks => durationDays / 7.0;

  String get label {
    final end = endExclusive.subtract(const Duration(days: 1));
    return '${start.day}/${start.month}/${start.year} – ${end.day}/${end.month}/${end.year}';
  }
}

class PeriodStrengthShift {
  final String exerciseName;
  final MuscleGroup muscleGroup;
  final double previousBestEstimatedOneRepMax;
  final double currentBestEstimatedOneRepMax;
  final double changePercent;

  const PeriodStrengthShift({
    required this.exerciseName,
    required this.muscleGroup,
    required this.previousBestEstimatedOneRepMax,
    required this.currentBestEstimatedOneRepMax,
    required this.changePercent,
  });

  bool get improved => changePercent > 2;
  bool get declined => changePercent < -2;
}

class PeriodMuscleShift {
  final MuscleGroup muscleGroup;
  final int previousSets;
  final int currentSets;
  final double? changePercent;

  const PeriodMuscleShift({
    required this.muscleGroup,
    required this.previousSets,
    required this.currentSets,
    required this.changePercent,
  });

  bool get newlyActive => previousSets == 0 && currentSets > 0;
}

class ProgressPeriodComparison {
  final ProgressComparisonRange range;
  final ProgressComparisonWindow currentWindow;
  final ProgressComparisonWindow previousWindow;
  final PeriodProgressReport current;
  final PeriodProgressReport previous;
  final List<PeriodStrengthShift> strengthShifts;
  final List<PeriodMuscleShift> muscleShifts;
  final Schedule? schedule;

  const ProgressPeriodComparison({
    required this.range,
    required this.currentWindow,
    required this.previousWindow,
    required this.current,
    required this.previous,
    required this.strengthShifts,
    required this.muscleShifts,
    required this.schedule,
  });

  double get currentWorkoutsPerWeek =>
      current.workouts / currentWindow.durationWeeks;
  double get previousWorkoutsPerWeek =>
      previous.workouts / previousWindow.durationWeeks;
  int get improvedStrengthCount =>
      strengthShifts.where((entry) => entry.improved).length;
  int get declinedStrengthCount =>
      strengthShifts.where((entry) => entry.declined).length;
}

ProgressPeriodComparison? buildProgressPeriodComparison({
  required List<WorkoutSession> history,
  required ProgressAnalytics analytics,
  required ProgressComparisonRange range,
  DateTime? now,
  Schedule? schedule,
}) {
  final reference = _dateOnly(now ?? DateTime.now());
  final endExclusive = reference.add(const Duration(days: 1));

  late ProgressComparisonWindow currentWindow;
  late ProgressComparisonWindow previousWindow;
  List<WorkoutSession> scopedHistory = history;
  ProgressAnalytics scopedAnalytics = analytics;

  switch (range) {
    case ProgressComparisonRange.fourWeeks:
      currentWindow = ProgressComparisonWindow(
        start: endExclusive.subtract(const Duration(days: 28)),
        endExclusive: endExclusive,
      );
      previousWindow = ProgressComparisonWindow(
        start: currentWindow.start.subtract(const Duration(days: 28)),
        endExclusive: currentWindow.start,
      );
    case ProgressComparisonRange.eightWeeks:
      currentWindow = ProgressComparisonWindow(
        start: endExclusive.subtract(const Duration(days: 56)),
        endExclusive: endExclusive,
      );
      previousWindow = ProgressComparisonWindow(
        start: currentWindow.start.subtract(const Duration(days: 56)),
        endExclusive: currentWindow.start,
      );
    case ProgressComparisonRange.threeMonths:
      final currentStart = _shiftMonths(endExclusive, -3);
      currentWindow = ProgressComparisonWindow(
        start: currentStart,
        endExclusive: endExclusive,
      );
      previousWindow = ProgressComparisonWindow(
        start: _shiftMonths(currentStart, -3),
        endExclusive: currentStart,
      );
    case ProgressComparisonRange.mesocycle:
      if (schedule == null) return null;
      final cycleStart = _dateOnly(schedule.createdAt);
      if (!cycleStart.isBefore(endExclusive)) return null;
      final cycleDays = math.max(1, schedule.mesocycleWeeks) * 7;
      final plannedCycleEnd = cycleStart.add(Duration(days: cycleDays));
      final currentEnd = endExclusive.isBefore(plannedCycleEnd)
          ? endExclusive
          : plannedCycleEnd;
      final elapsedDays = math.max(1, currentEnd.difference(cycleStart).inDays);
      currentWindow = ProgressComparisonWindow(
        start: cycleStart,
        endExclusive: currentEnd,
      );
      previousWindow = ProgressComparisonWindow(
        start: cycleStart.subtract(Duration(days: elapsedDays)),
        endExclusive: cycleStart,
      );
      scopedHistory = history
          .where((session) => _matchesSchedule(session, schedule))
          .toList();
      scopedAnalytics = buildProgressAnalytics(
        history: scopedHistory,
        now: reference,
      );
  }

  final currentReport = buildPeriodProgressReport(
    history: scopedHistory,
    personalRecords: scopedAnalytics.personalRecords,
    start: currentWindow.start,
    endExclusive: currentWindow.endExclusive,
  );
  final previousReport = buildPeriodProgressReport(
    history: scopedHistory,
    personalRecords: scopedAnalytics.personalRecords,
    start: previousWindow.start,
    endExclusive: previousWindow.endExclusive,
  );

  return ProgressPeriodComparison(
    range: range,
    currentWindow: currentWindow,
    previousWindow: previousWindow,
    current: currentReport,
    previous: previousReport,
    strengthShifts: List.unmodifiable(
      _buildStrengthShifts(scopedHistory, currentWindow, previousWindow),
    ),
    muscleShifts: List.unmodifiable(
      _buildMuscleShifts(scopedHistory, currentWindow, previousWindow),
    ),
    schedule: range == ProgressComparisonRange.mesocycle ? schedule : null,
  );
}

List<PeriodStrengthShift> _buildStrengthShifts(
  List<WorkoutSession> history,
  ProgressComparisonWindow current,
  ProgressComparisonWindow previous,
) {
  final currentBest = _bestE1rmByExercise(history, current);
  final previousBest = _bestE1rmByExercise(history, previous);
  final shifts = <PeriodStrengthShift>[];

  for (final entry in currentBest.entries) {
    final previousEntry = previousBest[entry.key];
    if (previousEntry == null || previousEntry.best <= 0) continue;
    final change = ((entry.value.best - previousEntry.best) / previousEntry.best) * 100;
    shifts.add(
      PeriodStrengthShift(
        exerciseName: entry.value.name,
        muscleGroup: entry.value.muscleGroup,
        previousBestEstimatedOneRepMax: previousEntry.best,
        currentBestEstimatedOneRepMax: entry.value.best,
        changePercent: change,
      ),
    );
  }

  shifts.sort((a, b) => b.changePercent.compareTo(a.changePercent));
  return shifts;
}

Map<String, _StrengthAccumulator> _bestE1rmByExercise(
  List<WorkoutSession> history,
  ProgressComparisonWindow window,
) {
  final result = <String, _StrengthAccumulator>{};
  for (final session in history) {
    if (!_inWindow(session.startTime, window)) continue;
    for (final exercise in session.exercises) {
      double? best;
      for (final set in exercise.sets) {
        if (!set.isCompleted || set.isWarmup) continue;
        final e1rm = _estimatedOneRepMax(set);
        if (e1rm == null) continue;
        if (best == null || e1rm > best) best = e1rm;
      }
      if (best == null) continue;
      final key = _normalize(exercise.name);
      final existing = result[key];
      if (existing == null || best > existing.best) {
        result[key] = _StrengthAccumulator(
          name: exercise.name,
          muscleGroup: exercise.muscleGroup,
          best: best,
        );
      }
    }
  }
  return result;
}

List<PeriodMuscleShift> _buildMuscleShifts(
  List<WorkoutSession> history,
  ProgressComparisonWindow current,
  ProgressComparisonWindow previous,
) {
  final currentSets = _setsByMuscle(history, current);
  final previousSets = _setsByMuscle(history, previous);
  final groups = <MuscleGroup>{...currentSets.keys, ...previousSets.keys};
  final shifts = groups.map((group) {
    final currentValue = currentSets[group] ?? 0;
    final previousValue = previousSets[group] ?? 0;
    return PeriodMuscleShift(
      muscleGroup: group,
      previousSets: previousValue,
      currentSets: currentValue,
      changePercent: previousValue <= 0
          ? null
          : ((currentValue - previousValue) / previousValue) * 100,
    );
  }).toList();
  shifts.sort((a, b) {
    final byCurrent = b.currentSets.compareTo(a.currentSets);
    if (byCurrent != 0) return byCurrent;
    return (b.currentSets - b.previousSets).abs().compareTo(
      (a.currentSets - a.previousSets).abs(),
    );
  });
  return shifts;
}

Map<MuscleGroup, int> _setsByMuscle(
  List<WorkoutSession> history,
  ProgressComparisonWindow window,
) {
  final result = <MuscleGroup, int>{};
  for (final session in history) {
    if (!_inWindow(session.startTime, window)) continue;
    for (final exercise in session.exercises) {
      if (exercise.muscleGroup == MuscleGroup.unassigned) continue;
      final count = exercise.sets
          .where((set) => set.isCompleted && !set.isWarmup)
          .length;
      if (count == 0) continue;
      result.update(
        exercise.muscleGroup,
        (value) => value + count,
        ifAbsent: () => count,
      );
    }
  }
  return result;
}

bool _matchesSchedule(WorkoutSession session, Schedule schedule) {
  if (session.scheduleId != null) return session.scheduleId == schedule.id;
  return _normalize(session.scheduleTitle) == _normalize(schedule.title);
}

bool _inWindow(DateTime value, ProgressComparisonWindow window) {
  final day = _dateOnly(value);
  return !day.isBefore(window.start) && day.isBefore(window.endExclusive);
}

double? _estimatedOneRepMax(ExerciseSet set) {
  if (set.weight <= 0 || set.reps <= 0 || set.reps > 15) return null;
  return set.weight * (1 + set.reps / 30.0);
}

DateTime _shiftMonths(DateTime date, int delta) {
  final monthIndex = date.year * 12 + date.month - 1 + delta;
  final year = monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, math.min(date.day, lastDay));
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
String _normalize(String value) => value.trim().toLowerCase();

class _StrengthAccumulator {
  final String name;
  final MuscleGroup muscleGroup;
  final double best;

  const _StrengthAccumulator({
    required this.name,
    required this.muscleGroup,
    required this.best,
  });
}
''')

# ---------------------------------------------------------------------------
# Progress Center UI: new Periodi tab + schedule support.
# ---------------------------------------------------------------------------
path = Path('lib/screens/progress_center.dart')
text = path.read_text()
text = text.replace(
    "import '../models/exercise.dart';\n",
    "import '../models/exercise.dart';\nimport '../models/schedule.dart';\n",
    1,
)
text = text.replace(
    "import '../progress_intelligence.dart';\n",
    "import '../progress_intelligence.dart';\nimport '../progress_period_comparison.dart';\n",
    1,
)
text = text.replace(
    "class ProgressCenterScreen extends StatelessWidget {\n  final List<WorkoutSession> history;\n  final DateTime? now;\n\n  const ProgressCenterScreen({super.key, required this.history, this.now});",
    "class ProgressCenterScreen extends StatelessWidget {\n  final List<WorkoutSession> history;\n  final List<Schedule> schedules;\n  final DateTime? now;\n\n  const ProgressCenterScreen({\n    super.key,\n    required this.history,\n    this.schedules = const <Schedule>[],\n    this.now,\n  });",
    1,
)
text = text.replace("      length: 5,", "      length: 6,", 1)
text = text.replace(
    "                Tab(icon: Icon(Icons.track_changes), text: 'Focus'),\n                Tab(icon: Icon(Icons.show_chart), text: 'Esercizi'),",
    "                Tab(icon: Icon(Icons.track_changes), text: 'Focus'),\n                Tab(icon: Icon(Icons.compare_arrows), text: 'Periodi'),\n                Tab(icon: Icon(Icons.show_chart), text: 'Esercizi'),",
    1,
)
text = text.replace(
    "                _ProgressFocusTab(\n                  intelligence: intelligence,\n                  history: history,\n                  now: now,\n                ),\n                _ExerciseProgressTab(",
    "                _ProgressFocusTab(\n                  intelligence: intelligence,\n                  history: history,\n                  now: now,\n                ),\n                _PeriodComparisonTab(\n                  history: history,\n                  analytics: analytics,\n                  schedules: schedules,\n                  now: now,\n                ),\n                _ExerciseProgressTab(",
    1,
)

marker = "class _ProgressFocusTab extends StatelessWidget {"
period_ui = r'''class _PeriodComparisonTab extends StatefulWidget {
  final List<WorkoutSession> history;
  final ProgressAnalytics analytics;
  final List<Schedule> schedules;
  final DateTime? now;

  const _PeriodComparisonTab({
    required this.history,
    required this.analytics,
    required this.schedules,
    required this.now,
  });

  @override
  State<_PeriodComparisonTab> createState() => _PeriodComparisonTabState();
}

class _PeriodComparisonTabState extends State<_PeriodComparisonTab> {
  ProgressComparisonRange _range = ProgressComparisonRange.fourWeeks;
  String? _scheduleId;

  @override
  Widget build(BuildContext context) {
    final schedules = List<Schedule>.from(widget.schedules)
      ..sort((a, b) {
        if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
        return b.createdAt.compareTo(a.createdAt);
      });
    Schedule? selectedSchedule;
    if (schedules.isNotEmpty) {
      final desiredId = _scheduleId;
      selectedSchedule = schedules.first;
      if (desiredId != null) {
        for (final schedule in schedules) {
          if (schedule.id == desiredId) {
            selectedSchedule = schedule;
            break;
          }
        }
      }
    }

    final comparison = buildProgressPeriodComparison(
      history: widget.history,
      analytics: widget.analytics,
      range: _range,
      now: widget.now,
      schedule: _range == ProgressComparisonRange.mesocycle
          ? selectedSchedule
          : null,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Confronto periodi',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'Stessa durata contro il periodo immediatamente precedente: volume, frequenza, PR, forza ed esposizione muscolare.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ProgressComparisonRange.values.map((range) {
            return ChoiceChip(
              key: ValueKey('period-range-${range.name}'),
              label: Text(range.label),
              selected: _range == range,
              onSelected: (_) => setState(() => _range = range),
            );
          }).toList(),
        ),
        if (_range == ProgressComparisonRange.mesocycle) ...[
          const SizedBox(height: 12),
          if (schedules.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Nessuna scheda disponibile per il confronto del mesociclo.',
                ),
              ),
            )
          else
            DropdownButtonFormField<String>(
              key: const ValueKey('period-mesocycle-schedule'),
              initialValue: selectedSchedule?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Scheda / mesociclo',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: schedules
                  .map(
                    (schedule) => DropdownMenuItem<String>(
                      value: schedule.id,
                      child: Text(
                        '${schedule.title} · ciclo ${schedule.cycleNumber} · ${schedule.mesocycleWeeks} sett.',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _scheduleId = value),
            ),
        ],
        const SizedBox(height: 12),
        if (comparison == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Il confronto non è ancora disponibile per questa selezione.',
              ),
            ),
          )
        else
          ..._comparisonContent(context, comparison),
        const SizedBox(height: 80),
      ],
    );
  }

  List<Widget> _comparisonContent(
    BuildContext context,
    ProgressPeriodComparison comparison,
  ) {
    final current = comparison.current;
    final previous = comparison.previous;
    final strength = comparison.strengthShifts.take(8).toList();
    final muscles = comparison.muscleShifts.take(8).toList();

    return [
      Card(
        key: const ValueKey('period-comparison-window'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                comparison.range == ProgressComparisonRange.mesocycle
                    ? '${comparison.schedule?.title ?? 'Mesociclo'} · ciclo ${comparison.schedule?.cycleNumber ?? '-'}'
                    : comparison.range.label,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text('Adesso: ${comparison.currentWindow.label}'),
              Text('Prima: ${comparison.previousWindow.label}'),
              if (comparison.range == ProgressComparisonRange.mesocycle) ...[
                const SizedBox(height: 6),
                Text(
                  'Confronto allineato sui ${comparison.currentWindow.durationDays} giorni già trascorsi del ciclo corrente.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      _ComparisonMetricGrid(
        items: [
          _ComparisonMetric(
            keyName: 'workouts',
            label: 'Allenamenti',
            current: '${current.workouts}',
            previous: '${previous.workouts}',
            change: _percentDelta(
              current.workouts.toDouble(),
              previous.workouts.toDouble(),
            ),
            icon: Icons.fitness_center,
          ),
          _ComparisonMetric(
            keyName: 'frequency',
            label: 'Freq. / settimana',
            current: comparison.currentWorkoutsPerWeek.toStringAsFixed(1),
            previous: comparison.previousWorkoutsPerWeek.toStringAsFixed(1),
            change: _percentDelta(
              comparison.currentWorkoutsPerWeek,
              comparison.previousWorkoutsPerWeek,
            ),
            icon: Icons.calendar_view_week,
          ),
          _ComparisonMetric(
            keyName: 'volume',
            label: 'Volume',
            current: _compactPeriodKg(current.volume),
            previous: _compactPeriodKg(previous.volume),
            change: _percentDelta(current.volume, previous.volume),
            icon: Icons.monitor_weight_outlined,
          ),
          _ComparisonMetric(
            keyName: 'sets',
            label: 'Set',
            current: '${current.completedSets}',
            previous: '${previous.completedSets}',
            change: _percentDelta(
              current.completedSets.toDouble(),
              previous.completedSets.toDouble(),
            ),
            icon: Icons.format_list_numbered,
          ),
          _ComparisonMetric(
            keyName: 'prs',
            label: 'PR',
            current: '${current.personalRecords}',
            previous: '${previous.personalRecords}',
            change: _percentDelta(
              current.personalRecords.toDouble(),
              previous.personalRecords.toDouble(),
            ),
            icon: Icons.emoji_events_outlined,
          ),
          _ComparisonMetric(
            keyName: 'duration',
            label: 'Minuti',
            current: '${current.durationMinutes}',
            previous: '${previous.durationMinutes}',
            change: _percentDelta(
              current.durationMinutes.toDouble(),
              previous.durationMinutes.toDouble(),
            ),
            icon: Icons.timer_outlined,
          ),
        ],
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: Text(
              'Forza per esercizio',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (comparison.strengthShifts.isNotEmpty)
            Text(
              '${comparison.improvedStrengthCount} ↑ · ${comparison.declinedStrengthCount} ↓',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Best e1RM del periodo confrontato solo tra esercizi presenti in entrambe le finestre.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      if (strength.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nessun esercizio con e1RM confrontabile nei due periodi.'),
          ),
        )
      else
        ...strength.map((entry) => _PeriodStrengthTile(shift: entry)),
      const SizedBox(height: 20),
      Text(
        'Distribuzione muscolare',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Set di lavoro completati nel periodo corrente contro il precedente.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      if (muscles.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nessun set muscolare disponibile nei due periodi.'),
          ),
        )
      else
        ...muscles.map((entry) => _PeriodMuscleTile(shift: entry)),
    ];
  }
}

class _ComparisonMetric {
  final String keyName;
  final String label;
  final String current;
  final String previous;
  final double? change;
  final IconData icon;

  const _ComparisonMetric({
    required this.keyName,
    required this.label,
    required this.current,
    required this.previous,
    required this.change,
    required this.icon,
  });
}

class _ComparisonMetricGrid extends StatelessWidget {
  final List<_ComparisonMetric> items;

  const _ComparisonMetricGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 3 : 2;
        final spacing = 10.0;
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: _ComparisonMetricCard(item: item),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ComparisonMetricCard extends StatelessWidget {
  final _ComparisonMetric item;

  const _ComparisonMetricCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final change = item.change;
    final accent = change == null || change.abs() < 0.1
        ? scheme.onSurfaceVariant
        : change > 0
        ? scheme.primary
        : scheme.error;
    return Card(
      key: ValueKey('period-metric-${item.keyName}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(item.icon, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.current,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'prima ${item.previous}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _changeLabel(change, item.current != '0'),
              style: TextStyle(color: accent, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodStrengthTile extends StatelessWidget {
  final PeriodStrengthShift shift;

  const _PeriodStrengthTile({required this.shift});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = shift.declined
        ? scheme.error
        : shift.improved
        ? scheme.primary
        : scheme.onSurfaceVariant;
    return Card(
      key: ValueKey('period-strength-${shift.exerciseName}'),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            shift.declined
                ? Icons.trending_down
                : shift.improved
                ? Icons.trending_up
                : Icons.trending_flat,
          ),
        ),
        title: Text(
          shift.exerciseName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_periodKg(shift.previousBestEstimatedOneRepMax)} → ${_periodKg(shift.currentBestEstimatedOneRepMax)} e1RM',
        ),
        trailing: Text(
          _signedPeriodPercent(shift.changePercent),
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _PeriodMuscleTile extends StatelessWidget {
  final PeriodMuscleShift shift;

  const _PeriodMuscleTile({required this.shift});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final change = shift.changePercent;
    final color = change != null && change < 0 ? scheme.error : scheme.primary;
    return Card(
      key: ValueKey('period-muscle-${shift.muscleGroup.name}'),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.accessibility_new)),
        title: Text(
          shift.muscleGroup.label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('${shift.previousSets} → ${shift.currentSets} set'),
        trailing: Text(
          shift.newlyActive
              ? 'Nuovo'
              : change == null
              ? '-'
              : _signedPeriodPercent(change),
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

double? _percentDelta(double current, double previous) {
  if (previous <= 0) return current > 0 ? null : 0;
  return ((current - previous) / previous) * 100;
}

String _changeLabel(double? change, bool hasCurrent) {
  if (change == null) return hasCurrent ? 'Nuovo' : '—';
  return _signedPeriodPercent(change);
}

String _signedPeriodPercent(double value) =>
    '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}%';

String _periodKg(double value) => '${value.toStringAsFixed(1)} kg';

String _compactPeriodKg(double value) {
  if (value.abs() >= 1000) return '${(value / 1000).toStringAsFixed(1)}k kg';
  return '${value.toStringAsFixed(0)} kg';
}

'''
if period_ui.strip() not in text:
    if marker not in text:
        raise SystemExit('progress focus marker not found')
    text = text.replace(marker, period_ui + marker, 1)
path.write_text(text)

# ---------------------------------------------------------------------------
# Home passes schedules to Progress Center for mesocycle mode.
# ---------------------------------------------------------------------------
path = Path('lib/screens/home.dart')
text = path.read_text()
old = "ProgressCenterScreen(history: history),"
new = "ProgressCenterScreen(history: history, schedules: schedules),"
if old not in text:
    raise SystemExit('home ProgressCenterScreen anchor not found')
text = text.replace(old, new, 1)
path.write_text(text)

# ---------------------------------------------------------------------------
# Tests.
# ---------------------------------------------------------------------------
Path('test/progress_period_comparison_test.dart').write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/progress_analytics.dart';
import 'package:gymapp/progress_period_comparison.dart';
import 'package:gymapp/screens/progress_center.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('compares equal rolling 4-week windows with strength and muscle shifts', () {
    final now = DateTime(2026, 8, 26);
    final history = [
      _session(
        id: 'prev',
        date: DateTime(2026, 7, 10),
        scheduleId: 's1',
        weight: 80,
        reps: 8,
        sets: 2,
      ),
      _session(
        id: 'current-1',
        date: DateTime(2026, 8, 2),
        scheduleId: 's1',
        weight: 90,
        reps: 8,
        sets: 3,
      ),
      _session(
        id: 'current-2',
        date: DateTime(2026, 8, 18),
        scheduleId: 's1',
        weight: 92.5,
        reps: 8,
        sets: 3,
      ),
    ];
    final analytics = buildProgressAnalytics(history: history, now: now);

    final comparison = buildProgressPeriodComparison(
      history: history,
      analytics: analytics,
      range: ProgressComparisonRange.fourWeeks,
      now: now,
    )!;

    expect(comparison.currentWindow.durationDays, 28);
    expect(comparison.previousWindow.durationDays, 28);
    expect(comparison.current.workouts, 2);
    expect(comparison.previous.workouts, 1);
    expect(comparison.current.completedSets, 6);
    expect(comparison.previous.completedSets, 2);
    expect(comparison.strengthShifts, hasLength(1));
    expect(comparison.strengthShifts.single.exerciseName, 'Panca');
    expect(comparison.strengthShifts.single.changePercent, greaterThan(15));
    expect(comparison.muscleShifts.single.muscleGroup, MuscleGroup.chest);
    expect(comparison.muscleShifts.single.currentSets, 6);
    expect(comparison.muscleShifts.single.previousSets, 2);
  });

  test('mesocycle compares equal elapsed days and filters the selected schedule', () {
    final now = DateTime(2026, 8, 15);
    final schedule = Schedule(
      id: 's1',
      title: 'Upper',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: const [],
      mesocycleWeeks: 8,
      cycleNumber: 2,
    );
    final history = [
      _session(
        id: 'prev-upper',
        date: DateTime(2026, 7, 20),
        scheduleId: 's1',
        weight: 80,
        reps: 8,
      ),
      _session(
        id: 'current-upper',
        date: DateTime(2026, 8, 5),
        scheduleId: 's1',
        weight: 85,
        reps: 8,
      ),
      _session(
        id: 'other',
        date: DateTime(2026, 8, 6),
        scheduleId: 's2',
        scheduleTitle: 'Lower',
        weight: 160,
        reps: 5,
      ),
    ];
    final analytics = buildProgressAnalytics(history: history, now: now);

    final comparison = buildProgressPeriodComparison(
      history: history,
      analytics: analytics,
      range: ProgressComparisonRange.mesocycle,
      schedule: schedule,
      now: now,
    )!;

    expect(comparison.currentWindow.start, DateTime(2026, 8, 1));
    expect(comparison.currentWindow.durationDays, 15);
    expect(comparison.previousWindow.durationDays, 15);
    expect(comparison.current.workouts, 1);
    expect(comparison.previous.workouts, 1);
    expect(comparison.schedule?.id, 's1');
    expect(comparison.strengthShifts, hasLength(1));
  });

  testWidgets('Progress Center exposes rolling and mesocycle comparison UI', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 26);
    final schedule = Schedule(
      id: 's1',
      title: 'Upper',
      week: 1,
      createdAt: DateTime(2026, 8, 1),
      exercises: const [],
      mesocycleWeeks: 8,
      cycleNumber: 2,
    );
    final history = [
      _session(
        id: 'prev',
        date: DateTime(2026, 7, 10),
        scheduleId: 's1',
        weight: 80,
        reps: 8,
      ),
      _session(
        id: 'current',
        date: DateTime(2026, 8, 10),
        scheduleId: 's1',
        weight: 90,
        reps: 8,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressCenterScreen(
            history: history,
            schedules: [schedule],
            now: now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Periodi'));
    await tester.pumpAndSettle();
    expect(find.text('Confronto periodi'), findsOneWidget);
    expect(find.byKey(const ValueKey('period-comparison-window')), findsOneWidget);
    expect(find.byKey(const ValueKey('period-metric-workouts')), findsOneWidget);
    expect(find.byKey(const ValueKey('period-metric-volume')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('period-range-mesocycle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('period-mesocycle-schedule')), findsOneWidget);
    expect(find.textContaining('ciclo 2'), findsWidgets);
  });
}

WorkoutSession _session({
  required String id,
  required DateTime date,
  required String scheduleId,
  String scheduleTitle = 'Upper',
  required double weight,
  required int reps,
  int sets = 1,
}) {
  return WorkoutSession(
    id: id,
    scheduleId: scheduleId,
    scheduleTitle: scheduleTitle,
    startTime: date,
    endTime: date.add(const Duration(minutes: 60)),
    exercises: [
      WorkoutExercise(
        name: 'Panca',
        notes: '',
        muscleGroup: MuscleGroup.chest,
        technique: IntensityTechnique.none,
        sets: List.generate(
          sets,
          (_) => ExerciseSet(
            weight: weight,
            reps: reps,
            isCompleted: true,
          ),
        ),
      ),
    ],
  );
}
''')
