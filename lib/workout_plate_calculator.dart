import 'package:flutter/material.dart';

class PlateCalculatorResult {
  final List<double> platesPerSide;
  final double loadedWeight;
  final double remainder;

  const PlateCalculatorResult({
    required this.platesPerSide,
    required this.loadedWeight,
    required this.remainder,
  });
}

PlateCalculatorResult calculatePlatesPerSide({
  required double targetWeight,
  required double barWeight,
  List<double> availablePlates = const [25, 20, 15, 10, 5, 2.5, 1.25],
}) {
  if (targetWeight <= barWeight) {
    return PlateCalculatorResult(
      platesPerSide: const [],
      loadedWeight: barWeight,
      remainder: (targetWeight - barWeight).abs(),
    );
  }

  var perSide = (targetWeight - barWeight) / 2;
  final plates = <double>[];
  final sorted = [...availablePlates]..sort((a, b) => b.compareTo(a));

  for (final plate in sorted) {
    if (plate <= 0) continue;
    while (perSide + 1e-9 >= plate) {
      plates.add(plate);
      perSide -= plate;
    }
  }

  final loadedWeight =
      barWeight + 2 * plates.fold<double>(0, (sum, plate) => sum + plate);
  return PlateCalculatorResult(
    platesPerSide: plates,
    loadedWeight: loadedWeight,
    remainder: (targetWeight - loadedWeight).abs(),
  );
}

Future<void> showWorkoutPlateCalculator(
  BuildContext context, {
  required double initialWeight,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _WorkoutPlateCalculatorSheet(
      initialWeight: initialWeight,
    ),
  );
}

class _WorkoutPlateCalculatorSheet extends StatefulWidget {
  final double initialWeight;

  const _WorkoutPlateCalculatorSheet({required this.initialWeight});

  @override
  State<_WorkoutPlateCalculatorSheet> createState() =>
      _WorkoutPlateCalculatorSheetState();
}

class _WorkoutPlateCalculatorSheetState
    extends State<_WorkoutPlateCalculatorSheet> {
  late final TextEditingController _targetController;
  late final TextEditingController _barController;

  @override
  void initState() {
    super.initState();
    _targetController = TextEditingController(
      text: widget.initialWeight > 0 ? _format(widget.initialWeight) : '60',
    );
    _barController = TextEditingController(text: '20');
  }

  @override
  void dispose() {
    _targetController.dispose();
    _barController.dispose();
    super.dispose();
  }

  double _parse(String value, double fallback) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? fallback;
  }

  String _format(double value) {
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final target = _parse(_targetController.text, widget.initialWeight);
    final bar = _parse(_barController.text, 20);
    final result = calculatePlatesPerSide(
      targetWeight: target,
      barWeight: bar,
    );
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plate calculator',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Calcolo per lato con piastre 25 / 20 / 15 / 10 / 5 / 2.5 / 1.25 kg.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Peso totale kg',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _barController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Bilanciere',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Per lato',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      result.platesPerSide.isEmpty
                          ? 'Nessuna piastra'
                          : '${result.platesPerSide.map(_format).join(' + ')} kg',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Carico ottenuto: ${_format(result.loadedWeight)} kg'),
                    if (result.remainder > 0.01) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Differenza: ${_format(result.remainder)} kg con le piastre disponibili.',
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Chiudi'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
