import 'package:flutter/material.dart';

import '../app_data_store.dart';
import '../exercise_catalog.dart';
import '../models/exercise.dart';

class ExercisePickerResult {
  final List<ExerciseCatalogEntry> entries;
  final bool addCustom;

  const ExercisePickerResult.entries(this.entries) : addCustom = false;

  const ExercisePickerResult.custom() : entries = const [], addCustom = true;
}

class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({super.key});

  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, ExerciseCatalogEntry> _selectedEntries = {};
  final Set<String> _favoriteEntryIds = {};
  late final Future<List<ExerciseCatalogEntry>> _catalogFuture;

  MuscleGroup? _selectedGroup;
  String? _selectedEquipment;
  bool _showFavoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _catalogFuture = loadExerciseCatalog();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favorites = await AppDataStore.loadFavoriteExerciseIds();
    if (!mounted) return;
    setState(() {
      _favoriteEntryIds
        ..clear()
        ..addAll(favorites);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleEntry(ExerciseCatalogEntry entry) {
    final key = _entryKey(entry);
    setState(() {
      if (_selectedEntries.containsKey(key)) {
        _selectedEntries.remove(key);
      } else {
        _selectedEntries[key] = entry;
      }
    });
  }

  void _finishSelection() {
    if (_selectedEntries.isEmpty) {
      return;
    }

    Navigator.pop(
      context,
      ExercisePickerResult.entries(_selectedEntries.values.toList()),
    );
  }

  Future<void> _toggleFavorite(ExerciseCatalogEntry entry) async {
    final key = _entryKey(entry);
    setState(() {
      if (_favoriteEntryIds.contains(key)) {
        _favoriteEntryIds.remove(key);
      } else {
        _favoriteEntryIds.add(key);
      }
    });
    await AppDataStore.saveFavoriteExerciseIds(_favoriteEntryIds);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedCount = _selectedEntries.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aggiungi esercizi'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, const ExercisePickerResult.custom());
            },
            child: const Text('Personalizzato'),
          ),
        ],
      ),
      body: FutureBuilder<List<ExerciseCatalogEntry>>(
        future: _catalogFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Catalogo esercizi non disponibile.',
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
            );
          }

          final catalog = snapshot.data ?? const <ExerciseCatalogEntry>[];
          final baseEntries = filterExerciseCatalog(
            catalog,
            query: _searchController.text,
            muscleGroup: _selectedGroup,
            limit: 1500,
          );
          final visibleEntries = baseEntries.where((entry) {
            final equipmentMatches =
                _selectedEquipment == null ||
                entry.equipment == _selectedEquipment;
            final favoriteMatches =
                !_showFavoritesOnly ||
                _favoriteEntryIds.contains(_entryKey(entry));
            return equipmentMatches && favoriteMatches;
          }).toList();
          final equipmentFilters =
              catalog
                  .map((entry) => entry.equipment)
                  .where((equipment) => equipment.trim().isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  key: const ValueKey('exercise-picker-search'),
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Cerca esercizio',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: const ValueKey('exercise-filter-all'),
                        label: const Text('Tutti'),
                        selected: _selectedGroup == null,
                        onSelected: (_) => setState(() {
                          _selectedGroup = null;
                        }),
                      ),
                    ),
                    ...selectableMuscleGroups.map((group) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: ValueKey('exercise-filter-${group.name}'),
                          label: Text(_shortGroupLabel(group)),
                          selected: _selectedGroup == group,
                          onSelected: (_) => setState(() {
                            _selectedGroup = group;
                          }),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: const Icon(Icons.star, size: 18),
                        label: const Text('Preferiti'),
                        selected: _showFavoritesOnly,
                        onSelected: (selected) => setState(() {
                          _showFavoritesOnly = selected;
                        }),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('Tutti attrezzi'),
                        selected: _selectedEquipment == null,
                        onSelected: (_) => setState(() {
                          _selectedEquipment = null;
                        }),
                      ),
                    ),
                    ...equipmentFilters.take(24).map((equipment) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(equipment),
                          selected: _selectedEquipment == equipment,
                          onSelected: (_) => setState(() {
                            _selectedEquipment = equipment;
                          }),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _selectedGroup == null
                        ? '${visibleEntries.length} esercizi'
                        : '${visibleEntries.length} per ${_shortGroupLabel(_selectedGroup!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              Expanded(
                child: visibleEntries.isEmpty
                    ? const Center(child: Text('Nessun esercizio trovato.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        itemCount: visibleEntries.length,
                        itemBuilder: (context, index) {
                          final entry = visibleEntries[index];
                          final selected = _selectedEntries.containsKey(
                            _entryKey(entry),
                          );
                          final favorite = _favoriteEntryIds.contains(
                            _entryKey(entry),
                          );

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              color: selected
                                  ? colorScheme.primaryContainer
                                  : null,
                              child: ListTile(
                                key: ValueKey('exercise-picker-${entry.id}'),
                                leading: CircleAvatar(
                                  backgroundColor: selected
                                      ? colorScheme.primary
                                      : colorScheme.secondary.withValues(
                                          alpha: isDark ? 0.22 : 0.14,
                                        ),
                                  foregroundColor: selected
                                      ? colorScheme.onPrimary
                                      : colorScheme.secondary,
                                  child: Text(
                                    _groupInitial(entry.muscleGroup),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  entry.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: selected
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    entry.muscleGroup.label,
                                    if (entry.subtitle.isNotEmpty)
                                      entry.subtitle,
                                  ].join(' - '),
                                  style: TextStyle(
                                    color: selected
                                        ? colorScheme.onPrimaryContainer
                                              .withValues(alpha: 0.82)
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: favorite
                                          ? 'Rimuovi preferito'
                                          : 'Aggiungi preferito',
                                      icon: Icon(
                                        favorite
                                            ? Icons.star
                                            : Icons.star_border,
                                      ),
                                      color: favorite
                                          ? colorScheme.tertiary
                                          : colorScheme.onSurfaceVariant,
                                      onPressed: () => _toggleFavorite(entry),
                                    ),
                                    Checkbox(
                                      value: selected,
                                      onChanged: (_) => _toggleEntry(entry),
                                    ),
                                  ],
                                ),
                                onTap: () => _toggleEntry(entry),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: selectedCount == 0 ? null : _finishSelection,
            child: Text(
              selectedCount == 1
                  ? 'Aggiungi 1 esercizio'
                  : 'Aggiungi $selectedCount esercizi',
            ),
          ),
        ),
      ),
    );
  }
}

