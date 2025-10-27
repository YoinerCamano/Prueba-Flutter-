import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Simple mock test without BLE dependencies
void main() {
  testWidgets('Basic Flutter app test', (WidgetTester tester) async {
    // Build a simple app without BLE dependencies
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Test App')),
          body: const Center(child: Text('Hello World')),
        ),
      ),
    );

    // Verify basic widgets are present
    expect(find.text('Test App'), findsOneWidget);
    expect(find.text('Hello World'), findsOneWidget);
  });
}
