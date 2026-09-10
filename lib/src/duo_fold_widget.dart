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
  /// Creates a fold effect driven by an explicit [tiltDegrees].
  const DuoFold({
    super.key,
    required this.tiltDegrees,
    this.hingeSide,
    this.parameters = const DuoFoldParameters(),
    this.pixelsPerMillimeter,
    this.enabled = true,
    required this.child,
  });

  /// Below this many degrees the effect is invisible and the widget renders the
  /// child directly, skipping the layer and the shader entirely.
  static const double tiltEpsilon = 0.05;

  /// Signed tilt about the screen-space Y axis. Positive means the right edge is
  /// farther from the viewer.
  final double tiltDegrees;

  /// Overrides the hinge. Defaults to [hingeSideFor] of [tiltDegrees].
  final double? hingeSide;

  /// Physical tuning.
  final DuoFoldParameters parameters;

  /// Display density from `DuoMotionSource.readMetrics`, if known.
  final double? pixelsPerMillimeter;

  /// Set false to bypass the effect without rebuilding the subtree.
  final bool enabled;

  /// The content that appears to sit behind the glass.
  final Widget child;

  /// The hinge implied by a tilt sign: right for zero and positive, left for
  /// negative.
  static double hingeSideFor(double tiltDegrees) => tiltDegrees >= 0 ? 1 : -1;

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
        hingeSide: widget.hingeSide ?? DuoFold.hingeSideFor(widget.tiltDegrees),
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
