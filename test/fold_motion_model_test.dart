import 'dart:math' as math;

import 'package:duo_animation/src/motion/fold_motion_model.dart';
import 'package:duo_animation/src/motion/matrix3.dart';
import 'package:duo_animation/src/motion/motion_sample.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a sample whose pose is [degrees] of tilt about the screen Y axis.
MotionSample sampleAt(
  double degrees, {
  double omegaScreenY = 0,
  double omegaMagnitude = 0,
  bool hasGyro = true,
  required double t,
}) {
  return MotionSample(
    screenMatrix: Matrix3.rotationAboutY(degrees * math.pi / 180),
    omegaScreenY: omegaScreenY,
    omegaMagnitude: omegaMagnitude,
    hasGyro: hasGyro,
    timestampSeconds: t,
  );
}

/// Feeds [count] identical samples 20 ms apart, as deliberate motion so the
/// washout stays out of it, starting after calibration.
FoldState settle(FoldMotionModel model, double degrees, {int count = 60}) {
  var state = FoldState.zero;
  for (var i = 0; i < count; i++) {
    state = model.update(
      sampleAt(degrees, omegaMagnitude: 1, t: 0.02 * (i + 1)),
    );
  }
  return state;
}

void main() {
  group('calibration', () {
    test('the first sample latches the reference pose and reports zero tilt', () {
      final model = FoldMotionModel();
      final state = model.update(sampleAt(30, t: 0));

      expect(state.tiltDegrees, 0);
      expect(state.hingeSide, 1);
      expect(model.state, state);
    });

    test('tilt is measured relative to the latched pose, not to level', () {
      final model = FoldMotionModel()..update(sampleAt(30, t: 0));
      final state = settle(model, 40);

      // 40 degrees of world tilt, 30 of which was calibrated away.
      expect(state.tiltDegrees, closeTo(10, 0.01));
    });

    test('recalibrate snaps to zero immediately and re-latches on the next sample',
        () {
      final model = FoldMotionModel()..update(sampleAt(0, t: 0));
      settle(model, 20);

      model.recalibrate();
      expect(model.state.tiltDegrees, 0);

      final next = model.update(sampleAt(20, t: 5));
      expect(next.tiltDegrees, 0);

      expect(settle(model, 25, count: 60).tiltDegrees, closeTo(5, 0.01));
    });
  });

  group('hinge side', () {
    test('positive tilt hinges right, negative hinges left', () {
      final right = FoldMotionModel()..update(sampleAt(0, t: 0));
      expect(settle(right, 20).hingeSide, 1);

      final left = FoldMotionModel()..update(sampleAt(0, t: 0));
      expect(settle(left, -20).hingeSide, -1);
    });
  });

  group('smoothing', () {
    test('closes 70 percent of the remaining error on each sample', () {
      final model = FoldMotionModel(autoRecenter: false)..update(sampleAt(0, t: 0));

      final first = model.update(sampleAt(10, t: 0.02));
      expect(first.tiltDegrees, closeTo(7, 0.01));

      final second = model.update(sampleAt(10, t: 0.04));
      expect(second.tiltDegrees, closeTo(9.1, 0.01));
    });
  });

  group('gyro prediction', () {
    test('extrapolates the measurement forward over the prediction horizon', () {
      final model = FoldMotionModel(autoRecenter: false)..update(sampleAt(0, t: 0));

      // 1 rad/s for 40 ms is 0.04 rad, about 2.29 degrees ahead of the pose.
      final state = model.update(
        sampleAt(0, omegaScreenY: 1, omegaMagnitude: 1, t: 0.02),
      );
      expect(state.tiltDegrees, closeTo(0.7 * 0.04 * 180 / math.pi, 0.01));
    });

    test('ignores the horizon when the sample carries no gyro reading', () {
      final model = FoldMotionModel(autoRecenter: false)..update(sampleAt(0, t: 0));

      final state = model.update(
        sampleAt(0, omegaScreenY: 1, hasGyro: false, t: 0.02),
      );
      expect(state.tiltDegrees, 0);
    });
  });

  group('auto-recenter washout', () {
    test('drags a still, drifted pose back toward zero', () {
      final model = FoldMotionModel()..update(sampleAt(0, t: 0));
      final drifted = settle(model, 8);
      expect(drifted.tiltDegrees, closeTo(8, 0.01));

      // 30 s of stillness at 20 ms per sample, twice the 15 s time constant.
      var t = drifted.tiltDegrees;
      for (var i = 0; i < 1500; i++) {
        t = model.update(sampleAt(8, t: 1.2 + 0.02 * i)).tiltDegrees;
      }
      expect(t.abs(), lessThan(1.5));
    });

    test('leaves deliberate motion alone', () {
      final model = FoldMotionModel()..update(sampleAt(0, t: 0));

      var state = FoldState.zero;
      for (var i = 0; i < 1500; i++) {
        state = model.update(
          sampleAt(8, omegaMagnitude: 0.9, t: 0.02 * (i + 1)),
        );
      }
      expect(state.tiltDegrees, closeTo(8, 0.01));
    });

    test('disabling the washout stops it entirely', () {
      final model = FoldMotionModel(autoRecenter: false)..update(sampleAt(0, t: 0));

      var state = FoldState.zero;
      for (var i = 0; i < 1500; i++) {
        state = model.update(sampleAt(8, t: 0.02 * (i + 1)));
      }
      expect(state.tiltDegrees, closeTo(8, 0.01));
    });

    test('re-enabling snaps the baseline so the output does not jump', () {
      final model = FoldMotionModel(autoRecenter: false)..update(sampleAt(0, t: 0));
      final before = settle(model, 8).tiltDegrees;

      model.autoRecenter = true;
      final after = model.update(sampleAt(8, t: 99)).tiltDegrees;

      expect((after - before).abs(), lessThan(0.5));
    });
  });

  group('clamping', () {
    test('never reports beyond the stable range', () {
      final model = FoldMotionModel(autoRecenter: false)..update(sampleAt(0, t: 0));
      expect(settle(model, 80).tiltDegrees, 45);
      expect(settle(model, -80).tiltDegrees, -45);
    });
  });

  group('MotionSample.fromPayload', () {
    test('decodes the 13-double wire format', () {
      final payload = <double>[
        1, 0, 0, 0, 1, 0, 0, 0, 1, // matrix
        0.5, // omegaScreenY
        0.9, // omegaMagnitude
        1, // hasGyro
        12.25, // timestampSeconds
      ];

      final sample = MotionSample.fromPayload(payload);

      expect(sample.screenMatrix, Matrix3.identity);
      expect(sample.omegaScreenY, 0.5);
      expect(sample.omegaMagnitude, 0.9);
      expect(sample.hasGyro, isTrue);
      expect(sample.timestampSeconds, 12.25);
    });

    test('rejects a payload of the wrong length', () {
      expect(
        () => MotionSample.fromPayload(<double>[1, 2, 3]),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
