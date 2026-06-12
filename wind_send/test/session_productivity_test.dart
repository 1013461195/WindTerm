import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wind_send/features/network/network_config.dart';
import 'package:wind_send/features/security/auth_identity.dart';
import 'package:wind_send/features/session/session_productivity.dart';
import 'package:wind_send/features/session/session_profile.dart';

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

  test('authentication identity index never stores its secret', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wind-send-identity-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = AuthIdentityStore(directory.path);
    store.upsert(
      const AuthIdentity(
        id: 'identity-1',
        name: 'Production',
        username: 'root',
        authType: SshAuthType.password,
        secretId: 'keychain-reference',
        credentialStorage: 'platform',
      ),
    );
    await store.save();

    final content = await File(
      '${directory.path}/auth_identities.json',
    ).readAsString();
    final entry =
        (jsonDecode(content) as List<dynamic>).single as Map<String, dynamic>;
    expect(content, contains('keychain-reference'));
    expect(content, isNot(contains('hunter2')));
    expect(entry.containsKey('password'), isFalse);
    expect(entry.containsKey('passphrase'), isFalse);
  });

  test('SSH advanced options survive profile serialization', () {
    const profile = SessionProfile(
      id: 'ssh-1',
      name: 'Production',
      type: SessionProfileType.ssh,
      host: 'example.com',
      port: 22,
      authIdentityId: 'identity-1',
      sshOptions: <String, Object?>{
        'connectTimeoutMs': 12000,
        'terminalType': 'vt100',
        'jumpHosts': <Map<String, Object?>>[
          <String, Object?>{
            'host': 'jump.example.com',
            'port': 22,
            'identityId': 'identity-2',
          },
        ],
      },
    );

    final restored = SessionProfile.fromJson(profile.toJson());
    expect(restored.authIdentityId, 'identity-1');
    expect(restored.sshOptions['connectTimeoutMs'], 12000);
    expect(restored.sshOptions['terminalType'], 'vt100');
    expect(restored.sshOptions['jumpHosts'], isA<List<dynamic>>());
  });
}
