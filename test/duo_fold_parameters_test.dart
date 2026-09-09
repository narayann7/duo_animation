import 'package:duo_animation/duo_animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolvePixelsPerMillimeter', () {
    test('prefers an explicit non-zero value over the display metric', () {
      const params = DuoFoldParameters(pixelsPerMillimeter: 9.5);
      expect(params.resolvePixelsPerMillimeter(6.4), 9.5);
    });

    test('uses the display metric when the parameter is the auto sentinel', () {
      const params = DuoFoldParameters();
      expect(params.resolvePixelsPerMillimeter(6.4), 6.4);
    });

    test('falls back when the display metric is missing or nonsensical', () {
      const params = DuoFoldParameters();
      expect(params.resolvePixelsPerMillimeter(null),
          DuoFoldParameters.fallbackPixelsPerMillimeter);
      expect(params.resolvePixelsPerMillimeter(0),
          DuoFoldParameters.fallbackPixelsPerMillimeter);
      expect(params.resolvePixelsPerMillimeter(double.nan),
          DuoFoldParameters.fallbackPixelsPerMillimeter);
      expect(params.resolvePixelsPerMillimeter(double.infinity),
          DuoFoldParameters.fallbackPixelsPerMillimeter);
    });
  });

  group('packUniforms', () {
    test('emits the five floats in shader declaration order', () {
      const params = DuoFoldParameters(
        eyeDistanceMillimeters: 450,
        blurSpread: 0.12,
        darkening: 0.015,
      );

      final uniforms = params.packUniforms(
        tiltDegrees: 12.5,
        hingeSide: 1,
        pixelsPerMillimeter: 6,
      );

      expect(uniforms, hasLength(5));
      expect(uniforms[0], 12.5);
      expect(uniforms[1], closeTo(2700, 1e-9)); // 450 mm at 6 px/mm
      expect(uniforms[2], 1);
      expect(uniforms[3], 0.12);
      expect(uniforms[4], closeTo(0.015, 1e-9)); // reference density, unchanged
    });

    test('normalizes darkening by density so dense screens do not crush to black', () {
      const params = DuoFoldParameters(darkening: 0.015);

      final dense = params.packUniforms(
        tiltDegrees: 10,
        hingeSide: 1,
        pixelsPerMillimeter: 18, // three times the 6 px/mm reference
      );

      // Radius is measured in physical px, so loss per px must shrink threefold.
      expect(dense[4], closeTo(0.005, 1e-9));
    });

    test('clamps tilt to the range the shader is stable over', () {
      const params = DuoFoldParameters();

      expect(
        params.packUniforms(tiltDegrees: 91, hingeSide: 1, pixelsPerMillimeter: 6)[0],
        45,
      );
      expect(
        params.packUniforms(tiltDegrees: -91, hingeSide: -1, pixelsPerMillimeter: 6)[0],
        -45,
      );
    });
  });

  group('value semantics', () {
    test('copyWith replaces only the named field', () {
      const params = DuoFoldParameters();
      final tuned = params.copyWith(blurSpread: 0.2);

      expect(tuned.blurSpread, 0.2);
      expect(tuned.eyeDistanceMillimeters, params.eyeDistanceMillimeters);
      expect(tuned, isNot(params));
      expect(params.copyWith(), params);
      expect(params.copyWith().hashCode, params.hashCode);
    });
  });
}
