from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'{label}: anchor not found')
    return text.replace(old, new, 1)


def block_bounds(text: str, marker: str):
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f'block marker not found: {marker}')
    brace = text.find('{', start)
    if brace < 0:
        raise RuntimeError(f'opening brace not found: {marker}')
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return start, i + 1
    raise RuntimeError(f'unclosed block: {marker}')


def replace_in_block(text: str, marker: str, old: str, new: str, label: str):
    start, end = block_bounds(text, marker)
    block = text[start:end]
    if old not in block:
        raise RuntimeError(f'{label}: anchor not found in {marker}')
    block = block.replace(old, new, 1)
    return text[:start] + block + text[end:]


Path('lib/routine_factory.dart').write_text(r'''import 'models/exercise.dart';
import 'models/schedule.dart';
import 'models/workout.dart';

/// Deterministic conversions between completed workouts and reusable routines.
class RoutineFactory {
  const RoutineFactory._();

  static Schedule fromSession(
    WorkoutSession session, {
    required String title,
    String folder = '',
    DateTime? createdAt,
  }) {
    final normalizedTitle = title.trim().isEmpty ? 'Nuova scheda' : title.trim();
    return Schedule(
      title: normalizedTitle,
      folder: folder.trim(),
      week: 1,
      createdAt: createdAt ?? DateTime.now(),
      exercises: session.exercises.map(_exerciseFromWorkout).toList(),
    );
  }

  static Exercise _exerciseFromWorkout(WorkoutExercise workout) {
    final workSets = workout.sets.where((set) => !set.isWarmup).toList();
    final completedWorkSets = workSets.where((set) => set.isCompleted).toList();
    final sourceSets = completedWorkSets.isNotEmpty
        ? completedWorkSets
        : workSets.isNotEmpty
        ? workSets
        : workout.sets;
    final referenceSet = sourceSets.isEmpty ? null : sourceSets.first;

    return Exercise(
      name: workout.name,
      reps: referenceSet?.reps ?? workout.targetMaxReps ?? workout.targetMinReps ?? 0,
      set: sourceSets.isEmpty ? 1 : sourceSets.length,
      notes: workout.notes,
      weight: referenceSet?.weight ?? 0,
      muscleGroup: workout.muscleGroup,
      equipment: workout.equipment,
      movementPattern: workout.movementPattern,
      targetMinReps: workout.targetMinReps,
      targetMaxReps: workout.targetMaxReps,
      technique: workout.technique,
      backoffReductionPercent: workout.backoffReductionPercent,
      restSeconds: workout.restSeconds,
      supersetGroup: workout.supersetGroup,
      progressionKgStep: workout.progressionKgStep,
      progressionRepStep: workout.progressionRepStep,
      progressionScheme: workout.progressionScheme,
    );
  }
}
''')

