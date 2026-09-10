import 'package:duo_animation/duo_animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'DuoFoldUnsupportedError names the reason and the renderer requirement',
    () {
      const error = DuoFoldUnsupportedError(reason: 'web uses CanvasKit');

      expect(error, isA<Exception>());
      expect(error.message, contains('web uses CanvasKit'));
      expect(error.message, contains('Impeller'));
      expect(error.toString(), contains('DuoFoldUnsupportedError'));
    },
  );

  test('DuoFoldShaderError keeps the underlying cause', () {
    final cause = StateError('compile failed');
    final error = DuoFoldShaderError(
      'could not load duo_animation.frag',
      cause,
    );

    expect(error.message, 'could not load duo_animation.frag');
    expect(error.cause, same(cause));
    expect(error.toString(), contains('compile failed'));
  });
}
