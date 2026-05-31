import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../models/exercise.dart';
import '../models/workout.dart';

class SessionSummaryScreen extends StatefulWidget {
  final WorkoutSession session;
  final List<WorkoutSession> previousHistory;

  const SessionSummaryScreen({
    super.key,
    required this.session,
    this.previousHistory = const [],
  });

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  final GlobalKey _shareKey = GlobalKey();
  bool _isSharing = false;

  String _formatWeight(double weight) {
    return weight % 1 == 0
        ? weight.toStringAsFixed(0)
        : weight.toStringAsFixed(1);
  }

  String _formatVolume(double volume) => '${_formatWeight(volume)} kg';

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${math.max(1, duration.inMinutes)} min';
  }

  String _normalizeExerciseName(String name) => name.trim().toLowerCase();

  double _setVolume(ExerciseSet set) => set.weight * set.reps;

  Iterable<ExerciseSet> _completedSets(WorkoutExercise exercise) {
    return exercise.sets.where((set) => set.isCompleted);
  }

  Iterable<ExerciseSet> _completedWorkSets(WorkoutExercise exercise) {
    return exercise.sets.where((set) => set.isCompleted && !set.isWarmup);
  }

  double _exerciseVolume(WorkoutExercise exercise) {
    return _completedWorkSets(
      exercise,
    ).fold<double>(0, (total, set) => total + _setVolume(set));
  }

  double get _totalVolume {
    return widget.session.exercises.fold<double>(
      0,
      (total, exercise) => total + _exerciseVolume(exercise),
    );
  }

  int get _completedSetCount {
    return widget.session.exercises.fold<int>(
      0,
      (total, exercise) => total + _completedSets(exercise).length,
    );
  }

  ExerciseSet? _bestSetFor(WorkoutExercise exercise) {
    ExerciseSet? bestSet;
    for (final set in _completedWorkSets(exercise)) {
      if (bestSet == null || _setVolume(set) > _setVolume(bestSet)) {
        bestSet = set;
      }
    }
    return bestSet;
  }

  Iterable<WorkoutExercise> _historicalExercisesFor(WorkoutExercise exercise) {
    final exerciseName = _normalizeExerciseName(exercise.name);
    return widget.previousHistory.expand((session) {
      return session.exercises.where(
        (historicalExercise) =>
            _normalizeExerciseName(historicalExercise.name) == exerciseName,
      );
    });
  }

  Iterable<ExerciseSet> _historicalWorkSetsFor(WorkoutExercise exercise) {
    return _historicalExercisesFor(exercise)
        .expand((historicalExercise) => historicalExercise.sets)
        .where((set) => set.isCompleted && !set.isWarmup);
  }

  double? _maxHistoricalWeightFor(WorkoutExercise exercise) {
    double? maxWeight;
    for (final set in _historicalWorkSetsFor(exercise)) {
      if (maxWeight == null || set.weight > maxWeight) {
        maxWeight = set.weight;
      }
    }
    return maxWeight;
  }

  int? _maxHistoricalRepsFor(WorkoutExercise exercise) {
    int? maxReps;
    for (final set in _historicalWorkSetsFor(exercise)) {
      if (maxReps == null || set.reps > maxReps) {
        maxReps = set.reps;
      }
    }
    return maxReps;
  }

  double? _bestHistoricalSetVolumeFor(WorkoutExercise exercise) {
    double? bestVolume;
    for (final set in _historicalWorkSetsFor(exercise)) {
      final volume = _setVolume(set);
      if (bestVolume == null || volume > bestVolume) {
        bestVolume = volume;
      }
    }
    return bestVolume;
  }

  double? _bestHistoricalExerciseVolumeFor(WorkoutExercise exercise) {
    double? bestVolume;
    for (final historicalExercise in _historicalExercisesFor(exercise)) {
      final volume = _exerciseVolume(historicalExercise);
      if (volume <= 0) {
        continue;
      }
      if (bestVolume == null || volume > bestVolume) {
        bestVolume = volume;
      }
    }
    return bestVolume;
  }

  List<String> _personalRecordLabelsFor(WorkoutExercise exercise) {
    final labels = <String>{};
    final maxWeight = _maxHistoricalWeightFor(exercise);
    final maxReps = _maxHistoricalRepsFor(exercise);
    final bestSetVolume = _bestHistoricalSetVolumeFor(exercise);
    final bestExerciseVolume = _bestHistoricalExerciseVolumeFor(exercise);
    final currentExerciseVolume = _exerciseVolume(exercise);

    for (final set in _completedWorkSets(exercise)) {
      if (maxWeight != null && set.weight > maxWeight) {
        labels.add('PR kg');
      }
      if (maxReps != null && set.reps > maxReps) {
        labels.add('PR reps');
      }
      if (bestSetVolume != null && _setVolume(set) > bestSetVolume) {
        labels.add('PR set');
      }
    }

    if (bestExerciseVolume != null &&
        currentExerciseVolume > bestExerciseVolume) {
      labels.add('PR volume');
    }

    if (_historicalWorkSetsFor(exercise).isEmpty &&
        _completedWorkSets(exercise).isNotEmpty) {
      labels.add('Prima volta');
    }

    return labels.toList();
  }

  List<String> get _sessionRecordLabels {
    final labels = <String>{};
    for (final exercise in widget.session.exercises) {
      labels.addAll(_personalRecordLabelsFor(exercise));
    }
    return labels.toList();
  }

  Future<void> _shareSummary() async {
    if (_isSharing) {
      return;
    }

    setState(() => _isSharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _shareKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        return;
      }

      final fileName =
          'allenamento-${widget.session.endTime.year}-${widget.session.endTime.month.toString().padLeft(2, '0')}-${widget.session.endTime.day.toString().padLeft(2, '0')}.png';
      await SharePlus.instance.share(
        ShareParams(
          text:
              'Allenamento ${widget.session.scheduleTitle} - ${_formatVolume(_totalVolume)}',
          files: [XFile.fromData(bytes, mimeType: 'image/png')],
          fileNameOverrides: [fileName],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.session.endTime.difference(
      widget.session.startTime,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riepilogo'),
        actions: [
          IconButton(
            tooltip: 'Condividi screenshot',
            icon: _isSharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            onPressed: _isSharing ? null : _shareSummary,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: RepaintBoundary(
          key: _shareKey,
          child: _SummaryShareCard(
            session: widget.session,
            dateLabel: _formatDate(widget.session.endTime),
            durationLabel: _formatDuration(duration),
            volumeLabel: _formatVolume(_totalVolume),
            completedSetsLabel: '$_completedSetCount',
            recordLabels: _sessionRecordLabels,
            exerciseCards: widget.session.exercises.map((exercise) {
              return _ExerciseSummaryCard(
                exercise: exercise,
                completedSets: _completedSets(exercise).toList(),
                volumeLabel: _formatVolume(_exerciseVolume(exercise)),
                bestSet: _bestSetFor(exercise),
                recordLabels: _personalRecordLabelsFor(exercise),
                formatWeight: _formatWeight,
                formatVolume: _formatVolume,
              );
            }).toList(),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Chiudi'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isSharing ? null : _shareSummary,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Condividi'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryShareCard extends StatelessWidget {
  final WorkoutSession session;
  final String dateLabel;
  final String durationLabel;
  final String volumeLabel;
  final String completedSetsLabel;
  final List<String> recordLabels;
  final List<Widget> exerciseCards;

  const _SummaryShareCard({
    required this.session,
    required this.dateLabel,
    required this.durationLabel,
    required this.volumeLabel,
    required this.completedSetsLabel,
    required this.recordLabels,
    required this.exerciseCards,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: isDark ? 0.20 : 0.12),
            colorScheme.surface,
            colorScheme.tertiary.withValues(alpha: isDark ? 0.12 : 0.08),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.fitness_center,
                  color: colorScheme.onPrimaryContainer,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.scheduleTitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryMetricTile(
                icon: Icons.scale,
                label: 'Volume',
                value: volumeLabel,
              ),
              _SummaryMetricTile(
                icon: Icons.check_circle,
                label: 'Set',
                value: completedSetsLabel,
              ),
              _SummaryMetricTile(
                icon: Icons.timer,
                label: 'Durata',
                value: durationLabel,
              ),
              _SummaryMetricTile(
                icon: Icons.list_alt,
                label: 'Esercizi',
                value: '${session.exercises.length}',
              ),
            ],
          ),
          if (recordLabels.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: recordLabels
                  .map(
                    (label) => Chip(
                      avatar: Icon(
                        Icons.emoji_events,
                        color: colorScheme.tertiary,
                        size: 18,
                      ),
                      label: Text(label),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 18),
          ...exerciseCards,
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Gym diary',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryMetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colorScheme.primary, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseSummaryCard extends StatelessWidget {
  final WorkoutExercise exercise;
  final List<ExerciseSet> completedSets;
  final String volumeLabel;
  final ExerciseSet? bestSet;
  final List<String> recordLabels;
  final String Function(double weight) formatWeight;
  final String Function(double volume) formatVolume;

  const _ExerciseSummaryCard({
    required this.exercise,
    required this.completedSets,
    required this.volumeLabel,
    required this.bestSet,
    required this.recordLabels,
    required this.formatWeight,
    required this.formatVolume,
  });

  String _setTitle(ExerciseSet set, int index) {
    final base = set.isWarmup ? 'W${index + 1}' : '${index + 1}';
    return base;
  }

  String _setMeta(ExerciseSet set) {
    final meta = <String>[];
    if (set.rpe != null) {
      meta.add('RPE ${formatWeight(set.rpe!)}');
    }
    if (set.rir != null) {
      meta.add('RIR ${set.rir}');
    }
    if (set.notes.trim().isNotEmpty) {
      meta.add(set.notes.trim());
    }
    return meta.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surface.withValues(alpha: 0.86),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        exercise.muscleGroup.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  volumeLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (bestSet != null) ...[
              const SizedBox(height: 8),
              Text(
                'Top set: ${formatWeight(bestSet!.weight)} kg x ${bestSet!.reps} (${formatVolume(bestSet!.weight * bestSet!.reps)})',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (recordLabels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: recordLabels
                    .map(
                      (label) => Chip(
                        avatar: Icon(
                          Icons.emoji_events,
                          color: colorScheme.tertiary,
                          size: 16,
                        ),
                        label: Text(label),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            if (completedSets.isEmpty)
              Text(
                'Nessun set completato.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...List.generate(completedSets.length, (index) {
                final set = completedSets[index];
                final meta = _setMeta(set);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 42,
                            child: Text(
                              _setTitle(set, index),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${formatWeight(set.weight)} kg x ${set.reps}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(formatVolume(set.weight * set.reps)),
                        ],
                      ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 42, top: 2),
                          child: Text(
                            meta,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
