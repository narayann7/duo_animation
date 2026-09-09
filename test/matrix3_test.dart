import 'dart:math' as math;

import 'package:duo_animation/src/motion/matrix3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('transpose', () {
    test('swaps rows and columns', () {
      final m = <double>[1, 2, 3, 4, 5, 6, 7, 8, 9];
      expect(Matrix3.transpose(m), <double>[1, 4, 7, 2, 5, 8, 3, 6, 9]);
    });

    test('is its own inverse', () {
      final m = Matrix3.rotationAboutY(0.7);
      final round = Matrix3.transpose(Matrix3.transpose(m));
      for (var i = 0; i < 9; i++) {
        expect(round[i], closeTo(m[i], 1e-12));
      }
    });
  });

  group('multiply', () {
    test('identity is neutral on both sides', () {
      final m = Matrix3.rotationAboutY(0.3);
      final left = Matrix3.multiply(Matrix3.identity, m);
      final right = Matrix3.multiply(m, Matrix3.identity);
      for (var i = 0; i < 9; i++) {
        expect(left[i], closeTo(m[i], 1e-12));
        expect(right[i], closeTo(m[i], 1e-12));
      }
    });

    test('a rotation times its transpose is the identity', () {
      final m = Matrix3.rotationAboutY(1.1);
      final product = Matrix3.multiply(Matrix3.transpose(m), m);
      for (var i = 0; i < 9; i++) {
        expect(product[i], closeTo(Matrix3.identity[i], 1e-12));
      }
    });

    test('composes rotations additively about the same axis', () {
      final composed =
          Matrix3.multiply(Matrix3.rotationAboutY(0.2), Matrix3.rotationAboutY(0.3));
      final direct = Matrix3.rotationAboutY(0.5);
      for (var i = 0; i < 9; i++) {
        expect(composed[i], closeTo(direct[i], 1e-12));
      }
    });
  });

  group('screenNormalTilt', () {
    test('recovers the rotation angle about the screen Y axis', () {
      for (final angle in <double>[-1.0, -0.25, 0, 0.25, 1.0]) {
        expect(
          Matrix3.screenNormalTilt(Matrix3.rotationAboutY(angle)),
          closeTo(angle, 1e-12),
        );
      }
    });

    test('is zero for the identity pose', () {
      expect(Matrix3.screenNormalTilt(Matrix3.identity), 0);
    });
  });

  group('wrapAngle', () {
    test('leaves angles already inside the principal range alone', () {
      expect(Matrix3.wrapAngle(0), 0);
      expect(Matrix3.wrapAngle(1.0), closeTo(1.0, 1e-12));
      expect(Matrix3.wrapAngle(-1.0), closeTo(-1.0, 1e-12));
    });

    test('folds angles past pi back into the principal range', () {
      expect(Matrix3.wrapAngle(3 * math.pi / 2), closeTo(-math.pi / 2, 1e-12));
      expect(Matrix3.wrapAngle(-3 * math.pi / 2), closeTo(math.pi / 2, 1e-12));
      expect(Matrix3.wrapAngle(2 * math.pi + 0.4), closeTo(0.4, 1e-12));
    });
  });
}
