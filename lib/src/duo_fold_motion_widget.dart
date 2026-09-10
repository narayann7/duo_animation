import 'package:flutter/widgets.dart';

import 'duo_fold_controller.dart';
import 'duo_fold_parameters.dart';
import 'duo_fold_widget.dart';

/// A [DuoFold] driven by a [DuoFoldController].
///
/// Rebuilds only the filter wrapper on each sensor sample. [child] is built once
/// by the caller and reused, so a 50 Hz sample stream does not rebuild the
/// subtree being folded.
class DuoFoldMotion extends StatelessWidget {
  /// Creates a sensor-driven fold around [child].
  const DuoFoldMotion({
    super.key,
    required this.controller,
    this.parameters = const DuoFoldParameters(),
    this.enabled = true,
    required this.child,
  });

  /// Supplies tilt, hinge and display density.
  final DuoFoldController controller;

  /// Physical tuning.
  final DuoFoldParameters parameters;

  /// Set false to bypass the effect.
  final bool enabled;

  /// The content that appears to sit behind the glass.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, folded) {
        return DuoFold(
          tiltDegrees: controller.tiltDegrees,
          hingeSide: controller.hingeSide,
          parameters: parameters,
          pixelsPerMillimeter: controller.pixelsPerMillimeter,
          enabled: enabled,
          child: folded!,
        );
      },
      child: child,
    );
  }
}
