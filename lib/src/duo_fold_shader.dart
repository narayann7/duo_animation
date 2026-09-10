import 'dart:ui' as ui;

import 'duo_fold_errors.dart';

/// Loads and feeds the fold fragment program.
///
/// The program is compiled once per process and cached. A `FragmentShader` is
/// cheap to mutate but not free to create, so callers hold one and re-upload
/// uniforms each frame rather than building a new one.
abstract final class DuoFoldShader {
  /// Runtime asset key. Shaders declared by a package live under `packages/`.
  static const String assetKey =
      'packages/duo_animation/shaders/duo_animation.frag';

  /// The engine owns float uniforms 0 and 1, the filter input size.
  static const int firstCustomFloatIndex = 2;

  /// Number of floats `DuoFoldParameters.packUniforms` produces. The surround
  /// and haze colours are three scalar uniforms each, never a `vec3`: see
  /// `DuoFoldParameters.packUniforms` for why that matters.
  static const int customFloatCount = 14;

  static Future<ui.FragmentProgram>? _program;

  /// Returns the compiled program, loading it on first call.
  static Future<ui.FragmentProgram> program() {
    return _program ??= _load();
  }

  static Future<ui.FragmentProgram> _load() async {
    try {
      return await ui.FragmentProgram.fromAsset(assetKey);
    } on Object catch (error) {
      _program = null;
      throw DuoFoldShaderError(
        'could not load $assetKey. Check that the package pubspec declares it '
        'under flutter.shaders and that the app has been rebuilt, not hot '
        'reloaded, since it was added.',
        error,
      );
    }
  }

  /// Uploads [uniforms] into [shader] at the indices the shader declares.
  static void applyUniforms(ui.FragmentShader shader, List<double> uniforms) {
    assert(
      uniforms.length == customFloatCount,
      'expected $customFloatCount uniforms, got ${uniforms.length}',
    );
    for (var i = 0; i < uniforms.length; i++) {
      shader.setFloat(firstCustomFloatIndex + i, uniforms[i]);
    }
  }

  /// Drops the cached program. Tests only.
  static void resetForTesting() {
    _program = null;
  }
}
