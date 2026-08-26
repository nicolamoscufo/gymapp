from pathlib import Path

path = Path('lib/screens/active_workout.dart')
text = path.read_text()

helper_marker = '  Future<void> _showSetDetailsDialog(ExerciseSet set) async {'
if 'void _submitSetFromKeyboard(' not in text:
    helper = '''  void _submitSetFromKeyboard(
    WorkoutExercise exercise,
    ExerciseSet set,
    int setIndex,
    String value,
  ) {
    final reps = parseIntInput(value);
    if (reps == null || reps <= 0 || set.isCompleted) return;
    FocusScope.of(context).unfocus();
    _toggleSetCompleted(exercise, set, setIndex);
  }

'''
    if text.count(helper_marker) != 1:
        raise SystemExit('keyboard submit helper marker not found exactly once')
    text = text.replace(helper_marker, helper + helper_marker)


def section(start_marker: str, end_marker: str) -> tuple[int, int]:
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'start marker not found: {start_marker}')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'end marker not found: {end_marker}')
    return start, end


# Rest seconds: select existing value, keep numeric input clean, close keyboard on Done.
start, end = section("key: ValueKey('rest-${exercise.id}')", 'PopupMenuButton<int>(')
block = text[start:end]
if 'selectAllOnFocus: true' not in block:
    block = block.replace(
        'keyboardType: TextInputType.number,\n',
        '''keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textInputAction: TextInputAction.done,
                              selectAllOnFocus: true,
                              onSubmitted: (_) => FocusScope.of(context).unfocus(),
''',
        1,
    )
    text = text[:start] + block + text[end:]

# Set weight: select the prefilled value and make Next move naturally to reps.
start, end = section("key: ValueKey('${exSet.id}-weight')", "key: ValueKey('${exSet.id}-reps')")
block = text[start:end]
if 'selectAllOnFocus: true' not in block:
    keyboard = '''keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
'''
    replacement = keyboard + '''                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                              RegExp(r'[0-9.,]'),
                                            ),
                                          ],
                                          textInputAction: TextInputAction.next,
                                          selectAllOnFocus: true,
'''
    if keyboard not in block:
        raise SystemExit('weight keyboard anchor not found')
    block = block.replace(keyboard, replacement, 1)
    text = text[:start] + block + text[end:]

# Set reps: Done becomes the check action.
start, end = section("key: ValueKey('${exSet.id}-reps')", "key: ValueKey('complete-${exSet.id}')")
block = text[start:end]
if 'onSubmitted: (value)' not in block:
    block = block.replace(
        'keyboardType: TextInputType.number,\n',
        '''keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.digitsOnly,
                                          ],
                                          textInputAction: TextInputAction.done,
                                          selectAllOnFocus: true,
                                          onSubmitted: (value) =>
                                              _submitSetFromKeyboard(
                                                exercise,
                                                exSet,
                                                setIndex,
                                                value,
                                              ),
''',
        1,
    )
    text = text[:start] + block + text[end:]

stable_start = text.find('class _StableSetTextField extends StatefulWidget {')
if stable_start < 0:
    raise SystemExit('stable numeric field class not found')

new_stable_class = '''class _StableSetTextField extends StatefulWidget {
  final String text;
  final TextInputType keyboardType;
  final TextAlign textAlign;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool selectAllOnFocus;

  const _StableSetTextField({
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
  State<_StableSetTextField> createState() => _StableSetTextFieldState();
}

class _StableSetTextFieldState extends State<_StableSetTextField> {
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
  void didUpdateWidget(covariant _StableSetTextField oldWidget) {
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
'''

text = text[:stable_start] + new_stable_class
path.write_text(text)