String _entryKey(ExerciseCatalogEntry entry) {
  return entry.id.isNotEmpty ? entry.id : entry.name.toLowerCase();
}

String _groupInitial(MuscleGroup group) {
  return switch (group) {
    MuscleGroup.unassigned => '?',
    MuscleGroup.chest => 'P',
    MuscleGroup.back => 'D',
    MuscleGroup.quadriceps => 'Q',
    MuscleGroup.hamstrings => 'F',
    MuscleGroup.glutes => 'G',
    MuscleGroup.calves => 'Po',
    MuscleGroup.legs => 'Ga',
    MuscleGroup.biceps => 'B',
    MuscleGroup.triceps => 'T',
    MuscleGroup.arms => 'Br',
    MuscleGroup.forearms => 'Av',
    MuscleGroup.shoulders => 'S',
    MuscleGroup.traps => 'Tr',
    MuscleGroup.abs => 'A',
    MuscleGroup.cardio => 'C',
    MuscleGroup.neck => 'Co',
  };
}

String _shortGroupLabel(MuscleGroup group) {
  return switch (group) {
    MuscleGroup.unassigned => 'Tutti',
    MuscleGroup.chest => 'Petto',
    MuscleGroup.back => 'Dorso',
    MuscleGroup.quadriceps => 'Quadricipiti',
    MuscleGroup.hamstrings => 'Femorali',
    MuscleGroup.glutes => 'Glutei',
    MuscleGroup.calves => 'Polpacci',
    MuscleGroup.legs => 'Gambe',
    MuscleGroup.biceps => 'Bicipiti',
    MuscleGroup.triceps => 'Tricipiti',
    MuscleGroup.arms => 'Braccia',
    MuscleGroup.forearms => 'Avambracci',
    MuscleGroup.shoulders => 'Spalle',
    MuscleGroup.traps => 'Trapezi',
    MuscleGroup.abs => 'Addome',
    MuscleGroup.cardio => 'Cardio',
    MuscleGroup.neck => 'Collo',
  };
}
