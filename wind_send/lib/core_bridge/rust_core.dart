import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef _CoreVersionNative = Pointer<Utf8Char> Function();
typedef _CoreVersionDart = Pointer<Utf8Char> Function();

typedef _CoreOpenMockSessionNative = Uint64 Function(Uint16 cols, Uint16 rows);
typedef _CoreOpenMockSessionDart = int Function(int cols, int rows);

typedef _CorePollEventNative = Pointer<Utf8Char> Function(Uint64 sessionId);
typedef _CorePollEventDart = Pointer<Utf8Char> Function(int sessionId);

typedef _CoreStringFreeNative = Void Function(Pointer<Utf8Char> ptr);
typedef _CoreStringFreeDart = void Function(Pointer<Utf8Char> ptr);

final class Utf8Char extends Opaque {}

class CoreEvent {
  const CoreEvent({required this.sessionId, required this.line});

  final int sessionId;
  final String line;

  static CoreEvent? fromJsonString(String jsonString) {
    final Object? decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    if (decoded['type'] != 'terminal_line') {
      return null;
    }
    return CoreEvent(
      sessionId: decoded['session_id'] as int,
      line: decoded['line'] as String,
    );
  }
}

abstract class RustCore {
  String get version;

  int openMockSession({required int cols, required int rows});

  CoreEvent? pollEvent(int sessionId);

  static RustCore load() {
    final DynamicLibrary? library = _tryOpenLibrary();
    if (library == null) {
      return const DartMockCore();
    }
    return NativeRustCore(library);
  }

  static DynamicLibrary? _tryOpenLibrary() {
    final List<String> candidates = _libraryCandidates();
    for (final String candidate in candidates) {
      try {
        return DynamicLibrary.open(candidate);
      } on Object {
        continue;
      }
    }
    return null;
  }

  static List<String> _libraryCandidates() {
    final String cwd = Directory.current.path;
    if (Platform.isMacOS) {
      return <String>[
        '$cwd/rust/target/debug/librust_core.dylib',
        '$cwd/../rust/target/debug/librust_core.dylib',
        '$cwd/target/debug/librust_core.dylib',
        'librust_core.dylib',
      ];
    }
    if (Platform.isLinux) {
      return <String>[
        '$cwd/rust/target/debug/librust_core.so',
        '$cwd/../rust/target/debug/librust_core.so',
        '$cwd/target/debug/librust_core.so',
        'librust_core.so',
      ];
    }
    if (Platform.isWindows) {
      return <String>[
        r'rust\target\debug\rust_core.dll',
        r'..\rust\target\debug\rust_core.dll',
        r'target\debug\rust_core.dll',
        'rust_core.dll',
      ];
    }
    return const <String>[];
  }
}

class NativeRustCore implements RustCore {
  NativeRustCore(DynamicLibrary library)
    : _version = library.lookupFunction<_CoreVersionNative, _CoreVersionDart>(
        'core_version',
      ),
      _openMockSession = library
          .lookupFunction<_CoreOpenMockSessionNative, _CoreOpenMockSessionDart>(
            'core_open_mock_session',
          ),
      _pollEvent = library
          .lookupFunction<_CorePollEventNative, _CorePollEventDart>(
            'core_poll_event',
          ),
      _free = library
          .lookupFunction<_CoreStringFreeNative, _CoreStringFreeDart>(
            'core_string_free',
          );

  final _CoreVersionDart _version;
  final _CoreOpenMockSessionDart _openMockSession;
  final _CorePollEventDart _pollEvent;
  final _CoreStringFreeDart _free;

  @override
  String get version => _takeString(_version());

  @override
  int openMockSession({required int cols, required int rows}) {
    return _openMockSession(cols, rows);
  }

  @override
  CoreEvent? pollEvent(int sessionId) {
    final Pointer<Utf8Char> ptr = _pollEvent(sessionId);
    if (ptr.address == 0) {
      return null;
    }
    return CoreEvent.fromJsonString(_takeString(ptr));
  }

  String _takeString(Pointer<Utf8Char> ptr) {
    if (ptr.address == 0) {
      return '';
    }
    try {
      return _readUtf8(ptr);
    } finally {
      _free(ptr);
    }
  }

  String _readUtf8(Pointer<Utf8Char> ptr) {
    final List<int> bytes = <int>[];
    int offset = 0;
    while (true) {
      final int byte = (ptr.cast<Uint8>() + offset).value;
      if (byte == 0) {
        break;
      }
      bytes.add(byte);
      offset++;
    }
    return utf8.decode(bytes);
  }
}

class DartMockCore implements RustCore {
  const DartMockCore();

  static int _nextSessionId = 0;
  static int _tick = 0;

  @override
  String get version => 'dart fallback core (Rust library not loaded)';

  @override
  int openMockSession({required int cols, required int rows}) {
    _nextSessionId++;
    return _nextSessionId;
  }

  @override
  CoreEvent? pollEvent(int sessionId) {
    _tick++;
    return CoreEvent(
      sessionId: sessionId,
      line: '[dart fallback] tick=$_tick session=$sessionId',
    );
  }
}
