import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_send/main.dart';

void main() {
  testWidgets('renders phase 0 workspace', (WidgetTester tester) async {
    await tester.pumpWidget(const WindSendApp());

    expect(find.text('WindSend'), findsOneWidget);
    expect(find.text('Rust core bridge'), findsOneWidget);
    expect(find.byIcon(Icons.terminal_rounded), findsOneWidget);
  });
}
