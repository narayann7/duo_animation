import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/motion/motion_api.g.dart',
    dartPackageName: 'duo_animation',
    kotlinOut:
        'android/src/main/kotlin/dev/duoanimation/duo_animation/MotionApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'dev.duoanimation.duo_animation'),
    swiftOut: 'ios/duo_animation/Sources/duo_animation/MotionApi.g.swift',
  ),
)
/// One orientation reading, already reduced to screen axes by the native side.
///
/// The native halves do no filtering. Calibration, latency prediction,
/// smoothing and drift washout all live in Dart.
class MotionFrame {
  /// Current pose as a row-major 3x3, columns being screen-right, screen-up
  /// and screen-normal, expressed in the platform's orientation reference
  /// frame. Exactly nine values.
  late Float64List screenMatrix;

  /// Angular rate about the screen's up axis, rad/s. Drives latency
  /// prediction for the horizontal tilt axis.
  late double omegaScreenY;

  /// Angular rate about the screen's right axis, rad/s. Drives latency
  /// prediction for the vertical tilt axis.
  late double omegaScreenX;

  /// Magnitude of the full rotation rate vector, rad/s. Decides whether the
  /// device is still enough for the auto-recenter washout to run.
  late double omegaMagnitude;

  /// Whether a gyroscope reading backed this frame.
  late bool hasGyro;

  /// Sensor timestamp in seconds. Only differences are ever used, so the
  /// epoch need not agree across platforms.
  late double timestampSeconds;
}

/// Physical facts about the display and the sensors behind it.
class MotionMetrics {
  /// Physical pixels per millimetre, or zero when the platform cannot answer.
  late double pixelsPerMillimeter;

  /// Whether a usable gyro-backed orientation sensor exists. False on
  /// emulators and on devices with no gyroscope.
  late bool hasRotationSensor;
}

/// Request and response calls into the native side.
@HostApi()
abstract class DuoMotionHostApi {
  /// Reads display density and sensor availability once.
  MotionMetrics metrics();

  /// Unregisters native sensor listeners.
  void stop();
}

/// The orientation sample stream.
@EventChannelApi()
abstract class DuoMotionEventApi {
  /// Orientation frames at roughly the platform's game-sensor rate.
  MotionFrame streamMotion();
}
