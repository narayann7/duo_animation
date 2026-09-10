import 'package:duo_animation/duo_animation.dart';
import 'package:duo_animation/src/duo_fold_shader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the asset key carries the package prefix', () {
    // Shaders declared by a package are addressed through packages/<name>/.
    // Dropping the prefix is the classic way this fails only in a consumer app.
    expect(DuoFoldShader.assetKey, 'packages/duo_animation/shaders/duo_animation.frag');
  });

  test('custom floats start after the two the engine owns', () {
    expect(DuoFoldShader.firstCustomFloatIndex, 2);
  });

  test('the uniform pack length matches what the shader declares', () {
    const params = DuoFoldParameters();
    final uniforms = params.packUniforms(
      tiltDegrees: 10,
      hingeSide: 1,
      pixelsPerMillimeter: 6,
    );

    // uTiltDegrees, uEyeDistancePx, uHingeSide, uBlurSpread, uDarkening.
    expect(uniforms.length, DuoFoldShader.customFloatCount);
  });
}
