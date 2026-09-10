import 'package:duo_animation/duo_animation.dart';
import 'package:duo_animation/src/motion/matrix3.dart';
import 'package:flutter_test/flutter_test.dart';

MotionSample poseAt(double degrees, {required double t}) {
  return MotionSample(
    screenMatrix: Matrix3.rotationAboutY(degrees * 3.141592653589793 / 180),
    omegaScreenY: 0,
    omegaScreenX: 0,
    omegaMagnitude: 1, // above the still threshold, so washout stays out of it
    hasGyro: true,
    timestampSeconds: t,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start reads metrics and reports sensor availability', () async {
    final source = FakeMotionSource(
      metrics: const DuoFoldDisplayMetrics(
        pixelsPerMillimeter: 6.4,
        hasRotationSensor: true,
      ),
    );
    final controller = DuoFoldController(source: source);

    await controller.start();

    expect(controller.hasSensor, isTrue);
    expect(controller.pixelsPerMillimeter, closeTo(6.4, 1e-9));
    expect(controller.useSensor, isTrue);

    controller.dispose();
    await source.dispose();
  });

  test('defaults to manual mode when the platform reports no sensor', () async {
    final source = FakeMotionSource();
    final controller = DuoFoldController(source: source);

    await controller.start();

    expect(controller.hasSensor, isFalse);
    expect(controller.useSensor, isFalse);

    controller.dispose();
    await source.dispose();
  });

  test('samples drive the tilt and notify listeners', () async {
    final source = FakeMotionSource(
      metrics: const DuoFoldDisplayMetrics(
        pixelsPerMillimeter: 6,
        hasRotationSensor: true,
      ),
    );
    final controller = DuoFoldController(source: source);
    await controller.start();

    var notifications = 0;
    controller.addListener(() => notifications++);

    source.emit(poseAt(0, t: 0));
    await Future<void>.delayed(Duration.zero);
    for (var i = 1; i <= 40; i++) {
      source.emit(poseAt(20, t: 0.02 * i));
    }
    await Future<void>.delayed(Duration.zero);

    expect(controller.tiltDegrees, closeTo(20, 0.05));
    expect(controller.liftDirX, closeTo(-1, 0.01));
    expect(controller.liftDirY, closeTo(0, 0.01));
    expect(notifications, greaterThan(0));

    controller.dispose();
    await source.dispose();
  });

  test('manual tilt wins when the sensor is switched off', () async {
    final source = FakeMotionSource(
      metrics: const DuoFoldDisplayMetrics(
        pixelsPerMillimeter: 6,
        hasRotationSensor: true,
      ),
    );
    final controller = DuoFoldController(source: source);
    await controller.start();

    source.emit(poseAt(0, t: 0));
    for (var i = 1; i <= 40; i++) {
      source.emit(poseAt(20, t: 0.02 * i));
    }
    await Future<void>.delayed(Duration.zero);

    controller.useSensor = false;
    controller.manualTiltDegrees = -12;

    expect(controller.tiltDegrees, 12);
    expect(controller.liftDirX, 1);
    expect(controller.liftDirY, 0);

    controller.dispose();
    await source.dispose();
  });

  test('manual tilt is clamped to the stable range', () async {
    final controller = DuoFoldController(source: FakeMotionSource());
    await controller.start();

    controller.manualTiltDegrees = 200;
    expect(controller.tiltDegrees, 45);
    expect(controller.liftDirX, -1);

    controller.manualTiltDegrees = -200;
    expect(controller.tiltDegrees, 45);
    expect(controller.liftDirX, 1);

    controller.dispose();
  });

  test('recalibrate zeroes both the model and the manual offset', () async {
    final source = FakeMotionSource(
      metrics: const DuoFoldDisplayMetrics(
        pixelsPerMillimeter: 6,
        hasRotationSensor: true,
      ),
    );
    final controller = DuoFoldController(source: source);
    await controller.start();
    controller.manualTiltDegrees = 30;

    controller.recalibrate();

    expect(controller.manualTiltDegrees, 0);
    expect(controller.tiltDegrees, 0);

    controller.dispose();
    await source.dispose();
  });

  test('defaults to horizontal constraints', () async {
    final controller = DuoFoldController(source: FakeMotionSource());
    expect(controller.constraints, const DuoFoldConstraints.horizontal());
    controller.dispose();
  });

  test('constraints are swappable at runtime without recalibration', () async {
    final controller = DuoFoldController(source: FakeMotionSource());
    await controller.start();

    controller.manualTiltDegrees = 20;
    expect(controller.tiltDegrees, 20);
    expect(controller.liftDirX, -1); // horizontal default: hinge right

    controller.constraints = const DuoFoldConstraints.vertical();

    // The same underlying pose is still purely horizontal, so a vertical-only
    // constraint reads it as flat without any new sample or recalibration.
    expect(controller.tiltDegrees, 0);

    controller.dispose();
  });
}
