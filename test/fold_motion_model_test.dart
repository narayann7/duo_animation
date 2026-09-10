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

/// Rotation of [radians] about the screen-space X axis, screen-right.
///
/// The counterpart to [Matrix3.rotationAboutY], which the package ships because
/// the horizontal axis needs it. Positive angles swing the screen normal toward
/// screen-down, so the top edge is the one that comes toward the viewer.
List<double> rotationAboutX(double radians) {
  final c = math.cos(radians);
  final s = math.sin(radians);
  return <double>[1, 0, 0, 0, c, -s, 0, s, c];
}

/// Builds a sample from a genuine pose rather than a hand-set normal column.
///
/// [sampleAtXY] sets matrix entries directly, which is exact for reading an
/// angle back out but says nothing about how a pose and a gyro rate relate.
/// Anything asserting on the prediction has to come through here instead.
MotionSample sampleFromPose(
  List<double> pose, {
  double omegaScreenY = 0,
  double omegaScreenX = 0,
  double omegaMagnitude = 0,
  bool hasGyro = true,
  required double t,
}) {
  return MotionSample(
    screenMatrix: pose,
    omegaScreenY: omegaScreenY,
    omegaScreenX: omegaScreenX,
    omegaMagnitude: omegaMagnitude,
    hasGyro: hasGyro,
    timestampSeconds: t,
  );
}

