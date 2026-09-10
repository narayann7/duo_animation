# duo_animation example

The smallest thing that uses the package: a controller, a `DuoFoldMotion` around
a card, and a slider for devices with no gyroscope.

It carries no `android/` or `ios/` directory, so it is source to read rather
than an app to launch. To run it, generate the platform folders first:

```sh
flutter create --platforms=android,ios .
flutter run
```

Impeller only, so Android and iOS. Anywhere else the widget throws
`DuoFoldUnsupportedError`.

## Going further

For every parameter exposed at once, constraint modes side by side, and the
effect run over real screens rather than a painted stand-in, the playground app
is the place to look.

https://github.com/narayann7/duo_animation_playground