Path('test/routine_system_v2_test.dart').write_text(r'''import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/schedule.dart';
import 'package:gymapp/models/workout.dart';
import 'package:gymapp/routine_factory.dart';
import 'package:gymapp/screens/home.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('schedule folder survives JSON serialization', () {
    final schedule = Schedule(
      id: 'push',
      title: 'Push',
      folder: 'Upper / Lower',
      week: 1,
      createdAt: DateTime(2026, 8, 26),
      exercises: const [],
    );

    final restored = Schedule.fromJson(schedule.toJson());
    expect(restored.folder, 'Upper / Lower');
  });

  test('routine factory converts completed work sets and ignores warmups', () {
    final workoutExercise = WorkoutExercise(
      id: 'work-bench',
      name: 'Panca piana',
      notes: 'pausa al petto',
      muscleGroup: MuscleGroup.chest,
      equipment: 'Bilanciere',
      targetMinReps: 6,
      targetMaxReps: 8,
      technique: IntensityTechnique.none,
      restSeconds: 180,
      progressionKgStep: 2.5,
      progressionRepStep: 1,
      sets: [
        ExerciseSet(
          id: 'warmup',
          weight: 40,
          reps: 12,
          isCompleted: true,
          type: SetType.warmup,
        ),
        ExerciseSet(
          id: 'work-1',
          weight: 80,
          reps: 8,
          isCompleted: true,
        ),
        ExerciseSet(
          id: 'work-2',
          weight: 80,
          reps: 7,
          isCompleted: true,
        ),
        ExerciseSet(
          id: 'unfinished',
          weight: 80,
          reps: 6,
          isCompleted: false,
        ),
      ],
    );
    final session = WorkoutSession(
      id: 'session',
      scheduleTitle: 'Push',
      startTime: DateTime(2026, 8, 26, 18),
      endTime: DateTime(2026, 8, 26, 19),
      exercises: [workoutExercise],
    );

    final routine = RoutineFactory.fromSession(
      session,
      title: 'Push salvata',
      folder: 'I miei programmi',
      createdAt: DateTime(2026, 8, 26),
    );

    expect(routine.title, 'Push salvata');
    expect(routine.folder, 'I miei programmi');
    expect(routine.exercises, hasLength(1));
    final exercise = routine.exercises.single;
    expect(exercise.id, isNot(workoutExercise.id));
    expect(exercise.set, 2);
    expect(exercise.weight, 80);
    expect(exercise.reps, 8);
    expect(exercise.targetMinReps, 6);
    expect(exercise.targetMaxReps, 8);
    expect(exercise.restSeconds, 180);
  });

  testWidgets('schedule can be moved into a routine folder', (tester) async {
    final schedule = Schedule(
      id: 'schedule_1',
      title: 'Push',
      week: 1,
      createdAt: DateTime(2026),
      exercises: const [],
    );
    SharedPreferences.setMockInitialValues({
      'schedules': jsonEncode([schedule.toJson()]),
      'history': '[]',
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cartella'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Upper / Lower');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Salva'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Upper / Lower'), findsWidgets);
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('schedules')!) as List;
    expect(stored.single['folder'], 'Upper / Lower');
  });
}
''')

# Schedule model: backward-compatible folder field.
path = Path('lib/models/schedule.dart')
text = path.read_text()
text = replace_once(text, "  String title;\n  int week;", "  String title;\n  String folder;\n  int week;", 'schedule folder field')
text = replace_once(text, "    required this.title,\n    required this.week,", "    required this.title,\n    this.folder = '',\n    required this.week,", 'schedule folder constructor')
text = replace_once(text, "    'title': title,\n    'week': week,", "    'title': title,\n    'folder': folder,\n    'week': week,", 'schedule folder json')
text = replace_once(text, "    title: json['title'],\n    week: json['week'],", "    title: json['title'],\n    folder: json['folder'] as String? ?? '',\n    week: json['week'],", 'schedule folder from json')
path.write_text(text)

# SQLite v2 migration and persistence.
path = Path('lib/local_sqlite_store.dart')
text = path.read_text()
text = replace_once(
    text,
    "        version: 1,\n        onConfigure: (db) async {",
    "        version: 2,\n        onConfigure: (db) async {",
    'sqlite version',
)
text = replace_once(
    text,
    "        onCreate: _createSchema,\n",
    "        onCreate: _createSchema,\n        onUpgrade: _upgradeSchema,\n",
    'sqlite onUpgrade',
)
upgrade = r'''  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE schedules ADD COLUMN folder TEXT NOT NULL DEFAULT ''",
      );
    }
  }

'''
text = replace_once(text, "  Future<void> _createSchema(Database db, int version) async {\n", upgrade + "  Future<void> _createSchema(Database db, int version) async {\n", 'sqlite upgrade method')
text = replace_once(text, "        title TEXT NOT NULL,\n        week INTEGER NOT NULL,", "        title TEXT NOT NULL,\n        folder TEXT NOT NULL,\n        week INTEGER NOT NULL,", 'sqlite folder schema')
text = replace_once(text, "      'title': schedule.title,\n      'week': schedule.week,", "      'title': schedule.title,\n      'folder': schedule.folder,\n      'week': schedule.week,", 'sqlite folder insert')
text = replace_once(text, "          title: row['title'] as String,\n          week: row['week'] as int,", "          title: row['title'] as String,\n          folder: row['folder'] as String? ?? '',\n          week: row['week'] as int,", 'sqlite folder load')
path.write_text(text)

