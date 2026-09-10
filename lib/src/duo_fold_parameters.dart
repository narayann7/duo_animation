import 'dart:math' as math;
import 'dart:ui' as ui;

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
    this.darkening = 0.0084,
    this.surroundColor = const ui.Color(0xFF000000),
    this.hazeColor = const ui.Color(0xFF000000),
    this.baseBlurMillimeters = 0.10,
    this.stretchEdges = true,
    this.tiltResponse = 1,
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

  /// Blur carried everywhere the moment the fold leaves rest, in millimetres of
  /// physical screen.
  ///
  /// [blurSpread] alone gives a gradient that reaches zero on the hinge line,
  /// which leaves the hinge side of the screen perfectly sharp. That is what
  /// the optics say happens, since the glass touches the content there, but a
  /// pane of frosted glass is frosted across its whole face. This adds that
  /// even frost. Zero leaves the pure model alone. It is specified in
  /// millimetres so it holds its size across displays.
  final double baseBlurMillimeters;

  /// Fraction of light lost per pixel of blur radius. Frostier glass reads
  /// further from the content and closer to [hazeColor].
  ///
  /// Authored against [referencePixelsPerMillimeter]; [packUniforms] rescales it
  /// for the real display so the look holds on any screen.
  final double darkening;

  /// How tilt maps onto the fold, as an exponent.
  ///
  /// One, the default, is linear: half the tilt gives half the fold. Higher
  /// values hold the small tilts back while leaving the widest tilt exactly
  /// where it was, so the effect starts gently and arrives late instead of
  /// spending itself in the first few degrees. Two is a good starting point.
  ///
  /// This matters most on a large display. The fold's reach is set by the pixel
  /// distance from the hinge to the far edge, so the same few degrees open a
  /// much wider gap on a tablet than on a phone, and a linear response there
  /// covers the screen almost at once.
  ///
  /// Values below one do the opposite, front-loading the response. Anything at
  /// or below zero is ignored and treated as linear.
  final double tiltResponse;

  /// Whether content is sampled clamped to its own edge.
  ///
  /// A tilt swings part of the glass past the edge of the content, and the two
  /// honest answers differ. Clamped, the default, the edge row and column smear
  /// outward to fill that space and carry the same frost as everything else, so
  /// the effect covers the whole screen with no boundary in it. Unclamped, that
  /// region shows [surroundColor], which is the plainer reading of the optics:
  /// there is nothing out there to see. [surroundColor] still applies to the
  /// degenerate case where the glass reaches the eye.
  final bool stretchEdges;

  /// What lies beyond the edge of the content plane.
  ///
  /// Tilting swings part of the glass past the edge of the content, and there
  /// is nothing there to sample. The shader writes an opaque colour, and the
  /// filter input is the folded subtree alone, so nothing a host paints behind
  /// the widget can show through those pixels: the colour has to be supplied
  /// here. Black reads as a void, which is right for content floating in the
  /// dark. Passing the host's own background colour instead makes the fold look
  /// like it is happening on the surface it is drawn on, which is usually what
  /// an app wants. Alpha is ignored.
  final ui.Color surroundColor;

  /// What the scattered light fades toward, at a rate set by [darkening].
  ///
  /// Glass that only absorbed would fade to black, and black here gives exactly
  /// that. Real frosted glass scatters some light back out and veils toward
  /// white, and any colour between the two tints the frost without changing how
  /// fast it takes hold. At zero [darkening] this has no effect at all. Alpha is
  /// ignored: the strength of the veil lives in [darkening].
  final ui.Color hazeColor;

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
  /// 0 (the filter input itself), so these fourteen land at indices 2 through
  /// 15.
  /// The last six are the surround and haze colours, three components each. The
  /// shader declares all six as separate scalars rather than two `vec3`s: a
  /// vector uniform is padded and aligned by the backend, and these are
  /// addressed by float index, so a padded vector silently shifts every uniform
  /// after it. `uLiftDirX` and `uLiftDirY` are split for the same reason.
  ///
  /// [tiltDegrees] is clamped to plus or minus [maxTiltDegrees] and then
  /// reported to the shader as a magnitude: direction lives in [liftDirX] and
  /// [liftDirY] instead of in the sign, so a negative [tiltDegrees] and a
  /// positive one of the same size pack identically unless the lift direction
  /// also differs.
  ///
  /// [pixelsPerMillimeter] must already be a resolved, finite, positive value:
  /// this method clamps it away from zero but does not guard against NaN,
  /// since `math.max` propagates NaN rather than rejecting it. Callers must
  /// route the raw density through [resolvePixelsPerMillimeter] first; do not
  /// pass a platform-reported or user-supplied value straight through.
  List<double> packUniforms({
    required double tiltDegrees,
    required double liftDirX,
    required double liftDirY,
    required double pixelsPerMillimeter,
  }) {
    final clampedTilt = tiltDegrees
        .clamp(-maxTiltDegrees, maxTiltDegrees)
        .toDouble();
    final shapedTilt = _shape(clampedTilt.abs());
    final density = math.max(pixelsPerMillimeter, 1e-6);
    return <double>[
      shapedTilt,
      liftDirX,
      liftDirY,
      eyeDistanceMillimeters * density,
      blurSpread,
      darkening * referencePixelsPerMillimeter / density,
      surroundColor.r,
      surroundColor.g,
      surroundColor.b,
      hazeColor.r,
      hazeColor.g,
      hazeColor.b,
      baseBlurMillimeters * density,
      stretchEdges ? 1.0 : 0.0,
    ];
  }

  /// Applies [tiltResponse] to a tilt magnitude, holding the endpoints fixed:
  /// rest stays rest and [maxTiltDegrees] stays [maxTiltDegrees], with only the
  /// path between them curved.
  double _shape(double magnitude) {
    if (tiltResponse == 1 || tiltResponse <= 0 || !tiltResponse.isFinite) {
      return magnitude;
    }
    final fraction = magnitude / maxTiltDegrees;
    return math.pow(fraction, tiltResponse).toDouble() * maxTiltDegrees;
  }

  /// Returns a copy with the given fields replaced.
  DuoFoldParameters copyWith({
    double? eyeDistanceMillimeters,
    double? pixelsPerMillimeter,
    double? blurSpread,
    double? darkening,
    ui.Color? surroundColor,
    ui.Color? hazeColor,
    double? baseBlurMillimeters,
    bool? stretchEdges,
    double? tiltResponse,
  }) {
    return DuoFoldParameters(
      eyeDistanceMillimeters:
          eyeDistanceMillimeters ?? this.eyeDistanceMillimeters,
      pixelsPerMillimeter: pixelsPerMillimeter ?? this.pixelsPerMillimeter,
      blurSpread: blurSpread ?? this.blurSpread,
      darkening: darkening ?? this.darkening,
      surroundColor: surroundColor ?? this.surroundColor,
      hazeColor: hazeColor ?? this.hazeColor,
      baseBlurMillimeters: baseBlurMillimeters ?? this.baseBlurMillimeters,
      stretchEdges: stretchEdges ?? this.stretchEdges,
      tiltResponse: tiltResponse ?? this.tiltResponse,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DuoFoldParameters &&
        other.eyeDistanceMillimeters == eyeDistanceMillimeters &&
        other.pixelsPerMillimeter == pixelsPerMillimeter &&
        other.blurSpread == blurSpread &&
        other.darkening == darkening &&
        other.surroundColor == surroundColor &&
        other.hazeColor == hazeColor &&
        other.baseBlurMillimeters == baseBlurMillimeters &&
        other.stretchEdges == stretchEdges &&
        other.tiltResponse == tiltResponse;
  }

  @override
  int get hashCode => Object.hash(
    eyeDistanceMillimeters,
    pixelsPerMillimeter,
    blurSpread,
    darkening,
    surroundColor,
    hazeColor,
    baseBlurMillimeters,
    stretchEdges,
    tiltResponse,
  );

  @override
  String toString() =>
      'DuoFoldParameters(eye: ${eyeDistanceMillimeters}mm, '
      'pxPerMm: $pixelsPerMillimeter, blur: $blurSpread, darken: $darkening, '
      'surround: $surroundColor, haze: $hazeColor, '
      'baseBlur: ${baseBlurMillimeters}mm, stretchEdges: $stretchEdges)';
}
