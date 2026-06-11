import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wind_send/features/network/network_config.dart';
import 'package:wind_send/features/session/session_productivity.dart';

void main() {
  test('crash reporter redacts credentials and private keys', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wind-send-crash-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final reporter = CrashReporter(directory.path);
    await reporter.record(
      Exception(
        'password=hunter2 token=abc '
        '-----BEGIN PRIVATE KEY----- secret -----END PRIVATE KEY-----',
      ),
      StackTrace.fromString('${directory.path}/source.dart:1'),
      source: 'test',
    );

    final line = await File(
      '${directory.path}/crashes/crash.jsonl',
    ).readAsString();
    final entry = jsonDecode(line.trim()) as Map<String, dynamic>;
    expect(entry['error'], isNot(contains('hunter2')));
    expect(entry['error'], isNot(contains('abc')));
    expect(entry['error'], isNot(contains(' secret ')));
  });

  test('network config can explicitly clear proxy settings', () {
    const config = NetworkConfig(
      proxy: ProxyConfig(type: ProxyType.socks5, host: 'localhost', port: 1080),
      proxyCommand: 'proxy %h %p',
    );

    final cleared = config.copyWith(clearProxy: true, clearProxyCommand: true);
    expect(cleared.proxy, isNull);
    expect(cleared.proxyCommand, isNull);
  });
}
