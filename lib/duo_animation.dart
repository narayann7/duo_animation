/// iPhone Duo style tilt-driven frosted-glass fold effect.
///
/// See `DuoFold` for the widget entry point and `DuoFoldParameters` for the
/// physical tuning knobs.
library;

export 'src/duo_fold_constraints.dart';
export 'src/duo_fold_controller.dart';
export 'src/duo_fold_errors.dart';
export 'src/duo_fold_motion_widget.dart';
export 'src/duo_fold_parameters.dart';
export 'src/duo_fold_widget.dart';
export 'src/motion/display_metrics.dart';
export 'src/motion/fold_motion_model.dart' show FoldMotionModel, FoldState;
export 'src/motion/motion_sample.dart';
export 'src/motion/motion_source.dart' show DuoMotionSource, FakeMotionSource;