/// Turns the device at a constant [rate] rad/s about one screen axis for
/// [seconds], and returns the tilt the model ends up reporting.
///
/// [about] picks the axis: `x` is screen-right, driving the vertical fold,
/// `y` is screen-up, driving the horizontal one. Set [hasGyro] false to run the
/// same sweep with the prediction term switched off, which is the baseline the
/// gyro is supposed to beat.
double sweep({
  required double rate,
  required double seconds,
  required String about,
  bool hasGyro = true,
}) {
  final model = FoldMotionModel(autoRecenter: false);
  final identity = about == 'x' ? rotationAboutX(0) : Matrix3.rotationAboutY(0);
  model.update(sampleFromPose(identity, t: 0));

  var state = model.state;
  const step = 0.02;
  for (var t = step; t <= seconds + 1e-9; t += step) {
    final angle = rate * t;
    state = model.update(
      sampleFromPose(
        about == 'x' ? rotationAboutX(angle) : Matrix3.rotationAboutY(angle),
        omegaScreenX: about == 'x' ? rate : 0,
        omegaScreenY: about == 'y' ? rate : 0,
        omegaMagnitude: rate.abs(),
        hasGyro: hasGyro,
        t: t,
      ),
    );
  }
  return state.tiltDegrees;
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
    test(
      'the first sample latches the reference pose and reports zero tilt',
      () {
        final model = FoldMotionModel();
        final state = model.update(sampleAt(30, t: 0));

        expect(state.tiltDegrees, 0);
        expect(state.liftDirX, -1);
        expect(state.liftDirY, 0);
        expect(model.state, state);
      },
    );

    test('tilt is measured relative to the latched pose, not to level', () {
      final model = FoldMotionModel()..update(sampleAt(30, t: 0));
      final state = settle(model, 40);

      // 40 degrees of world tilt, 30 of which was calibrated away.
      expect(state.tiltDegrees, closeTo(10, 0.01));
    });

    test(
      'recalibrate snaps to zero immediately and re-latches on the next sample',
      () {
        final model = FoldMotionModel()..update(sampleAt(0, t: 0));
        settle(model, 20);

        model.recalibrate();
        expect(model.state.tiltDegrees, 0);

        final next = model.update(sampleAt(20, t: 5));
        expect(next.tiltDegrees, 0);

        expect(settle(model, 25, count: 60).tiltDegrees, closeTo(5, 0.01));
      },
    );
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

    test('a pure pitch pose lifts down the screen with magnitude equal to the '
        'pitch angle', () {
      final model = FoldMotionModel()..update(sampleAtXY(0, 0, t: 0));
      final state = settleXY(model, 0, 20);

      expect(state.tiltDegrees, closeTo(20, 0.01));
      expect(state.liftDirX, closeTo(0, 0.01));
      expect(state.liftDirY, closeTo(1, 0.01));
    });

    test('a diagonal pose has a magnitude equal to the hypotenuse of the two '
        'angles and a 45-degree-ish direction', () {
      final model = FoldMotionModel()..update(sampleAtXY(0, 0, t: 0));
      final state = settleXY(model, 20, 20);

      expect(state.tiltDegrees, closeTo(math.sqrt(20 * 20 + 20 * 20), 0.05));
      expect(state.liftDirX, closeTo(-math.sqrt1_2, 0.01));
      expect(state.liftDirY, closeTo(math.sqrt1_2, 0.01));
    });

    test(
      'at rest the direction is finite and equals the documented fallback',
      () {
        final model = FoldMotionModel()..update(sampleAtXY(0, 0, t: 0));
        final state = settleXY(model, 0, 0);

        expect(state.tiltDegrees, 0);
        expect(state.liftDirX, -1);
        expect(state.liftDirY, 0);
        expect(state.liftDirX.isFinite, isTrue);
        expect(state.liftDirY.isFinite, isTrue);
      },
    );
  });

  group('smoothing', () {
    test('closes 70 percent of the remaining error on each sample', () {
      final model = FoldMotionModel(autoRecenter: false)
        ..update(sampleAt(0, t: 0));

      final first = model.update(sampleAt(10, t: 0.02));
      expect(first.tiltDegrees, closeTo(7, 0.01));

      final second = model.update(sampleAt(10, t: 0.04));
      expect(second.tiltDegrees, closeTo(9.1, 0.01));
    });
  });

  group('gyro prediction', () {
    test(
      'extrapolates the measurement forward over the prediction horizon',
      () {
        final model = FoldMotionModel(autoRecenter: false)
          ..update(sampleAt(0, t: 0));

        // 1 rad/s for 40 ms is 0.04 rad, about 2.29 degrees ahead of the pose.
        final state = model.update(
          sampleAt(0, omegaScreenY: 1, omegaMagnitude: 1, t: 0.02),
        );
        expect(state.tiltDegrees, closeTo(0.7 * 0.04 * 180 / math.pi, 0.01));
      },
    );

    test('ignores the horizon when the sample carries no gyro reading', () {
      final model = FoldMotionModel(autoRecenter: false)
        ..update(sampleAt(0, t: 0));

      final state = model.update(
        sampleAt(0, omegaScreenY: 1, hasGyro: false, t: 0.02),
      );
      expect(state.tiltDegrees, 0);
    });

    test('omegaScreenX moves the second axis by the same amount', () {
      final model = FoldMotionModel(autoRecenter: false)
        ..update(sampleAtXY(0, 0, t: 0));

      final state = model.update(
        sampleAtXY(0, 0, omegaScreenX: 1, omegaMagnitude: 1, t: 0.02),
      );
      expect(state.tiltDegrees, closeTo(0.7 * 0.04 * 180 / math.pi, 0.01));
      expect(state.liftDirX, closeTo(0, 0.01));
      // A positive rate about screen-right swings the normal toward
      // screen-down, so it is the top edge that comes toward the viewer, and
      // the lift direction is negative in fragment coordinates.
      expect(state.liftDirY, closeTo(-1, 0.01));
    });

    // The tests above feed a pose built by hand and a rate chosen to match it,
    // so they pin the size of the prediction but not its direction: flip the
    // sign of the gyro term and they all still pass. These two turn the device
    // for real and check the only thing that actually matters, which is whether
    // the prediction lands nearer the pose one horizon ahead than doing nothing
    // would have.
    const rate = 1.0;
    const seconds = 0.6;
    final aheadDegrees =
        rate * (seconds + FoldMotionModel.predictionInterval) * 180 / math.pi;

    test('leads the pose on the vertical axis rather than trailing it', () {
      final withGyro = sweep(rate: rate, seconds: seconds, about: 'x');
      final withoutGyro = sweep(
        rate: rate,
        seconds: seconds,
        about: 'x',
        hasGyro: false,
      );

      expect(
        (withGyro - aheadDegrees).abs(),
        lessThan((withoutGyro - aheadDegrees).abs()),
        reason:
            'predicting with the wrong sign puts the output further from the '
            'pose than not predicting at all',
      );
      expect(withGyro, closeTo(aheadDegrees, 0.6));
    });

    test('leads the pose on the horizontal axis too', () {
      final withGyro = sweep(rate: rate, seconds: seconds, about: 'y');
      final withoutGyro = sweep(
        rate: rate,
        seconds: seconds,
        about: 'y',
        hasGyro: false,
      );

      expect(
        (withGyro - aheadDegrees).abs(),
        lessThan((withoutGyro - aheadDegrees).abs()),
      );
      expect(withGyro, closeTo(aheadDegrees, 0.6));
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

    test('a gyro-less device keeps a held tilt instead of washing it out', () {
      // A frame with no gyro behind it carries a zero rate, which reads as
      // perfectly still on the face of it. Trusting that hands the washout a
      // tilt the user is holding on purpose, and 30 seconds later there is
      // almost nothing left of it.
      final model = FoldMotionModel()
        ..update(sampleAt(0, hasGyro: false, t: 0));

      var state = FoldState.zero;
      for (var i = 1; i <= 1500; i++) {
        state = model.update(sampleAt(20, hasGyro: false, t: 0.02 * i));
      }
      expect(state.tiltDegrees, closeTo(20, 0.01));
    });

    test('disabling the washout stops it entirely', () {
      final model = FoldMotionModel(autoRecenter: false)
        ..update(sampleAt(0, t: 0));

      var state = FoldState.zero;
      for (var i = 0; i < 1500; i++) {
        state = model.update(sampleAt(8, t: 0.02 * (i + 1)));
      }
      expect(state.tiltDegrees, closeTo(8, 0.01));
    });

    test('re-enabling snaps the baseline so the output does not jump', () {
      final model = FoldMotionModel(autoRecenter: false)
        ..update(sampleAt(0, t: 0));
      final before = settle(model, 8).tiltDegrees;

      model.autoRecenter = true;
      final after = model.update(sampleAt(8, t: 99)).tiltDegrees;

      expect((after - before).abs(), lessThan(0.5));
    });
  });

  group('clamping', () {
    test('never reports a magnitude beyond the stable range', () {
      final model = FoldMotionModel(autoRecenter: false)
        ..update(sampleAt(0, t: 0));
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
