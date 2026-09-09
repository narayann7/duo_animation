/// Thrown when the effect cannot run on the current platform or renderer.
///
/// The effect is built on `ui.ImageFilter.shader`, which only exists on the
/// Impeller backend. Rather than degrade to an unfiltered child or a silent
/// no-op that reads as "the package is broken", duo_animation fails loudly.
class DuoFoldUnsupportedError implements Exception {
  /// Creates an error explaining why the effect cannot run.
  const DuoFoldUnsupportedError({required this.reason});

  /// Platform-specific detail, for example `'web uses CanvasKit'`.
  final String reason;

  /// Full human-readable explanation, including the renderer requirement.
  String get message =>
      'duo_animation requires the Impeller renderer on Android or iOS: $reason. '
      'ui.ImageFilter.shader is not available on any other backend.';

  @override
  String toString() => 'DuoFoldUnsupportedError: $message';
}

/// Thrown when the fragment program fails to load or compile.
class DuoFoldShaderError implements Exception {
  /// Creates a shader error, optionally wrapping the [cause] that triggered it.
  DuoFoldShaderError(this.message, [this.cause]);

  /// What went wrong.
  final String message;

  /// The original exception, when there was one.
  final Object? cause;

  @override
  String toString() =>
      'DuoFoldShaderError: $message${cause == null ? '' : ' (caused by: $cause)'}';
}
