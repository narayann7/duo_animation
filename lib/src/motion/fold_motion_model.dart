import 'dart:math' as math;

import 'matrix3.dart';
import 'motion_sample.dart';

/// The filter's output: a signed tilt and the hinge it implies.
class FoldState {
  /// Creates a state.
  const FoldState({required this.tiltDegrees, required this.hingeSide});

  /// Level, hinge on the right by convention.
  static const FoldState zero = FoldState(tiltDegrees: 0, hingeSide: 1);

  /// Signed tilt about the screen-space Y axis, clamped to plus or minus 45.
  final double tiltDegrees;

  /// `1` for a hinge on the right edge, `-1` for the left.
  final double hingeSide;

  @override
  bool operator ==(Object other) =>
      other is FoldState &&
      other.tiltDegrees == tiltDegrees &&
      other.hingeSide == hingeSide;

  @override
  int get hashCode => Object.hash(tiltDegrees, hingeSide);

  @override
  String toString() =>
      'FoldState(${tiltDegrees.toStringAsFixed(2)} deg, '
      'hinge ${hingeSide < 0 ? 'L' : 'R'})';
}

/// Turns a stream of orientation samples into a smoothed, self-zeroing tilt.
///
/// The pipeline per sample is: express the pose in the calibrated frame, read
/// the screen normal's excursion, extrapolate along the gyro to cover sensor
/// and display latency, wash out slow drift while the device is still, then
/// low-pass.
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

  /// Widest tilt reported, in degrees.
  static const double maxTiltDegrees = 45;

  List<double>? _reference;
  bool _pendingRecalibrate = false;
  double _tiltRadians = 0;
  double _baselineRadians = 0;
  double _lastPredicted = 0;
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
      // Snap the baseline so the reported tilt keeps its current value
      // instead of jumping the moment recentering resumes.
      _baselineRadians = Matrix3.wrapAngle(_lastPredicted - _tiltRadians);
    }
  }

  /// Makes the next sample's pose the new zero, and reports zero right away.
  void recalibrate() {
    _pendingRecalibrate = true;
    _tiltRadians = 0;
    _baselineRadians = 0;
    _lastTimestampSeconds = null;
    _state = FoldState.zero;
  }

  /// Folds [sample] into the filter and returns the new state.
  FoldState update(MotionSample sample) {
    if (_reference == null || _pendingRecalibrate) {
      _reference = List<double>.of(sample.screenMatrix);
      _pendingRecalibrate = false;
      _tiltRadians = 0;
      _baselineRadians = 0;
      _lastPredicted = 0;
      _lastTimestampSeconds = sample.timestampSeconds;
      return _state = FoldState.zero;
    }

    final relative =
        Matrix3.multiply(Matrix3.transpose(_reference!), sample.screenMatrix);
    final measured = Matrix3.screenNormalTilt(relative);

    var predicted = measured;
    if (sample.hasGyro) {
      predicted = measured + sample.omegaScreenY * predictionInterval;
    }
    _lastPredicted = predicted;

    final previous = _lastTimestampSeconds;
    // Clamped so a stale or jumped timestamp (for example after the app was
    // backgrounded) cannot feed the washout an outsized dt.
    final dt = previous == null
        ? 0.02
        : (sample.timestampSeconds - previous).clamp(0.0, 0.5).toDouble();
    _lastTimestampSeconds = sample.timestampSeconds;

    if (_autoRecenter && sample.omegaMagnitude < stillThreshold) {
      final alpha = (dt / recenterTau).clamp(0.0, 1.0).toDouble();
      _baselineRadians +=
          Matrix3.wrapAngle(predicted - _baselineRadians) * alpha;
    }

    final target = _autoRecenter
        ? Matrix3.wrapAngle(predicted - _baselineRadians)
        : predicted;

    _tiltRadians += Matrix3.wrapAngle(target - _tiltRadians) * smoothing;

    final degrees = (_tiltRadians * 180 / math.pi)
        .clamp(-maxTiltDegrees, maxTiltDegrees)
        .toDouble();

    return _state = FoldState(
      tiltDegrees: degrees,
      hingeSide: degrees >= 0 ? 1 : -1,
    );
  }
}
