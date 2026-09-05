# Dependency audit — 2026-09-05

Baseline: Flutter 3.47.2 / Dart SDK constraint `^3.9.2`.

This audit deliberately separates routine dependency refreshes from migrations that change APIs, platform floors, native toolchains, or the on-device model/runtime contract.

## Applied in this audit

### `file_picker`

- Lockfile refreshed from `11.0.2` to `11.0.3`.
- No source migration required.
- `flutter analyze`, the full functional suite, and all UI golden tests pass after the refresh.

### Gemma runtime pinning

The following packages are now exact-pinned in `pubspec.yaml`:

- `flutter_gemma: 1.6.5`
- `flutter_gemma_litertlm: 1.5.2`

They are intentionally coupled. A normal `flutter pub upgrade` must not silently change one side of the on-device inference stack while leaving the other side or the shipped `.litertlm` artifact unchanged.

Any future upgrade of this pair requires, at minimum:

1. package/API migration review;
2. model install + integrity verification;
3. real generation on the target `.litertlm` artifact;
4. lifecycle/fault-injection regression tests;
5. physical ARM64 Android validation.

## Deferred migrations

### `file_picker` 12.x

Not a routine lockfile update. Version 12 changes the plugin architecture and public picking API: `pickFiles()` returns a `List<PlatformFile>` rather than `FilePickerResult`, cancellation is represented by an empty list, and byte/stream access moves from `withData` / `withReadStream` flags to `PlatformFile` methods.

The app currently uses the v11 API in Home import/restore flows and AI Coach image attachment flows. Upgrade only in a dedicated migration PR with tests for cancel, single/multi-file selection, image bytes, and backup restore.

### `csv` 8.x

Deferred because the 8.x line contains codec/stream API changes. Migrate separately and validate import/export round-trips against existing backup fixtures before changing the constraint.

### `flutter_local_notifications` 20–22

Deferred. Version 20 converts several currently used positional APIs (`initialize`, `show`, `cancel`, `zonedSchedule`, etc.) to named parameters. Version 21 also raises platform/toolchain requirements, including Android API 24 minimum and compileSdk 36.

The app currently uses the pre-20 call style in `lib/local_notifications.dart`. Migrate notifications together with targeted Android notification tests and a real-device check for permission flow, scheduled workout reminders, and rest-timer completion.

### `timezone` 0.11.x

Deferred with the notification migration. Version 0.11 changes `Location.offset` from `int` to `Duration`; keeping timezone and notifications together reduces the chance of introducing scheduling drift in separate changes.

### `share_plus` 13.x

Deferred. The current app already uses `SharePlus.instance.share(ShareParams(...))`, but the 13.x line changes native dependency/toolchain requirements. Validate Android/iOS/macOS build floors and the workout-image share flow in a dedicated native-dependency PR.

### `wakelock_plus` 1.8.x

Deferred as a native/toolchain migration. The 1.7+ line raises Dart/Flutter requirements and changes native plugin integration; 1.8 targets the Flutter 3.47 generation. Upgrade separately with Android lifecycle tests and a device check that the active workout keeps the screen awake and reliably releases the wakelock on exit/background paths.

### `flutter_lints` 6.x

Deferred intentionally rather than mixed with runtime dependency work. It changes the static-analysis contract by adding lint rules such as `strict_top_level_inference` and `unnecessary_underscores`. Handle it as a small code-quality PR where analyzer fixes can be reviewed on their own.

### `flutter_gemma` 1.7.x + `flutter_gemma_litertlm` 1.6.x

Deferred from routine dependency maintenance. The current releases add a Hugging Face install path and a manifest-driven LiteRT-LM resolver. These are useful capabilities but touch the model installation/runtime boundary, so they require the ARM64 validation described above before adoption.

## Validation result

Safe refresh result on this branch:

- `flutter analyze`: PASS, zero issues;
- functional suite: 499 passed, 4 skipped golden-gated tests;
- explicit visual regression suite: 4/4 passed;
- `flutter_gemma` remained `1.6.5`;
- `flutter_gemma_litertlm` remained `1.5.2`.

The known non-failing FlutterGemma cleanup warning in tests remains unchanged and is not introduced by this dependency refresh.

## Maintenance rule

Use routine lockfile refreshes only for versions already admitted by reviewed constraints. Treat any dependency change that modifies public APIs, minimum OS versions, Gradle/Kotlin/Swift requirements, persistence formats, notification scheduling, or the on-device inference stack as a dedicated migration with its own regression coverage.
