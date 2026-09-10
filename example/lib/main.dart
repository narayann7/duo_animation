import 'package:duo_animation/duo_animation.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

/// The whole example: a card behind the fold, and a slider to tilt it.
class ExampleApp extends StatefulWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final DuoFoldController _controller = DuoFoldController();

  @override
  void initState() {
    super.initState();
    // Subscribes to the sensor. On a device without one, the controller stays
    // in manual mode and the slider below drives the fold instead.
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: DuoFoldMotion(
                    controller: _controller,
                    child: Container(
                      width: 260,
                      height: 340,
                      alignment: Alignment.center,
                      color: const Color(0xFF3B2F63),
                      child: const Text(
                        'Tilt me',
                        style: TextStyle(fontSize: 32),
                      ),
                    ),
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => Slider(
                  value: _controller.manualTiltDegrees,
                  min: -45,
                  max: 45,
                  // The sign picks the hinge: negative folds the other way.
                  onChanged: _controller.useSensor
                      ? null
                      : (value) => _controller.manualTiltDegrees = value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
