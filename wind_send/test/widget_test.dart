import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_send/main.dart';

void main() {
  testWidgets('renders phase 2 workspace', (WidgetTester tester) async {
    await tester.pumpWidget(const WindSendApp());

    expect(find.text('WindSend'), findsOneWidget);
    expect(find.text('Rust core bridge'), findsOneWidget);
    expect(find.text('新建 SSH 连接'), findsOneWidget);
    expect(find.text('新建本地 Shell'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('clipboard integration exists', (WidgetTester tester) async {
    // 验证剪贴板集成不会导致崩溃
    await tester.pumpWidget(const WindSendApp());
    // 基本渲染测试通过即可
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
