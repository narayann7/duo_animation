import 'dart:math' as math;

/// Physical parameters of the frosted-glass fold.
///
/// Every value here is a real-world quantity: the model is an eye at a fixed
/// distance looking at a plane through a tilting pane of glass.
class DuoFoldParameters {
  /// Creates a parameter set.
  const DuoFoldParameters({
    this.eyeDistanceMillimeters = 450,
    this.pixelsPerMillimeter = 0,
    this.blurSpread = 0.12,
    this.darkening = 0.015,
  });

  /// Distance from the viewer's eyes to the untilted screen, looking head-on.
  ///
  /// The eye stays put while the device tilts. Larger values flatten the
  /// perspective magnification, meaning less sideways stretch and less edge
  /// cropping at big tilts, and leave blur and darkening untouched. 320 gives a
  /// more dramatic read; 450 is calmer.
  final double eyeDistanceMillimeters;

  /// Physical pixel density of the filter input. Zero means resolve it from the
  /// platform's display metrics, which is what you almost always want.
  final double pixelsPerMillimeter;

  /// Blur radius gained per pixel of separation between the glass and the UI
  /// plane, the tangent of the scattering half-angle.
  final double blurSpread;

  /// Fraction of light lost per pixel of blur radius. Frostier glass is darker.
  ///
  /// Authored against [referencePixelsPerMillimeter]; [packUniforms] rescales it
  /// for the real display so the look holds on any screen.
  final double darkening;

  /// Used when the platform reports no usable pixel density.
  static const double fallbackPixelsPerMillimeter = 6;

  /// Density [darkening] is authored against, roughly a phone panel.
  static const double referencePixelsPerMillimeter = 6;

  /// Widest tilt the optical model stays stable over, in degrees.
  static const double maxTiltDegrees = 45;

  /// Picks the density to use: explicit value first, then the platform's, then
  /// [fallbackPixelsPerMillimeter].
  double resolvePixelsPerMillimeter(double? fromDisplay) {
    if (pixelsPerMillimeter > 0) {
      return pixelsPerMillimeter;
    }
    if (fromDisplay != null && fromDisplay.isFinite && fromDisplay > 0) {
      return fromDisplay;
    }
    return fallbackPixelsPerMillimeter;
  }

  /// Packs the custom float uniforms in shader declaration order.
  ///
  /// The engine owns float uniforms 0 and 1 (the filter input size) and sampler
  /// 0 (the filter input itself), so these five land at indices 2 through 6.
  ///
  /// [pixelsPerMillimeter] must already be a resolved, finite, positive value:
  /// this method clamps it away from zero but does not guard against NaN,
  /// since `math.max` propagates NaN rather than rejecting it. Callers must
  /// route the raw density through [resolvePixelsPerMillimeter] first; do not
  /// pass a platform-reported or user-supplied value straight through.
  List<double> packUniforms({
    required double tiltDegrees,
    required double hingeSide,
    required double pixelsPerMillimeter,
  }) {
    final clampedTilt =
        tiltDegrees.clamp(-maxTiltDegrees, maxTiltDegrees).toDouble();
    final density = math.max(pixelsPerMillimeter, 1e-6);
    return <double>[
      clampedTilt,
      eyeDistanceMillimeters * density,
      hingeSide,
      blurSpread,
      darkening * referencePixelsPerMillimeter / density,
    ];
  }

  /// Returns a copy with the given fields replaced.
  DuoFoldParameters copyWith({
    double? eyeDistanceMillimeters,
    double? pixelsPerMillimeter,
    double? blurSpread,
    double? darkening,
  }) {
    return DuoFoldParameters(
      eyeDistanceMillimeters:
          eyeDistanceMillimeters ?? this.eyeDistanceMillimeters,
      pixelsPerMillimeter: pixelsPerMillimeter ?? this.pixelsPerMillimeter,
      blurSpread: blurSpread ?? this.blurSpread,
      darkening: darkening ?? this.darkening,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DuoFoldParameters &&
        other.eyeDistanceMillimeters == eyeDistanceMillimeters &&
        other.pixelsPerMillimeter == pixelsPerMillimeter &&
        other.blurSpread == blurSpread &&
        other.darkening == darkening;
  }

  @override
  int get hashCode => Object.hash(
        eyeDistanceMillimeters,
        pixelsPerMillimeter,
        blurSpread,
        darkening,
      );

  @override
  String toString() => 'DuoFoldParameters(eye: ${eyeDistanceMillimeters}mm, '
      'pxPerMm: $pixelsPerMillimeter, blur: $blurSpread, darken: $darkening)';
}
