final Map<String, String> _catalogIdsByCanonicalName = <String, String>{};
final Set<String> _ambiguousCanonicalNames = <String>{};

String normalizeCatalogExerciseName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

void registerExerciseCatalogIdentity({
  required String name,
  required String catalogId,
}) {
  final normalizedName = normalizeCatalogExerciseName(name);
  final normalizedId = catalogId.trim();
  if (normalizedName.isEmpty || normalizedId.isEmpty) return;
  if (_ambiguousCanonicalNames.contains(normalizedName)) return;

  final existing = _catalogIdsByCanonicalName[normalizedName];
  if (existing == null || existing == normalizedId) {
    _catalogIdsByCanonicalName[normalizedName] = normalizedId;
    return;
  }

  _catalogIdsByCanonicalName.remove(normalizedName);
  _ambiguousCanonicalNames.add(normalizedName);
}

String? catalogIdForExerciseName(String name) {
  final normalizedName = normalizeCatalogExerciseName(name);
  if (normalizedName.isEmpty ||
      _ambiguousCanonicalNames.contains(normalizedName)) {
    return null;
  }
  return _catalogIdsByCanonicalName[normalizedName];
}

void clearExerciseCatalogIdentityRegistryForTesting() {
  _catalogIdsByCanonicalName.clear();
  _ambiguousCanonicalNames.clear();
}
