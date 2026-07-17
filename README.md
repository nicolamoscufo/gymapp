# FitFlow (gymapp)

Privacy-first Flutter workout tracker for schedules, training history, body logs,
statistics, and optional on-device coaching with Gemma 4 E2B. Workout and chat
data stay on the device; the model is downloaded only when the user enables the
AI coach.

## Main features

- Create and edit workout schedules.
- Import schedules from CSV.
- Export schedules to CSV.
- Export and restore a full JSON backup, including history.
- Archive, duplicate, search, and filter schedules by week.
- Track completed workouts and view volume statistics.
- Generate conservative workout recaps and weekly reports locally with Gemma.
- Chat with an on-device coach that uses the user's logged training context.
- Compare progress photos locally, with explicit non-medical safety guidance.

## Local development

Requirements: Flutter compatible with Dart 3.9 and an Android device/emulator
for the LiteRT-LM model flow.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

The optional Gemma model is about 2.4 GB. Do not commit model files, generated
build output, IDE indexes, or personal training exports.

## CSV format

Each row must contain 7 columns in this order:

1. Schedule title
2. Week number
3. Exercise name
4. Sets
5. Reps
6. Weight
7. Notes

Example:

```csv
Push,4,Panca piana,4,2,120.0,
Push,4,Spinte su panca inclinata,2,9,32.0,3s iso sotto 3s discesa
```

The app accepts both comma-separated and semicolon-separated CSV files, and it skips a header row automatically if present.

## Backup format

The JSON backup contains both `schedules` and `history`. Use the export menu from the home screen to save it, then restore it later from the same menu.
