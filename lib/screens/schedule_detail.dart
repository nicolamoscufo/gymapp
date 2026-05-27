import 'package:flutter/material.dart';
import '../exercise_catalog.dart';
import '../models/schedule.dart';
import '../models/exercise.dart';
import '../models/workout.dart';
import '../number_input.dart';
import 'active_workout.dart';

class ScheduleDetailScreen extends StatefulWidget {
  final Schedule schedule;
  final List<WorkoutSession> history;
  final int defaultRestSeconds;
  final VoidCallback onUpdate;

  const ScheduleDetailScreen({
    super.key,
    required this.schedule,
    this.history = const [],
    required this.defaultRestSeconds,
    required this.onUpdate,
  });

  @override
  State<ScheduleDetailScreen> createState() => _ScheduleDetailScreenState();
}

class _ScheduleDetailScreenState extends State<ScheduleDetailScreen> {
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
    int? restSeconds,
  ) {
    setState(() {
      widget.schedule.exercises.add(
        Exercise(
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
          restSeconds: restSeconds,
        ),
      );
    });
    widget.onUpdate();
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
    int? restSeconds,
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
      widget.schedule.exercises[index].restSeconds = restSeconds;
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

  void _showExerciseDialog({int? indexToEdit, Exercise? exerciseToEdit}) {
    final bool isEditing = exerciseToEdit != null && indexToEdit != null;
    IntensityTechnique selectedTechnique = isEditing
        ? exerciseToEdit.technique
        : IntensityTechnique.none;
    MuscleGroup? selectedMuscleGroup =
        isEditing && exerciseToEdit.muscleGroup != MuscleGroup.unassigned
        ? exerciseToEdit.muscleGroup
        : null;
    String? selectedCatalogName = isEditing
        ? catalogEntryByName(exerciseToEdit.name)?.name
        : null;

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
    final notesController = TextEditingController(
      text: isEditing ? exerciseToEdit.notes : '',
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Modifica' : 'Nuovo esercizio'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: selectedCatalogName,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Catalogo'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Personalizzato'),
                    ),
                    ...exerciseCatalog.map(
                      (entry) => DropdownMenuItem<String?>(
                        value: entry.name,
                        child: Text(entry.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    final entry = value == null
                        ? null
                        : catalogEntryByName(value);
                    setDialogState(() {
                      selectedCatalogName = value;
                      if (entry != null) {
                        nameController.text = entry.name;
                        selectedMuscleGroup = entry.muscleGroup;
                        equipmentController.text = entry.equipment;
                        movementPatternController.text = entry.movementPattern;
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<MuscleGroup>(
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
                const SizedBox(height: 8),
                TextField(
                  controller: equipmentController,
                  decoration: const InputDecoration(labelText: 'Attrezzo'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: movementPatternController,
                  decoration: const InputDecoration(labelText: 'Movimento'),
                ),
                const SizedBox(height: 8),
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
                      selectedTechnique = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                if (selectedTechnique == IntensityTechnique.topsetBackoff) ...[
                  TextField(
                    controller: topSetRepsController,
                    decoration: const InputDecoration(
                      labelText: 'Top set reps',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: backoffRepsController,
                    decoration: const InputDecoration(
                      labelText: 'Back off reps',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: setsController,
                          decoration: const InputDecoration(labelText: 'Serie'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: repsController,
                          decoration: const InputDecoration(labelText: 'Reps'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: targetMinRepsController,
                        decoration: const InputDecoration(labelText: 'Min'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: targetMaxRepsController,
                        decoration: const InputDecoration(labelText: 'Max'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: weightController,
                  decoration: const InputDecoration(labelText: 'Kg'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: restSecondsController,
                  decoration: const InputDecoration(labelText: 'Recupero sec'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
              ],
            ),
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

                final int? parsedSets = isBackoff
                    ? 2
                    : parseIntInput(setsController.text);
                final int? parsedReps = isBackoff
                    ? parseIntInput(topSetRepsController.text)
                    : parseIntInput(repsController.text);
                final int? parsedBackoffReps = isBackoff
                    ? parseIntInput(backoffRepsController.text)
                    : null;
                final int? parsedRestSeconds = parseIntInput(
                  restSecondsController.text,
                );
                final parsedWeight = parseDecimalInput(weightController.text);
                final parsedTargetMinReps = parseIntInput(
                  targetMinRepsController.text,
                );
                final parsedTargetMaxReps = parseIntInput(
                  targetMaxRepsController.text,
                );

                if (exerciseName.isEmpty ||
                    parsedSets == null ||
                    parsedReps == null ||
                    parsedWeight == null ||
                    parsedRestSeconds == null ||
                    (isBackoff && parsedBackoffReps == null)) {
                  return;
                }

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
                    parsedRestSeconds,
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
                    parsedRestSeconds,
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schedule.title),
        actions: [
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
          ? const Center(child: Text('Vuota'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: widget.schedule.exercises.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final exercise = widget.schedule.exercises[index];
                return Dismissible(
                  key: ValueKey(exercise.id),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _removeExercise(index),
                  background: Container(
                    color: colorScheme.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(Icons.delete, color: colorScheme.onError),
                  ),
                  child: Card(
                    child: ListTile(
                      title: Text(
                        exercise.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${exercise.technique == IntensityTechnique.topsetBackoff && exercise.backoffReps != null ? '2 set • ${exercise.reps}/${exercise.backoffReps} reps • ${exercise.weight} kg' : '${exercise.set} x ${exercise.reps} • ${exercise.weight} kg'}'
                        '${exercise.muscleGroup == MuscleGroup.unassigned ? '' : '\n${exercise.muscleGroup.label}'}'
                        '${exercise.equipment.trim().isNotEmpty ? ' • ${exercise.equipment}' : ''}'
                        '\n${exercise.restSeconds ?? widget.defaultRestSeconds}s'
                        '${exercise.technique == IntensityTechnique.none ? '' : ' • ${_techniqueLabel(exercise.technique)}'}'
                        '${exercise.notes.trim().isNotEmpty ? '\nNote: ${exercise.notes}' : ''}',
                      ),
                      onTap: () => _showExerciseDialog(
                        indexToEdit: index,
                        exerciseToEdit: exercise,
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showExerciseDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
