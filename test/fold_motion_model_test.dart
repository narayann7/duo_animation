import 'dart:math' as math;

import 'package:duo_animation/src/motion/fold_motion_model.dart';
import 'package:duo_animation/src/motion/matrix3.dart';
import 'package:duo_animation/src/motion/motion_sample.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a sample whose pose is [degrees] of tilt about the screen Y axis
/// (screen-right lean only, `tiltY` stays zero). This is today's single-axis
/// pose, unchanged.
MotionSample sampleAt(
  double degrees, {
  double omegaScreenY = 0,
  double omegaScreenX = 0,
  double omegaMagnitude = 0,
  bool hasGyro = true,
  required double t,
}) {
  return MotionSample(
    screenMatrix: Matrix3.rotationAboutY(degrees * math.pi / 180),
    omegaScreenY: omegaScreenY,
    omegaScreenX: omegaScreenX,
    omegaMagnitude: omegaMagnitude,
    hasGyro: hasGyro,
    timestampSeconds: t,
  );
}

/// Builds a sample whose pose reads exactly [tiltXDegrees] and
/// [tiltYDegrees] once run through [Matrix3.screenNormalTilt]-style atan2.
///
/// The filter only ever reads indices 2, 5 and 8 of the relative matrix (the
/// screen-normal column) to derive `tiltX` and `tiltY`, so setting `nz = 1`
/// and `nx = tan(tiltX)`, `ny = tan(tiltY)` gives each axis an exact,
/// independent target angle without needing a fully orthonormal rotation
/// matrix.
MotionSample sampleAtXY(
  double tiltXDegrees,
  double tiltYDegrees, {
  double omegaScreenY = 0,
  double omegaScreenX = 0,
  double omegaMagnitude = 0,
  bool hasGyro = true,
  required double t,
}) {
  final matrix = List<double>.of(Matrix3.identity);
  matrix[2] = math.tan(tiltXDegrees * math.pi / 180);
  matrix[5] = math.tan(tiltYDegrees * math.pi / 180);
  matrix[8] = 1;
  return MotionSample(
    screenMatrix: matrix,
    omegaScreenY: omegaScreenY,
    omegaScreenX: omegaScreenX,
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

/// Same as [settle] but for a two-axis pose built with [sampleAtXY].
FoldState settleXY(
  FoldMotionModel model,
  double tiltXDegrees,
  double tiltYDegrees, {
  int count = 60,
}) {
  var state = FoldState.zero;
  for (var i = 0; i < count; i++) {
    state = model.update(
      sampleAtXY(
        tiltXDegrees,
        tiltYDegrees,
        omegaMagnitude: 1,
        t: 0.02 * (i + 1),
      ),
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
      expect(state.liftDirX, -1);
      expect(state.liftDirY, 0);
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

  group('lift direction', () {
    test('a rightward lean lifts the left edge, a leftward lean the right', () {
      final right = FoldMotionModel()..update(sampleAt(0, t: 0));
      final rightState = settle(right, 20);
      expect(rightState.liftDirX, closeTo(-1, 0.01));
      expect(rightState.liftDirY, closeTo(0, 0.01));

      final left = FoldMotionModel()..update(sampleAt(0, t: 0));
      final leftState = settle(left, -20);
      expect(leftState.liftDirX, closeTo(1, 0.01));
      expect(leftState.liftDirY, closeTo(0, 0.01));
    });

    test(
      'a pure pitch pose lifts down the screen with magnitude equal to the '
      'pitch angle',
      () {
        final model = FoldMotionModel()..update(sampleAtXY(0, 0, t: 0));
        final state = settleXY(model, 0, 20);

        expect(state.tiltDegrees, closeTo(20, 0.01));
        expect(state.liftDirX, closeTo(0, 0.01));
        expect(state.liftDirY, closeTo(1, 0.01));
      },
    );

    test(
      'a diagonal pose has a magnitude equal to the hypotenuse of the two '
      'angles and a 45-degree-ish direction',
      () {
        final model = FoldMotionModel()..update(sampleAtXY(0, 0, t: 0));
        final state = settleXY(model, 20, 20);

        expect(state.tiltDegrees, closeTo(math.sqrt(20 * 20 + 20 * 20), 0.05));
        expect(state.liftDirX, closeTo(-math.sqrt1_2, 0.01));
        expect(state.liftDirY, closeTo(math.sqrt1_2, 0.01));
      },
    );

    test('at rest the direction is finite and equals the documented fallback', () {
      final model = FoldMotionModel()..update(sampleAtXY(0, 0, t: 0));
      final state = settleXY(model, 0, 0);

      expect(state.tiltDegrees, 0);
      expect(state.liftDirX, -1);
      expect(state.liftDirY, 0);
      expect(state.liftDirX.isFinite, isTrue);
      expect(state.liftDirY.isFinite, isTrue);
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

    test('omegaScreenX drives the second axis prediction the same way', () {
      final model = FoldMotionModel(autoRecenter: false)
        ..update(sampleAtXY(0, 0, t: 0));

      final state = model.update(
        sampleAtXY(0, 0, omegaScreenX: 1, omegaMagnitude: 1, t: 0.02),
      );
      expect(state.tiltDegrees, closeTo(0.7 * 0.04 * 180 / math.pi, 0.01));
      expect(state.liftDirX, closeTo(0, 0.01));
      expect(state.liftDirY, closeTo(1, 0.01));
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
    test('never reports a magnitude beyond the stable range', () {
      final model = FoldMotionModel(autoRecenter: false)..update(sampleAt(0, t: 0));
      final positive = settle(model, 80);
      expect(positive.tiltDegrees, 45);
      expect(positive.liftDirX, closeTo(-1, 0.01));

      final negativeModel = FoldMotionModel(autoRecenter: false)
        ..update(sampleAt(0, t: 0));
      final negative = settle(negativeModel, -80);
      expect(negative.tiltDegrees, 45);
      expect(negative.liftDirX, closeTo(1, 0.01));
    });
  });
}
