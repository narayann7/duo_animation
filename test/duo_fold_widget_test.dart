import 'package:duo_animation/duo_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The effect is a no-op below this tilt, so these cases must not build an
  /// ImageFiltered at all. That matters twice over: it keeps a level device off
  /// the shader path entirely, and it is the only part of the widget that is
  /// testable off Impeller, since flutter_test rasterizes with Skia.
  group('pass-through', () {
    testWidgets('renders the child directly when disabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DuoFold(
            tiltDegrees: 30,
            enabled: false,
            child: Text('content', textDirection: TextDirection.ltr),
          ),
        ),
      );

      expect(find.text('content'), findsOneWidget);
      expect(find.byType(ImageFiltered), findsNothing);
    });

    testWidgets('renders the child directly at rest', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DuoFold(
            tiltDegrees: 0,
            child: Text('content', textDirection: TextDirection.ltr),
          ),
        ),
      );

      expect(find.text('content'), findsOneWidget);
      expect(find.byType(ImageFiltered), findsNothing);
    });

    testWidgets('treats sub-epsilon tilt as rest', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DuoFold(
            tiltDegrees: DuoFold.tiltEpsilon / 2,
            child: const Text('content', textDirection: TextDirection.ltr),
          ),
        ),
      );

      expect(find.byType(ImageFiltered), findsNothing);
    });
  });

  group('hingeSideFor', () {
    test('positive and zero tilt hinge right, negative hinges left', () {
      expect(DuoFold.hingeSideFor(0), 1);
      expect(DuoFold.hingeSideFor(12), 1);
      expect(DuoFold.hingeSideFor(-12), -1);
    });
  });
}
