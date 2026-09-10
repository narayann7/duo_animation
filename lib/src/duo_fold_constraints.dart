/// Which edge a pane hinges on.
///
/// The lift direction is the opposite side: a pane hinged on [right] lifts
/// toward the left, and so on.
enum DuoFoldHinge {
  /// Hinge on the left edge. The pane lifts toward the right.
  left,

  /// Hinge on the right edge. The pane lifts toward the left.
  right,

  /// Hinge on the top edge. The pane lifts toward the bottom.
  top,

  /// Hinge on the bottom edge. The pane lifts toward the top.
  bottom,
}

/// The unit lift direction each [DuoFoldHinge] resolves to, in fragment
/// coordinates (y down). Not public API: callers reach these through
/// [DuoFoldConstraints.resolve].
extension on DuoFoldHinge {
  double get _liftDirX {
    switch (this) {
      case DuoFoldHinge.left:
        return 1;
      case DuoFoldHinge.right:
        return -1;
      case DuoFoldHinge.top:
      case DuoFoldHinge.bottom:
        return 0;
    }
  }

  double get _liftDirY {
    switch (this) {
      case DuoFoldHinge.top:
        return 1;
      case DuoFoldHinge.bottom:
        return -1;
      case DuoFoldHinge.left:
      case DuoFoldHinge.right:
        return 0;
    }
  }
}

/// Which fold directions a widget will respond to.
///
/// Free rotation is one option among several, not the only one: a consumer
/// can restrict the effect to a single axis, a single edge, or an arbitrary
/// subset of edges. This is pure logic, with no dependency on `dart:ui`, so it
/// can be shared between [DuoFoldController] and any future engine-specific
/// widget layer.
class DuoFoldConstraints {
  const DuoFoldConstraints._(this._allowedHinges, {this.maxTiltDegrees = 45});

  /// Any direction, continuous. The hinge line follows the device freely.
  const DuoFoldConstraints.free({double maxTiltDegrees = 45})
      : this._(null, maxTiltDegrees: maxTiltDegrees);

  /// Left and right only. The hinge is always a vertical edge.
  const DuoFoldConstraints.horizontal({double maxTiltDegrees = 45})
      : this._(
          const {DuoFoldHinge.left, DuoFoldHinge.right},
          maxTiltDegrees: maxTiltDegrees,
        );

  /// Top and bottom only. The hinge is always a horizontal edge.
  const DuoFoldConstraints.vertical({double maxTiltDegrees = 45})
      : this._(
          const {DuoFoldHinge.top, DuoFoldHinge.bottom},
          maxTiltDegrees: maxTiltDegrees,
        );

  /// One hinge only. Tilting the other way reads as flat.
  const DuoFoldConstraints.only(DuoFoldHinge hinge, {double maxTiltDegrees = 45})
      : this._(
          // A set literal built directly from a formal parameter (`{hinge}`)
          // trips a const-evaluation limitation in the Dart compiler, so the
          // set is picked from four fully-literal consts instead.
          hinge == DuoFoldHinge.left
              ? const {DuoFoldHinge.left}
              : hinge == DuoFoldHinge.right
                  ? const {DuoFoldHinge.right}
                  : hinge == DuoFoldHinge.top
                      ? const {DuoFoldHinge.top}
                      : const {DuoFoldHinge.bottom},
          maxTiltDegrees: maxTiltDegrees,
        );

  /// An arbitrary subset of hinges. An empty set always reads as flat.
  ///
  /// Not const: [hinges] is defensively copied through `Set.unmodifiable`,
  /// which is not a const expression. If a const value is what you need,
  /// reach for [only], [horizontal], [vertical] or [free] instead.
  DuoFoldConstraints.allow(Set<DuoFoldHinge> hinges, {double maxTiltDegrees = 45})
      : this._(Set<DuoFoldHinge>.unmodifiable(hinges), maxTiltDegrees: maxTiltDegrees);

  /// Null means unconstrained: [resolve] passes the pose through untouched.
  final Set<DuoFoldHinge>? _allowedHinges;

  /// Widest tilt this widget will report, in degrees. Defaults to 45.
  final double maxTiltDegrees;

  /// Applies this constraint to a raw, free-rotation pose.
  ///
  /// [tiltDegrees], [liftDirX] and [liftDirY] are the unconstrained output:
  /// a non-negative magnitude and a unit direction in fragment coordinates
  /// (y down). [free] passes them through unchanged, aside from clamping the
  /// magnitude to [maxTiltDegrees].
  ///
  /// A constrained set picks the allowed hinge whose lift direction is
  /// closest to the raw one, keeps only the component of the pose along that
  /// hinge's axis, and discards the perpendicular component. If every
  /// allowed hinge points away from the raw lean, the result is flat: a
  /// magnitude of zero, with [liftDirX] and [liftDirY] passed through so the
  /// direction stays finite even though the tilt has no effect.
  ({double tiltDegrees, double liftDirX, double liftDirY}) resolve({
    required double tiltDegrees,
    required double liftDirX,
    required double liftDirY,
  }) {
    final clampedMagnitude = tiltDegrees.clamp(0.0, maxTiltDegrees).toDouble();
    final hinges = _allowedHinges;
    if (hinges == null) {
      return (tiltDegrees: clampedMagnitude, liftDirX: liftDirX, liftDirY: liftDirY);
    }
    if (hinges.isEmpty || clampedMagnitude <= 0) {
      return (tiltDegrees: 0, liftDirX: liftDirX, liftDirY: liftDirY);
    }

    DuoFoldHinge? bestHinge;
    var bestCosine = double.negativeInfinity;
    for (final hinge in hinges) {
      final cosine = liftDirX * hinge._liftDirX + liftDirY * hinge._liftDirY;
      if (cosine > bestCosine) {
        bestCosine = cosine;
        bestHinge = hinge;
      }
    }

    if (bestHinge == null || bestCosine <= 0) {
      return (tiltDegrees: 0, liftDirX: liftDirX, liftDirY: liftDirY);
    }

    final component =
        (clampedMagnitude * bestCosine).clamp(0.0, maxTiltDegrees).toDouble();
    return (
      tiltDegrees: component,
      liftDirX: bestHinge._liftDirX,
      liftDirY: bestHinge._liftDirY,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DuoFoldConstraints &&
        _setEquals(other._allowedHinges, _allowedHinges) &&
        other.maxTiltDegrees == maxTiltDegrees;
  }

  @override
  int get hashCode => Object.hash(
        _allowedHinges == null
            ? null
            : Object.hashAllUnordered(_allowedHinges),
        maxTiltDegrees,
      );

  @override
  String toString() {
    final hinges = _allowedHinges;
    final hingeDescription = hinges == null ? 'free' : hinges.toString();
    return 'DuoFoldConstraints($hingeDescription, maxTilt: ${maxTiltDegrees}deg)';
  }
}

bool _setEquals(Set<DuoFoldHinge>? a, Set<DuoFoldHinge>? b) {
  if (a == null || b == null) {
    return a == b;
  }
  return a.length == b.length && a.containsAll(b);
}
