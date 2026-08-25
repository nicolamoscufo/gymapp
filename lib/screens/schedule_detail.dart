import 'package:flutter/material.dart';
import '../app_data_store.dart';
import '../dialog_form.dart';
import '../exercise_catalog.dart';
import '../models/schedule.dart';
import '../models/exercise.dart';
import '../models/workout.dart';
import '../number_input.dart';
import 'active_workout.dart';
import 'exercise_picker.dart';

class ScheduleDetailScreen extends StatefulWidget {
  final Schedule schedule;
  final List<WorkoutSession> history;
  final int defaultRestSeconds;
  final double defaultBackoffReductionPercent;
  final VoidCallback onUpdate;

  const ScheduleDetailScreen({
    super.key,
    required this.schedule,
    this.history = const [],
    required this.defaultRestSeconds,
    required this.defaultBackoffReductionPercent,
    required this.onUpdate,
  });

  @override
  State<ScheduleDetailScreen> createState() => _ScheduleDetailScreenState();
}

class _ScheduleDetailScreenState extends State<ScheduleDetailScreen> {
  Color _accentForIndex(ColorScheme colorScheme, int index) {
    final accents = [
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      colorScheme.error,
    ];
    return accents[index % accents.length];
  }

  String _techniqueLabel(IntensityTechnique technique) {
    switch (technique) {
      case IntensityTechnique.none:
        return 'Nessuna tecnica';
      case IntensityTechnique.dropSet:
        return 'Drop Set';
      case IntensityTechnique.restPause:
        return 'Rest-Pause';
      case IntensityTechnique.superSet:
        return 'Superset';
      case IntensityTechnique.cluster:
        return 'Cluster Set';
      case IntensityTechnique.isometric:
        return 'Isometria';
      case IntensityTechnique.negative:
        return 'Ripetizioni negative';
      case IntensityTechnique.forcedReps:
        return 'Ripetizioni forzate';
      case IntensityTechnique.topsetBackoff:
        return 'Top Set / Back off';
    }
  }

