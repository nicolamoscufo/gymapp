import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/workout.dart';

class WorkoutExerciseJumpBar extends StatelessWidget {
  final List<WorkoutExercise> exercises;
  final ValueChanged<String> onSelected;

  const WorkoutExerciseJumpBar({
    super.key,
    required this.exercises,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SizedBox(
        height: 58,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          itemBuilder: (context, index) {
            final exercise = exercises[index];
            return ActionChip(
              avatar: Icon(
                Icons.keyboard_arrow_down,
                color: colorScheme.primary,
              ),
              label: Text(exercise.name),
              onPressed: () => onSelected(exercise.id),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemCount: exercises.length,
        ),
      ),
    );
  }
}

/// Text field used by live set rows.
///
/// It keeps its controller stable while autosave rebuilds the parent screen,
/// preventing the caret from jumping or the current edit from being replaced.
class StableWorkoutSetTextField extends StatefulWidget {
  final String text;
  final TextInputType keyboardType;
  final TextAlign textAlign;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool selectAllOnFocus;

  const StableWorkoutSetTextField({
    super.key,
    required this.text,
    required this.keyboardType,
    required this.textAlign,
    required this.decoration,
    required this.onChanged,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.selectAllOnFocus = false,
  });

  @override
  State<StableWorkoutSetTextField> createState() =>
      _StableWorkoutSetTextFieldState();
}

class _StableWorkoutSetTextFieldState extends State<StableWorkoutSetTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus && widget.selectAllOnFocus) {
      _selectAll();
    }
  }

  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void didUpdateWidget(covariant StableWorkoutSetTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != widget.text) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      textInputAction: widget.textInputAction,
      textAlign: widget.textAlign,
      decoration: widget.decoration,
      onTap: widget.selectAllOnFocus ? _selectAll : null,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
    );
  }
}
