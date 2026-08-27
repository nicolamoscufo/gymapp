# AGENTS.md

## Project

`gymapp` is a single-package Flutter application written in Dart (SDK `^3.9.2`). It is a privacy-first workout tracker with local persistence and an on-device AI Coach. The AI runtime uses `flutter_gemma` / LiteRT-LM; model installation downloads the configured Gemma model, while inference and training data processing are local.

The repository is not a monorepo and has no application backend or Docker build.

## Repository map

- `lib/main.dart` — application entry point.
- `lib/models/` — persisted domain models such as schedules, exercises and workout sessions.
- `lib/screens/` — Flutter screens and user-facing flows.
- `lib/ai_coach/` — local LLM integration, prompts, structured action protocol, program-draft flow, memory/context and exercise-catalog retrieval.
- `lib/app_data_store.dart` — normalized SQLite-backed application data store and migrations.
- `lib/app_preferences.dart` — lightweight preferences stored with `SharedPreferences`.
- `lib/exercise_catalog.dart` and `lib/exercise_catalog_identity.dart` — local exercise-catalog loading and identity handling.
- `esercizi2_en_fields_minified.json` — bundled exercise catalog used by the app and AI retrieval layer.
- `test/` — unit and widget tests.
- `android/`, `ios/`, `linux/`, `macos/`, `windows/` — Flutter platform hosts.
- `.github/workflows/` — CI, security scanning and Graphify refresh workflows.
- `.semgrep/` — repository-specific low-noise Dart security rules.
- `graphify-out/` — committed code-intelligence outputs when generated.

## Build and dependency commands

Run commands from the repository root.

- `flutter pub get` — resolve dependencies.
- `flutter run` — run the app on a selected target.
- `flutter build apk` — Android release build when an APK is needed.
- `flutter pub run flutter_launcher_icons` — regenerate launcher icons after changing `assets/app_icon.png`.

Do not add another package manager for Dart dependencies; `pubspec.yaml` and `pubspec.lock` are authoritative.

## Formatting, linting and type checking

- `dart format lib test` — apply canonical Dart formatting.
- `dart format --output=none --set-exit-if-changed lib test` — CI formatting check.
- `flutter analyze` — lint and static/type analysis using `analysis_options.yaml` and `flutter_lints`.

Do not introduce a second Dart linter or type checker unless there is a concrete gap that `flutter analyze` cannot cover.

## Tests and coverage

- `flutter test` — run the full unit/widget suite.
- `flutter test test/<file>.dart` — run one test file.
- `flutter test --coverage` — run tests and write standard LCOV output to `coverage/lcov.info`.

Tests that use Flutter services, assets, `SharedPreferences`, or SQLite may require Flutter test binding setup and the repository's existing mocks/FFI initialization. Follow nearby tests rather than inventing a parallel test harness.

Never disable, skip or weaken an existing test merely to make CI pass.

## Persistence and migration conventions

- SQLite schema changes must preserve upgrade paths in `AppDataStore`; do not silently discard existing user data.
- `SharedPreferences` is for lightweight preferences/flags, not a replacement for normalized workout data.
- Persisted IDs and `catalogId` values are identity contracts. Do not silently backfill or rewrite legacy/custom exercise identity unless the feature explicitly defines a safe migration.
- Exercise-catalog resolution must fail closed on ambiguous matches; custom exercises remain custom unless a unique canonical match is established.

## AI Coach conventions

- Treat model output as untrusted input. Keep structured parsing/validation between Gemma output and persisted application state.
- Deterministic application logic and persisted training facts take precedence over generative claims.
- Keep the local exercise catalog as retrieval context; do not dump the full catalog into prompts.
- When catalog metadata is used, preserve canonical fields and `catalogId` semantics.
- Do not add secrets, tokens or private user data to prompts, fixtures, logs or repository files.
- Changes to action schemas, persistence or program-draft commit behavior require focused tests for malformed/ambiguous model output.

## Files and generated content

Do not hand-edit Flutter-generated build artifacts under `build/` or `.dart_tool/`.

`graphify-out/graph.json`, `graphify-out/graph.html`, and `graphify-out/GRAPH_REPORT.md` are generated code-intelligence artifacts. Prefer refreshing them with Graphify rather than editing them manually. Legacy `.graphify/` output is intentionally not authoritative.

Large bundled exercise data files should not be reformatted or rewritten unless the task is explicitly about catalog data.

## Code intelligence with Graphify

For broad architectural questions, impact analysis, cross-file dependency tracing, callers/callees, references, boundaries, or module discovery, consult these files first when present:

1. `graphify-out/GRAPH_REPORT.md`
2. `graphify-out/graph.json`
3. the relevant source files

Use the graph to identify candidate modules, dependency paths, high-connectivity nodes, callers/callees, references and likely impact areas. Then verify every delicate or behavior-changing conclusion against the source code and tests.

**Graphify is a structural index; source code remains the final source of truth.** A stale or incomplete graph must never override what the code actually does.

Useful local commands after installing the official `graphifyy` package:

- `graphify query "<question>"`
- `graphify path "<symbol A>" "<symbol B>"`
- `graphify explain "<concept>"`
- `graphify update .`

For a repository-scoped Codex setup, run `tool/setup_graphify.sh`. The underlying supported install command is `graphify install --project --platform codex`.

## Security tooling

- Semgrep uses `.semgrep/dart-security.yml` for focused Dart security checks.
- Trivy scans `pubspec.lock`, repository configuration and secrets/misconfiguration surfaces.
- CodeQL is intentionally limited to GitHub Actions because CodeQL does not support Dart source analysis.
- Dependabot covers both Dart/pub dependencies and GitHub Actions.

Do not hardcode API keys, tokens, passwords or CI credentials. GitHub Actions should use least-privilege `permissions`, avoid executing privileged code from untrusted pull requests, and avoid unnecessary write tokens.

## Validation before a change is complete

At minimum, for Dart/application changes run:

1. `dart format --output=none --set-exit-if-changed lib test`
2. `flutter analyze`
3. `flutter test`

For dependency, workflow or security-tooling changes, also inspect the corresponding GitHub Actions results. For broad structural changes, refresh Graphify and verify the resulting impact area against source and tests.
