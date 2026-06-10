import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_send/main.dart';

void main() {
  testWidgets('renders phase 1 workspace', (WidgetTester tester) async {
    await tester.pumpWidget(const WindSendApp());

    expect(find.text('WindSend'), findsOneWidget);
    expect(find.text('Rust core bridge'), findsOneWidget);
    expect(find.text('新建连接'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });
}