  String _weekdayLabel(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'Lun',
      DateTime.tuesday => 'Mar',
      DateTime.wednesday => 'Mer',
      DateTime.thursday => 'Gio',
      DateTime.friday => 'Ven',
      DateTime.saturday => 'Sab',
      DateTime.sunday => 'Dom',
      _ => '?',
    };
  }

  Future<void> _showScheduleProgramDialog() async {
    final goalController = TextEditingController(text: widget.schedule.goal);
    final mesocycleController = TextEditingController(
      text: widget.schedule.mesocycleWeeks.toString(),
    );
    final deloadController = TextEditingController(
      text: widget.schedule.deloadEveryWeeks.toString(),
    );
    final blockController = TextEditingController(
      text: widget.schedule.programBlock,
    );
    final cycleController = TextEditingController(
      text: widget.schedule.cycleNumber.toString(),
    );
    final cycleNotesController = TextEditingController(
      text: widget.schedule.cycleNotes,
    );
    final selectedDays = widget.schedule.trainingWeekdays.toSet();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Programmazione'),
          content: AppDialogContent(
            children: [
              TextField(
                controller: goalController,
                decoration: const InputDecoration(labelText: 'Obiettivo'),
              ),
              appDialogFieldGap,
              AppFieldRow(
                children: [
                  TextField(
                    controller: mesocycleController,
                    decoration: const InputDecoration(labelText: 'Settimane'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: deloadController,
                    decoration: const InputDecoration(labelText: 'Deload ogni'),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              appDialogFieldGap,
              TextField(
                controller: blockController,
                decoration: const InputDecoration(labelText: 'Blocco'),
              ),
              appDialogFieldGap,
              AppFieldRow(
                children: [
                  TextField(
                    controller: cycleController,
                    decoration: const InputDecoration(labelText: 'Ciclo'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: cycleNotesController,
                    decoration: const InputDecoration(labelText: 'Note ciclo'),
                  ),
                ],
              ),
              appDialogFieldGap,
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Giorni allenamento',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(7, (index) {
                  final weekday = index + 1;
                  return FilterChip(
                    label: Text(_weekdayLabel(weekday)),
                    selected: selectedDays.contains(weekday),
                    onSelected: (selected) => setDialogState(() {
                      if (selected) {
                        selectedDays.add(weekday);
                      } else {
                        selectedDays.remove(weekday);
                      }
                    }),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      return;
    }

    setState(() {
      widget.schedule.goal = goalController.text.trim();
      widget.schedule.mesocycleWeeks =
          parseIntInput(mesocycleController.text) ??
          widget.schedule.mesocycleWeeks;
      widget.schedule.deloadEveryWeeks =
          parseIntInput(deloadController.text) ??
          widget.schedule.deloadEveryWeeks;
      widget.schedule.trainingWeekdays = selectedDays.toList()..sort();
      widget.schedule.programBlock = blockController.text.trim();
      widget.schedule.cycleNumber =
          parseIntInput(cycleController.text) ?? widget.schedule.cycleNumber;
      widget.schedule.cycleNotes = cycleNotesController.text.trim();
    });
    widget.onUpdate();
  }

  Future<void> _resetCycle() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset ciclo?'),
        content: const Text('La scheda torna a week 1 da oggi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => widget.schedule.resetCycle());
    widget.onUpdate();
  }

  Future<void> _completeMesocycle() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fine mesociclo?'),
        content: const Text(
          'Apre ciclo successivo e riporta la scheda a week 1.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Chiudi mesociclo'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => widget.schedule.completeMesocycle());
    widget.onUpdate();
  }

  void _showUndoSnackBar({
    required String message,
    required VoidCallback onUndo,
  }) {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'ANNULLA', onPressed: onUndo),
      ),
    );
  }

  void _addExercise(
    String name,
    int sets,
    int reps,
    double weight,
    MuscleGroup muscleGroup,
    String equipment,
    String movementPattern,
    int? targetMinReps,
    int? targetMaxReps,
    String notes,
    IntensityTechnique technique,
    int? backoffReps,
    double backoffReductionPercent,
    int? restSeconds,
    int? supersetGroup,
    double progressionKgStep,
    int progressionRepStep,
    ProgressionScheme progressionScheme,
  ) {
    final exercise = Exercise(
      name: name,
      set: sets,
      reps: reps,
      weight: weight,
      muscleGroup: muscleGroup,
      equipment: equipment,
      movementPattern: movementPattern,
      targetMinReps: targetMinReps,
      targetMaxReps: targetMaxReps,
      notes: notes,
      technique: technique,
      backoffReps: backoffReps,
      backoffReductionPercent: backoffReductionPercent,
      restSeconds: restSeconds,
      supersetGroup: supersetGroup,
      progressionKgStep: progressionKgStep,
      progressionRepStep: progressionRepStep,
      progressionScheme: progressionScheme,
    );
    setState(() {
      widget.schedule.exercises.add(exercise);
    });
    AppDataStore.addCustomExercise(exercise);
    widget.onUpdate();
  }

  void _addCatalogExercises(List<ExerciseCatalogEntry> entries) {
    if (entries.isEmpty) {
      return;
    }

    setState(() {
      for (final entry in entries) {
        widget.schedule.exercises.add(
          Exercise(
            name: entry.name,
            set: 3,
            reps: 10,
            weight: 0,
            muscleGroup: entry.muscleGroup,
            equipment: entry.equipment,
            movementPattern: entry.movementPattern,
            notes: '',
            technique: IntensityTechnique.none,
            backoffReductionPercent: widget.defaultBackoffReductionPercent,
            restSeconds: widget.defaultRestSeconds,
            progressionKgStep: 2.5,
            progressionRepStep: 1,
            progressionScheme: ProgressionScheme.doubleProgression,
          ),
        );
      }
    });
    widget.onUpdate();
  }

  void _addCustomExercises(List<Exercise> exercises) {
    if (exercises.isEmpty) {
      return;
    }

    setState(() {
      widget.schedule.exercises.addAll(
        exercises.map((exercise) => Exercise.fromJson(exercise.toJson())),
      );
    });
    widget.onUpdate();
  }

  Future<void> _openExercisePicker() async {
    final result = await Navigator.push<ExercisePickerResult>(
      context,
      MaterialPageRoute(builder: (context) => const ExercisePickerScreen()),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result.addCustom) {
      _showExerciseDialog();
      return;
    }

    if (result.customExercises.isNotEmpty) {
      _addCustomExercises(result.customExercises);
    }
    _addCatalogExercises(result.entries);
  }

  void _editExercise(
    int index,
    String name,
    int sets,
    int reps,
    double weight,
    MuscleGroup muscleGroup,
    String equipment,
    String movementPattern,
    int? targetMinReps,
    int? targetMaxReps,
    String notes,
    IntensityTechnique technique,
    int? backoffReps,
    double backoffReductionPercent,
    int? restSeconds,
    int? supersetGroup,
    double progressionKgStep,
    int progressionRepStep,
    ProgressionScheme progressionScheme,
  ) {
    setState(() {
      widget.schedule.exercises[index].name = name;
      widget.schedule.exercises[index].set = sets;
      widget.schedule.exercises[index].reps = reps;
      widget.schedule.exercises[index].weight = weight;
      widget.schedule.exercises[index].muscleGroup = muscleGroup;
      widget.schedule.exercises[index].equipment = equipment;
      widget.schedule.exercises[index].movementPattern = movementPattern;
      widget.schedule.exercises[index].targetMinReps = targetMinReps;
      widget.schedule.exercises[index].targetMaxReps = targetMaxReps;
      widget.schedule.exercises[index].notes = notes;
      widget.schedule.exercises[index].technique = technique;
      widget.schedule.exercises[index].backoffReps = backoffReps;
      widget.schedule.exercises[index].backoffReductionPercent =
          backoffReductionPercent;
      widget.schedule.exercises[index].restSeconds = restSeconds;
      widget.schedule.exercises[index].supersetGroup = supersetGroup;
      widget.schedule.exercises[index].progressionKgStep = progressionKgStep;
      widget.schedule.exercises[index].progressionRepStep = progressionRepStep;
      widget.schedule.exercises[index].progressionScheme = progressionScheme;
    });
    widget.onUpdate();
  }

  void _removeExercise(int index) {
    if (index < 0 || index >= widget.schedule.exercises.length) {
      return;
    }

    final deletedExercise = widget.schedule.exercises[index];
    setState(() {
      widget.schedule.exercises.removeAt(index);
    });
    widget.onUpdate();

    _showUndoSnackBar(
      message: 'Esercizio eliminato.',
      onUndo: () {
        if (!mounted || widget.schedule.exercises.contains(deletedExercise)) {
          return;
        }

        setState(() {
          final restoreIndex = index > widget.schedule.exercises.length
              ? widget.schedule.exercises.length
              : index;
          widget.schedule.exercises.insert(restoreIndex, deletedExercise);
        });
        widget.onUpdate();
      },
    );
  }

  void _reorderExercise(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= widget.schedule.exercises.length) {
      return;
    }

    if (newIndex < 0 || newIndex >= widget.schedule.exercises.length) {
      return;
    }

    setState(() {
      final exercise = widget.schedule.exercises.removeAt(oldIndex);
      widget.schedule.exercises.insert(newIndex, exercise);
    });
    widget.onUpdate();
  }

  void _showExerciseDialog({int? indexToEdit, Exercise? exerciseToEdit}) {
    final bool isEditing = exerciseToEdit != null && indexToEdit != null;
    IntensityTechnique selectedTechnique = isEditing
        ? exerciseToEdit.technique
        : IntensityTechnique.none;
    MuscleGroup? selectedMuscleGroup =
        isEditing && exerciseToEdit.muscleGroup != MuscleGroup.unassigned
        ? exerciseToEdit.muscleGroup
        : null;
    ProgressionScheme selectedProgressionScheme = isEditing
        ? exerciseToEdit.progressionScheme
        : ProgressionScheme.doubleProgression;
    final nameController = TextEditingController(
      text: isEditing ? exerciseToEdit.name : '',
    );
    final setsController = TextEditingController(
      text: isEditing ? exerciseToEdit.set.toString() : '',
    );
    final repsController = TextEditingController(
      text: isEditing ? exerciseToEdit.reps.toString() : '',
    );
    final topSetRepsController = TextEditingController(
      text: isEditing ? exerciseToEdit.reps.toString() : '',
    );
    final backoffRepsController = TextEditingController(
      text:
          isEditing &&
              exerciseToEdit.technique == IntensityTechnique.topsetBackoff
          ? (exerciseToEdit.backoffReps ?? exerciseToEdit.reps).toString()
          : '',
    );
    final weightController = TextEditingController(
      text: isEditing ? exerciseToEdit.weight.toString() : '',
    );
    final equipmentController = TextEditingController(
      text: isEditing ? exerciseToEdit.equipment : '',
    );
    final movementPatternController = TextEditingController(
      text: isEditing ? exerciseToEdit.movementPattern : '',
    );
    final targetMinRepsController = TextEditingController(
      text: isEditing ? (exerciseToEdit.targetMinReps?.toString() ?? '') : '',
    );
    final targetMaxRepsController = TextEditingController(
      text: isEditing ? (exerciseToEdit.targetMaxReps?.toString() ?? '') : '',
    );
    final restSecondsController = TextEditingController(
      text: isEditing
          ? (exerciseToEdit.restSeconds ?? widget.defaultRestSeconds).toString()
          : widget.defaultRestSeconds.toString(),
    );
    final supersetController = TextEditingController(
      text: isEditing ? (exerciseToEdit.supersetGroup?.toString() ?? '') : '',
    );
    final progressionKgController = TextEditingController(
      text: isEditing ? exerciseToEdit.progressionKgStep.toString() : '2.5',
    );
    final progressionRepController = TextEditingController(
      text: isEditing ? exerciseToEdit.progressionRepStep.toString() : '1',
    );
    final notesController = TextEditingController(
      text: isEditing ? exerciseToEdit.notes : '',
    );
    String? validationMessage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Modifica' : 'Nuovo esercizio'),
          content: AppDialogContent(
            maxWidth: 560,
            children: [
              DropdownButtonFormField<MuscleGroup>(
                key: ValueKey(selectedMuscleGroup),
                initialValue: selectedMuscleGroup,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Gruppo'),
                items: selectableMuscleGroups
                    .map(
                      (group) => DropdownMenuItem<MuscleGroup>(
                        value: group,
                        child: Text(group.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setDialogState(() {
                    selectedMuscleGroup = value;
                  });
                },
              ),
              appDialogFieldGap,
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              appDialogFieldGap,
              TextField(
                controller: equipmentController,
                decoration: const InputDecoration(labelText: 'Attrezzo'),
              ),
              appDialogFieldGap,
              TextField(
                controller: movementPatternController,
                decoration: const InputDecoration(labelText: 'Movimento'),
              ),
              appDialogFieldGap,
              DropdownButtonFormField<IntensityTechnique>(
                initialValue: selectedTechnique,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tecnica'),
                items: IntensityTechnique.values
                    .map(
                      (technique) => DropdownMenuItem<IntensityTechnique>(
                        value: technique,
                        child: Text(_techniqueLabel(technique)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }

                  setDialogState(() {
                    final wasBackoff =
                        selectedTechnique == IntensityTechnique.topsetBackoff;
                    final willBeBackoff =
                        value == IntensityTechnique.topsetBackoff;
                    if (!wasBackoff && willBeBackoff) {
                      final currentReps = repsController.text.trim();
                      if (topSetRepsController.text.trim().isEmpty &&
                          currentReps.isNotEmpty) {
                        topSetRepsController.text = currentReps;
                      }
                      if (backoffRepsController.text.trim().isEmpty) {
                        backoffRepsController.text = currentReps.isNotEmpty
                            ? currentReps
                            : topSetRepsController.text.trim();
                      }
                    } else if (wasBackoff && !willBeBackoff) {
                      final currentTopSet = topSetRepsController.text.trim();
                      if (repsController.text.trim().isEmpty &&
                          currentTopSet.isNotEmpty) {
                        repsController.text = currentTopSet;
                      }
                      if (setsController.text.trim().isEmpty) {
                        setsController.text = '2';
                      }
                    }

                    selectedTechnique = value;
                    validationMessage = null;
                  });
                },
              ),
              appDialogFieldGap,
              if (selectedTechnique == IntensityTechnique.topsetBackoff) ...[
                AppFieldRow(
                  children: [
                    TextField(
                      controller: topSetRepsController,
                      decoration: const InputDecoration(
                        labelText: 'Top set reps',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: backoffRepsController,
                      decoration: const InputDecoration(
                        labelText: 'Back off reps',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ] else ...[
                AppFieldRow(
                  children: [
                    TextField(
                      controller: setsController,
                      decoration: const InputDecoration(labelText: 'Serie'),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: repsController,
                      decoration: const InputDecoration(labelText: 'Reps'),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ],
              appDialogFieldGap,
              AppFieldRow(
                children: [
                  TextField(
                    controller: targetMinRepsController,
                    decoration: const InputDecoration(labelText: 'Min'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: targetMaxRepsController,
                    decoration: const InputDecoration(labelText: 'Max'),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              appDialogFieldGap,
              DropdownButtonFormField<ProgressionScheme>(
                initialValue: selectedProgressionScheme,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Schema progressione',
                ),
                items: ProgressionScheme.values
                    .map(
                      (scheme) => DropdownMenuItem<ProgressionScheme>(
                        value: scheme,
                        child: Text(scheme.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedProgressionScheme = value);
                },
              ),
              appDialogFieldGap,
              TextField(
                controller: weightController,
                decoration: const InputDecoration(labelText: 'Kg'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              appDialogFieldGap,
              TextField(
                controller: restSecondsController,
                decoration: const InputDecoration(labelText: 'Recupero sec'),
                keyboardType: TextInputType.number,
              ),
              appDialogFieldGap,
              TextField(
                controller: supersetController,
                decoration: const InputDecoration(
                  labelText: 'Superset gruppo',
                  hintText: 'Esempio: 1',
                ),
                keyboardType: TextInputType.number,
              ),
              appDialogFieldGap,
              AppFieldRow(
                children: [
                  TextField(
                    controller: progressionKgController,
                    decoration: const InputDecoration(
                      labelText: 'Step kg auto',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  TextField(
                    controller: progressionRepController,
                    decoration: const InputDecoration(
                      labelText: 'Step reps auto',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              appDialogFieldGap,
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
              if (validationMessage != null) ...[
                appDialogFieldGap,
                Text(
                  validationMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () {
                final bool isBackoff =
                    selectedTechnique == IntensityTechnique.topsetBackoff;
                final selectedGroup =
                    selectedMuscleGroup ?? MuscleGroup.unassigned;
                final exerciseName = nameController.text.trim();

                int? parsedSets = isBackoff
                    ? 2
                    : parseIntInput(setsController.text);
                int? parsedReps = isBackoff
                    ? parseIntInput(topSetRepsController.text)
                    : parseIntInput(repsController.text);
                int? parsedBackoffReps = isBackoff
                    ? parseIntInput(backoffRepsController.text)
                    : null;
                int? parsedRestSeconds = parseIntInput(
                  restSecondsController.text,
                );
                double? parsedWeight = parseDecimalInput(weightController.text);
                final parsedTargetMinReps = parseIntInput(
                  targetMinRepsController.text,
                );
                final parsedTargetMaxReps = parseIntInput(
                  targetMaxRepsController.text,
                );
                final parsedSupersetGroup = parseIntInput(
                  supersetController.text,
                );
                final parsedProgressionKgStep =
                    parseDecimalInput(progressionKgController.text) ?? 2.5;
                final parsedProgressionRepStep =
                    parseIntInput(progressionRepController.text) ?? 1;

                if (isEditing) {
                  parsedSets ??= isBackoff ? 2 : exerciseToEdit.set;
                  parsedReps ??= exerciseToEdit.reps;
                  parsedWeight ??= exerciseToEdit.weight;
                  parsedRestSeconds ??=
                      exerciseToEdit.restSeconds ?? widget.defaultRestSeconds;
                  if (isBackoff) {
                    parsedBackoffReps ??=
                        exerciseToEdit.backoffReps ?? exerciseToEdit.reps;
                  }
                }

                if (exerciseName.isEmpty ||
                    parsedSets == null ||
                    parsedReps == null ||
                    parsedWeight == null ||
                    parsedRestSeconds == null ||
                    (isBackoff && parsedBackoffReps == null)) {
                  setDialogState(() {
                    validationMessage = isBackoff
                        ? 'Completa nome, top set reps, back off reps, kg e recupero.'
                        : 'Completa nome, serie, reps, kg e recupero.';
                  });
                  return;
                }

                final hasInvalidRange =
                    parsedSets < 1 ||
                    parsedReps < 1 ||
                    parsedWeight < 0 ||
                    parsedRestSeconds < 0 ||
                    parsedRestSeconds > 3600 ||
                    (parsedBackoffReps != null && parsedBackoffReps < 1) ||
                    (parsedTargetMinReps != null && parsedTargetMinReps < 1) ||
                    (parsedTargetMaxReps != null && parsedTargetMaxReps < 1) ||
                    (parsedTargetMinReps != null &&
                        parsedTargetMaxReps != null &&
                        parsedTargetMinReps > parsedTargetMaxReps) ||
                    (parsedSupersetGroup != null && parsedSupersetGroup < 1) ||
                    parsedProgressionKgStep < 0 ||
                    parsedProgressionRepStep < 1;
                if (hasInvalidRange) {
                  setDialogState(() {
                    validationMessage =
                        'Usa valori validi: serie/reps almeno 1, kg e recupero non negativi, range reps coerente.';
                  });
                  return;
                }

                setDialogState(() {
                  validationMessage = null;
                });

                final backoffReductionPercent = isEditing
                    ? exerciseToEdit.backoffReductionPercent
                    : widget.defaultBackoffReductionPercent;

                if (isEditing) {
                  _editExercise(
                    indexToEdit,
                    exerciseName,
                    parsedSets,
                    parsedReps,
                    parsedWeight,
                    selectedGroup,
                    equipmentController.text.trim(),
                    movementPatternController.text.trim(),
                    parsedTargetMinReps,
                    parsedTargetMaxReps,
                    notesController.text,
                    selectedTechnique,
                    parsedBackoffReps,
                    backoffReductionPercent,
                    parsedRestSeconds,
                    parsedSupersetGroup,
                    parsedProgressionKgStep,
                    parsedProgressionRepStep,
                    selectedProgressionScheme,
                  );
                } else {
                  _addExercise(
                    exerciseName,
                    parsedSets,
                    parsedReps,
                    parsedWeight,
                    selectedGroup,
                    equipmentController.text.trim(),
                    movementPatternController.text.trim(),
                    parsedTargetMinReps,
                    parsedTargetMaxReps,
                    notesController.text,
                    selectedTechnique,
                    parsedBackoffReps,
                    backoffReductionPercent,
                    parsedRestSeconds,
                    parsedSupersetGroup,
                    parsedProgressionKgStep,
                    parsedProgressionRepStep,
                    selectedProgressionScheme,
                  );
                }
                Navigator.pop(context);
              },
              child: Text(isEditing ? 'Salva' : 'Aggiungi'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schedule.title),
        actions: [
          IconButton(
            tooltip: 'Programmazione',
            icon: const Icon(Icons.calendar_month),
            onPressed: _showScheduleProgramDialog,
          ),
          PopupMenuButton<String>(
            tooltip: 'Ciclo',
            onSelected: (value) {
              if (value == 'reset') {
                _resetCycle();
              } else if (value == 'complete') {
                _completeMesocycle();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'reset', child: Text('Reset ciclo')),
              PopupMenuItem(value: 'complete', child: Text('Fine mesociclo')),
            ],
          ),
          TextButton(
            onPressed: () {
              if (widget.schedule.exercises.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Aggiungi degli esercizi prima di allenarti!',
                    ),
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ActiveWorkoutScreen(
                    schedule: widget.schedule,
                    history: widget.history,
                    defaultRestSeconds: widget.defaultRestSeconds,
                    defaultBackoffReductionPercent:
                        widget.defaultBackoffReductionPercent,
                  ),
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
            child: const Text('Start'),
          ),
        ],
      ),
      body: widget.schedule.exercises.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Icon(
                        Icons.fitness_center,
                        color: colorScheme.onPrimaryContainer,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Scheda vuota',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Aggiungi esercizi dal catalogo o crea un esercizio personalizzato.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _openExercisePicker,
                      icon: const Icon(Icons.add),
                      label: const Text('Aggiungi esercizi'),
                    ),
                  ],
                ),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              buildDefaultDragHandles: false,
              onReorderItem: _reorderExercise,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final t = Curves.easeOut.transform(animation.value);
                    return Transform.scale(
                      scale: 1 + (t * 0.03),
                      child: Material(
                        elevation: 8 + (t * 8),
                        color: Colors.transparent,
                        shadowColor: colorScheme.shadow.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(26),
                        child: child,
                      ),
                    );
                  },
                  child: child,
                );
              },
              itemCount: widget.schedule.exercises.length,
              itemBuilder: (context, index) {
                final exercise = widget.schedule.exercises[index];
                final accent = _accentForIndex(colorScheme, index);
                return Dismissible(
                  key: ValueKey(exercise.id),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _removeExercise(index),
                  background: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 20),
                          child: Icon(
                            Icons.delete,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: isDark ? 0.18 : 0.10),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: accent.withValues(
                              alpha: isDark ? 0.22 : 0.14,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(Icons.fitness_center, color: accent),
                        ),
                        title: Text(
                          exercise.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${exercise.technique == IntensityTechnique.topsetBackoff && exercise.backoffReps != null ? '2 set • ${exercise.reps}/${exercise.backoffReps} reps • ${exercise.weight} kg' : '${exercise.set} x ${exercise.reps} • ${exercise.weight} kg'}'
                            '${exercise.muscleGroup == MuscleGroup.unassigned ? '' : '\n${exercise.muscleGroup.label}'}'
                            '${exercise.equipment.trim().isNotEmpty ? ' • ${exercise.equipment}' : ''}'
                            '\nRecupero ${exercise.restSeconds ?? widget.defaultRestSeconds}s'
                            '${exercise.supersetGroup == null ? '' : ' • Superset ${exercise.supersetGroup}'}'
                            ' • Auto +${exercise.progressionKgStep} kg/${exercise.progressionRepStep} rep'
                            '${exercise.technique == IntensityTechnique.none ? '' : ' • ${_techniqueLabel(exercise.technique)}'}'
                            '${exercise.notes.trim().isNotEmpty ? '\nNote: ${exercise.notes}' : ''}',
                          ),
                        ),
                        onTap: () => _showExerciseDialog(
                          indexToEdit: index,
                          exerciseToEdit: exercise,
                        ),
                        trailing: Tooltip(
                          message: 'Trascina per riordinare',
                          child: ReorderableDragStartListener(
                            key: ValueKey('exercise-reorder-${exercise.id}'),
                            index: index,
                            child: const MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: SizedBox.square(
                                dimension: 48,
                                child: Center(child: Icon(Icons.drag_handle)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openExercisePicker,
        child: const Icon(Icons.add),
      ),
    );
  }
}
