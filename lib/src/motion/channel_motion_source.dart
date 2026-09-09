import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'motion_source.dart';

/// Talks to the Kotlin and Swift halves of the plugin.
///
/// The native side does exactly two things: reduce the platform's orientation
/// reading to screen axes, and project the gyro onto the screen's up axis. All
/// filtering happens in Dart, so the two native implementations stay small
/// enough to eyeball for correctness.
class ChannelMotionSource implements DuoMotionSource {
  /// Creates a source. The channel arguments exist for tests.
  ChannelMotionSource({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methods = methodChannel ?? const MethodChannel(methodChannelName),
       _events = eventChannel ?? const EventChannel(eventChannelName);

  /// Name of the request and response channel.
  static const String methodChannelName = 'dev.duoanimation/duo_animation';

  /// Name of the sample stream channel.
  static const String eventChannelName =
      'dev.duoanimation/duo_animation/motion';

  final MethodChannel _methods;
  final EventChannel _events;
  Stream<MotionSample>? _samples;

  @override
  Future<DuoFoldDisplayMetrics> readMetrics() async {
    try {
      final result = await _methods.invokeMapMethod<Object?, Object?>(
        'metrics',
      );
      if (result == null) {
        return DuoFoldDisplayMetrics.unknown;
      }
      return DuoFoldDisplayMetrics.fromMap(result);
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
    return _samples ??= _events
        .receiveBroadcastStream()
        .map(_decode)
        .where((sample) => sample != null)
        .cast<MotionSample>();
  }

  /// Returns null for a frame that does not parse, so one bad packet cannot
  /// tear down the subscription for the rest of the session.
  MotionSample? _decode(Object? event) {
    if (event is! Float64List) {
      debugPrint(
        'duo_animation: unexpected motion frame type ${event.runtimeType}',
      );
      return null;
    }
    try {
      return MotionSample.fromPayload(event);
    } on FormatException catch (error) {
      debugPrint('duo_animation: ${error.message}');
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _samples = null;
    try {
      await _methods.invokeMethod<void>('stop');
    } on PlatformException catch (_) {
      // Nothing to do: the native side is already gone.
    } on MissingPluginException {
      // Same.
    }
  }
}
