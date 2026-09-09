import 'dart:async';

import 'display_metrics.dart';
import 'motion_sample.dart';

export 'display_metrics.dart';
export 'motion_sample.dart';

/// Where orientation samples come from.
///
/// One implementation talks to the platform channel; the other is a fake the
/// tests and the example app's manual mode drive by hand.
abstract class DuoMotionSource {
  /// Reads display density and sensor availability once.
  Future<DuoFoldDisplayMetrics> readMetrics();

  /// Orientation samples, at roughly the platform's game-sensor rate.
  Stream<MotionSample> get samples;

  /// Releases native listeners.
  Future<void> dispose();
}

/// A source the caller drives, for tests and for emulator fallback.
class FakeMotionSource implements DuoMotionSource {
  /// Creates a fake reporting [metrics].
  FakeMotionSource({DuoFoldDisplayMetrics metrics = _defaultMetrics}) {
    _metrics = metrics;
  }

  static const DuoFoldDisplayMetrics _defaultMetrics = DuoFoldDisplayMetrics(
    pixelsPerMillimeter: 6,
    hasRotationSensor: false,
  );

  DuoFoldDisplayMetrics _metrics = _defaultMetrics;
  final StreamController<MotionSample> _controller =
      StreamController<MotionSample>.broadcast();

  /// Pushes [sample] to every listener.
  void emit(MotionSample sample) => _controller.add(sample);

  @override
  Future<DuoFoldDisplayMetrics> readMetrics() async => _metrics;

  @override
  Stream<MotionSample> get samples => _controller.stream;

  @override
  Future<void> dispose() => _controller.close();
}
