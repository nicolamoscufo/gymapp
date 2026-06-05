const double defaultBackoffReductionPercent = 10;

double backoffReductionPercentFor({
  double reductionPercent = defaultBackoffReductionPercent,
}) {
  return reductionPercent.clamp(0, 100).toDouble();
}

double recommendedBackoffWeight(
  double topSetWeight, {
  double reductionPercent = defaultBackoffReductionPercent,
}) {
  final normalizedReduction = reductionPercent.clamp(0, 100).toDouble();
  final multiplier = (100 - normalizedReduction) / 100;
  return (topSetWeight * multiplier * 2).roundToDouble() / 2;
}
