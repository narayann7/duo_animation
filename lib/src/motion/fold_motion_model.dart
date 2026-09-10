import 'dart:math' as math;

import 'matrix3.dart';
import 'motion_sample.dart';

/// The filter's output: a tilt magnitude and the direction the far edge
/// lifts toward.
class FoldState {
  /// Creates a state.
  const FoldState({
    required this.tiltDegrees,
    required this.liftDirX,
    required this.liftDirY,
  });

  /// Level, lift direction the fallback for a vanishing tilt.
  static const FoldState zero = FoldState(
    tiltDegrees: 0,
    liftDirX: -1,
    liftDirY: 0,
  );

  /// Tilt magnitude, always non-negative and clamped to plus or minus 45.
  final double tiltDegrees;

  /// X of the unit lift direction, in fragment coordinates (y down).
  final double liftDirX;

  /// Y of the unit lift direction, in fragment coordinates (y down).
  final double liftDirY;

  @override
  bool operator ==(Object other) =>
      other is FoldState &&
      other.tiltDegrees == tiltDegrees &&
      other.liftDirX == liftDirX &&
      other.liftDirY == liftDirY;

  @override
  int get hashCode => Object.hash(tiltDegrees, liftDirX, liftDirY);

  @override
  String toString() =>
      'FoldState(${tiltDegrees.toStringAsFixed(2)} deg, '
      'lift (${liftDirX.toStringAsFixed(2)}, '
      '${liftDirY.toStringAsFixed(2)}))';
}

/// Per-axis prediction, smoothing and washout state.
///
/// Both tilt axes run the identical pipeline with identical constants, so
/// this holds one axis's state and applies [FoldMotionModel]'s shared
/// constants. The two axes share a single calibrated reference pose (there is
/// only one latched matrix), but each carries its own predicted angle,
/// smoothed angle and washout baseline.
class _AxisFilter {
  double tiltRadians = 0;
  double baselineRadians = 0;
  double lastPredicted = 0;

  void reset() {
    tiltRadians = 0;
    baselineRadians = 0;
    lastPredicted = 0;
  }

  /// Snaps the washout baseline so the reported tilt keeps its current value
  /// instead of jumping the moment recentering resumes.
  void snapBaseline() {
    baselineRadians = Matrix3.wrapAngle(lastPredicted - tiltRadians);
  }

  double update({
    required double measured,
    required double omega,
    required bool hasGyro,
    required double dt,
    required bool autoRecenter,
    required bool still,
  }) {
    var predicted = measured;
    if (hasGyro) {
      predicted = measured + omega * FoldMotionModel.predictionInterval;
    }
    lastPredicted = predicted;

    if (autoRecenter && still) {
      final alpha = (dt / FoldMotionModel.recenterTau).clamp(0.0, 1.0).toDouble();
      baselineRadians += Matrix3.wrapAngle(predicted - baselineRadians) * alpha;
    }

    final target = autoRecenter
        ? Matrix3.wrapAngle(predicted - baselineRadians)
        : predicted;

    tiltRadians +=
        Matrix3.wrapAngle(target - tiltRadians) * FoldMotionModel.smoothing;
    return tiltRadians;
  }
}

/// Turns a stream of orientation samples into a smoothed, self-zeroing tilt.
///
/// The pipeline per sample is: express the pose in the calibrated frame, read
/// the screen normal's excursion on both axes, extrapolate each along its
/// gyro rate to cover sensor and display latency, wash out slow drift while
/// the device is still, then low-pass. The two axes are filtered
/// independently with identical constants and combined only at the end, into
/// a magnitude and a lift direction.
///
/// Pure Dart on purpose. No `dart:ui`, no plugin calls, no clock of its own,
/// so every branch is reachable from a unit test.
class FoldMotionModel {
  /// Creates a model. [autoRecenter] can be flipped later.
  FoldMotionModel({bool autoRecenter = true}) {
    _autoRecenter = autoRecenter;
  }

  /// Fraction of the remaining error closed per sample.
  static const double smoothing = 0.7;

  /// Gyro extrapolation horizon, in seconds.
  static const double predictionInterval = 0.04;

