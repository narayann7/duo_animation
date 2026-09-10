import 'package:duo_animation/duo_animation.dart';
import 'package:flutter/material.dart';

/// Entry point for the duo_animation demo.
///
/// Tilt is driven by the device orientation sensors. The first sample latches
/// the pose the phone was held at on launch, so that angle reads as flat and
/// everything is measured against it. Recalibrate re-latches it.
void main() {
  runApp(const _DuoFoldDemoApp());
}

class _DuoFoldDemoApp extends StatelessWidget {
  const _DuoFoldDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'duo_animation example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const _DuoFoldDemoPage(),
    );
  }
}

class _DuoFoldDemoPage extends StatefulWidget {
  const _DuoFoldDemoPage();

  @override
  State<_DuoFoldDemoPage> createState() => _DuoFoldDemoPageState();
}

class _DuoFoldDemoPageState extends State<_DuoFoldDemoPage> {
  final DuoFoldController _controller = DuoFoldController();

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DuoFoldMotion(
        controller: _controller,
        child: _DemoContent(controller: _controller),
      ),
    );
  }
}

/// Live tilt readout and a recalibrate button.
///
/// The readout reads the filtered output rather than the raw sensor, so a value
/// pinned at zero while the phone is moving means samples are not arriving at
/// all, which is a different problem from the effect looking wrong.
class _TiltReadout extends StatelessWidget {
  const _TiltReadout({required this.controller});

  final DuoFoldController controller;

  /// Names the hinge nearest the current lift direction, for display only.
  /// Ties (an exactly diagonal lift) favor the horizontal label.
  static String _hingeLabel(double liftDirX, double liftDirY) {
    if (liftDirX.abs() >= liftDirY.abs()) {
      return liftDirX < 0 ? 'right' : 'left';
    }
    return liftDirY > 0 ? 'top' : 'bottom';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tilt = controller.tiltDegrees;
        final hinge = _hingeLabel(controller.liftDirX, controller.liftDirY);
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'tilt ${tilt.toStringAsFixed(1)} deg, hinge $hinge',
                    style: textTheme.bodyMedium,
                  ),
                  if (!controller.hasSensor)
                    Text(
                      'no rotation sensor found, tilt will not move',
                      style: textTheme.labelSmall
                          ?.copyWith(color: const Color(0xFFB3261E)),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: controller.recalibrate,
              child: const Text('Recalibrate'),
            ),
          ],
        );
      },
    );
  }
}

/// Which of the four constraint presets the demo chips can pick.
enum _ConstraintOption { free, horizontal, vertical, rightOnly }

/// Extension is private to this file: it just turns each preset into the
/// [DuoFoldConstraints] value and label the chip row needs.
extension on _ConstraintOption {
  String get label {
    switch (this) {
      case _ConstraintOption.free:
        return 'Free';
      case _ConstraintOption.horizontal:
        return 'Horizontal';
      case _ConstraintOption.vertical:
        return 'Vertical';
      case _ConstraintOption.rightOnly:
        return 'Right only';
    }
  }

  DuoFoldConstraints get constraints {
    switch (this) {
      case _ConstraintOption.free:
        return const DuoFoldConstraints.free();
      case _ConstraintOption.horizontal:
        return const DuoFoldConstraints.horizontal();
      case _ConstraintOption.vertical:
        return const DuoFoldConstraints.vertical();
      case _ConstraintOption.rightOnly:
        return DuoFoldConstraints.only(DuoFoldHinge.right);
    }
  }
}

/// A row of choice chips that switch [controller]'s constraint mode live, so
/// the difference between free and axis-locked folding is one tap away.
class _ConstraintPicker extends StatefulWidget {
  const _ConstraintPicker({required this.controller});

  final DuoFoldController controller;

  @override
  State<_ConstraintPicker> createState() => _ConstraintPickerState();
}

class _ConstraintPickerState extends State<_ConstraintPicker> {
  // DuoFoldController defaults to DuoFoldConstraints.horizontal().
  _ConstraintOption _selected = _ConstraintOption.horizontal;

  void _select(_ConstraintOption option) {
    setState(() => _selected = option);
    widget.controller.constraints = option.constraints;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final option in _ConstraintOption.values)
          ChoiceChip(
            label: Text(option.label),
            selected: _selected == option,
            onSelected: (_) => _select(option),
          ),
      ],
    );
  }
}

/// Ordinary app furniture behind the glass: a heading, a card of body copy
/// and a scrolling list of rows with avatars and two-line captions. Fine
/// text and edges are what make the frosted look worth looking at, so this
/// avoids anything as coarse as a single large image or a flat gradient.
class _DemoContent extends StatelessWidget {
  const _DemoContent({required this.controller});

  final DuoFoldController controller;

  static const _rows = <(String name, String detail)>[
    ('Priya Nathan', 'Filed the quarterly review notes and tagged three follow-ups for the design sync.'),
    ('Marcus Oduya', 'Rebuilt the onboarding flow after the last round of usability feedback came in.'),
    ('Elena Sorescu', 'Pushed the copy edits for the settings screen; still waiting on legal sign-off.'),
    ('Tomas Berglund', 'Closed out the backlog grooming session with four items moved to next sprint.'),
    ('Ada Chukwu', 'Paired on the caching layer rewrite and left comments on the open pull request.'),
    ('Felix Amaro', 'Drafted the release notes for the upcoming version and queued them for review.'),
    ('Naomi Kessler', 'Ran the accessibility pass on the checkout flow and logged two contrast issues.'),
    ('Ravi Deshmukh', 'Set up the new staging environment and documented the deploy steps.'),
    ('Ines Almeida', 'Triaged the overnight crash reports and reassigned two to the platform team.'),
    ('Callum Reyes', 'Wrapped up the interview loop notes and shared a summary with the panel.'),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('Team updates', style: textTheme.headlineMedium),
        const SizedBox(height: 4),
        _TiltReadout(controller: controller),
        const SizedBox(height: 8),
        _ConstraintPicker(controller: controller),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'This card is here to give the fold shader something worth '
              'looking at: fine strokes on ordinary body text catch the '
              'frosted-glass distortion in a way a single flat image or a '
              'gradient never will. Tilt the phone and the pane swings on a '
              'hinge: lean the right edge away and the hinge sits on the '
              'right, so the frost spreads to the left.',
              style: textTheme.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final row in _rows)
          ListTile(
            leading: CircleAvatar(
              child: Text(
                row.$1.split(' ').map((part) => part[0]).take(2).join(),
              ),
            ),
            title: Text(row.$1),
            subtitle: Text(row.$2, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}
