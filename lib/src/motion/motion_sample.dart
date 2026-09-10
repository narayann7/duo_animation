/// One orientation reading, already reduced to screen axes by the native side.
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

  /// Decodes the 14-double payload the platform channel delivers.
  ///
  /// Layout: nine matrix values row-major, then `omegaScreenY`,
  /// `omegaScreenX`, `omegaMagnitude`, `hasGyro` as 1 or 0, and the timestamp
  /// in seconds.
  factory MotionSample.fromPayload(List<double> payload) {
    if (payload.length != payloadLength) {
      throw FormatException(
        'duo_animation motion payload must hold $payloadLength doubles, '
        'got ${payload.length}',
      );
    }
    return MotionSample(
      screenMatrix: payload.sublist(0, 9),
      omegaScreenY: payload[9],
      omegaScreenX: payload[10],
      omegaMagnitude: payload[11],
      hasGyro: payload[12] != 0,
      timestampSeconds: payload[13],
    );
  }

  /// Number of doubles in the wire format.
  static const int payloadLength = 14;

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
