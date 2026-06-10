import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

// FFI 类型定义

// core_version
typedef _CoreVersionNative = Pointer<Utf8Char> Function();
typedef _CoreVersionDart = Pointer<Utf8Char> Function();

// core_session_open
typedef _CoreSessionOpenNative = Uint64 Function(
  Pointer<Utf8Char> host,
  Uint16 port,
  Pointer<Utf8Char> username,
  Pointer<Utf8Char> password,
);
typedef _CoreSessionOpenDart = int Function(
  Pointer<Utf8Char> host,
  int port,
  Pointer<Utf8Char> username,
  Pointer<Utf8Char> password,
);

// core_session_close
typedef _CoreSessionCloseNative = Void Function(Uint64 sessionId);
typedef _CoreSessionCloseDart = void Function(int sessionId);

// core_session_read
typedef _CoreSessionReadNative = Pointer<Utf8Char> Function(Uint64 sessionId);
typedef _CoreSessionReadDart = Pointer<Utf8Char> Function(int sessionId);

// core_session_write
typedef _CoreSessionWriteNative = Int32 Function(
  Uint64 sessionId,
  Pointer<Uint8> data,
  Uint64 len,
);
typedef _CoreSessionWriteDart = int Function(
  int sessionId,
  Pointer<Uint8> data,
  int len,
);

// core_session_resize
typedef _CoreSessionResizeNative = Int32 Function(
  Uint64 sessionId,
  Uint16 cols,
  Uint16 rows,
);
typedef _CoreSessionResizeDart = int Function(
  int sessionId,
  int cols,
  int rows,
);

// core_session_state
typedef _CoreSessionStateNative = Pointer<Utf8Char> Function(Uint64 sessionId);
typedef _CoreSessionStateDart = Pointer<Utf8Char> Function(int sessionId);

// core_string_free
typedef _CoreStringFreeNative = Void Function(Pointer<Utf8Char> ptr);
typedef _CoreStringFreeDart = void Function(Pointer<Utf8Char> ptr);

// Opaque 类型
final class Utf8Char extends Opaque {}

// 终端颜色
enum TerminalColor {
  defaultColor,
  black,
  red,
  green,
  yellow,
  blue,
  magenta,
  cyan,
  white,
  brightBlack,
  brightRed,
  brightGreen,
  brightYellow,
  brightBlue,
  brightMagenta,
  brightCyan,
  brightWhite,
  rgb,
  indexed,
}

// 终端单元格属性
class CellAttr {
  final TerminalColor fg;
  final TerminalColor bg;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool inverse;

  const CellAttr({
    this.fg = TerminalColor.defaultColor,
    this.bg = TerminalColor.defaultColor,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.inverse = false,
  });

  factory CellAttr.fromJson(Map<String, dynamic> json) {
    return CellAttr(
      fg: _parseColor(json['fg']),
      bg: _parseColor(json['bg']),
      bold: json['bold'] ?? false,
      italic: json['italic'] ?? false,
      underline: json['underline'] ?? false,
      inverse: json['inverse'] ?? false,
    );
  }

  static TerminalColor _parseColor(dynamic colorJson) {
    if (colorJson is String) {
      switch (colorJson) {
        case 'Default': return TerminalColor.defaultColor;
        case 'Black': return TerminalColor.black;
        case 'Red': return TerminalColor.red;
        case 'Green': return TerminalColor.green;
        case 'Yellow': return TerminalColor.yellow;
        case 'Blue': return TerminalColor.blue;
        case 'Magenta': return TerminalColor.magenta;
        case 'Cyan': return TerminalColor.cyan;
        case 'White': return TerminalColor.white;
        case 'BrightBlack': return TerminalColor.brightBlack;
        case 'BrightRed': return TerminalColor.brightRed;
        case 'BrightGreen': return TerminalColor.brightGreen;
        case 'BrightYellow': return TerminalColor.brightYellow;
        case 'BrightBlue': return TerminalColor.brightBlue;
        case 'BrightMagenta': return TerminalColor.brightMagenta;
        case 'BrightCyan': return TerminalColor.brightCyan;
        case 'BrightWhite': return TerminalColor.brightWhite;
        default: return TerminalColor.defaultColor;
      }
    }
    return TerminalColor.defaultColor;
  }
}

