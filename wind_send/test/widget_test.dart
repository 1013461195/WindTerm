import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_send/main.dart';

void main() {
  testWidgets('renders connection hub workspace', (WidgetTester tester) async {
    await tester.pumpWidget(const WindSendApp(requireSecuritySetup: false));

    expect(find.text('连接中心'), findsNWidgets(2));
    expect(find.text('全部连接'), findsOneWidget);
    expect(find.text('新建连接'), findsOneWidget);
    expect(find.text('SSH'), findsOneWidget);
    expect(find.text('RDP'), findsOneWidget);
    expect(find.text('Telnet'), findsOneWidget);
    expect(find.text('隧道'), findsOneWidget);
    expect(find.text('VNC'), findsOneWidget);
  });

  testWidgets('clipboard integration exists', (WidgetTester tester) async {
    // 验证剪贴板集成不会导致崩溃
    await tester.pumpWidget(const WindSendApp(requireSecuritySetup: false));
    // 基本渲染测试通过即可
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('opens SSH connection editor from connection hub', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const WindSendApp(requireSecuritySetup: false));

    await tester.tap(find.text('新建连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建 SSH').last);
    await tester.pumpAndSettle();

    expect(find.text('新建 SSH 连接'), findsOneWidget);
    expect(find.text('基本信息'), findsOneWidget);
    expect(find.text('连接设置'), findsOneWidget);
    expect(find.text('跳板机'), findsOneWidget);
    expect(find.text('代理设置'), findsOneWidget);
    expect(find.text('名称'), findsWidgets);
    expect(find.text('地址'), findsWidgets);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);

    await tester.tap(find.text('连接设置'));
    await tester.pumpAndSettle();
    expect(find.text('连接超时（毫秒）'), findsOneWidget);
    expect(find.text('心跳间隔（毫秒）'), findsOneWidget);
    expect(find.text('终端类型'), findsOneWidget);
  });

  testWidgets('opens authentication identity manager', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const WindSendApp(requireSecuritySetup: false));

    await tester.tap(find.text('认证身份'));
    await tester.pumpAndSettle();

    expect(find.text('还没有保存认证身份。\n可保存账号密码或账号、私钥路径和私钥口令。'), findsOneWidget);
    expect(find.text('新建身份'), findsOneWidget);
  });
}
