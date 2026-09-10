## 0.1.0

First release.

* `DuoFold` wraps any widget subtree and renders it behind a hinged pane of
  frosted glass. Tilt magnitude and lift direction are passed in, so the effect
  can be driven by anything: a sensor, an animation, a slider. The child is
  rasterized into a layer and run through a fragment shader, which means it has
  to be Flutter-drawn. Platform views and texture widgets do not participate in
  a layer filter. Below `DuoFold.tiltEpsilon` the widget renders the child
  directly and skips the layer and the shader entirely.
* `DuoFoldMotion` is the sensor-driven form: hand it a `DuoFoldController` and
  it rebuilds only the filter wrapper on each sample, so the sensor stream does
  not rebuild the subtree being folded.
* `DuoFoldController` owns the sensor subscription and the tilt filter and
  publishes the result as a `ChangeNotifier`. It runs in one of two modes
  against the same output, either from the sensor or from `manualTiltDegrees` for
  emulators and tuning sessions, and falls back to manual on a device with no
  rotation sensor.
* `DuoFoldParameters` carries the physical tuning: viewing distance and the
  perspective it implies, how fast frost thickens with distance from the hinge,
  how much light the glass loses, and what colour it scatters toward. The base
  frost is specified in millimetres of physical screen, so it holds its size
  across densities.
* `DuoFoldConstraints` limits which hinges the fold may resolve to: `free`,
  `horizontal`, `vertical`, or an explicit set. Constraints apply before the
  tilt is published, so the readout and the effect always agree and swapping
  them at runtime needs no recalibration.
* `FakeMotionSource` feeds the controller scripted samples, so an app's own
  tests can drive the effect without a device.
* Android and iOS, both through Pigeon. Attitude is read in a reference frame
  that excludes the magnetometer, so a passing magnet does not shift the pose
  the effect is measured against. Calibration, latency prediction, smoothing and
  drift washout all live in Dart.
* Requires the Impeller renderer. Any other backend throws
  `DuoFoldUnsupportedError` rather than quietly rendering the child unfiltered.
