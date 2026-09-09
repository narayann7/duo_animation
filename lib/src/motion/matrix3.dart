import 'dart:math' as math;

/// Minimal row-major 3x3 helpers for the orientation filter.
///
/// Matrices are plain `List<double>` of length 9, laid out row-major:
/// `[m00, m01, m02, m10, m11, m12, m20, m21, m22]`. Columns are the screen
/// axes: column 0 is screen-right, column 1 screen-up, column 2 the screen
/// normal.
abstract final class Matrix3 {
  /// The identity pose.
  static const List<double> identity = <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];

  /// Returns the transpose of [m], which for a rotation is also its inverse.
  static List<double> transpose(List<double> m) {
    assert(m.length == 9, 'expected a 3x3 matrix, got ${m.length} values');
    return <double>[m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]];
  }

  /// Returns the matrix product `a * b`.
  static List<double> multiply(List<double> a, List<double> b) {
    assert(a.length == 9 && b.length == 9, 'both operands must be 3x3');
    final out = List<double>.filled(9, 0);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        out[row * 3 + col] =
            a[row * 3] * b[col] +
            a[row * 3 + 1] * b[3 + col] +
            a[row * 3 + 2] * b[6 + col];
      }
    }
    return out;
  }

  /// Rotation of [radians] about the screen-space Y axis.
  ///
  /// Positive angles swing the screen normal toward screen-right, which is the
  /// sign convention the whole package uses: positive tilt means the right edge
  /// moves away from the viewer.
  static List<double> rotationAboutY(double radians) {
    final c = math.cos(radians);
    final s = math.sin(radians);
    return <double>[c, 0, s, 0, 1, 0, -s, 0, c];
  }

  /// The screen normal's excursion toward screen-right, in radians.
  ///
  /// [relative] is the current pose expressed in the calibrated frame, that is
  /// `transpose(reference) * current`. Reading the normal column (index 2 and 8)
  /// gives the tilt directly.
  static double screenNormalTilt(List<double> relative) {
    assert(relative.length == 9, 'expected a 3x3 matrix');
    return math.atan2(relative[2], relative[8]);
  }

  /// Folds [radians] into the principal range, minus pi to pi.
  ///
  /// Dart's `%` on doubles always returns a non-negative remainder for a
  /// positive divisor, so a single correction above pi is enough; the result
  /// can never land below minus pi.
  static double wrapAngle(double radians) {
    var x = radians % (2 * math.pi);
    if (x > math.pi) {
      x -= 2 * math.pi;
    }
    return x;
  }
}
