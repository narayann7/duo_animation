/// Physical facts about the display and the sensors behind it.
class DuoFoldDisplayMetrics {
  /// Creates a metrics snapshot.
  const DuoFoldDisplayMetrics({
    required this.pixelsPerMillimeter,
    required this.hasRotationSensor,
  });

  /// What the package assumes when the platform cannot answer.
  static const DuoFoldDisplayMetrics unknown = DuoFoldDisplayMetrics(
    pixelsPerMillimeter: 0,
    hasRotationSensor: false,
  );

  /// Physical pixels per millimetre, or zero when the platform did not answer.
  final double pixelsPerMillimeter;

  /// Whether a usable gyro-backed orientation sensor exists.
  ///
  /// False on emulators, which is why the controller falls back to manual
  /// mode rather than showing a dead effect.
  final bool hasRotationSensor;

  @override
  String toString() =>
      'DuoFoldDisplayMetrics('
      '${pixelsPerMillimeter.toStringAsFixed(2)} px/mm, '
      'sensor: $hasRotationSensor)';
}
