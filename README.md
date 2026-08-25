# gymapp

Privacy-first Flutter workout tracker with training schedules, workout history, statistics, body tracking, and an on-device AI coach.

## Main features

- Create and edit workout schedules and mesocycles.
- Track completed workouts, sets, loads, RIR/RPE, notes, rest times, and progression.
- Browse workout history, calendar views, body logs, and training statistics.
- Import and export schedules/history/body data as CSV.
- Export and restore a full JSON backup.
- Archive, duplicate, search, and filter schedules.
- Use the AI Coach to analyze recent training data and chat about training locally on the device.

## On-device AI Coach

The AI Coach uses `flutter_gemma` with the LiteRT-LM backend and is designed around Gemma 4 E2B.

The model is not bundled in the application package. The first time the user enables the coach, the app downloads `gemma-4-E2B-it.litertlm` (roughly 2.6 GB). The network is used for that model download; inference and the training context used by the coach run locally on the device afterwards.

The coach can use local app data such as workout history, schedules, set notes, RIR/RPE, training volume, body logs, and the optional AI Coach profile. Chat conversations, profile data, and coach memory are persisted locally.

Current AI capabilities include:

- multi-turn training chat;
- latest-workout recap;
- weekly training report;
- weak-point analysis;
- training-note summaries;
- suggested workout adjustments that require user confirmation;
- multimodal progress-photo input when supported by the installed model/runtime.

## CSV format

Legacy schedule CSV rows contain 7 columns in this order:

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

The app accepts both comma-separated and semicolon-separated CSV files, skips a header row automatically when present, and also supports its newer extended CSV schema.

## Backup format

The JSON backup contains schedules, workout history, body logs, the current workout session, custom exercises, and favorites when available. Use the export/restore tools from the app to move or recover local data.

## Development

The repository includes a Flutter CI workflow that runs dependency resolution, static analysis, and tests on pushes and pull requests.
