import 'dart:convert';
import 'dart:io';

import '../../core_bridge/rust_core.dart';
import 'session_manager.dart';

String windSendDataDirectory() {
  if (Platform.isWindows) {
    final base = Platform.environment['APPDATA'];
    if (base != null && base.isNotEmpty) return '$base/WindSend';
  }
  final home = Platform.environment['HOME'] ?? Directory.current.path;
  return '$home/.wind_send';
}

class WorkspaceState {
  const WorkspaceState({
    this.profileIds = const [],
    this.localShells = const [],
    this.activeIndex = 0,
  });

  final List<String> profileIds;
  final List<Map<String, Object?>> localShells;
  final int activeIndex;

  Map<String, Object?> toJson() => <String, Object?>{
    'profileIds': profileIds,
    'localShells': localShells,
    'activeIndex': activeIndex,
  };

  factory WorkspaceState.fromJson(Map<String, dynamic> json) {
    return WorkspaceState(
      profileIds: List<String>.from(json['profileIds'] ?? const []),
      localShells: (json['localShells'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((value) => Map<String, Object?>.from(value))
          .toList(),
      activeIndex: json['activeIndex'] as int? ?? 0,
    );
  }
}

class WorkspaceStore {
  WorkspaceStore(this.dataDirectory);

  final String dataDirectory;

  File get _file => File('$dataDirectory/workspace.json');

  Future<WorkspaceState> load() async {
    if (!await _file.exists()) return const WorkspaceState();
    try {
      final value = jsonDecode(await _file.readAsString());
      return WorkspaceState.fromJson(value as Map<String, dynamic>);
    } on Object {
      return const WorkspaceState();
    }
  }

  Future<void> save(List<SessionInfo> sessions, int activeIndex) async {
    final profileIds = <String>[];
    final localShells = <Map<String, Object?>>[];
    for (final session in sessions) {
      final config = session.profileConfig ?? const <String, Object?>{};
      final profileId = config['profileId'] as String?;
      if (profileId != null && profileId.isNotEmpty) {
        profileIds.add(profileId);
      } else if (session.type == SessionType.localShell) {
        localShells.add(<String, Object?>{
          'name': session.name,
          'shell': config['shell'],
          'workingDir': config['workingDir'],
        });
      }
    }
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        WorkspaceState(
          profileIds: profileIds,
          localShells: localShells,
          activeIndex: activeIndex,
        ).toJson(),
      ),
      flush: true,
    );
  }
}

class AppConfigStore {
  AppConfigStore(this.dataDirectory);

  final String dataDirectory;

  File get _file => File('$dataDirectory/settings.json');

  Future<Map<String, dynamic>> load() async {
    if (!await _file.exists()) return <String, dynamic>{};
    try {
      return Map<String, dynamic>.from(
        jsonDecode(await _file.readAsString()) as Map,
      );
    } on Object {
      return <String, dynamic>{};
    }
  }

  Future<void> save(Map<String, Object?> value) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
  }
}

class SessionLogWriter {
  SessionLogWriter(this.dataDirectory);

  final String dataDirectory;
  final Map<int, IOSink> _sinks = {};

  Future<void> append(SessionInfo session, TerminalSnapshot snapshot) async {
    if (snapshot.outputText.isEmpty) return;
    final config = session.profileConfig ?? const <String, Object?>{};
    if (config['logging'] != true) return;
    final configuredPath = config['logPath'] as String?;
    final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final path = configuredPath?.trim().isNotEmpty == true
        ? configuredPath!
        : '$dataDirectory/logs/${_safeName(session.name)}-$day.log';
    final sink = _sinks[session.id] ??= await _open(path);
    sink.write(_stripUnsafeControls(snapshot.outputText));
  }

  Future<IOSink> _open(String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.openWrite(mode: FileMode.append);
  }

  void close(int sessionId) {
    _sinks.remove(sessionId)?.close();
  }

  Future<void> dispose() async {
    final sinks = _sinks.values.toList();
    _sinks.clear();
    await Future.wait(sinks.map((sink) => sink.close()));
  }

  String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  String _stripUnsafeControls(String value) {
    return value
        .replaceAll(RegExp(r'\x1b\][^\x07]*(?:\x07|\x1b\\)'), '')
        .replaceAll(RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]'), '')
        .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'), '');
  }
}

class CrashReporter {
  CrashReporter(this.dataDirectory);

  final String dataDirectory;

  Future<void> record(
    Object error,
    StackTrace? stack, {
    required String source,
  }) async {
    try {
      final file = File('$dataDirectory/crashes/crash.jsonl');
      await file.parent.create(recursive: true);
      final entry = <String, Object?>{
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'source': source,
        'error': _sanitize(error.toString()),
        'stack': _sanitize(stack?.toString() ?? ''),
      };
      await file.writeAsString(
        '${jsonEncode(entry)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // Crash reporting must never cause another application failure.
    }
  }

  String _sanitize(String value) {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    var sanitized = value
        .replaceAll(
          RegExp(
            r'-----BEGIN [^-]*PRIVATE KEY-----[\s\S]*?'
            r'-----END [^-]*PRIVATE KEY-----',
            caseSensitive: false,
          ),
          '<private-key-redacted>',
        )
        .replaceAll(
          RegExp(
            r'(password|passphrase|token|authorization|proxy-authorization|'
            r'secret)\s*[=:]\s*[^\s,;]+',
            caseSensitive: false,
          ),
          r'$1=<redacted>',
        )
        .replaceAll(
          RegExp(r'(https?://)[^/@\s]+:[^/@\s]+@'),
          r'$1<credentials-redacted>@',
        );
    if (home.isNotEmpty) sanitized = sanitized.replaceAll(home, '~');
    return sanitized;
  }
}
