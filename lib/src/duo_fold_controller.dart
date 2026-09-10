import 'dart:async';

import 'package:flutter/foundation.dart';

import 'motion/channel_motion_source.dart';
import 'motion/fold_motion_model.dart';
import 'motion/motion_source.dart';

/// Owns the sensor subscription and the tilt filter, and exposes the result as
/// a [ChangeNotifier] a widget can listen to.
///
/// Two modes share one output. In sensor mode the tilt comes from
/// [FoldMotionModel]; in manual mode it comes from [manualTiltDegrees], which is
/// what emulators and tuning sessions use. Devices with no rotation sensor start
/// in manual mode.
class DuoFoldController extends ChangeNotifier {
  /// Creates a controller. [source] defaults to the platform channel.
  DuoFoldController({DuoMotionSource? source, bool autoRecenter = true})
      : _source = source ?? ChannelMotionSource(),
        _model = FoldMotionModel(autoRecenter: autoRecenter);

  final DuoMotionSource _source;
  final FoldMotionModel _model;

  StreamSubscription<MotionSample>? _subscription;
  DuoFoldDisplayMetrics _metrics = DuoFoldDisplayMetrics.unknown;
  FoldState _sensorState = FoldState.zero;
  double _manualTiltDegrees = 0;
  bool _useSensor = false;
  bool _started = false;

  /// Reads display metrics and subscribes to the sample stream.
  ///
  /// Safe to call more than once; later calls do nothing.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    _metrics = await _source.readMetrics();
    _useSensor = _metrics.hasRotationSensor;
    _subscription = _source.samples.listen(_onSample);
    notifyListeners();
  }

  void _onSample(MotionSample sample) {
    _sensorState = _model.update(sample);
    if (_useSensor) {
      notifyListeners();
    }
  }

  /// Whether the platform reported a usable orientation sensor.
  bool get hasSensor => _metrics.hasRotationSensor;

  /// Display density, or null when the platform did not report one.
  double? get pixelsPerMillimeter =>
      _metrics.pixelsPerMillimeter > 0 ? _metrics.pixelsPerMillimeter : null;

  /// Whether sensor readings, rather than [manualTiltDegrees], drive the tilt.
  bool get useSensor => _useSensor && hasSensor;

  set useSensor(bool value) {
    final next = value && hasSensor;
    if (next == _useSensor) {
      return;
    }
    _useSensor = next;
    notifyListeners();
  }

  /// Tilt used while [useSensor] is false, in degrees.
  double get manualTiltDegrees => _manualTiltDegrees;

  set manualTiltDegrees(double value) {
    final clamped = value
        .clamp(-FoldMotionModel.maxTiltDegrees, FoldMotionModel.maxTiltDegrees)
        .toDouble();
    if (clamped == _manualTiltDegrees) {
      return;
    }
    _manualTiltDegrees = clamped;
    if (!useSensor) {
      notifyListeners();
    }
  }

  /// Whether the slow drift washout is running.
  bool get autoRecenter => _model.autoRecenter;

  set autoRecenter(bool value) {
    if (value == _model.autoRecenter) {
      return;
    }
    _model.autoRecenter = value;
    notifyListeners();
  }

  /// Current tilt in degrees, from whichever mode is active.
  double get tiltDegrees =>
      useSensor ? _sensorState.tiltDegrees : _manualTiltDegrees;

  /// Hinge implied by the current tilt.
  double get hingeSide =>
      useSensor ? _sensorState.hingeSide : (_manualTiltDegrees >= 0 ? 1 : -1);

  /// Re-zeroes the pose and clears any manual offset.
  void recalibrate() {
    _model.recalibrate();
    _sensorState = FoldState.zero;
    _manualTiltDegrees = 0;
    notifyListeners();
  }

  /// Cancels the sample subscription, then releases the source's native
  /// listener.
  ///
  /// [DuoMotionSource.dispose] releases the native listener but does not
  /// cancel subscriptions a caller already holds on its [DuoMotionSource.samples]
  /// stream, so this cancels this controller's own subscription first.
  @override
  void dispose() {
    _subscription?.cancel();
    _source.dispose();
    super.dispose();
  }
}
