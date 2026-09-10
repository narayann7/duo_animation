/// One orientation reading, already reduced to screen axes by the native side.
///
/// This is what a motion source hands the filter. It is deliberately
/// plain Dart with no Flutter import, which is what lets the orientation
/// filter be tested with no binding and no hardware. The wire format that
/// carries a reading across from the native side is a separate concern and is
/// defined by the schema at `pigeons/motion.dart`.
class MotionSample {
  /// Creates a sample. [screenMatrix] must be a row-major 3x3.
  const MotionSample({
    required this.screenMatrix,
    required this.omegaScreenY,
    required this.omegaScreenX,
    required this.omegaMagnitude,
    required this.hasGyro,
    required this.timestampSeconds,
  });

  /// Current pose, columns being screen-right, screen-up and screen-normal.
  final List<double> screenMatrix;

  /// Angular rate about the screen's up axis, rad/s. Drives latency prediction.
  final double omegaScreenY;

  /// Angular rate about the screen's right axis, rad/s. Drives latency
  /// prediction for the second tilt axis.
  final double omegaScreenX;

  /// Magnitude of the full gyro vector, rad/s. Decides whether the device is
  /// still enough for the auto-recenter washout to run.
  final double omegaMagnitude;

  /// Whether a gyroscope reading backed this sample.
  final bool hasGyro;

  /// Sensor timestamp in seconds, used only for time deltas.
  final double timestampSeconds;
}
