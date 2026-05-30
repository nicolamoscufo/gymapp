const double defaultBackoffReductionPercent = 10;

double backoffReductionPercentFor({double? rpe, int? rir}) {
  if ((rpe != null && rpe >= 9) || (rir != null && rir <= 1)) {
    return 12.5;
  }
  if ((rpe != null && rpe <= 7) || (rir != null && rir >= 3)) {
    return 7.5;
  }
  return defaultBackoffReductionPercent;
}

double recommendedBackoffWeight(
  double topSetWeight, {
  double reductionPercent = defaultBackoffReductionPercent,
}) {
  final normalizedReduction = reductionPercent.clamp(0, 100).toDouble();
  final multiplier = (100 - normalizedReduction) / 100;
  return (topSetWeight * multiplier * 2).roundToDouble() / 2;
}
