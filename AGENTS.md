# AGENTS.md

## Project

Flutter app (Dart SDK ^3.9.2). Single-package, no monorepo. Pure client-side storage via `shared_preferences` — no backend or network calls.

## Commands

- `flutter test` — run all tests
- `flutter test test/<file>.dart` — run a single test file
- `dart analyze` — lint (uses `flutter_lints` rules from `analysis_options.yaml`)
- `flutter pub run flutter_launcher_icons` — regenerate platform launcher icons after editing `assets/app_icon.png`

## Graphify Commands

- Windows: use `graphify.cmd`, not `graphify`, to avoid PowerShell execution-policy issues.
- First/full project index: `graphify.cmd update . --all`
- Normal refresh from repo root: `graphify.cmd update .`
- Check whether graph needs refresh: `graphify.cmd check-update .`
- Project summary: `graphify.cmd summary`
- Ask graph question: `graphify.cmd query "where is exercise editing handled?"`
- Query with token cap: `graphify.cmd query "where are schedules saved?" --budget 1200`
- Use explicit graph path if needed: `graphify.cmd query "home screen flow" --graph .graphify\graph.json`
- Do not use `graphify.cmd build .`; this installed CLI has no `build` command.

## Testing quirks

- Every test file must call `SharedPreferences.setMockInitialValues({})` in `setUp`, otherwise tests fail silently.
- Seed data via `SharedPreferences.setMockInitialValues({'schedules': jsonEncode(...), 'history': '[]'})`.
- After widget interaction, await `tester.pumpAndSettle()` for async prefs to flush before assertions.

## Architecture

- Entry point: `lib/main.dart` → `HomePage` as root route (no router).
- Models in `lib/models/`: `Schedule`, `Exercise`, `WorkoutSession`, `WorkoutExercise`. All self-generate IDs on construction if absent (legacy JSON migration support).
- Screens in `lib/screens/`: `home`, `schedule_detail`, `active_workout`, `stats`, `settings`.
- Persistence layer: `lib/app_preferences.dart` wraps `SharedPreferences` with typed accessors.

## App icon

Configured via `flutter_launcher_icons` in `pubspec.yaml`. Source image is `assets/app_icon.png`. Run the pub command above after changing it.