// 终端单元格
class TerminalCell {
  final String ch;
  final CellAttr attr;

  const TerminalCell({this.ch = ' ', this.attr = const CellAttr()});

  factory TerminalCell.fromJson(Map<String, dynamic> json) {
    return TerminalCell(
      ch: json['ch'] ?? ' ',
      attr: CellAttr.fromJson(json['attr'] ?? {}),
    );
  }
}

// 终端行
class TerminalLine {
  final List<TerminalCell> cells;

  const TerminalLine({required this.cells});

  factory TerminalLine.fromJson(Map<String, dynamic> json) {
    final cellsJson = json['cells'] as List<dynamic>? ?? [];
    return TerminalLine(
      cells: cellsJson.map((c) => TerminalCell.fromJson(c)).toList(),
    );
  }
}

// 终端快照
class TerminalSnapshot {
  final int cols;
  final int rows;
  final int cursorRow;
  final int cursorCol;
  final bool cursorVisible;
  final List<TerminalLine> lines;

  const TerminalSnapshot({
    required this.cols,
    required this.rows,
    required this.cursorRow,
    required this.cursorCol,
    required this.cursorVisible,
    required this.lines,
  });

  factory TerminalSnapshot.fromJson(Map<String, dynamic> json) {
    final linesJson = json['lines'] as List<dynamic>? ?? [];
    return TerminalSnapshot(
      cols: json['cols'] ?? 0,
      rows: json['rows'] ?? 0,
      cursorRow: json['cursor_row'] ?? 0,
      cursorCol: json['cursor_col'] ?? 0,
      cursorVisible: json['cursor_visible'] ?? true,
      lines: linesJson.map((l) => TerminalLine.fromJson(l)).toList(),
    );
  }
}

// SSH Session 封装
class SshSession {
  final int id;
  final RustCore _core;
  String _state;

  SshSession(this.id, this._core) : _state = 'created';

  String get state => _state;

  /// 读取终端输出
  TerminalSnapshot? readOutput() {
    return _core.sessionRead(id);
  }

  /// 发送输入
  int writeInput(String data) {
    final bytes = utf8.encode(data);
    return _core.sessionWrite(id, bytes);
  }

  /// 发送原始字节
  int writeBytes(Uint8List bytes) {
    return _core.sessionWrite(id, bytes);
  }

  /// 调整终端大小
  int resize(int cols, int rows) {
    return _core.sessionResize(id, cols, rows);
  }

  /// 获取状态
  String getState() {
    _state = _core.sessionState(id);
    return _state;
  }

  /// 关闭会话
  void close() {
    _core.sessionClose(id);
  }
}

// Rust Core 主类
abstract class RustCore {
  String get version;

  SshSession openSession({
    required String host,
    required int port,
    required String username,
    required String password,
  });

  TerminalSnapshot? sessionRead(int sessionId);
  int sessionWrite(int sessionId, List<int> data);
  int sessionResize(int sessionId, int cols, int rows);
  String sessionState(int sessionId);
  void sessionClose(int sessionId);

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

// 原生 Rust Core 实现
class NativeRustCore implements RustCore {
  NativeRustCore(DynamicLibrary library)
    : _version = library.lookupFunction<_CoreVersionNative, _CoreVersionDart>(
        'core_version',
      ),
      _sessionOpen = library.lookupFunction<_CoreSessionOpenNative, _CoreSessionOpenDart>(
        'core_session_open',
      ),
      _sessionClose = library.lookupFunction<_CoreSessionCloseNative, _CoreSessionCloseDart>(
        'core_session_close',
      ),
      _sessionRead = library.lookupFunction<_CoreSessionReadNative, _CoreSessionReadDart>(
        'core_session_read',
      ),
      _sessionWrite = library.lookupFunction<_CoreSessionWriteNative, _CoreSessionWriteDart>(
        'core_session_write',
      ),
      _sessionResize = library.lookupFunction<_CoreSessionResizeNative, _CoreSessionResizeDart>(
        'core_session_resize',
      ),
      _sessionState = library.lookupFunction<_CoreSessionStateNative, _CoreSessionStateDart>(
        'core_session_state',
      ),
      _free = library.lookupFunction<_CoreStringFreeNative, _CoreStringFreeDart>(
        'core_string_free',
      );

