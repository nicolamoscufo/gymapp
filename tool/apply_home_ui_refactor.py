from pathlib import Path
import re

path = Path('lib/screens/home.dart')
text = path.read_text()
original = text

import_anchor = "import '../top_set_backoff.dart';\n"
ui_import = "import '../ui/home_dashboard_components.dart';\n"
if ui_import not in text:
    if import_anchor not in text:
        raise SystemExit('home import anchor not found')
    text = text.replace(import_anchor, import_anchor + ui_import, 1)

home_method = re.compile(
    r"  Widget _buildHomeDashboard\(\) \{[\s\S]*?\n  \}\n\n  Widget _buildProgressTab",
    re.MULTILINE,
)
replacement = '''  Widget _buildHomeDashboard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final planned = _nextPlannedWorkout();
    final latestBody = _latestBodyLog();
    final computedReadiness = buildGlobalReadinessReport(
      history: history,
      bodyLogs: bodyLogs,
    );
    final workoutsThisWeek = _workoutsThisWeek();
    final progress = _buildExerciseProgressSummaries();
    final strongestProgress = progress.isEmpty ? null : progress.first;
    final now = DateTime.now();

    final workoutTitle = _savedSession != null
        ? _savedSession!.scheduleTitle
        : planned?.schedule.title ?? 'Nessun allenamento pianificato';
    final workoutSubtitle = _savedSession != null
        ? 'Allenamento in corso'
        : planned == null
        ? 'Crea una scheda e assegna i giorni di allenamento.'
        : _sameDay(planned.date, now)
        ? 'Oggi • ${planned.schedule.exercises.length} esercizi • Week ${planned.schedule.currentWeek()}'
        : '${_weekdayLabel(planned.date.weekday)} ${planned.date.day}/${planned.date.month} • ${planned.schedule.exercises.length} esercizi • Week ${planned.schedule.currentWeek()}';

    final coachPreview = strongestProgress == null
        ? history.isEmpty
              ? 'Completa qualche allenamento: il Coach userà storico, schede e recupero per darti indicazioni contestuali.'
              : 'I tuoi dati sono pronti. Apri il Coach per analizzare progressione, volume e recupero in locale.'
        : strongestProgress.isImproved
        ? '${strongestProgress.name}: volume ${_formatSignedVolume(strongestProgress.volumeDelta)} rispetto alla sessione precedente.'
        : '${strongestProgress.name}: nessun miglioramento netto nell’ultimo confronto. Puoi chiedere al Coach cosa cambiare.';

    final primaryAction = _savedSession != null
        ? _resumeSavedWorkoutFromHome
        : planned == null
        ? () => setState(() => _currentIndex = 1)
        : () => _startScheduleFromHome(planned.schedule);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Oggi',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_weekdayLabel(now.weekday)} ${now.day}/${now.month}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        HomeWorkoutCard(
          eyebrow: _savedSession == null
              ? 'Prossimo allenamento'
              : 'Riprendi allenamento',
          title: workoutTitle,
          subtitle: workoutSubtitle,
          icon: _savedSession == null
              ? Icons.fitness_center
              : Icons.play_arrow_rounded,
          primaryLabel: _savedSession != null
              ? 'Riprendi'
              : planned == null
              ? 'Crea scheda'
              : 'Inizia',
          primaryIcon: planned == null && _savedSession == null
              ? Icons.add
              : Icons.play_arrow,
          onPrimary: primaryAction,
          secondaryLabel: planned != null && _savedSession == null
              ? 'Dettagli'
              : null,
          onSecondary: planned != null && _savedSession == null
              ? () => _openScheduleDetail(planned.schedule)
              : null,
        ),
        const SizedBox(height: 12),
        HomeMetricsStrip(
          metrics: [
            HomeDashboardMetric(
              icon: Icons.calendar_view_week,
              value: '$workoutsThisWeek',
              label: 'questa settimana',
            ),
            HomeDashboardMetric(
              icon: Icons.monitor_weight_outlined,
              value: latestBody?.bodyWeight == null
                  ? '--'
                  : '${latestBody!.bodyWeight!.toStringAsFixed(1)} kg',
              label: 'peso',
            ),
            HomeDashboardMetric(
              icon: Icons.bolt,
              value: '${computedReadiness.score}',
              label: '${computedReadiness.status.label.toLowerCase()} /100',
            ),
          ],
        ),
        const SizedBox(height: 12),
        HomeCoachCard(
          preview: coachPreview,
          onOpen: () => setState(() => _currentIndex = 4),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.insights),
            title: const Text(
              'Progressi',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              history.isEmpty
                  ? 'Cronologia, statistiche e misure corpo in un’unica sezione.'
                  : '${history.length} allenamenti registrati • ${progress.where((entry) => entry.isImproved).length} miglioramenti recenti',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _currentIndex = 3),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressTab'''
text, count = home_method.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit(f'home dashboard replacement count={count}')

body_gradient = '''            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.secondary.withValues(alpha: isDark ? 0.20 : 0.12),
                  Colors.transparent,
                ],
              ),
            ),'''
body_surface = '''            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
            ),'''
if body_gradient not in text:
    raise SystemExit('body snapshot gradient anchor not found')
text = text.replace(body_gradient, body_surface, 1)

nav_pattern = re.compile(
    r"      bottomNavigationBar: SafeArea\([\s\S]*?\n      \),\n    \);\n  \}\n\}",
    re.MULTILINE,
)
nav_replacement = '''      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Schede',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Allenati',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Progressi',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_alt_outlined),
            selectedIcon: Icon(Icons.psychology_alt),
            label: 'Coach',
          ),
        ],
      ),
    );
  }
}'''
text, count = nav_pattern.subn(nav_replacement, text, count=1)
if count != 1:
    raise SystemExit(f'navigation replacement count={count}')

# _DashboardMetric moved to lib/ui/home_dashboard_components.dart.
dashboard_metric = re.compile(
    r"\nclass _DashboardMetric extends StatelessWidget \{[\s\S]*?\n\}\n\nclass _ExerciseOccurrence",
    re.MULTILINE,
)
text, count = dashboard_metric.subn('\nclass _ExerciseOccurrence', text, count=1)
if count != 1:
    raise SystemExit(f'dashboard metric removal count={count}')

# Build no longer needs brightness solely for the floating nav shadow.
text = text.replace(
    "    final isDark = theme.brightness == Brightness.dark;\n    final isCoach = _currentIndex == 4;",
    "    final isCoach = _currentIndex == 4;",
    1,
)

if text == original:
    raise SystemExit('No home changes produced')

path.write_text(text)
print('home.dart refactor applied')
