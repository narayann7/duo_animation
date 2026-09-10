import 'dart:typed_data';

import 'package:duo_animation/src/motion/channel_motion_source.dart';
import 'package:duo_animation/src/motion/motion_api.g.dart';
import 'package:duo_animation/src/motion/motion_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Channel names Pigeon derives from the schema. Hard-coding them here is
/// deliberate: if a rename in the schema silently moves a channel, these
/// tests are what notices.
const String _metricsChannel =
    'dev.flutter.pigeon.duo_animation.DuoMotionHostApi.metrics';
const String _streamChannel =
    'dev.flutter.pigeon.duo_animation.DuoMotionEventApi.streamMotion';
const String _stopChannel =
    'dev.flutter.pigeon.duo_animation.DuoMotionHostApi.stop';

/// The mock messenger encodes through the codec of whatever channel it is
/// handed, so the stub has to carry Pigeon's codec rather than the standard
/// one. A plain `EventChannel` here fails to encode a `MotionFrame`.
const EventChannel _streamStub = EventChannel(
  _streamChannel,
  pigeonMethodCodec,
);

MotionFrame _frame({double timestampSeconds = 1}) {
  return MotionFrame(
    screenMatrix: Float64List.fromList(<double>[1, 0, 0, 0, 1, 0, 0, 0, 1]),
    omegaScreenY: 0.25,
    omegaScreenX: 0.35,
    omegaMagnitude: 0.75,
    hasGyro: true,
    timestampSeconds: timestampSeconds,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMessageHandler(_metricsChannel, null);
    messenger.setMockMessageHandler(_stopChannel, null);
    messenger.setMockStreamHandler(_streamStub, null);
  });

  group('readMetrics', () {
    test('decodes density and sensor availability', () async {
      messenger.setMockMessageHandler(_metricsChannel, (message) async {
        final metrics = MotionMetrics(
          pixelsPerMillimeter: 6.42,
          hasRotationSensor: true,
        );
        return DuoMotionHostApi.pigeonChannelCodec.encodeMessage(<Object?>[
          metrics,
        ]);
      });

      final metrics = await ChannelMotionSource().readMetrics();

      expect(metrics.pixelsPerMillimeter, closeTo(6.42, 1e-9));
      expect(metrics.hasRotationSensor, isTrue);
    });

    test('reports no sensor and zero density when the call fails', () async {
      messenger.setMockMessageHandler(_metricsChannel, (message) async => null);

      final metrics = await ChannelMotionSource().readMetrics();

      expect(metrics.hasRotationSensor, isFalse);
      expect(metrics.pixelsPerMillimeter, 0);
    });
  });

  group('samples', () {
    test('maps generated frames onto MotionSample', () async {
      messenger.setMockStreamHandler(
        _streamStub,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            sink.success(_frame(timestampSeconds: 7.5));
            sink.endOfStream();
          },
        ),
      );

      final source = ChannelMotionSource();
      final sample = await source.samples.first;

      expect(sample.screenMatrix, <double>[1, 0, 0, 0, 1, 0, 0, 0, 1]);
      expect(sample.omegaScreenY, 0.25);
      expect(sample.omegaScreenX, 0.35);
      expect(sample.omegaMagnitude, 0.75);
      expect(sample.hasGyro, isTrue);
      expect(sample.timestampSeconds, 7.5);
      await source.dispose();
    });

    test(
      'survives a stream error instead of losing the subscription',
      () async {
        messenger.setMockStreamHandler(
          _streamStub,
          MockStreamHandler.inline(
            onListen: (arguments, sink) {
              sink.error(code: 'sensor', message: 'transient glitch');
              sink.success(_frame(timestampSeconds: 2));
              sink.endOfStream();
            },
          ),
        );

        final source = ChannelMotionSource();
        final samples = await source.samples.toList();

        expect(samples, hasLength(1));
        expect(samples.single.timestampSeconds, 2);
        await source.dispose();
      },
    );
  });

  group('dispose', () {
    test('tells the native side to unregister its listeners', () async {
      var stopCalls = 0;
      messenger.setMockMessageHandler(_stopChannel, (message) async {
        stopCalls++;
        return DuoMotionHostApi.pigeonChannelCodec.encodeMessage(<Object?>[
          null,
        ]);
      });

      await ChannelMotionSource().dispose();

      expect(stopCalls, 1);
    });

    test('survives a native side that is already gone', () async {
      // No handler registered, so the call fails the way a detached engine
      // makes it fail. dispose must swallow that rather than throw.
      await expectLater(ChannelMotionSource().dispose(), completes);
    });
  });

  group('FakeMotionSource', () {
    test('replays whatever is pushed into it', () async {
      final fake = FakeMotionSource();
      final received = <double>[];
      final subscription = fake.samples.listen(
        (s) => received.add(s.timestampSeconds),
      );

      fake.emit(
        const MotionSample(
          screenMatrix: <double>[1, 0, 0, 0, 1, 0, 0, 0, 1],
          omegaScreenY: 0,
          omegaScreenX: 0,
          omegaMagnitude: 0,
          hasGyro: true,
          timestampSeconds: 3,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, <double>[3]);
      await subscription.cancel();
      await fake.dispose();
    });
  });
}
