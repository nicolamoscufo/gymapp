double? parseDecimalInput(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return null;
  }
  return double.tryParse(normalized);
}

int? parseIntInput(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return null;
  }
  return int.tryParse(normalized);
}

String formatDecimal(double value) {
  return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
}