# Existing SQLite roundtrip must include folder.
path = Path('test/local_sqlite_store_test.dart')
text = path.read_text()
text = replace_once(text, "        title: 'Push',\n        week: 2,", "        title: 'Push',\n        folder: 'Upper / Lower',\n        week: 2,", 'sqlite test folder fixture')
text = replace_once(text, "      expect(data.schedules.single.id, 'push');\n", "      expect(data.schedules.single.id, 'push');\n      expect(data.schedules.single.folder, 'Upper / Lower');\n", 'sqlite test folder assertion')
path.write_text(text)

# Home integration.
path = Path('lib/screens/home.dart')
text = path.read_text()
text = replace_once(text, "import '../number_input.dart';\n", "import '../number_input.dart';\nimport '../routine_factory.dart';\n", 'home routine factory import')
text = replace_once(
    text,
    "enum _ScheduleMenuAction { rename, duplicate, toggleArchive, delete }",
    "enum _ScheduleMenuAction { rename, duplicate, folder, toggleArchive, delete }",
    'home schedule menu enum',
)
text = replace_once(text, "  int? _selectedWeekFilter;\n", "  int? _selectedWeekFilter;\n  String? _selectedFolderFilter;\n", 'home folder filter state')

# Add folder filtering.
text = replace_in_block(
    text,
    "  List<Schedule> _filteredSchedules()",
    "      if (_selectedWeekFilter != null &&\n          schedule.currentWeek() != _selectedWeekFilter) {\n        return false;\n      }\n\n",
    "      if (_selectedWeekFilter != null &&\n          schedule.currentWeek() != _selectedWeekFilter) {\n        return false;\n      }\n\n      if (_selectedFolderFilter != null &&\n          schedule.folder.trim() != _selectedFolderFilter) {\n        return false;\n      }\n\n",
    'home folder filter predicate',
)

# Add helper and actions before duplicate schedule method.
methods = r'''  List<String> _availableRoutineFolders() {
    final folders = schedules
        .map((schedule) => schedule.folder.trim())
        .where((folder) => folder.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return folders;
  }

  Future<void> _moveScheduleToFolder(Schedule schedule) async {
    final controller = TextEditingController(text: schedule.folder);
    final folder = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cartella scheda'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Cartella',
            hintText: 'Es. Upper / Lower',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (folder == null || !mounted) return;
    setState(() {
      schedule.folder = folder;
      if (_selectedFolderFilter != null && folder != _selectedFolderFilter) {
        _selectedFolderFilter = null;
      }
      _sortSchedules();
    });
    await _saveSchedules();
  }

  Future<void> _saveHistoryAsRoutine(WorkoutSession session) async {
    final defaultTitle = session.scheduleTitle.trim().isEmpty ||
            session.scheduleTitle == 'Allenamento libero'
        ? 'Nuova scheda'
        : '${session.scheduleTitle} copia';
    final titleController = TextEditingController(text: defaultTitle);
    final folderController = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salva come scheda'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nome scheda'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: folderController,
              decoration: const InputDecoration(
                labelText: 'Cartella (opzionale)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, [
              titleController.text.trim(),
              folderController.text.trim(),
            ]),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    titleController.dispose();
    folderController.dispose();
    if (result == null || !mounted) return;

    final routine = RoutineFactory.fromSession(
      session,
      title: result.first,
      folder: result.length > 1 ? result[1] : '',
    );
    setState(() {
      schedules.add(routine);
      _sortSchedules();
    });
    await _saveSchedules();
    _showInfo('Scheda salvata da ${session.scheduleTitle}.');
  }

'''
marker = "  void _duplicateSchedule(Schedule schedule)"
idx = text.find(marker)
if idx < 0:
    raise RuntimeError('duplicate schedule marker missing')
text = text[:idx] + methods + text[idx:]

# Duplicate stays in same folder.
text = replace_in_block(
    text,
    "  void _duplicateSchedule(Schedule schedule)",
    "      title: '${schedule.title} copia',",
    "      title: '${schedule.title} copia',\n      folder: schedule.folder,",
    'duplicate preserves folder',
) if "      title: '${schedule.title} copia'," in text[block_bounds(text, "  void _duplicateSchedule(Schedule schedule)")[0]:block_bounds(text, "  void _duplicateSchedule(Schedule schedule)")[1]] else text

