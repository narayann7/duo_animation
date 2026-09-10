import 'dart:math' as math;

import 'package:duo_animation/duo_animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A pose with two equal tilt axes, as FoldMotionModel would report for a
  // 20-degree lean on each of screen right and screen up: magnitude is the
  // hypotenuse, direction sits at 45 degrees between hinge-right and
  // hinge-top.
  const diagonalMagnitude = 28.284271247461902; // sqrt(20^2 + 20^2)
  final diagonalDirX = -math.sqrt1_2;
  final diagonalDirY = math.sqrt1_2;

  group('horizontal', () {
    test('a diagonal pose folds purely left or right, at the on-axis component',
        () {
      const constraints = DuoFoldConstraints.horizontal();

      final resolved = constraints.resolve(
        tiltDegrees: diagonalMagnitude,
        liftDirX: diagonalDirX,
        liftDirY: diagonalDirY,
      );

      // Not the full 28.28-degree hypotenuse: just the 20-degree component
      // along the horizontal axis.
      expect(resolved.tiltDegrees, closeTo(20, 0.01));
      expect(resolved.liftDirX, -1);
      expect(resolved.liftDirY, 0);
    });

    test('a leftward-leaning pose resolves to the left hinge', () {
      const constraints = DuoFoldConstraints.horizontal();

      final resolved = constraints.resolve(
        tiltDegrees: diagonalMagnitude,
        liftDirX: -diagonalDirX,
        liftDirY: diagonalDirY,
      );

      expect(resolved.tiltDegrees, closeTo(20, 0.01));
      expect(resolved.liftDirX, 1);
      expect(resolved.liftDirY, 0);
    });
  });

  group('vertical', () {
    test('a diagonal pose folds purely top or bottom, at the on-axis component',
        () {
      const constraints = DuoFoldConstraints.vertical();

      final resolved = constraints.resolve(
        tiltDegrees: diagonalMagnitude,
        liftDirX: diagonalDirX,
        liftDirY: diagonalDirY,
      );

      expect(resolved.tiltDegrees, closeTo(20, 0.01));
      expect(resolved.liftDirX, 0);
      expect(resolved.liftDirY, 1);
    });

    test('a downward-leaning pose resolves to the bottom hinge', () {
      const constraints = DuoFoldConstraints.vertical();

      final resolved = constraints.resolve(
        tiltDegrees: diagonalMagnitude,
        liftDirX: diagonalDirX,
        liftDirY: -diagonalDirY,
      );

      expect(resolved.tiltDegrees, closeTo(20, 0.01));
      expect(resolved.liftDirX, 0);
      expect(resolved.liftDirY, -1);
    });
  });

  group('only', () {
    test('responds to a lean toward the allowed hinge', () {
      final constraints = DuoFoldConstraints.only(DuoFoldHinge.right);

      final resolved = constraints.resolve(
        tiltDegrees: diagonalMagnitude,
        liftDirX: diagonalDirX, // leans toward right + top
        liftDirY: diagonalDirY,
      );

      expect(resolved.tiltDegrees, closeTo(20, 0.01));
      expect(resolved.liftDirX, -1);
      expect(resolved.liftDirY, 0);
    });

    test('reports exactly flat for the opposite lean', () {
      final constraints = DuoFoldConstraints.only(DuoFoldHinge.right);

      final resolved = constraints.resolve(
        tiltDegrees: diagonalMagnitude,
        liftDirX: -diagonalDirX, // leans toward left + bottom
        liftDirY: -diagonalDirY,
      );

      expect(resolved.tiltDegrees, 0);
    });

    test('reports flat for a lean exactly perpendicular to the hinge axis', () {
      final constraints = DuoFoldConstraints.only(DuoFoldHinge.right);

      final resolved = constraints.resolve(
        tiltDegrees: 20,
        liftDirX: 0,
        liftDirY: 1,
      );

      expect(resolved.tiltDegrees, 0);
    });

    test('is usable as a const value, e.g. a default parameter', () {
      // This would fail to compile, not just fail at runtime, if
      // DuoFoldConstraints.only ever stopped being a const constructor.
      const constraints = DuoFoldConstraints.only(DuoFoldHinge.right);

      final resolved = constraints.resolve(
        tiltDegrees: diagonalMagnitude,
        liftDirX: diagonalDirX, // leans toward right + top
        liftDirY: diagonalDirY,
      );

      expect(resolved.tiltDegrees, closeTo(20, 0.01));
      expect(resolved.liftDirX, -1);
      expect(resolved.liftDirY, 0);
    });
  });

  group('free', () {
    test('passes a diagonal pose through unchanged', () {
      const constraints = DuoFoldConstraints.free();

      final resolved = constraints.resolve(
        tiltDegrees: diagonalMagnitude,
        liftDirX: diagonalDirX,
        liftDirY: diagonalDirY,
      );

      expect(resolved.tiltDegrees, closeTo(diagonalMagnitude, 1e-9));
      expect(resolved.liftDirX, diagonalDirX);
      expect(resolved.liftDirY, diagonalDirY);
    });

    test('still clamps to maxTiltDegrees', () {
      const constraints = DuoFoldConstraints.free();

      final resolved = constraints.resolve(
        tiltDegrees: 90,
        liftDirX: -1,
        liftDirY: 0,
      );

      expect(resolved.tiltDegrees, 45);
    });
  });

  group('resting pose', () {
    // A resting pose is the exact case that blanks a screen in production if
    // a zero vector ever gets normalized. Every constraint mode must survive
    // it with a finite direction.
    const restingDirX = -1.0;
    const restingDirY = 0.0;

    for (final constraints in <String, DuoFoldConstraints>{
      'free': const DuoFoldConstraints.free(),
      'horizontal': const DuoFoldConstraints.horizontal(),
      'vertical': const DuoFoldConstraints.vertical(),
      'only(right)': DuoFoldConstraints.only(DuoFoldHinge.right),
      'allow(all)': DuoFoldConstraints.allow(DuoFoldHinge.values.toSet()),
    }.entries) {
      test('${constraints.key} yields a finite direction at rest', () {
        final resolved = constraints.value.resolve(
          tiltDegrees: 0,
          liftDirX: restingDirX,
          liftDirY: restingDirY,
        );

        expect(resolved.tiltDegrees, 0);
        expect(resolved.liftDirX.isFinite, isTrue);
        expect(resolved.liftDirY.isFinite, isTrue);
      });
    }

    test('an empty allow-set always reads as flat, with a finite direction',
        () {
      final constraints = DuoFoldConstraints.allow(const <DuoFoldHinge>{});

      final resolved = constraints.resolve(
        tiltDegrees: 20,
        liftDirX: -1,
        liftDirY: 0,
      );

      expect(resolved.tiltDegrees, 0);
      expect(resolved.liftDirX.isFinite, isTrue);
      expect(resolved.liftDirY.isFinite, isTrue);
    });
  });
}
