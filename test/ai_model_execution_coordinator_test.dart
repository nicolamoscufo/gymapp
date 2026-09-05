import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/ai_coach/ai_model_execution_coordinator.dart';

void main() {
  test('concurrent initialize calls collapse into one runtime load', () async {
    final coordinator = AiModelExecutionCoordinator();
    final release = Completer<void>();
    var initCalls = 0;

    Future<void> initialize() async {
      initCalls++;
      await release.future;
    }

    final first = coordinator.ensureReady(initialize);
    final second = coordinator.ensureReady(initialize);

    expect(initCalls, 1);
    release.complete();
    await Future.wait([first, second]);

    expect(initCalls, 1);
    expect(coordinator.isReady, isTrue);
  });

  test('concurrent generation is serialized in acceptance order', () async {
    final coordinator = AiModelExecutionCoordinator();
    final firstRelease = Completer<void>();
    final events = <String>[];

    final first = coordinator.runExclusive(() async {
      events.add('first-start');
      await firstRelease.future;
      events.add('first-end');
      return 'first';
    });
    final second = coordinator.runExclusive(() async {
      events.add('second-start');
      events.add('second-end');
      return 'second';
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);

    firstRelease.complete();
    expect(await first, 'first');
    expect(await second, 'second');
    expect(events, [
      'first-start',
      'first-end',
      'second-start',
      'second-end',
    ]);
  });

  test('failed inference does not poison the next queued request', () async {
    final coordinator = AiModelExecutionCoordinator();

    final failed = coordinator.runExclusive<String>(() async {
      throw StateError('injected inference fault');
    });
    final recovered = coordinator.runExclusive(() async => 'recovered');

    await expectLater(failed, throwsStateError);
    expect(await recovered, 'recovered');
  });

  test('dispose drains accepted work, blocks new work, and can recover', () async {
    final coordinator = AiModelExecutionCoordinator();
    final release = Completer<void>();
    final events = <String>[];

    await coordinator.ensureReady(() async {
      events.add('init-1');
    });

    final inFlight = coordinator.runExclusive(() async {
      events.add('generation-start');
      await release.future;
      events.add('generation-end');
      return 1;
    });

    await Future<void>.delayed(Duration.zero);
    final disposing = coordinator.dispose(() async {
      events.add('dispose');
    });

    await expectLater(
      coordinator.runExclusive(() async => 2),
      throwsStateError,
    );

    release.complete();
    expect(await inFlight, 1);
    await disposing;

    expect(events, ['init-1', 'generation-start', 'generation-end', 'dispose']);
    expect(coordinator.isReady, isFalse);

    await coordinator.ensureReady(() async {
      events.add('init-2');
    });
    expect(coordinator.isReady, isTrue);
    expect(events.last, 'init-2');
  });
}
