# Contributing

duo_animation is pre-1.0, so the API can still move between releases. Bug
reports, fixes, and questions are welcome.

By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- For a bug, open an issue with a minimal repro: Flutter version, device and OS
  version, and the smallest widget tree that shows it. Say whether you are on
  Impeller. The effect is built on `ui.ImageFilter.shader` and exists nowhere
  else, so "nothing renders" and "the renderer is wrong" look identical from the
  outside.
- For an API change or a new parameter, open an issue first and agree on the
  shape before writing code. `DuoFoldParameters` is a physical model rather than
  a bag of knobs, and a new field has to mean something in millimeters or
  degrees to earn its place.
- Typos, docs, and obvious fixes can go straight to a pull request.

## Setup

The package pins its Flutter SDK with [fvm](https://fvm.app):

```bash
fvm install          # reads .fvmrc, currently Flutter 3.44.9
fvm flutter pub get
```

Run every Dart and Flutter command through `fvm` so you are on the pinned SDK.
The formatter changed style in Dart 3.7, so a different SDK will reformat files
you never touched.

## Running it

```bash
cd example
fvm flutter run
```

The example has a slider, so it does something visible on a simulator. The
sensor path needs real hardware.

## Making changes

Branch off `main` and keep one concern per pull request.

Public members need a doc comment. `public_member_api_docs` is on as a lint and
the analyzer runs with strict casts and strict raw types, so an undocumented
export fails analysis rather than slipping through review.

Before pushing:

```bash
fvm dart format .
fvm flutter analyze          # must be clean
fvm flutter test             # all green
cd example && fvm flutter analyze
```

## Touching the platform channel

The Dart, Kotlin, and Swift sides of the motion channel are generated from
`pigeons/motion.dart`. Edit the schema, never the generated files:

```bash
fvm dart run pigeon --input pigeons/motion.dart
fvm dart format .
```

The format step is not optional. Pigeon emits Dart that the current formatter
rewrites, so skipping it commits a file that fails the format gate on the next
push.

Then commit the regenerated `motion_api.g.dart`, `MotionApi.g.kt`, and
`MotionApi.g.swift` alongside the schema change. All three have to move together
or the channel breaks at runtime rather than at compile time.

Native code stays thin on purpose. Attitude is reduced to screen axes and handed
straight to Dart; calibration, latency prediction, smoothing, and drift washout
all live in `FoldMotionModel`. If you are about to add filtering in Kotlin or
Swift, it probably belongs in Dart instead, where it is testable and identical
across platforms.

## Touching the shader

`shaders/duo_animation.frag` is a runtime asset. There is no golden-image
coverage, so a visual change needs before and after captures in the pull
request, on a real device at a few tilt angles rather than one flattering one.

## Tests

`FakeMotionSource` drives the controller from scripted samples, so the motion
path is testable without a device. Anything that changes how tilt is filtered or
constrained should come with a test that pins the numbers.

## Pull requests

- Say what changed and why, and link the issue it closes.
- Add or update tests for the behavior you touched.
- Note anything user-facing in the CHANGELOG under an `## Unreleased` heading at
  the top, adding the heading if it is not there. Released version headings are
  frozen; do not rewrite them.

Reviews happen when time allows. If a pull request goes quiet, a ping is fine.