  /// Time constant of the auto-recenter washout, in seconds.
  static const double recenterTau = 15;

  /// Below this angular rate the device counts as still, in rad/s.
  static const double stillThreshold = 0.15;

  /// Widest tilt magnitude reported, in degrees.
  static const double maxTiltDegrees = 45;

  /// Below this combined-angle magnitude, in degrees, the lift direction is
  /// undefined and falls back to [FoldState.zero]'s direction instead of
  /// normalizing a near-zero vector into NaN.
  static const double _liftDirEpsilonDegrees = 1e-9;

  List<double>? _reference;
  bool _pendingRecalibrate = false;
  final _AxisFilter _axisX = _AxisFilter();
  final _AxisFilter _axisY = _AxisFilter();
  double? _lastTimestampSeconds;
  bool _autoRecenter = true;
  FoldState _state = FoldState.zero;

  /// Latest computed state.
  FoldState get state => _state;

  /// Whether the slow drift washout is running.
  bool get autoRecenter => _autoRecenter;

  set autoRecenter(bool value) {
    if (value == _autoRecenter) {
      return;
    }
    _autoRecenter = value;
    if (value) {
      _axisX.snapBaseline();
      _axisY.snapBaseline();
    }
  }

  /// Makes the next sample's pose the new zero, and reports zero right away.
  void recalibrate() {
    _pendingRecalibrate = true;
    _axisX.reset();
    _axisY.reset();
    _lastTimestampSeconds = null;
    _state = FoldState.zero;
  }

  /// Folds [sample] into the filter and returns the new state.
  FoldState update(MotionSample sample) {
    if (_reference == null || _pendingRecalibrate) {
      _reference = List<double>.of(sample.screenMatrix);
      _pendingRecalibrate = false;
      _axisX.reset();
      _axisY.reset();
      _lastTimestampSeconds = sample.timestampSeconds;
      return _state = FoldState.zero;
    }

    final relative =
        Matrix3.multiply(Matrix3.transpose(_reference!), sample.screenMatrix);
    final measuredX = Matrix3.screenNormalTilt(relative);
    final measuredY = math.atan2(relative[5], relative[8]);

    final previous = _lastTimestampSeconds;
    // Clamped so a stale or jumped timestamp (for example after the app was
    // backgrounded) cannot feed the washout an outsized dt.
    final dt = previous == null
        ? 0.02
        : (sample.timestampSeconds - previous).clamp(0.0, 0.5).toDouble();
    _lastTimestampSeconds = sample.timestampSeconds;

    final still = sample.omegaMagnitude < stillThreshold;

    final tiltRadiansX = _axisX.update(
      measured: measuredX,
      omega: sample.omegaScreenY,
      hasGyro: sample.hasGyro,
      dt: dt,
      autoRecenter: _autoRecenter,
      still: still,
    );
    final tiltRadiansY = _axisY.update(
      measured: measuredY,
      omega: sample.omegaScreenX,
      hasGyro: sample.hasGyro,
      dt: dt,
      autoRecenter: _autoRecenter,
      still: still,
    );

    final tiltDegreesX = tiltRadiansX * 180 / math.pi;
    final tiltDegreesY = tiltRadiansY * 180 / math.pi;

    final magnitude = math
        .sqrt(tiltDegreesX * tiltDegreesX + tiltDegreesY * tiltDegreesY)
        .clamp(0.0, maxTiltDegrees)
        .toDouble();

    final rawDirX = -tiltDegreesX;
    final rawDirY = tiltDegreesY;
    final dirNorm = math.sqrt(rawDirX * rawDirX + rawDirY * rawDirY);

    double liftDirX;
    double liftDirY;
    if (dirNorm < _liftDirEpsilonDegrees) {
      liftDirX = FoldState.zero.liftDirX;
      liftDirY = FoldState.zero.liftDirY;
    } else {
      liftDirX = rawDirX / dirNorm;
      liftDirY = rawDirY / dirNorm;
    }

    return _state = FoldState(
      tiltDegrees: magnitude,
      liftDirX: liftDirX,
      liftDirY: liftDirY,
    );
  }
}