# Add menu action handler.
text = replace_in_block(
    text,
    "  Widget _buildSchedulesTab()",
    "                                  case _ScheduleMenuAction.duplicate:\n                                    _duplicateSchedule(schedule);\n                                    break;\n",
    "                                  case _ScheduleMenuAction.duplicate:\n                                    _duplicateSchedule(schedule);\n                                    break;\n                                  case _ScheduleMenuAction.folder:\n                                    _moveScheduleToFolder(schedule);\n                                    break;\n",
    'folder menu handler',
)
# Add menu item before archive action.
text = replace_in_block(
    text,
    "  Widget _buildSchedulesTab()",
    "                                const PopupMenuItem(\n                                  value: _ScheduleMenuAction.toggleArchive,",
    "                                const PopupMenuItem(\n                                  value: _ScheduleMenuAction.folder,\n                                  child: ListTile(\n                                    leading: Icon(Icons.folder_outlined),\n                                    title: Text('Cartella'),\n                                  ),\n                                ),\n                                const PopupMenuItem(\n                                  value: _ScheduleMenuAction.toggleArchive,",
    'folder menu item',
)
# Show folder in schedule summary.
text = replace_in_block(
    text,
    "  Widget _buildSchedulesTab()",
    "'${schedule.exercises.length} esercizi${schedule.isDeloadWeek() ? ' • deload' : ''}",
    "'${schedule.exercises.length} esercizi${schedule.folder.trim().isEmpty ? '' : ' • ${schedule.folder}'}${schedule.isDeloadWeek() ? ' • deload' : ''}",
    'folder subtitle',
)

# Folder dropdown next to week filter.
text = replace_in_block(
    text,
    "  Widget _buildSchedulesTab()",
    "    final availableWeeks = _availableWeeks();\n",
    "    final availableWeeks = _availableWeeks();\n    final availableFolders = _availableRoutineFolders();\n    final selectedFolderValue = availableFolders.contains(_selectedFolderFilter)\n        ? _selectedFolderFilter\n        : null;\n",
    'folder filter data',
)
folder_dropdown = r'''                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String?>(
                      initialValue: selectedFolderValue,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Cartella'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Tutte'),
                        ),
                        ...availableFolders.map(
                          (folder) => DropdownMenuItem<String?>(
                            value: folder,
                            child: Text(folder),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedFolderFilter = value);
                      },
                    ),
                  ),
'''
text = replace_in_block(
    text,
    "  Widget _buildSchedulesTab()",
    "                children: [\n                  SizedBox(\n                    width: 190,\n                    child: DropdownButtonFormField<int?>(",
    "                children: [\n" + folder_dropdown + "                  SizedBox(\n                    width: 190,\n                    child: DropdownButtonFormField<int?>(",
    'folder filter dropdown',
)

# History: save completed workout as a routine.
text = replace_in_block(
    text,
    "  Widget _buildHistoryTab()",
    "                      IconButton(\n                        tooltip: 'Modifica allenamento',",
    "                      IconButton(\n                        tooltip: 'Salva come scheda',\n                        icon: const Icon(Icons.bookmark_add_outlined),\n                        onPressed: () => _saveHistoryAsRoutine(session),\n                      ),\n                      IconButton(\n                        tooltip: 'Modifica allenamento',",
    'history save routine action',
)
path.write_text(text)

# Sort routines by folder within archived state.
path = Path('lib/home_data_policy.dart')
text = path.read_text()
text = replace_once(
    text,
    "      final weekCompare = a.currentWeek().compareTo(b.currentWeek());\n",
    "      final folderCompare = a.folder.toLowerCase().compareTo(\n        b.folder.toLowerCase(),\n      );\n      if (folderCompare != 0) {\n        return folderCompare;\n      }\n\n      final weekCompare = a.currentWeek().compareTo(b.currentWeek());\n",
    'routine folder ordering',
)
path.write_text(text)
