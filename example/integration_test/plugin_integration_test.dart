// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they exercise
// the widget tree the way a real device would.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:duo_animation/duo_animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('duo_animation errors are exported from the package root', (
    WidgetTester tester,
  ) async {
    const error = DuoFoldUnsupportedError(reason: 'integration test smoke check');

    expect(error, isA<Exception>());
  });
}
