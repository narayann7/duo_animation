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

  group('liftDirection', () {
    testWidgets('defaults to hinge-right when not supplied', (tester) async {
      const widget = DuoFold(
        tiltDegrees: 30,
        enabled: false,
        child: Text('content', textDirection: TextDirection.ltr),
      );

      expect(widget.liftDirection, const Offset(-1, 0));

      await tester.pumpWidget(const MaterialApp(home: widget));
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('an explicit value overrides the default', (tester) async {
      const widget = DuoFold(
        tiltDegrees: 30,
        liftDirection: Offset(0, 1),
        enabled: false,
        child: Text('content', textDirection: TextDirection.ltr),
      );

      expect(widget.liftDirection, const Offset(0, 1));

      await tester.pumpWidget(const MaterialApp(home: widget));
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('a non-unit liftDirection asserts when tiltDegrees is nonzero',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DuoFold(
            tiltDegrees: 30,
            liftDirection: Offset(2, 0),
            child: SizedBox(),
          ),
        ),
      );

      expect(tester.takeException(), isAssertionError);
    });

    testWidgets(
        'a zero-length liftDirection asserts when tiltDegrees is nonzero',
        (tester) async {
      // Zero length is not the sanctioned way to say "no fold": that is what
      // an at-rest tiltDegrees is for. Paired with a real tilt, it is a
      // caller bug and should fail loudly, the same as any other non-unit
      // vector.
      await tester.pumpWidget(
        const MaterialApp(
          home: DuoFold(
            tiltDegrees: 30,
            liftDirection: Offset.zero,
            child: SizedBox(),
          ),
        ),
      );

      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('a zero-length liftDirection is accepted at rest',
        (tester) async {
      // At rest, liftDirection is never consumed (see the pass-through
      // group), so any value, including a zero vector, is fine there.
      await tester.pumpWidget(
        const MaterialApp(
          home: DuoFold(
            tiltDegrees: 0,
            liftDirection: Offset.zero,
            child: SizedBox(),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
