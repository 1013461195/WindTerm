import 'dart:convert';
import 'dart:io';

import '../session/session_profile.dart';

class AuthIdentity {
  const AuthIdentity({
    required this.id,
    required this.name,
    required this.username,
    required this.authType,
    required this.secretId,
    required this.credentialStorage,
    this.privateKeyPath,
  });

  final String id;
  final String name;
  final String username;
  final SshAuthType authType;
  final String secretId;
  final String credentialStorage;
  final String? privateKeyPath;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'username': username,
    'authType': authType.name,
    'secretId': secretId,
    'credentialStorage': credentialStorage,
    'privateKeyPath': privateKeyPath,
  };

  factory AuthIdentity.fromJson(Map<String, dynamic> json) {
    return AuthIdentity(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      authType: SshAuthType.values.firstWhere(
        (value) => value.name == json['authType'],
        orElse: () => SshAuthType.password,
      ),
      secretId: json['secretId'] as String? ?? '',
      credentialStorage: json['credentialStorage'] as String? ?? 'platform',
      privateKeyPath: json['privateKeyPath'] as String?,
    );
  }
}

class AuthIdentitySecret {
  const AuthIdentitySecret({this.password = '', this.passphrase = ''});

  final String password;
  final String passphrase;

  String encode() => jsonEncode(<String, String>{
    'password': password,
    'passphrase': passphrase,
  });

  factory AuthIdentitySecret.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    return AuthIdentitySecret(
      password: json['password'] as String? ?? '',
      passphrase: json['passphrase'] as String? ?? '',
    );
  }
}

class AuthIdentityStore {
  AuthIdentityStore(this.dataDirectory);

  final String dataDirectory;
  final List<AuthIdentity> _identities = <AuthIdentity>[];

  List<AuthIdentity> get identities => List.unmodifiable(_identities);

  Future<void> load() async {
    final file = File('$dataDirectory/auth_identities.json');
    if (!await file.exists()) return;
    try {
      final values = jsonDecode(await file.readAsString()) as List<dynamic>;
      _identities
        ..clear()
        ..addAll(
          values
              .whereType<Map<String, dynamic>>()
              .map(AuthIdentity.fromJson)
              .where((identity) => identity.id.isNotEmpty),
        );
    } on Object {
      _identities.clear();
    }
  }

  Future<void> save() async {
    final file = File('$dataDirectory/auth_identities.json');
    await file.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(_identities.map((identity) => identity.toJson()).toList()),
      flush: true,
    );
  }

  void upsert(AuthIdentity identity) {
    final index = _identities.indexWhere((value) => value.id == identity.id);
    if (index < 0) {
      _identities.add(identity);
    } else {
      _identities[index] = identity;
    }
    _identities.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
  }

  void delete(String id) {
    _identities.removeWhere((identity) => identity.id == id);
  }
}
