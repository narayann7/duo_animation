import 'dart:ui';

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
    test('emits the fourteen floats in shader declaration order', () {
      const params = DuoFoldParameters(
        eyeDistanceMillimeters: 450,
        blurSpread: 0.12,
        darkening: 0.015,
      );

      final uniforms = params.packUniforms(
        tiltDegrees: 12.5,
        liftDirX: -1,
        liftDirY: 0,
        pixelsPerMillimeter: 6,
      );

      expect(uniforms, hasLength(14));
      expect(uniforms[0], 12.5);
      expect(uniforms[1], -1);
      expect(uniforms[2], 0);
      expect(uniforms[3], closeTo(2700, 1e-9)); // 450 mm at 6 px/mm
      expect(uniforms[4], 0.12);
      expect(uniforms[5], closeTo(0.015, 1e-9)); // reference density, unchanged
      expect(uniforms[6], 0); // surround defaults to black
      expect(uniforms[7], 0);
      expect(uniforms[8], 0);
      expect(uniforms[9], 0); // haze defaults to black, a pure absorber
      expect(uniforms[10], 0);
      expect(uniforms[11], 0);
      // Base blur defaults to 0.10 mm, packed in pixels at the density given.
      expect(uniforms[12], closeTo(0.6, 1e-9));
      expect(uniforms[13], 1); // edges stretch by default
    });

    test('a tilt response above one holds the small tilts back', () {
      const linear = DuoFoldParameters();
      const eased = DuoFoldParameters(tiltResponse: 2);

      double packedTilt(DuoFoldParameters params, double tilt) =>
          params.packUniforms(
            tiltDegrees: tilt,
            liftDirX: -1,
            liftDirY: 0,
            pixelsPerMillimeter: 6,
          )[0];

      // Half of the widest tilt spends half the fold when linear, a quarter of
      // it when squared.
      expect(packedTilt(linear, 22.5), closeTo(22.5, 1e-9));
      expect(packedTilt(eased, 22.5), closeTo(11.25, 1e-9));

      // The endpoints do not move, which is what keeps the widest tilt looking
      // the same as it did before the curve was applied.
      expect(packedTilt(eased, 0), 0);
      expect(packedTilt(eased, DuoFoldParameters.maxTiltDegrees),
          closeTo(DuoFoldParameters.maxTiltDegrees, 1e-9));
    });

    test('a nonsensical tilt response falls back to linear', () {
      for (final response in <double>[0, -2, double.nan, double.infinity]) {
        final params = DuoFoldParameters(tiltResponse: response);
        expect(
          params.packUniforms(
            tiltDegrees: 20,
            liftDirX: -1,
            liftDirY: 0,
            pixelsPerMillimeter: 6,
          )[0],
          closeTo(20, 1e-9),
          reason: 'response $response should behave as linear',
        );
      }
    });

    test('sends the edge mode as a flag the shader can branch on', () {
      List<double> pack(bool stretch) =>
          DuoFoldParameters(stretchEdges: stretch).packUniforms(
            tiltDegrees: 10,
            liftDirX: -1,
            liftDirY: 0,
            pixelsPerMillimeter: 6,
          );

      expect(pack(true)[13], 1);
      expect(pack(false)[13], 0);
    });

    test('converts the base blur from millimetres to pixels', () {
      // Specified physically so the even frost holds its size on any display.
      const params = DuoFoldParameters(baseBlurMillimeters: 0.5);

      final coarse = params.packUniforms(
        tiltDegrees: 10,
        liftDirX: -1,
        liftDirY: 0,
        pixelsPerMillimeter: 6,
      );
      final dense = params.packUniforms(
        tiltDegrees: 10,
        liftDirX: -1,
        liftDirY: 0,
        pixelsPerMillimeter: 18,
      );

      expect(coarse[12], closeTo(3, 1e-9));
      expect(dense[12], closeTo(9, 1e-9));
    });

    test('packs the two colours in the order the shader declares them', () {
      // Surround comes first, haze second. Swap them and a white haze silently
      // turns into a white void around the content instead.
      const params = DuoFoldParameters(
        surroundColor: Color.from(alpha: 1, red: 1, green: 0, blue: 0),
        hazeColor: Color.from(alpha: 1, red: 0, green: 0, blue: 1),
      );

      final uniforms = params.packUniforms(
        tiltDegrees: 10,
        liftDirX: -1,
        liftDirY: 0,
        pixelsPerMillimeter: 6,
      );

      expect(uniforms.sublist(6, 9), [1, 0, 0]);
      expect(uniforms.sublist(9, 12), [0, 0, 1]);
    });

    test('unpacks the surround colour into three components', () {
      // The shader reads these as three consecutive scalars, so the order is
      // load-bearing in a way no compiler checks: a swapped pair shows up only
      // as a wrong colour on a tilted device.
      const params = DuoFoldParameters(
        surroundColor: Color.from(alpha: 1, red: 0.25, green: 0.5, blue: 0.75),
      );

      final uniforms = params.packUniforms(
        tiltDegrees: 10,
        liftDirX: -1,
        liftDirY: 0,
        pixelsPerMillimeter: 6,
      );

      expect(uniforms[6], closeTo(0.25, 1e-6));
      expect(uniforms[7], closeTo(0.5, 1e-6));
      expect(uniforms[8], closeTo(0.75, 1e-6));
    });

    test('the surround alpha never reaches the shader', () {
      // The shader writes an opaque colour either way, so a translucent
      // surround would be a promise the optical model cannot keep.
      const opaque = DuoFoldParameters(surroundColor: Color(0xFF204080));
      const translucent = DuoFoldParameters(surroundColor: Color(0x33204080));

      List<double> pack(DuoFoldParameters params) => params.packUniforms(
            tiltDegrees: 10,
            liftDirX: -1,
            liftDirY: 0,
            pixelsPerMillimeter: 6,
          );

      expect(pack(translucent).sublist(6), pack(opaque).sublist(6));
    });

    test('the haze alpha never reaches the shader', () {
      // How strongly the haze takes hold is uDarkening's job, not an alpha's.
      const opaque = DuoFoldParameters(hazeColor: Color(0xFFEFEAFF));
      const translucent = DuoFoldParameters(hazeColor: Color(0x40EFEAFF));

      List<double> pack(DuoFoldParameters params) => params.packUniforms(
            tiltDegrees: 10,
            liftDirX: -1,
            liftDirY: 0,
            pixelsPerMillimeter: 6,
          );

      expect(pack(translucent).sublist(9), pack(opaque).sublist(9));
    });

    test('reports the tilt to the shader as a magnitude, never negative', () {
      const params = DuoFoldParameters();

      final uniforms = params.packUniforms(
        tiltDegrees: -12.5,
        liftDirX: 1,
        liftDirY: 0,
        pixelsPerMillimeter: 6,
      );

      expect(uniforms[0], 12.5);
    });

    test('normalizes darkening by density so dense screens do not crush to black', () {
      const params = DuoFoldParameters(darkening: 0.015);

      final dense = params.packUniforms(
        tiltDegrees: 10,
        liftDirX: -1,
        liftDirY: 0,
        pixelsPerMillimeter: 18, // three times the 6 px/mm reference
      );

      // Radius is measured in physical px, so loss per px must shrink threefold.
      expect(dense[5], closeTo(0.005, 1e-9));
    });

    test('clamps tilt magnitude to the range the shader is stable over', () {
      const params = DuoFoldParameters();

      expect(
        params.packUniforms(
          tiltDegrees: 91,
          liftDirX: -1,
          liftDirY: 0,
          pixelsPerMillimeter: 6,
        )[0],
        45,
      );
      expect(
        params.packUniforms(
          tiltDegrees: -91,
          liftDirX: 1,
          liftDirY: 0,
          pixelsPerMillimeter: 6,
        )[0],
        45,
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