  final _CoreVersionDart _version;
  final _CoreSessionOpenDart _sessionOpen;
  final _CoreSessionCloseDart _sessionClose;
  final _CoreSessionReadDart _sessionRead;
  final _CoreSessionWriteDart _sessionWrite;
  final _CoreSessionResizeDart _sessionResize;
  final _CoreSessionStateDart _sessionState;
  final _CoreStringFreeDart _free;

  @override
  String get version => _takeString(_version());

  @override
  SshSession openSession({
    required String host,
    required int port,
    required String username,
    required String password,
  }) {
    final hostPtr = _toUtf8(host);
    final usernamePtr = _toUtf8(username);
    final passwordPtr = _toUtf8(password);

    try {
      final sessionId = _sessionOpen(hostPtr, port, usernamePtr, passwordPtr);
      if (sessionId == 0) {
        throw Exception('Failed to open SSH session');
      }
      return SshSession(sessionId, this);
    } finally {
      _free(hostPtr);
      _free(usernamePtr);
      _free(passwordPtr);
    }
  }

  @override
  TerminalSnapshot? sessionRead(int sessionId) {
    final ptr = _sessionRead(sessionId);
    if (ptr.address == 0) {
      return null;
    }
    final jsonStr = _takeString(ptr);
    try {
      final json = jsonDecode(jsonStr);
      return TerminalSnapshot.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  @override
  int sessionWrite(int sessionId, List<int> data) {
    final ptr = calloc<Uint8>(data.length);
    for (int i = 0; i < data.length; i++) {
      ptr[i] = data[i];
    }
    final result = _sessionWrite(sessionId, ptr, data.length);
    calloc.free(ptr);
    return result;
  }

  @override
  int sessionResize(int sessionId, int cols, int rows) {
    return _sessionResize(sessionId, cols, rows);
  }

  @override
  String sessionState(int sessionId) {
    return _takeString(_sessionState(sessionId));
  }

  @override
  void sessionClose(int sessionId) {
    _sessionClose(sessionId);
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

  Pointer<Utf8Char> _toUtf8(String str) {
    final units = utf8.encode(str);
    final ptr = calloc<Utf8Char>(units.length + 1);
    for (int i = 0; i < units.length; i++) {
      (ptr.cast<Uint8>() + i).value = units[i];
    }
    (ptr.cast<Uint8>() + units.length).value = 0;
    return ptr;
  }
}

// 简单的内存分配器（MVP 阶段）
final calloc = _Calloc();

class _Calloc {
  Pointer<T> allocate<T extends NativeType>(int count) {
    return calloc.allocate<T>(count);
  }

  void free(Pointer ptr) {
    calloc.free(ptr);
  }
}

// Dart Mock Core 实现（用于无 Rust 库时的开发）
class DartMockCore implements RustCore {
  const DartMockCore();

  static int _nextSessionId = 0;

  @override
  String get version => 'dart fallback core (Rust library not loaded)';

  @override
  SshSession openSession({
    required String host,
    required int port,
    required String username,
    required String password,
  }) {
    _nextSessionId++;
    // 返回一个模拟的 session
    return SshSession(_nextSessionId, this);
  }

  @override
  TerminalSnapshot? sessionRead(int sessionId) {
    // 返回模拟数据
    final line = TerminalLine(
      cells: List.generate(80, (i) => TerminalCell(ch: ' ')),
    );
    return TerminalSnapshot(
      cols: 80,
      rows: 24,
      cursorRow: 0,
      cursorCol: 0,
      cursorVisible: true,
      lines: List.generate(24, (_) => line),
    );
  }

  @override
  int sessionWrite(int sessionId, List<int> data) {
    return 0;
  }

  @override
  int sessionResize(int sessionId, int cols, int rows) {
    return 0;
  }

  @override
  String sessionState(int sessionId) {
    return 'running';
  }

  @override
  void sessionClose(int sessionId) {
    // Mock 实现
  }
}
