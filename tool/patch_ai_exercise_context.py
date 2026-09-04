from pathlib import Path

service_path = Path('lib/ai_coach/local_ai_coach_service.dart')
service = service_path.read_text()

service = service.replace(
    "import 'ai_coach_context_router.dart';\n",
    "import 'ai_coach_context_router.dart';\nimport 'ai_coach_exercise_context.dart';\n",
    1,
)

service = service.replace(
    "  final AiCoachContextRouter contextRouter;\n  final AiCoachMemoryUpdater memoryUpdater;\n",
    "  final AiCoachContextRouter contextRouter;\n  final AiCoachExerciseContextResolver exerciseContextResolver;\n  final AiCoachExerciseContextFilter exerciseContextFilter;\n  final AiCoachMemoryUpdater memoryUpdater;\n",
    1,
)

service = service.replace(
    "    this.contextRouter = const AiCoachContextRouter(),\n    this.memoryUpdater = const AiCoachMemoryUpdater(),\n",
    "    this.contextRouter = const AiCoachContextRouter(),\n    this.exerciseContextResolver = const AiCoachExerciseContextResolver(),\n    this.exerciseContextFilter = const AiCoachExerciseContextFilter(),\n    this.memoryUpdater = const AiCoachMemoryUpdater(),\n",
    1,
)

anchor = """    final longitudinal = _looksLongitudinal(latestUserQuery);\n    final intent = contextRouter.classify(latestUserQuery);\n"""
replacement = """    final exerciseFocus = focusContext == null || focusContext.isEmpty
        ? exerciseContextResolver.resolve(
            query: latestUserQuery,
            candidates: [
              for (final schedule in schedules)
                for (final exercise in schedule.exercises)
                  AiCoachExerciseCandidate(
                    name: exercise.name,
                    sourceExerciseId: exercise.id,
                    catalogId: exercise.catalogId,
                  ),
              for (final session in history)
                for (final exercise in session.exercises)
                  AiCoachExerciseCandidate(
                    name: exercise.name,
                    sourceExerciseId: exercise.sourceExerciseId,
                    catalogId: exercise.catalogId,
                  ),
            ],
          )
        : null;

    final longitudinal = _looksLongitudinal(latestUserQuery);
    final intent = contextRouter.classify(latestUserQuery);
"""
if anchor not in service:
    raise RuntimeError('exercise focus insertion anchor missing')
service = service.replace(anchor, replacement, 1)

old_route = """    final routedContext = contextRouter.route(
      compactContext,
      intent: intent,
      keepProgramHistory: longitudinal,
    );
    final contextJson = _encodeBoundedContext(
      routedContext,
"""
new_route = """    var routedContext = contextRouter.route(
      compactContext,
      intent: intent,
      keepProgramHistory: longitudinal,
    );
    if (exerciseFocus != null) {
      routedContext = exerciseContextFilter.apply(
        routedContext,
        focus: exerciseFocus,
        intent: intent,
      );
    }
    final contextJson = _encodeBoundedContext(
      routedContext,
"""
if old_route not in service:
    raise RuntimeError('route anchor missing')
service = service.replace(old_route, new_route, 1)

policy = "- Use focus_context first when present. Use program_history only when present.\n"
service = service.replace(
    policy,
    policy + "- When exercise_focus is present, treat it as the deterministic scope of the named exercise and do not use omitted exercises as evidence.\n",
    1,
)

service_path.write_text(service)

builder_path = Path('lib/ai_coach/training_context_builder.dart')
builder = builder_path.read_text()
old = """          (exercise) => {
            'catalog_id': exercise.catalogId,
            'name': exercise.name,
"""
new = """          (exercise) => {
            'source_exercise_id': exercise.sourceExerciseId,
            'catalog_id': exercise.catalogId,
            'name': exercise.name,
"""
if old not in builder:
    raise RuntimeError('training context exercise anchor missing')
builder = builder.replace(old, new, 1)
builder_path.write_text(builder)
