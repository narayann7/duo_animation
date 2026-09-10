import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'duo_fold_constraints.dart';
import 'motion/channel_motion_source.dart';
import 'motion/fold_motion_model.dart';
import 'motion/motion_source.dart';

/// Owns the sensor subscription and the tilt filter, and exposes the result as
/// a [ChangeNotifier] a widget can listen to.
///
/// Two modes share one output. In sensor mode the tilt comes from
/// [FoldMotionModel]; in manual mode it comes from [manualTiltDegrees], which is
/// what emulators and tuning sessions use. Devices with no rotation sensor start
/// in manual mode. Whichever mode is active, [constraints] is applied before
/// [tiltDegrees] and the lift direction are published, so the readout and the
/// effect always agree, and swapping [constraints] at runtime needs no
/// recalibration.
class DuoFoldController extends ChangeNotifier {
  /// Creates a controller. [source] defaults to the platform channel.
  DuoFoldController({
    DuoMotionSource? source,
    bool autoRecenter = true,
    DuoFoldConstraints constraints = const DuoFoldConstraints.horizontal(),
  })  : _source = source ?? ChannelMotionSource(),
        _model = FoldMotionModel(autoRecenter: autoRecenter) {
    _constraints = constraints;
  }

  final DuoMotionSource _source;
  final FoldMotionModel _model;

  StreamSubscription<MotionSample>? _subscription;
  DuoFoldDisplayMetrics _metrics = DuoFoldDisplayMetrics.unknown;
  FoldState _sensorState = FoldState.zero;
  double _manualTiltDegrees = 0;
  late DuoFoldConstraints _constraints;
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

  /// Which fold directions this controller will report. Defaults to
  /// [DuoFoldConstraints.horizontal].
  ///
  /// Applied on the way out, after the free-rotation pose is filtered, so
  /// swapping this needs no recalibration: the very next read reflects it.
  DuoFoldConstraints get constraints => _constraints;

  set constraints(DuoFoldConstraints value) {
    _constraints = value;
    notifyListeners();
  }

  double get _rawTiltDegrees =>
      useSensor ? _sensorState.tiltDegrees : _manualTiltDegrees.abs();

  double get _rawLiftDirX => useSensor
      ? _sensorState.liftDirX
      : (_manualTiltDegrees >= 0 ? -1.0 : 1.0);

  double get _rawLiftDirY => useSensor ? _sensorState.liftDirY : 0.0;

  ({double tiltDegrees, double liftDirX, double liftDirY}) get _resolved =>
      _constraints.resolve(
        tiltDegrees: _rawTiltDegrees,
        liftDirX: _rawLiftDirX,
        liftDirY: _rawLiftDirY,
      );

  /// Current tilt in degrees, from whichever mode is active, after
  /// [constraints] is applied. Always non-negative.
  double get tiltDegrees => _resolved.tiltDegrees;

  /// X of the unit lift direction the effect should hinge on, in fragment
  /// coordinates (y down), after [constraints] is applied.
  double get liftDirX => _resolved.liftDirX;

  /// Y of the unit lift direction, in fragment coordinates (y down), after
  /// [constraints] is applied.
  double get liftDirY => _resolved.liftDirY;

  /// [liftDirX] and [liftDirY] as an [ui.Offset], for callers passing the
  /// value straight to [DuoFold.liftDirection].
  ui.Offset get liftDirection => ui.Offset(liftDirX, liftDirY);

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
