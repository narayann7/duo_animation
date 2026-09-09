import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

/// Example host app for the duo_animation package.
///
/// The demo widget subtree is added in a later task once the fold effect
/// itself exists; for now this only confirms the package scaffolds cleanly.
class MyApp extends StatelessWidget {
  /// Creates the example app.
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('duo_animation example')),
        body: const Center(child: Text('duo_animation')),
      ),
    );
  }
}
