# Graph Report - .  (2026-05-26)

## Corpus Check
- Corpus is ~26.733 words - fits in a single context window. You may not need a graph.

## Summary
- 175 nodes · 164 edges · 13 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output


## Input Scope
- Requested: auto
- Resolved: committed (source: default-auto)
- Included files: 96 · Candidates: 152
- Excluded: 49 untracked · 5317 ignored · 0 sensitive · 0 missing committed
- Recommendation: Use --scope all or graphify.yaml inputs.corpus for a knowledge-base folder.

## Graph Freshness
- Built from Git commit: `8b1a9c5`
- Compare this hash to `git rev-parse HEAD` before trusting freshness-sensitive graph output.
## God Nodes (most connected - your core abstractions)
1. `Create()` - 6 edges
2. `Destroy()` - 6 edges
3. `MessageHandler()` - 5 edges
4. `Win32Window::WndProc()` - 4 edges
5. `GetClientArea()` - 3 edges
6. `UpdateTheme()` - 3 edges
7. `FlutterWindow()` - 2 edges
8. `GetCommandLineArguments()` - 2 edges
9. `Utf8FromUtf16()` - 2 edges
10. `Scale()` - 2 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Communities

### Community 12 - "Community 12"
Cohesion: 0.67
Nodes (1): AppPreferences

### Community 6 - "Community 6"
Cohesion: 0.29
Nodes (2): MainApp, _MainAppState

### Community 15 - "Community 15"
Cohesion: 1
Nodes (1): Exercise

### Community 9 - "Community 9"
Cohesion: 0.5
Nodes (1): Schedule

### Community 10 - "Community 10"
Cohesion: 0.5
Nodes (3): ExerciseSet, WorkoutExercise, WorkoutSession

### Community 1 - "Community 1"
Cohesion: 0.07
Nodes (2): ActiveWorkoutScreen, _ActiveWorkoutScreenState

### Community 0 - "Community 0"
Cohesion: 0.05
Nodes (2): HomePage, _HomePageState

### Community 5 - "Community 5"
Cohesion: 0.22
Nodes (2): ScheduleDetailScreen, _ScheduleDetailScreenState

### Community 7 - "Community 7"
Cohesion: 0.33
Nodes (2): SettingsScreen, _SettingsScreenState

### Community 3 - "Community 3"
Cohesion: 0.17
Nodes (6): StatsScreen, _MetricCard, _PeriodVolume, _DailyVolume, _ExerciseSummary, _MuscleGroupWeeklyStats

### Community 8 - "Community 8"
Cohesion: 0.33
Nodes (1): FlutterWindow()

### Community 11 - "Community 11"
Cohesion: 0.67
Nodes (2): GetCommandLineArguments(), Utf8FromUtf16()

### Community 2 - "Community 2"
Cohesion: 0.17
Nodes (16): Scale(), EnableFullDpiSupportIfAvailable(), WindowClassRegistrar, GetWindowClass(), UnregisterWindowClass(), Win32Window(), Create(), Win32Window::WndProc() (+8 more)

## Knowledge Gaps
- **22 isolated node(s):** `AppPreferences`, `MainApp`, `_MainAppState`, `Exercise`, `Schedule` (+17 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 12`** (1 nodes): `AppPreferences`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 6`** (2 nodes): `MainApp`, `_MainAppState`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 15`** (1 nodes): `Exercise`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 9`** (1 nodes): `Schedule`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 1`** (2 nodes): `ActiveWorkoutScreen`, `_ActiveWorkoutScreenState`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 0`** (2 nodes): `HomePage`, `_HomePageState`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 5`** (2 nodes): `ScheduleDetailScreen`, `_ScheduleDetailScreenState`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 7`** (2 nodes): `SettingsScreen`, `_SettingsScreenState`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 8`** (1 nodes): `FlutterWindow()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 11`** (2 nodes): `GetCommandLineArguments()`, `Utf8FromUtf16()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `AppPreferences`, `MainApp`, `_MainAppState` to the rest of the system?**
  _22 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.05 - nodes in this community are weakly interconnected._