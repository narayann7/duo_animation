import 'dart:typed_data';

import 'package:duo_animation/src/motion/channel_motion_source.dart';
import 'package:duo_animation/src/motion/motion_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel(ChannelMotionSource.methodChannelName);
  const eventChannel = EventChannel(ChannelMotionSource.eventChannelName);

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  group('readMetrics', () {
    test('decodes density and sensor availability', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        expect(call.method, 'metrics');
        return <String, Object?>{
          'pixelsPerMillimeter': 6.42,
          'hasRotationSensor': true,
        };
      });

      final metrics = await ChannelMotionSource().readMetrics();

      expect(metrics.pixelsPerMillimeter, closeTo(6.42, 1e-9));
      expect(metrics.hasRotationSensor, isTrue);
    });

    test(
      'reports no sensor and zero density when the platform call fails',
      () async {
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          throw PlatformException(code: 'unavailable');
        });

        final metrics = await ChannelMotionSource().readMetrics();

        expect(metrics.hasRotationSensor, isFalse);
        expect(metrics.pixelsPerMillimeter, 0);
      },
    );
  });

  group('samples', () {
    test('decodes Float64List frames into MotionSample', () async {
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            sink.success(
              Float64List.fromList(<double>[
                1,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                1,
                0.25,
                0.75,
                1,
                7.5,
              ]),
            );
            sink.endOfStream();
          },
        ),
      );

      final source = ChannelMotionSource();
      final sample = await source.samples.first;

      expect(sample.omegaScreenY, 0.25);
      expect(sample.omegaMagnitude, 0.75);
      expect(sample.hasGyro, isTrue);
      expect(sample.timestampSeconds, 7.5);
      await source.dispose();
    });

    test('drops malformed frames instead of killing the stream', () async {
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            sink.success(Float64List.fromList(<double>[1, 2, 3]));
            sink.success(
              Float64List.fromList(<double>[
                1,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                1,
              ]),
            );
            sink.endOfStream();
          },
        ),
      );

      final source = ChannelMotionSource();
      final samples = await source.samples.toList();

      expect(samples, hasLength(1));
      expect(samples.single.timestampSeconds, 1);
      await source.dispose();
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
        MotionSample.fromPayload(<double>[
          1,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          1,
          0,
          0,
          1,
          3,
        ]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, <double>[3]);
      await subscription.cancel();
      await fake.dispose();
    });
  });
}
