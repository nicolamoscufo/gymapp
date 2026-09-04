import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/app_theme.dart';
import 'package:gymapp/ui/home_dashboard_components.dart';
import 'package:gymapp/ui/workout_components.dart';

final bool _goldensEnabled = Platform.environment['GOLDEN_TESTS'] == '1';

void main() {
  testWidgets(
    'home visual contract - light phone',
    (tester) async {
      _configureView(tester, const Size(390, 844));
      await tester.pumpWidget(
        _visualApp(
          themeMode: ThemeMode.light,
          child: const _HomeVisualFixture(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/ui_home_light_phone.png'),
      );
    },
    skip: !_goldensEnabled,
  );

  testWidgets(
    'home visual contract - dark phone',
    (tester) async {
      _configureView(tester, const Size(390, 844));
      await tester.pumpWidget(
        _visualApp(
          themeMode: ThemeMode.dark,
          child: const _HomeVisualFixture(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/ui_home_dark_phone.png'),
      );
    },
    skip: !_goldensEnabled,
  );

  testWidgets(
    'workout visual contract - narrow phone with larger text',
    (tester) async {
      _configureView(tester, const Size(320, 720));
      await tester.pumpWidget(
        _visualApp(
          themeMode: ThemeMode.light,
          textScale: 1.30,
          child: const _WorkoutVisualFixture(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/ui_workout_narrow_large_text.png'),
      );
    },
    skip: !_goldensEnabled,
  );

  testWidgets(
    'workout visual contract - landscape',
    (tester) async {
      _configureView(tester, const Size(844, 390));
      await tester.pumpWidget(
        _visualApp(
          themeMode: ThemeMode.dark,
          child: const _WorkoutVisualFixture(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/ui_workout_landscape_dark.png'),
      );
    },
    skip: !_goldensEnabled,
  );
}

void _configureView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _visualApp({
  required ThemeMode themeMode,
  required Widget child,
  double textScale = 1,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: themeMode,
    builder: (context, appChild) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(textScaler: TextScaler.linear(textScale)),
        child: appChild!,
      );
    },
    home: child,
  );
}

class _HomeVisualFixture extends StatelessWidget {
  const _HomeVisualFixture();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FitFlow'),
        actions: [
          IconButton(onPressed: _noop, icon: const Icon(Icons.search)),
          IconButton(onPressed: _noop, icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          HomeWorkoutCard(
            eyebrow: 'PROSSIMO ALLENAMENTO',
            title: 'Push A',
            subtitle: '4 esercizi · focus petto e spalle · circa 52 min',
            icon: Icons.fitness_center,
            primaryLabel: 'Inizia allenamento',
            primaryIcon: Icons.play_arrow_rounded,
            onPrimary: _noop,
            secondaryLabel: 'Scheda',
            onSecondary: _noop,
          ),
          const SizedBox(height: AppSpacing.md),
          const HomeMetricsStrip(
            metrics: [
              HomeDashboardMetric(
                icon: Icons.local_fire_department_outlined,
                value: '3',
                label: 'settimana',
              ),
              HomeDashboardMetric(
                icon: Icons.monitor_weight_outlined,
                value: '8.240 kg',
                label: 'volume',
              ),
              HomeDashboardMetric(
                icon: Icons.emoji_events_outlined,
                value: '2',
                label: 'PR recenti',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          HomeCoachCard(
            preview:
                'Ultime due sessioni solide. Mantieni il carico sulla panca e prova una rep in più solo se il RIR resta stabile.',
            onOpen: _noop,
          ),
          const SizedBox(height: AppSpacing.md),
          WorkoutCompactExerciseCard(
            exerciseId: 'bench-home-golden',
            name: 'Panca piana bilanciere',
            completedSets: 2,
            totalSets: 4,
            nextPrescription: '82.5 kg × 8',
            isComplete: false,
            accent: Theme.of(context).colorScheme.primary,
            onTap: _noop,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Schede'),
          NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: 'Allenati',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'Progressi'),
        ],
      ),
    );
  }
}

class _WorkoutVisualFixture extends StatelessWidget {
  const _WorkoutVisualFixture();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Push A'),
        actions: [
          TextButton(onPressed: _noop, child: const Text('Termina')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        children: [
          const WorkoutSectionHeader(
            title: 'Allenamento in corso',
            subtitle: 'Set completati e prossimo target sempre in primo piano.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const Row(
            children: [
              Expanded(
                child: WorkoutMetricTile(
                  icon: Icons.check_circle_outline,
                  label: 'Set',
                  value: '8/12',
                  helper: '67% completato',
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: WorkoutMetricTile(
                  icon: Icons.timer_outlined,
                  label: 'Durata',
                  value: '38 min',
                  helper: 'ritmo regolare',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          WorkoutCompactExerciseCard(
            exerciseId: 'bench-workout-golden',
            name: 'Panca piana bilanciere',
            completedSets: 2,
            totalSets: 4,
            nextPrescription: '82.5 kg × 8',
            isComplete: false,
            accent: colorScheme.primary,
            onTap: _noop,
          ),
          WorkoutCompactExerciseCard(
            exerciseId: 'fly-workout-golden',
            name: 'Croci ai cavi',
            completedSets: 3,
            totalSets: 3,
            isComplete: true,
            accent: colorScheme.secondary,
            onTap: _noop,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Card(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: WorkoutSetTableHeader(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: WorkoutRestPanel(
        exerciseName: 'Panca piana bilanciere',
        countdown: '01:24',
        progress: 0.62,
        nextSetId: 'set-3',
        nextExerciseName: 'Panca piana bilanciere',
        nextSetLabel: 'Serie 3',
        nextPrescription: '82.5 kg × 8',
        onMinusThirty: _noop,
        onPlusThirty: _noop,
        onSkip: _noop,
      ),
    );
  }
}

void _noop() {}
