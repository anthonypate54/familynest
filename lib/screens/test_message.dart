import 'package:flutter/material.dart';

class TestMessageScreen extends StatelessWidget {
  const TestMessageScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Message (Service Demo)')),
      body: const Center(child: Text('Message service will be called here.')),
    );
  }
}
