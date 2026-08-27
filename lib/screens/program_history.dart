import 'package:flutter/material.dart';

import '../ai_coach/program_change_effectiveness.dart';
import '../app_data_store.dart';
import '../models/schedule.dart';
import '../models/schedule_version.dart';
import '../models/workout.dart';

typedef ScheduleVersionLoader = Future<List<ScheduleVersion>> Function();

class ProgramHistoryScreen extends StatefulWidget {
  final Schedule schedule;
  final List<WorkoutSession> history;
  final ScheduleVersionLoader? loadVersions;

  const ProgramHistoryScreen({
    super.key,
    required this.schedule,
    required this.history,
    this.loadVersions,
  });

  @override
  State<ProgramHistoryScreen> createState() => _ProgramHistoryScreenState();
}

class _ProgramHistoryScreenState extends State<ProgramHistoryScreen> {
  late Future<List<ScheduleVersion>> _versionsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _versionsFuture =
        widget.loadVersions?.call() ?? AppDataStore.loadScheduleVersions();
  }

  void _retry() {
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Evoluzione programma')),
      body: FutureBuilder<List<ScheduleVersion>>(
        future: _versionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(onRetry: _retry);
          }

          final versions = (snapshot.data ?? const <ScheduleVersion>[])
              .where((version) => version.scheduleId == widget.schedule.id)
              .toList()
            ..sort((a, b) {
              final byNumber = a.versionNumber.compareTo(b.versionNumber);
              if (byNumber != 0) return byNumber;
              return a.createdAt.compareTo(b.createdAt);
            });

          if (versions.isEmpty) {
            return const _EmptyState();
          }

          final effectiveness = buildProgramChangeEffectivenessContext(
            scheduleVersions: versions,
            history: widget.history,
          );
          final transitions = (effectiveness['transitions'] as List? ?? const [])
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList();
          final summary = Map<String, dynamic>.from(
            effectiveness['summary'] as Map? ?? const {},
          );
          final versionById = {for (final version in versions) version.id: version};

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _HeaderCard(
                schedule: widget.schedule,
                versionCount: versions.length,
                summary: summary,
              ),
              const SizedBox(height: 12),
              _VersionCard(version: versions.first, isBaseline: true),
              if (transitions.isEmpty) ...[
                const SizedBox(height: 12),
                const _WaitingForChangeCard(),
              ] else ...[
                const SizedBox(height: 16),
                Text(
                  'Modifiche e risultati successivi',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ...transitions.map((transition) {
                  final toVersionId = transition['to_version_id']?.toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TransitionCard(
                      transition: transition,
                      toVersion: versionById[toVersionId],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 4),
              const _EvidenceNote(),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Schedule schedule;
  final int versionCount;
  final Map<String, dynamic> summary;

  const _HeaderCard({
    required this.schedule,
    required this.versionCount,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final improved = (summary['improved'] as num?)?.toInt() ?? 0;
    final stable = (summary['stable'] as num?)?.toInt() ?? 0;
    final declined = (summary['declined'] as num?)?.toInt() ?? 0;
    final mixed = (summary['mixed'] as num?)?.toInt() ?? 0;
    final insufficient = (summary['insufficient'] as num?)?.toInt() ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schedule.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '$versionCount versioni storiche',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (improved > 0) _CountChip(label: '$improved migliorate'),
                if (stable > 0) _CountChip(label: '$stable stabili'),
                if (declined > 0) _CountChip(label: '$declined peggiorate'),
                if (mixed > 0) _CountChip(label: '$mixed miste'),
                if (insufficient > 0)
                  _CountChip(label: '$insufficient non valutabili'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;

  const _CountChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
    );
  }
}

class _VersionCard extends StatelessWidget {
  final ScheduleVersion version;
  final bool isBaseline;

  const _VersionCard({required this.version, required this.isBaseline});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reason = version.reason.trim();

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text('v${version.versionNumber}'),
        ),
        title: Text(
          isBaseline ? 'Versione iniziale' : 'Versione ${version.versionNumber}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_formatDate(version.createdAt)} • ${version.source.label}'
          '${reason.isEmpty ? '' : '\n$reason'}',
        ),
        trailing: Icon(
          isBaseline ? Icons.flag_outlined : Icons.history,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TransitionCard extends StatelessWidget {
  final Map<String, dynamic> transition;
  final ScheduleVersion? toVersion;

  const _TransitionCard({required this.transition, required this.toVersion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fromVersion = (transition['from_version_number'] as num?)?.toInt() ?? 0;
    final toVersionNumber = (transition['to_version_number'] as num?)?.toInt() ?? 0;
    final status = transition['status']?.toString() ?? 'insufficient';
    final signals = (transition['exercise_signals'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
    final reason = (transition['reason']?.toString() ?? '').trim();
    final changedAt = DateTime.tryParse(transition['changed_at']?.toString() ?? '');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'v$fromVersion → v$toVersionNumber',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (changedAt != null) _formatDate(changedAt),
                if (toVersion != null) toVersion!.source.label,
              ].join(' • '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(reason, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            if (signals.isEmpty)
              Text(
                'Questa versione non contiene modifiche prescrittive valutabili.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...signals.map(
                (signal) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ExerciseSignalTile(signal: signal),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseSignalTile extends StatelessWidget {
  final Map<String, dynamic> signal;

  const _ExerciseSignalTile({required this.signal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = signal['status']?.toString() ?? 'insufficient';
    final exercise = signal['exercise']?.toString().trim();
    final metric = signal['primary_metric']?.toString();
    final change = (signal['primary_change_percent'] as num?)?.toDouble();
    final previousSessions = (signal['previous_sessions'] as num?)?.toInt() ?? 0;
    final currentSessions = (signal['current_sessions'] as num?)?.toInt() ?? 0;
    final changedFields = (signal['changed_fields'] as List? ?? const [])
        .map((field) => _fieldLabel(field.toString()))
        .toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    exercise == null || exercise.isEmpty
                        ? 'Esercizio'
                        : exercise,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                _StatusChip(status: status, compact: true),
              ],
            ),
            if (change != null && metric != null && metric != 'none') ...[
              const SizedBox(height: 6),
              Text(
                '${_metricLabel(metric)} ${_formatPercent(change)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Sessioni esatte: $previousSessions → $currentSessions',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (changedFields.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Modifica: ${changedFields.join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (status == 'insufficient') ...[
              const SizedBox(height: 6),
              Text(
                _insufficientReason(signal['reason']?.toString()),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (metric == 'mean_volume_per_session') ...[
              const SizedBox(height: 6),
              Text(
                'Il volume può variare perché è cambiata la prescrizione: interpretalo come associazione di esposizione/capacità di lavoro.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final bool compact;

  const _StatusChip({required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visual = _statusVisual(status, colorScheme);
    return Chip(
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      avatar: Icon(visual.icon, size: 16, color: visual.color),
      label: Text(
        visual.label,
        style: TextStyle(color: visual.color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EvidenceNote extends StatelessWidget {
  const _EvidenceNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, color: colorScheme.tertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Associazione, non causalità. Il confronto usa solo sessioni collegate esattamente alle versioni salvate e allo stesso esercizio. Un miglioramento successivo non dimostra che la modifica lo abbia causato.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingForChangeCard extends StatelessWidget {
  const _WaitingForChangeCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.hourglass_empty),
        title: Text('Nessuna transizione ancora'),
        subtitle: Text(
          'Quando salverai una nuova versione della scheda, qui apparirà il confronto con la versione precedente.',
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Nessuna versione storica disponibile per questa scheda.'),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 8),
            const Text('Impossibile caricare la cronologia del programma.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Riprova')),
          ],
        ),
      ),
    );
  }
}

class _StatusVisual {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusVisual(this.label, this.icon, this.color);
}

_StatusVisual _statusVisual(String status, ColorScheme colorScheme) {
  return switch (status) {
    'improved' => _StatusVisual(
      'Migliorato',
      Icons.trending_up,
      colorScheme.primary,
    ),
    'stable' => _StatusVisual(
      'Stabile',
      Icons.trending_flat,
      colorScheme.secondary,
    ),
    'declined' => _StatusVisual(
      'Peggiorato',
      Icons.trending_down,
      colorScheme.error,
    ),
    'mixed' => _StatusVisual(
      'Misto',
      Icons.swap_vert,
      colorScheme.tertiary,
    ),
    _ => _StatusVisual(
      'Dati insufficienti',
      Icons.hourglass_empty,
      colorScheme.onSurfaceVariant,
    ),
  };
}

String _metricLabel(String metric) => switch (metric) {
  'mean_estimated_1rm' => 'e1RM medio',
  'mean_volume_per_session' => 'Volume/sessione',
  _ => metric,
};

String _fieldLabel(String field) => switch (field) {
  'weight' => 'carico',
  'reps' => 'ripetizioni',
  'set' => 'set',
  'targetMinReps' => 'rep minime',
  'targetMaxReps' => 'rep massime',
  'technique' => 'tecnica',
  'backoffReps' => 'rep backoff',
  'backoffReductionPercent' => 'riduzione backoff',
  'restSeconds' => 'recupero',
  'supersetGroup' => 'superset',
  'progressionKgStep' => 'step carico',
  'progressionRepStep' => 'step reps',
  'progressionScheme' => 'progressione',
  'equipment' => 'attrezzatura',
  'exercise_added' => 'esercizio aggiunto',
  'exercise_removed' => 'esercizio rimosso',
  _ => field,
};

String _insufficientReason(String? reason) => switch (reason) {
  'requires_at_least_two_exact_sessions_per_side' =>
    'Servono almeno 2 sessioni esatte prima e 2 dopo la modifica.',
  'exercise_added_without_pre_change_baseline' =>
    'Esercizio aggiunto: manca una baseline precedente confrontabile.',
  'exercise_removed_without_post_change_outcome' =>
    'Esercizio rimosso: manca un outcome successivo confrontabile.',
  _ => 'I dati disponibili non bastano per una valutazione affidabile.',
};

String _formatPercent(double value) {
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(1)}%';
}

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}
