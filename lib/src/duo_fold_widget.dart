import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'duo_fold_errors.dart';
import 'duo_fold_parameters.dart';
import 'duo_fold_shader.dart';

/// Renders [child] behind a hinged pane of frosted glass.
///
/// The child is rasterized into a layer and run through a fragment shader, the
/// direct analog of Android's `RenderEffect.createRuntimeShaderEffect`. Anything
/// inside must therefore be Flutter-drawn: platform views and texture widgets do
/// not participate in a layer filter.
///
/// Requires the Impeller renderer. Every other backend throws
/// [DuoFoldUnsupportedError] rather than quietly rendering the child unfiltered.
class DuoFold extends StatefulWidget {
  /// Creates a fold effect driven by an explicit [tiltDegrees] and
  /// [liftDirection].
  ///
  /// [liftDirection] must be a unit vector whenever [tiltDegrees] is
  /// meaningfully nonzero (that is, outside [tiltEpsilon] of rest); [build]
  /// checks this with an assert, so the mistake is caught in development and
  /// costs nothing in a release build. At rest, [liftDirection] is never
  /// consumed, so any value, including [ui.Offset.zero], is accepted there
  /// without complaint, the same way [tiltDegrees] alone already puts the
  /// widget in pass-through mode regardless of direction.
  ///
  /// The check lives in [build] rather than here so this constructor can
  /// stay const: validating [liftDirection] needs `Offset.distance`, which
  /// is not a constant expression, and Dart forbids non-constant assert
  /// clauses on a const constructor outright. Const matters more here than
  /// on a typical widget, since `DuoFold` wraps a whole subtree and is
  /// rebuilt on every sensor sample; a const construction lets Flutter skip
  /// that rebuild when nothing has changed.
  const DuoFold({
    super.key,
    required this.tiltDegrees,
    this.liftDirection = const ui.Offset(-1, 0),
    this.parameters = const DuoFoldParameters(),
    this.pixelsPerMillimeter,
    this.enabled = true,
    required this.child,
  });

  /// Below this many degrees the effect is invisible and the widget renders the
  /// child directly, skipping the layer and the shader entirely.
  static const double tiltEpsilon = 0.05;

  /// How far [liftDirection]'s length may stray from exactly 1 before the
  /// unit-vector assert at the top of `build()` fires.
  static const double _liftDirectionLengthTolerance = 1e-2;

  /// Tilt magnitude. The sign is not meaningful on its own: direction comes
  /// from [liftDirection].
  final double tiltDegrees;

  /// Unit vector, in fragment coordinates (y down), pointing from the hinge
  /// line toward the edge that lifts toward the viewer. Defaults to
  /// `Offset(-1, 0)`: hinge on the right, frost spreading left.
  final ui.Offset liftDirection;

  /// Physical tuning.
  final DuoFoldParameters parameters;

  /// Display density from `DuoMotionSource.readMetrics`, if known.
  final double? pixelsPerMillimeter;

  /// Set false to bypass the effect without rebuilding the subtree.
  final bool enabled;

  /// The content that appears to sit behind the glass.
  final Widget child;

  @override
  State<DuoFold> createState() => _DuoFoldState();
}

class _DuoFoldState extends State<DuoFold> {
  ui.FragmentShader? _shader;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    if (kIsWeb) {
      // Fail on the first build rather than at raster time, where the error
      // would surface as a red screen with no explanation.
      setState(() {
        _loadError = const DuoFoldUnsupportedError(
          reason: 'Flutter web renders with CanvasKit, not Impeller',
        );
      });
      return;
    }
    try {
      final program = await DuoFoldShader.program();
      if (!mounted) {
        return;
      }
      setState(() => _shader = program.fragmentShader());
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loadError = error);
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  bool get _atRest => widget.tiltDegrees.abs() < DuoFold.tiltEpsilon;

  @override
  Widget build(BuildContext context) {
    assert(
      _atRest ||
          (widget.liftDirection.distance - 1).abs() <=
              DuoFold._liftDirectionLengthTolerance,
      'liftDirection must be a unit vector when tiltDegrees is outside '
      'tiltEpsilon of rest; got ${widget.liftDirection} with length '
      '${widget.liftDirection.distance}',
    );

    final error = _loadError;
    if (error != null) {
      throw error;
    }

    final shader = _shader;
    if (!widget.enabled || _atRest || shader == null) {
      return widget.child;
    }

    final density =
        widget.parameters.resolvePixelsPerMillimeter(widget.pixelsPerMillimeter);
    DuoFoldShader.applyUniforms(
      shader,
      widget.parameters.packUniforms(
        tiltDegrees: widget.tiltDegrees,
        liftDirX: widget.liftDirection.dx,
        liftDirY: widget.liftDirection.dy,
        pixelsPerMillimeter: density,
      ),
    );

    final ui.ImageFilter filter;
    try {
      filter = ui.ImageFilter.shader(shader);
    } on Object catch (cause) {
      throw DuoFoldShaderError(
        'ui.ImageFilter.shader was rejected by this backend. duo_animation needs '
        'Impeller; check that the app was not launched with '
        '--no-enable-impeller.',
        cause,
      );
    }

    return ClipRect(
      child: ImageFiltered(
        imageFilter: filter,
        child: widget.child,
      ),
    );
  }
}
