import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'motion_api.g.dart';
import 'motion_source.dart';

/// Talks to the Kotlin and Swift halves of the plugin.
///
/// The wire format is generated from `pigeons/motion.dart`, so the three
/// languages cannot disagree about field order or container type without
/// failing to compile. This class exists to keep the generated types from
/// leaking outward: it maps the generated frame onto [MotionSample] and
/// implements the same [DuoMotionSource] contract the rest of the package
/// already talks to.
class ChannelMotionSource implements DuoMotionSource {
  /// Creates a source. The [api] argument exists for tests.
  ChannelMotionSource({DuoMotionHostApi? api})
    : _api = api ?? DuoMotionHostApi();

  final DuoMotionHostApi _api;
  Stream<MotionSample>? _samples;

  @override
  Future<DuoFoldDisplayMetrics> readMetrics() async {
    try {
      final metrics = await _api.metrics();
      return DuoFoldDisplayMetrics(
        pixelsPerMillimeter: metrics.pixelsPerMillimeter,
        hasRotationSensor: metrics.hasRotationSensor,
      );
    } on PlatformException catch (error) {
      debugPrint('duo_animation: metrics call failed: ${error.code}');
      return DuoFoldDisplayMetrics.unknown;
    } on MissingPluginException {
      debugPrint('duo_animation: no platform implementation registered');
      return DuoFoldDisplayMetrics.unknown;
    }
  }

  @override
  Stream<MotionSample> get samples {
    // streamMotion opens a new channel on every call, so it is called once
    // and the broadcast stream it returns is cached.
    return _samples ??= streamMotion()
        .handleError(_reportAndSwallow)
        .map(_toSample);
  }

  /// Keeps one bad frame from tearing down the subscription for the rest of
  /// the session. The generated stream surfaces a native `sink.error` as a
  /// stream error, and an unhandled stream error cancels the subscription.
  void _reportAndSwallow(Object error) {
    if (error is PlatformException) {
      debugPrint('duo_animation: motion stream error: ${error.code}');
      return;
    }
    debugPrint('duo_animation: motion stream error: $error');
  }

  MotionSample _toSample(MotionFrame frame) {
    return MotionSample(
      screenMatrix: frame.screenMatrix,
      omegaScreenY: frame.omegaScreenY,
      omegaScreenX: frame.omegaScreenX,
      omegaMagnitude: frame.omegaMagnitude,
      hasGyro: frame.hasGyro,
      timestampSeconds: frame.timestampSeconds,
    );
  }

  @override
  Future<void> dispose() async {
    _samples = null;
    try {
      await _api.stop();
    } on PlatformException catch (_) {
      // Nothing to do: the native side is already gone.
    } on MissingPluginException {
      // Same.
    }
  }
}
