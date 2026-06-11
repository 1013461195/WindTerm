import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// FFI 类型定义

// core_version
typedef _CoreVersionNative = Pointer<Utf8Char> Function();
typedef _CoreVersionDart = Pointer<Utf8Char> Function();

// core_session_open
typedef _CoreSessionOpenNative =
    Uint64 Function(
      Pointer<Utf8Char> host,
      Uint16 port,
      Pointer<Utf8Char> username,
      Pointer<Utf8Char> password,
    );
typedef _CoreSessionOpenDart =
    int Function(
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
typedef _CoreSessionWriteNative =
    Int32 Function(Uint64 sessionId, Pointer<Uint8> data, Uint64 len);
typedef _CoreSessionWriteDart =
    int Function(int sessionId, Pointer<Uint8> data, int len);

// core_session_resize
typedef _CoreSessionResizeNative =
    Int32 Function(Uint64 sessionId, Uint16 cols, Uint16 rows);
typedef _CoreSessionResizeDart =
    int Function(int sessionId, int cols, int rows);

// core_session_state
typedef _CoreSessionStateNative = Pointer<Utf8Char> Function(Uint64 sessionId);
typedef _CoreSessionStateDart = Pointer<Utf8Char> Function(int sessionId);

// core_session_mouse_event
typedef _CoreSessionMouseEventNative =
    Int32 Function(
      Uint64 sessionId,
      Uint8 eventType,
      Uint8 button,
      Uint16 col,
      Uint16 row,
      Bool shift,
      Bool meta,
      Bool ctrl,
    );
typedef _CoreSessionMouseEventDart =
    int Function(
      int sessionId,
      int eventType,
      int button,
      int col,
      int row,
      bool shift,
      bool meta,
      bool ctrl,
    );

// core_session_reconnect
typedef _CoreSessionReconnectNative = Int32 Function(Uint64 sessionId);
typedef _CoreSessionReconnectDart = int Function(int sessionId);

// core_session_reconnect_attempts
typedef _CoreSessionReconnectAttemptsNative = Uint32 Function(Uint64 sessionId);
typedef _CoreSessionReconnectAttemptsDart = int Function(int sessionId);

// core_session_can_reconnect
typedef _CoreSessionCanReconnectNative = Bool Function(Uint64 sessionId);
typedef _CoreSessionCanReconnectDart = bool Function(int sessionId);

// core_session_last_error
typedef _CoreSessionLastErrorNative =
    Pointer<Utf8Char> Function(Uint64 sessionId);
typedef _CoreSessionLastErrorDart = Pointer<Utf8Char> Function(int sessionId);

typedef _CoreSessionPortForwardStatusNative =
    Pointer<Utf8Char> Function(Uint64 sessionId);
typedef _CoreSessionPortForwardStatusDart =
    Pointer<Utf8Char> Function(int sessionId);

// core_session_check_timeout
typedef _CoreSessionCheckTimeoutNative = Bool Function(Uint64 sessionId);
typedef _CoreSessionCheckTimeoutDart = bool Function(int sessionId);

// core_local_shell_open
typedef _CoreLocalShellOpenNative =
    Uint64 Function(
      Pointer<Utf8Char> shell,
      Pointer<Utf8Char> workingDir,
      Uint16 cols,
      Uint16 rows,
    );
typedef _CoreLocalShellOpenDart =
    int Function(
      Pointer<Utf8Char> shell,
      Pointer<Utf8Char> workingDir,
      int cols,
      int rows,
    );

// core_local_shell_close
typedef _CoreLocalShellCloseNative = Void Function(Uint64 sessionId);
typedef _CoreLocalShellCloseDart = void Function(int sessionId);

// core_local_shell_read
typedef _CoreLocalShellReadNative =
    Pointer<Utf8Char> Function(Uint64 sessionId);
typedef _CoreLocalShellReadDart = Pointer<Utf8Char> Function(int sessionId);

// core_local_shell_write
typedef _CoreLocalShellWriteNative =
    Int32 Function(Uint64 sessionId, Pointer<Uint8> data, Uint64 len);
typedef _CoreLocalShellWriteDart =
    int Function(int sessionId, Pointer<Uint8> data, int len);

// core_local_shell_resize
typedef _CoreLocalShellResizeNative =
    Int32 Function(Uint64 sessionId, Uint16 cols, Uint16 rows);
typedef _CoreLocalShellResizeDart =
    int Function(int sessionId, int cols, int rows);

// core_local_shell_state
typedef _CoreLocalShellStateNative =
    Pointer<Utf8Char> Function(Uint64 sessionId);
typedef _CoreLocalShellStateDart = Pointer<Utf8Char> Function(int sessionId);

// core_protocol_*
typedef _CoreProtocolOpenNative =
    Uint64 Function(Pointer<Utf8Char> requestJson);
typedef _CoreProtocolOpenDart = int Function(Pointer<Utf8Char> requestJson);
typedef _CoreProtocolReadNative = Pointer<Utf8Char> Function(Uint64 sessionId);
typedef _CoreProtocolReadDart = Pointer<Utf8Char> Function(int sessionId);
typedef _CoreProtocolWriteNative =
    Int32 Function(Uint64 sessionId, Pointer<Uint8> data, Uint64 len);
typedef _CoreProtocolWriteDart =
    int Function(int sessionId, Pointer<Uint8> data, int len);
typedef _CoreProtocolResizeNative =
    Int32 Function(Uint64 sessionId, Uint16 cols, Uint16 rows);
typedef _CoreProtocolResizeDart =
    int Function(int sessionId, int cols, int rows);
typedef _CoreProtocolStateNative = Pointer<Utf8Char> Function(Uint64 sessionId);
typedef _CoreProtocolStateDart = Pointer<Utf8Char> Function(int sessionId);
typedef _CoreProtocolCloseNative = Void Function(Uint64 sessionId);
typedef _CoreProtocolCloseDart = void Function(int sessionId);
typedef _CoreSerialListPortsNative = Pointer<Utf8Char> Function();
typedef _CoreSerialListPortsDart = Pointer<Utf8Char> Function();
typedef _CoreCryptoTransformNative =
    Pointer<Utf8Char> Function(
      Pointer<Utf8Char> input,
      Pointer<Utf8Char> password,
    );
typedef _CoreCryptoTransformDart =
    Pointer<Utf8Char> Function(
      Pointer<Utf8Char> input,
      Pointer<Utf8Char> password,
    );
typedef _CoreKeychainSetNative =
    Int32 Function(Pointer<Utf8Char> credentialId, Pointer<Utf8Char> secret);
typedef _CoreKeychainSetDart =
    int Function(Pointer<Utf8Char> credentialId, Pointer<Utf8Char> secret);
typedef _CoreKeychainGetNative =
    Pointer<Utf8Char> Function(Pointer<Utf8Char> credentialId);
typedef _CoreKeychainGetDart =
    Pointer<Utf8Char> Function(Pointer<Utf8Char> credentialId);
typedef _CoreKeychainDeleteNative =
    Int32 Function(Pointer<Utf8Char> credentialId);
typedef _CoreKeychainDeleteDart = int Function(Pointer<Utf8Char> credentialId);

typedef _CoreUpdateVerifySignatureNative =
    Bool Function(
      Pointer<Uint8> payload,
      Uint64 payloadLen,
      Pointer<Utf8Char> signature,
      Pointer<Utf8Char> publicKey,
    );
typedef _CoreUpdateVerifySignatureDart =
    bool Function(
      Pointer<Uint8> payload,
      int payloadLen,
      Pointer<Utf8Char> signature,
      Pointer<Utf8Char> publicKey,
    );
typedef _CoreUpdateVerifySha256Native =
    Bool Function(
      Pointer<Uint8> data,
      Uint64 dataLen,
      Pointer<Utf8Char> expected,
    );
typedef _CoreUpdateVerifySha256Dart =
    bool Function(Pointer<Uint8> data, int dataLen, Pointer<Utf8Char> expected);
typedef _CoreUpdateVerifyFileSha256Native =
    Bool Function(Pointer<Utf8Char> path, Pointer<Utf8Char> expected);
typedef _CoreUpdateVerifyFileSha256Dart =
    bool Function(Pointer<Utf8Char> path, Pointer<Utf8Char> expected);

// core_string_free
typedef _CoreStringFreeNative = Void Function(Pointer<Utf8Char> ptr);
typedef _CoreStringFreeDart = void Function(Pointer<Utf8Char> ptr);

// core_sftp_open
typedef _CoreSftpOpenNative = Uint64 Function(Uint64 sessionId);
typedef _CoreSftpOpenDart = int Function(int sessionId);

// core_sftp_close
typedef _CoreSftpCloseNative = Void Function(Uint64 sftpId);
typedef _CoreSftpCloseDart = void Function(int sftpId);

// core_sftp_list_dir
typedef _CoreSftpListDirNative =
    Pointer<Utf8Char> Function(Uint64 sftpId, Pointer<Utf8Char> path);
typedef _CoreSftpListDirDart =
    Pointer<Utf8Char> Function(int sftpId, Pointer<Utf8Char> path);

// core_sftp_stat
typedef _CoreSftpStatNative =
    Pointer<Utf8Char> Function(Uint64 sftpId, Pointer<Utf8Char> path);
typedef _CoreSftpStatDart =
    Pointer<Utf8Char> Function(int sftpId, Pointer<Utf8Char> path);

// core_sftp_mkdir
typedef _CoreSftpMkdirNative =
    Int32 Function(Uint64 sftpId, Pointer<Utf8Char> path, Int32 mode);
typedef _CoreSftpMkdirDart =
    int Function(int sftpId, Pointer<Utf8Char> path, int mode);

// core_sftp_unlink
typedef _CoreSftpUnlinkNative =
    Int32 Function(Uint64 sftpId, Pointer<Utf8Char> path);
typedef _CoreSftpUnlinkDart = int Function(int sftpId, Pointer<Utf8Char> path);

// core_sftp_rmdir
typedef _CoreSftpRmdirNative =
    Int32 Function(Uint64 sftpId, Pointer<Utf8Char> path);
typedef _CoreSftpRmdirDart = int Function(int sftpId, Pointer<Utf8Char> path);

// core_sftp_rename
typedef _CoreSftpRenameNative =
    Int32 Function(Uint64 sftpId, Pointer<Utf8Char> src, Pointer<Utf8Char> dst);
typedef _CoreSftpRenameDart =
    int Function(int sftpId, Pointer<Utf8Char> src, Pointer<Utf8Char> dst);

// core_sftp_chmod
typedef _CoreSftpChmodNative =
    Int32 Function(Uint64 sftpId, Pointer<Utf8Char> path, Int32 mode);
typedef _CoreSftpChmodDart =
    int Function(int sftpId, Pointer<Utf8Char> path, int mode);

// core_sftp_upload
typedef _CoreSftpUploadNative =
    Int32 Function(
      Uint64 sftpId,
      Pointer<Utf8Char> localPath,
      Pointer<Utf8Char> remotePath,
    );
typedef _CoreSftpUploadDart =
    int Function(
      int sftpId,
      Pointer<Utf8Char> localPath,
      Pointer<Utf8Char> remotePath,
    );

// core_sftp_download
typedef _CoreSftpDownloadNative =
    Int32 Function(
      Uint64 sftpId,
      Pointer<Utf8Char> remotePath,
      Pointer<Utf8Char> localPath,
    );
typedef _CoreSftpDownloadDart =
    int Function(
      int sftpId,
      Pointer<Utf8Char> remotePath,
      Pointer<Utf8Char> localPath,
    );

typedef _CoreSftpTransferStartNative =
    Uint64 Function(
      Uint64 sftpId,
      Pointer<Utf8Char> localPath,
      Pointer<Utf8Char> remotePath,
      Bool isUpload,
    );
typedef _CoreSftpTransferStartDart =
    int Function(
      int sftpId,
      Pointer<Utf8Char> localPath,
      Pointer<Utf8Char> remotePath,
      bool isUpload,
    );
typedef _CoreSftpTransferStatusNative =
    Pointer<Utf8Char> Function(Uint64 transferId);
typedef _CoreSftpTransferStatusDart =
    Pointer<Utf8Char> Function(int transferId);
typedef _CoreSftpTransferCancelNative = Int32 Function(Uint64 transferId);
typedef _CoreSftpTransferCancelDart = int Function(int transferId);

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

/// RGB 颜色值
class RgbColor {
  final int r;
  final int g;
  final int b;
  const RgbColor(this.r, this.g, this.b);
}

/// 256 色索引颜色值
class IndexedColor {
  final int index;
  const IndexedColor(this.index);
}

// SFTP 文件类型
enum SftpFileType { file, directory, symlink, other }

/// SFTP 文件信息
class SftpFileInfo {
  final String name;
  final String path;
  final SftpFileType fileType;
  final int size;
  final int permissions;
  final int? modified;
  final int? accessed;
  final bool isDir;
  final bool isFile;
  final bool isSymlink;

  const SftpFileInfo({
    required this.name,
    required this.path,
    required this.fileType,
    required this.size,
    required this.permissions,
    this.modified,
    this.accessed,
    required this.isDir,
    required this.isFile,
    required this.isSymlink,
  });

  factory SftpFileInfo.fromJson(Map<String, dynamic> json) {
    SftpFileType fileType;
    switch (json['file_type']) {
      case 'File':
        fileType = SftpFileType.file;
        break;
      case 'Directory':
        fileType = SftpFileType.directory;
        break;
      case 'Symlink':
        fileType = SftpFileType.symlink;
        break;
      default:
        fileType = SftpFileType.other;
    }

    return SftpFileInfo(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      fileType: fileType,
      size: json['size'] ?? 0,
      permissions: json['permissions'] ?? 0,
      modified: json['modified'],
      accessed: json['accessed'],
      isDir: json['is_dir'] ?? false,
      isFile: json['is_file'] ?? false,
      isSymlink: json['is_symlink'] ?? false,
    );
  }

  String get permissionsString {
    // 转换为 rwxrwxrwx 格式
    final mode = permissions & 0x1FF; // 0o777 = 511 = 0x1FF
    final owner = _permissionBits(mode >> 6);
    final group = _permissionBits((mode >> 3) & 7);
    final other = _permissionBits(mode & 7);
    return '$owner$group$other';
  }

  String _permissionBits(int bits) {
    return '${bits & 4 != 0 ? 'r' : '-'}'
        '${bits & 2 != 0 ? 'w' : '-'}'
        '${bits & 1 != 0 ? 'x' : '-'}';
  }

  String get sizeString {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get modifiedString {
    if (modified == null) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(modified! * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

enum SftpTransferState { queued, running, completed, failed, canceled }

class SftpTransferTask {
  const SftpTransferTask({
    required this.id,
    required this.localPath,
    required this.remotePath,
    required this.isUpload,
    required this.state,
    required this.totalBytes,
    required this.transferredBytes,
    required this.speed,
    this.error,
  });

  final int id;
  final String localPath;
  final String remotePath;
  final bool isUpload;
  final SftpTransferState state;
  final int totalBytes;
  final int transferredBytes;
  final double speed;
  final String? error;

  double get progress =>
      totalBytes == 0 ? 0 : (transferredBytes / totalBytes).clamp(0.0, 1.0);

  factory SftpTransferTask.fromJson(Map<String, dynamic> json) {
    final rawState = json['state'];
    var state = SftpTransferState.queued;
    String? error;
    if (rawState is String) {
      state = switch (rawState) {
        'Queued' => SftpTransferState.queued,
        'Running' => SftpTransferState.running,
        'Completed' => SftpTransferState.completed,
        'Canceled' => SftpTransferState.canceled,
        _ => SftpTransferState.failed,
      };
    } else if (rawState is Map && rawState['Failed'] != null) {
      state = SftpTransferState.failed;
      error = rawState['Failed'].toString();
    }
    return SftpTransferTask(
      id: json['id'] ?? 0,
      localPath: json['local_path'] ?? '',
      remotePath: json['remote_path'] ?? '',
      isUpload: json['is_upload'] ?? false,
      state: state,
      totalBytes: json['total_bytes'] ?? 0,
      transferredBytes: json['transferred_bytes'] ?? 0,
      speed: (json['speed'] ?? 0).toDouble(),
      error: error,
    );
  }
}

// 终端单元格属性
class CellAttr {
  final TerminalColor fg;
  final TerminalColor bg;
  final RgbColor? fgRgb;
  final RgbColor? bgRgb;
  final IndexedColor? fgIndexed;
  final IndexedColor? bgIndexed;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool inverse;

  const CellAttr({
    this.fg = TerminalColor.defaultColor,
    this.bg = TerminalColor.defaultColor,
    this.fgRgb,
    this.bgRgb,
    this.fgIndexed,
    this.bgIndexed,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.inverse = false,
  });

  factory CellAttr.fromJson(Map<String, dynamic> json) {
    final fgResult = _parseColorFull(json['fg']);
    final bgResult = _parseColorFull(json['bg']);
    return CellAttr(
      fg: fgResult.$1,
      bg: bgResult.$1,
      fgRgb: fgResult.$2,
      bgRgb: bgResult.$2,
      fgIndexed: fgResult.$3,
      bgIndexed: bgResult.$3,
      bold: json['bold'] ?? false,
      italic: json['italic'] ?? false,
      underline: json['underline'] ?? false,
      inverse: json['inverse'] ?? false,
    );
  }

  /// 返回 (TerminalColor, RgbColor?, IndexedColor?)
  static (TerminalColor, RgbColor?, IndexedColor?) _parseColorFull(
    dynamic colorJson,
  ) {
    if (colorJson is Map) {
      if (colorJson.containsKey('Rgb')) {
        final rgb = colorJson['Rgb'] as List;
        return (TerminalColor.rgb, RgbColor(rgb[0], rgb[1], rgb[2]), null);
      }
      if (colorJson.containsKey('Indexed')) {
        final idx = colorJson['Indexed'] as int;
        return (TerminalColor.indexed, null, IndexedColor(idx));
      }
    }
    if (colorJson is String) {
      switch (colorJson) {
        case 'Default':
          return (TerminalColor.defaultColor, null, null);
        case 'Black':
          return (TerminalColor.black, null, null);
        case 'Red':
          return (TerminalColor.red, null, null);
        case 'Green':
          return (TerminalColor.green, null, null);
        case 'Yellow':
          return (TerminalColor.yellow, null, null);
        case 'Blue':
          return (TerminalColor.blue, null, null);
        case 'Magenta':
          return (TerminalColor.magenta, null, null);
        case 'Cyan':
          return (TerminalColor.cyan, null, null);
        case 'White':
          return (TerminalColor.white, null, null);
        case 'BrightBlack':
          return (TerminalColor.brightBlack, null, null);
        case 'BrightRed':
          return (TerminalColor.brightRed, null, null);
        case 'BrightGreen':
          return (TerminalColor.brightGreen, null, null);
        case 'BrightYellow':
          return (TerminalColor.brightYellow, null, null);
        case 'BrightBlue':
          return (TerminalColor.brightBlue, null, null);
        case 'BrightMagenta':
          return (TerminalColor.brightMagenta, null, null);
        case 'BrightCyan':
          return (TerminalColor.brightCyan, null, null);
        case 'BrightWhite':
          return (TerminalColor.brightWhite, null, null);
        default:
          return (TerminalColor.defaultColor, null, null);
      }
    }
    return (TerminalColor.defaultColor, null, null);
  }
}

// 终端单元格
class TerminalCell {
  final String ch;
  final CellAttr attr;

  /// 宽字符标记：0=正常，1=宽字符首字符，2=宽字符续字符（占位）
  final int wide;

  const TerminalCell({
    this.ch = ' ',
    this.attr = const CellAttr(),
    this.wide = 0,
  });

  factory TerminalCell.fromJson(Map<String, dynamic> json) {
    final chRaw = json['ch'];
    String ch;
    if (chRaw == null || chRaw == '\u0000') {
      ch = ' '; // 占位符映射为空格
    } else {
      ch = chRaw;
    }
    return TerminalCell(
      ch: ch,
      attr: CellAttr.fromJson(json['attr'] ?? {}),
      wide: json['wide'] ?? 0,
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
  final List<TerminalLine> scrollback;
  final int scrollOffset;
  final String outputText;
  final bool applicationCursorMode;
  final bool bracketedPaste;

  const TerminalSnapshot({
    required this.cols,
    required this.rows,
    required this.cursorRow,
    required this.cursorCol,
    required this.cursorVisible,
    required this.lines,
    this.scrollback = const [],
    this.scrollOffset = 0,
    this.outputText = '',
    this.applicationCursorMode = false,
    this.bracketedPaste = false,
  });

  factory TerminalSnapshot.fromJson(Map<String, dynamic> json) {
    final linesJson = json['lines'] as List<dynamic>? ?? [];
    final scrollbackJson = json['scrollback'] as List<dynamic>? ?? [];
    return TerminalSnapshot(
      cols: json['cols'] ?? 0,
      rows: json['rows'] ?? 0,
      cursorRow: json['cursor_row'] ?? 0,
      cursorCol: json['cursor_col'] ?? 0,
      cursorVisible: json['cursor_visible'] ?? true,
      lines: linesJson.map((l) => TerminalLine.fromJson(l)).toList(),
      scrollback: scrollbackJson.map((l) => TerminalLine.fromJson(l)).toList(),
      scrollOffset: json['scroll_offset'] ?? 0,
      outputText: json['output_text'] ?? '',
      applicationCursorMode: json['application_cursor_mode'] ?? false,
      bracketedPaste: json['bracketed_paste'] ?? false,
    );
  }
}

// 鼠标事件类型
enum TerminalMouseEventType { press, release, motion }

// 鼠标按键
enum TerminalMouseButton { left, middle, right, none }

class PortForwardStatus {
  const PortForwardStatus({
    required this.type,
    required this.bindAddress,
    required this.bindPort,
    this.remoteHost,
    this.remotePort,
    required this.state,
    required this.activeConnections,
    required this.totalConnections,
    required this.uploadedBytes,
    required this.downloadedBytes,
    this.lastError,
  });

  final String type;
  final String bindAddress;
  final int bindPort;
  final String? remoteHost;
  final int? remotePort;
  final String state;
  final int activeConnections;
  final int totalConnections;
  final int uploadedBytes;
  final int downloadedBytes;
  final String? lastError;

  factory PortForwardStatus.fromJson(Map<String, dynamic> json) {
    return PortForwardStatus(
      type: json['forwardType'] as String? ?? 'local',
      bindAddress: json['bindAddress'] as String? ?? '',
      bindPort: json['bindPort'] as int? ?? 0,
      remoteHost: json['remoteHost'] as String?,
      remotePort: json['remotePort'] as int?,
      state: json['state'] as String? ?? 'unknown',
      activeConnections: json['activeConnections'] as int? ?? 0,
      totalConnections: json['totalConnections'] as int? ?? 0,
      uploadedBytes: json['uploadedBytes'] as int? ?? 0,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      lastError: json['lastError'] as String?,
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

  /// 发送鼠标事件
  int sendMouseEvent({
    required TerminalMouseEventType eventType,
    required TerminalMouseButton button,
    required int col,
    required int row,
    bool shift = false,
    bool meta = false,
    bool ctrl = false,
  }) {
    return _core.sessionMouseEvent(
      id,
      eventType,
      button,
      col,
      row,
      shift,
      meta,
      ctrl,
    );
  }

  /// 尝试重新连接
  int reconnect() {
    return _core.sessionReconnect(id);
  }

  /// 获取重连次数
  int getReconnectAttempts() {
    return _core.sessionReconnectAttempts(id);
  }

  /// 检查是否可以重连
  bool canReconnect() {
    return _core.sessionCanReconnect(id);
  }

  /// 获取最后错误信息
  String? getLastError() {
    return _core.sessionLastError(id);
  }

  List<PortForwardStatus> portForwardStatus() {
    return _core.sessionPortForwardStatus(id);
  }

  /// 检查连接超时
  bool checkTimeout() {
    return _core.sessionCheckTimeout(id);
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

// 本地 Shell Session 封装
class LocalShellSession {
  final int id;
  final RustCore _core;
  String _state;

  LocalShellSession(this.id, this._core) : _state = 'created';

  String get state => _state;

  /// 读取终端输出
  TerminalSnapshot? readOutput() {
    return _core.localShellRead(id);
  }

  /// 发送输入
  int writeInput(String data) {
    final bytes = utf8.encode(data);
    return _core.localShellWrite(id, bytes);
  }

  /// 发送原始字节
  int writeBytes(Uint8List bytes) {
    return _core.localShellWrite(id, bytes);
  }

  int sendMouseEvent({
    required TerminalMouseEventType eventType,
    required TerminalMouseButton button,
    required int col,
    required int row,
    bool shift = false,
    bool meta = false,
    bool ctrl = false,
  }) {
    return _core.sessionMouseEvent(
      id,
      eventType,
      button,
      col,
      row,
      shift,
      meta,
      ctrl,
    );
  }

  /// 调整终端大小
  int resize(int cols, int rows) {
    return _core.localShellResize(id, cols, rows);
  }

  /// 获取状态
  String getState() {
    _state = _core.localShellState(id);
    return _state;
  }

  /// 关闭会话
  void close() {
    _core.localShellClose(id);
  }
}

/// Telnet、Raw TCP 和 Serial 共用的终端会话封装。
class ProtocolSession {
  final int id;
  final RustCore _core;

  ProtocolSession(this.id, this._core);

  TerminalSnapshot? readOutput() => _core.protocolRead(id);

  int writeInput(String data) => _core.protocolWrite(id, utf8.encode(data));

  int writeBytes(Uint8List bytes) => _core.protocolWrite(id, bytes);

  int sendMouseEvent({
    required TerminalMouseEventType eventType,
    required TerminalMouseButton button,
    required int col,
    required int row,
    bool shift = false,
    bool meta = false,
    bool ctrl = false,
  }) {
    return _core.sessionMouseEvent(
      id,
      eventType,
      button,
      col,
      row,
      shift,
      meta,
      ctrl,
    );
  }

  int resize(int cols, int rows) => _core.protocolResize(id, cols, rows);

  String getState() => _core.protocolState(id);

  void close() => _core.protocolClose(id);
}

/// SFTP 会话封装
class SftpSession {
  final int id;
  final RustCore _core;

  SftpSession(this.id, this._core);

  /// 列出目录内容
  List<SftpFileInfo> listDir(String path) {
    return _core.sftpListDir(id, path);
  }

  /// 获取文件信息
  SftpFileInfo? stat(String path) {
    return _core.sftpStat(id, path);
  }

  /// 创建目录
  int mkdir(String path, {int mode = 0x1ED}) {
    // 0o755 = 493 = 0x1ED
    return _core.sftpMkdir(id, path, mode);
  }

  /// 删除文件
  int unlink(String path) {
    return _core.sftpUnlink(id, path);
  }

  /// 删除目录
  int rmdir(String path) {
    return _core.sftpRmdir(id, path);
  }

  /// 重命名/移动
  int rename(String src, String dst) {
    return _core.sftpRename(id, src, dst);
  }

  /// 修改权限
  int chmod(String path, int mode) {
    return _core.sftpChmod(id, path, mode);
  }

  /// 上传文件
  int upload(String localPath, String remotePath) {
    return _core.sftpUpload(id, localPath, remotePath);
  }

  /// 下载文件
  int download(String remotePath, String localPath) {
    return _core.sftpDownload(id, remotePath, localPath);
  }

  int startUpload(String localPath, String remotePath) {
    return _core.sftpTransferStart(id, localPath, remotePath, true);
  }

  int startDownload(String remotePath, String localPath) {
    return _core.sftpTransferStart(id, localPath, remotePath, false);
  }

  SftpTransferTask? transferStatus(int transferId) {
    return _core.sftpTransferStatus(transferId);
  }

  int cancelTransfer(int transferId) {
    return _core.sftpTransferCancel(transferId);
  }

  /// 关闭会话
  void close() {
    _core.sftpClose(id);
  }
}

// Rust Core 主类
abstract class RustCore {
  String get version;

  SshSession attachSession(int sessionId);

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
  int sessionMouseEvent(
    int sessionId,
    TerminalMouseEventType eventType,
    TerminalMouseButton button,
    int col,
    int row,
    bool shift,
    bool meta,
    bool ctrl,
  );
  int sessionReconnect(int sessionId);
  int sessionReconnectAttempts(int sessionId);
  bool sessionCanReconnect(int sessionId);
  String? sessionLastError(int sessionId);
  List<PortForwardStatus> sessionPortForwardStatus(int sessionId);
  bool sessionCheckTimeout(int sessionId);
  void sessionClose(int sessionId);

  // 本地 Shell API
  LocalShellSession openLocalShell({
    required String shell,
    String? workingDir,
    int cols = 80,
    int rows = 24,
  });
  TerminalSnapshot? localShellRead(int sessionId);
  int localShellWrite(int sessionId, List<int> data);
  int localShellResize(int sessionId, int cols, int rows);
  String localShellState(int sessionId);
  void localShellClose(int sessionId);

  // Telnet / Raw TCP / Serial API
  ProtocolSession openProtocol(Map<String, Object?> request);
  TerminalSnapshot? protocolRead(int sessionId);
  int protocolWrite(int sessionId, List<int> data);
  int protocolResize(int sessionId, int cols, int rows);
  String protocolState(int sessionId);
  void protocolClose(int sessionId);
  List<String> serialListPorts();
  String encryptCredential(String plaintext, String password);
  String decryptCredential(String encryptedJson, String password);
  bool keychainSet(String credentialId, String secret);
  String? keychainGet(String credentialId);
  bool keychainDelete(String credentialId);
  bool verifyUpdateSignature(
    Uint8List payload,
    String signature,
    String publicKey,
  );
  bool verifyUpdateSha256(Uint8List data, String expectedHex);
  bool verifyUpdateFileSha256(String path, String expectedHex);

  // SFTP API
  SftpSession openSftp(int sessionId);
  List<SftpFileInfo> sftpListDir(int sftpId, String path);
  SftpFileInfo? sftpStat(int sftpId, String path);
  int sftpMkdir(int sftpId, String path, int mode);
  int sftpUnlink(int sftpId, String path);
  int sftpRmdir(int sftpId, String path);
  int sftpRename(int sftpId, String src, String dst);
  int sftpChmod(int sftpId, String path, int mode);
  int sftpUpload(int sftpId, String localPath, String remotePath);
  int sftpDownload(int sftpId, String remotePath, String localPath);
  int sftpTransferStart(
    int sftpId,
    String localPath,
    String remotePath,
    bool isUpload,
  );
  SftpTransferTask? sftpTransferStatus(int transferId);
  int sftpTransferCancel(int transferId);
  void sftpClose(int sftpId);

  static RustCore load() {
    final DynamicLibrary? library = _tryOpenLibrary();
    if (library == null) {
      return const DartMockCore();
    }
    try {
      return NativeRustCore(library);
    } on ArgumentError {
      // An older bundled library may load successfully but expose an
      // incompatible ABI. Keep the UI usable until the native library is rebuilt.
      return const DartMockCore();
    }
  }

  static DynamicLibrary? _tryOpenLibrary() {
    final List<String> candidates = libraryCandidates();
    for (final String candidate in candidates) {
      try {
        return DynamicLibrary.open(candidate);
      } on Object {
        continue;
      }
    }
    return null;
  }

  static List<String> libraryCandidates() {
    final String cwd = Directory.current.path;
    final String executableDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isMacOS) {
      return <String>[
        '$executableDir/../Frameworks/librust_core.dylib',
        '$cwd/rust/target/debug/librust_core.dylib',
        '$cwd/rust/target/release/librust_core.dylib',
        '$cwd/../rust/target/debug/librust_core.dylib',
        '$cwd/../rust/target/release/librust_core.dylib',
        '$cwd/target/debug/librust_core.dylib',
        '$cwd/target/release/librust_core.dylib',
        'librust_core.dylib',
      ];
    }
    if (Platform.isLinux) {
      return <String>[
        '$executableDir/lib/librust_core.so',
        '$cwd/rust/target/debug/librust_core.so',
        '$cwd/rust/target/release/librust_core.so',
        '$cwd/../rust/target/debug/librust_core.so',
        '$cwd/../rust/target/release/librust_core.so',
        '$cwd/target/debug/librust_core.so',
        '$cwd/target/release/librust_core.so',
        'librust_core.so',
      ];
    }
    if (Platform.isWindows) {
      return <String>[
        '$executableDir\\rust_core.dll',
        r'rust\target\debug\rust_core.dll',
        r'rust\target\release\rust_core.dll',
        r'..\rust\target\debug\rust_core.dll',
        r'..\rust\target\release\rust_core.dll',
        r'target\debug\rust_core.dll',
        r'target\release\rust_core.dll',
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
      _sessionOpen = library
          .lookupFunction<_CoreSessionOpenNative, _CoreSessionOpenDart>(
            'core_session_open',
          ),
      _sessionClose = library
          .lookupFunction<_CoreSessionCloseNative, _CoreSessionCloseDart>(
            'core_session_close',
          ),
      _sessionRead = library
          .lookupFunction<_CoreSessionReadNative, _CoreSessionReadDart>(
            'core_session_read',
          ),
      _sessionWrite = library
          .lookupFunction<_CoreSessionWriteNative, _CoreSessionWriteDart>(
            'core_session_write',
          ),
      _sessionResize = library
          .lookupFunction<_CoreSessionResizeNative, _CoreSessionResizeDart>(
            'core_session_resize',
          ),
      _sessionState = library
          .lookupFunction<_CoreSessionStateNative, _CoreSessionStateDart>(
            'core_session_state',
          ),
      _sessionMouseEvent = library
          .lookupFunction<
            _CoreSessionMouseEventNative,
            _CoreSessionMouseEventDart
          >('core_session_mouse_event'),
      _sessionReconnect = library
          .lookupFunction<
            _CoreSessionReconnectNative,
            _CoreSessionReconnectDart
          >('core_session_reconnect'),
      _sessionReconnectAttempts = library
          .lookupFunction<
            _CoreSessionReconnectAttemptsNative,
            _CoreSessionReconnectAttemptsDart
          >('core_session_reconnect_attempts'),
      _sessionCanReconnect = library
          .lookupFunction<
            _CoreSessionCanReconnectNative,
            _CoreSessionCanReconnectDart
          >('core_session_can_reconnect'),
      _sessionLastError = library
          .lookupFunction<
            _CoreSessionLastErrorNative,
            _CoreSessionLastErrorDart
          >('core_session_last_error'),
      _sessionPortForwardStatus = library
          .lookupFunction<
            _CoreSessionPortForwardStatusNative,
            _CoreSessionPortForwardStatusDart
          >('core_session_port_forward_status'),
      _sessionCheckTimeout = library
          .lookupFunction<
            _CoreSessionCheckTimeoutNative,
            _CoreSessionCheckTimeoutDart
          >('core_session_check_timeout'),
      _localShellOpen = library
          .lookupFunction<_CoreLocalShellOpenNative, _CoreLocalShellOpenDart>(
            'core_local_shell_open',
          ),
      _localShellClose = library
          .lookupFunction<_CoreLocalShellCloseNative, _CoreLocalShellCloseDart>(
            'core_local_shell_close',
          ),
      _localShellRead = library
          .lookupFunction<_CoreLocalShellReadNative, _CoreLocalShellReadDart>(
            'core_local_shell_read',
          ),
      _localShellWrite = library
          .lookupFunction<_CoreLocalShellWriteNative, _CoreLocalShellWriteDart>(
            'core_local_shell_write',
          ),
      _localShellResize = library
          .lookupFunction<
            _CoreLocalShellResizeNative,
            _CoreLocalShellResizeDart
          >('core_local_shell_resize'),
      _localShellState = library
          .lookupFunction<_CoreLocalShellStateNative, _CoreLocalShellStateDart>(
            'core_local_shell_state',
          ),
      _protocolOpen = library
          .lookupFunction<_CoreProtocolOpenNative, _CoreProtocolOpenDart>(
            'core_protocol_open',
          ),
      _protocolRead = library
          .lookupFunction<_CoreProtocolReadNative, _CoreProtocolReadDart>(
            'core_protocol_read',
          ),
      _protocolWrite = library
          .lookupFunction<_CoreProtocolWriteNative, _CoreProtocolWriteDart>(
            'core_protocol_write',
          ),
      _protocolResize = library
          .lookupFunction<_CoreProtocolResizeNative, _CoreProtocolResizeDart>(
            'core_protocol_resize',
          ),
      _protocolState = library
          .lookupFunction<_CoreProtocolStateNative, _CoreProtocolStateDart>(
            'core_protocol_state',
          ),
      _protocolClose = library
          .lookupFunction<_CoreProtocolCloseNative, _CoreProtocolCloseDart>(
            'core_protocol_close',
          ),
      _serialListPorts = library
          .lookupFunction<_CoreSerialListPortsNative, _CoreSerialListPortsDart>(
            'core_serial_list_ports',
          ),
      _cryptoEncrypt = library
          .lookupFunction<_CoreCryptoTransformNative, _CoreCryptoTransformDart>(
            'core_crypto_encrypt',
          ),
      _cryptoDecrypt = library
          .lookupFunction<_CoreCryptoTransformNative, _CoreCryptoTransformDart>(
            'core_crypto_decrypt',
          ),
      _keychainSet = library
          .lookupFunction<_CoreKeychainSetNative, _CoreKeychainSetDart>(
            'core_keychain_set',
          ),
      _keychainGet = library
          .lookupFunction<_CoreKeychainGetNative, _CoreKeychainGetDart>(
            'core_keychain_get',
          ),
      _keychainDelete = library
          .lookupFunction<_CoreKeychainDeleteNative, _CoreKeychainDeleteDart>(
            'core_keychain_delete',
          ),
      _updateVerifySignature = library
          .lookupFunction<
            _CoreUpdateVerifySignatureNative,
            _CoreUpdateVerifySignatureDart
          >('core_update_verify_signature'),
      _updateVerifySha256 = library
          .lookupFunction<
            _CoreUpdateVerifySha256Native,
            _CoreUpdateVerifySha256Dart
          >('core_update_verify_sha256'),
      _updateVerifyFileSha256 = library
          .lookupFunction<
            _CoreUpdateVerifyFileSha256Native,
            _CoreUpdateVerifyFileSha256Dart
          >('core_update_verify_file_sha256'),
      _sftpOpen = library
          .lookupFunction<_CoreSftpOpenNative, _CoreSftpOpenDart>(
            'core_sftp_open',
          ),
      _sftpClose = library
          .lookupFunction<_CoreSftpCloseNative, _CoreSftpCloseDart>(
            'core_sftp_close',
          ),
      _sftpListDir = library
          .lookupFunction<_CoreSftpListDirNative, _CoreSftpListDirDart>(
            'core_sftp_list_dir',
          ),
      _sftpStat = library
          .lookupFunction<_CoreSftpStatNative, _CoreSftpStatDart>(
            'core_sftp_stat',
          ),
      _sftpMkdir = library
          .lookupFunction<_CoreSftpMkdirNative, _CoreSftpMkdirDart>(
            'core_sftp_mkdir',
          ),
      _sftpUnlink = library
          .lookupFunction<_CoreSftpUnlinkNative, _CoreSftpUnlinkDart>(
            'core_sftp_unlink',
          ),
      _sftpRmdir = library
          .lookupFunction<_CoreSftpRmdirNative, _CoreSftpRmdirDart>(
            'core_sftp_rmdir',
          ),
      _sftpRename = library
          .lookupFunction<_CoreSftpRenameNative, _CoreSftpRenameDart>(
            'core_sftp_rename',
          ),
      _sftpChmod = library
          .lookupFunction<_CoreSftpChmodNative, _CoreSftpChmodDart>(
            'core_sftp_chmod',
          ),
      _sftpUpload = library
          .lookupFunction<_CoreSftpUploadNative, _CoreSftpUploadDart>(
            'core_sftp_upload',
          ),
      _sftpDownload = library
          .lookupFunction<_CoreSftpDownloadNative, _CoreSftpDownloadDart>(
            'core_sftp_download',
          ),
      _sftpTransferStart = library
          .lookupFunction<
            _CoreSftpTransferStartNative,
            _CoreSftpTransferStartDart
          >('core_sftp_transfer_start'),
      _sftpTransferStatus = library
          .lookupFunction<
            _CoreSftpTransferStatusNative,
            _CoreSftpTransferStatusDart
          >('core_sftp_transfer_status'),
      _sftpTransferCancel = library
          .lookupFunction<
            _CoreSftpTransferCancelNative,
            _CoreSftpTransferCancelDart
          >('core_sftp_transfer_cancel'),
      _free = library
          .lookupFunction<_CoreStringFreeNative, _CoreStringFreeDart>(
            'core_string_free',
          );

  final _CoreVersionDart _version;
  final _CoreSessionOpenDart _sessionOpen;
  final _CoreSessionCloseDart _sessionClose;
  final _CoreSessionReadDart _sessionRead;
  final _CoreSessionWriteDart _sessionWrite;
  final _CoreSessionResizeDart _sessionResize;
  final _CoreSessionStateDart _sessionState;
  final _CoreSessionMouseEventDart _sessionMouseEvent;
  final _CoreSessionReconnectDart _sessionReconnect;
  final _CoreSessionReconnectAttemptsDart _sessionReconnectAttempts;
  final _CoreSessionCanReconnectDart _sessionCanReconnect;
  final _CoreSessionLastErrorDart _sessionLastError;
  final _CoreSessionPortForwardStatusDart _sessionPortForwardStatus;
  final _CoreSessionCheckTimeoutDart _sessionCheckTimeout;
  final _CoreLocalShellOpenDart _localShellOpen;
  final _CoreLocalShellCloseDart _localShellClose;
  final _CoreLocalShellReadDart _localShellRead;
  final _CoreLocalShellWriteDart _localShellWrite;
  final _CoreLocalShellResizeDart _localShellResize;
  final _CoreLocalShellStateDart _localShellState;
  final _CoreProtocolOpenDart _protocolOpen;
  final _CoreProtocolReadDart _protocolRead;
  final _CoreProtocolWriteDart _protocolWrite;
  final _CoreProtocolResizeDart _protocolResize;
  final _CoreProtocolStateDart _protocolState;
  final _CoreProtocolCloseDart _protocolClose;
  final _CoreSerialListPortsDart _serialListPorts;
  final _CoreCryptoTransformDart _cryptoEncrypt;
  final _CoreCryptoTransformDart _cryptoDecrypt;
  final _CoreKeychainSetDart _keychainSet;
  final _CoreKeychainGetDart _keychainGet;
  final _CoreKeychainDeleteDart _keychainDelete;
  final _CoreUpdateVerifySignatureDart _updateVerifySignature;
  final _CoreUpdateVerifySha256Dart _updateVerifySha256;
  final _CoreUpdateVerifyFileSha256Dart _updateVerifyFileSha256;
  final _CoreSftpOpenDart _sftpOpen;
  final _CoreSftpCloseDart _sftpClose;
  final _CoreSftpListDirDart _sftpListDir;
  final _CoreSftpStatDart _sftpStat;
  final _CoreSftpMkdirDart _sftpMkdir;
  final _CoreSftpUnlinkDart _sftpUnlink;
  final _CoreSftpRmdirDart _sftpRmdir;
  final _CoreSftpRenameDart _sftpRename;
  final _CoreSftpChmodDart _sftpChmod;
  final _CoreSftpUploadDart _sftpUpload;
  final _CoreSftpDownloadDart _sftpDownload;
  final _CoreSftpTransferStartDart _sftpTransferStart;
  final _CoreSftpTransferStatusDart _sftpTransferStatus;
  final _CoreSftpTransferCancelDart _sftpTransferCancel;
  final _CoreStringFreeDart _free;

  @override
  String get version => _takeString(_version());

  @override
  SshSession attachSession(int sessionId) {
    if (sessionId <= 0 || sessionState(sessionId) == 'unknown') {
      throw ArgumentError.value(sessionId, 'sessionId', 'Unknown SSH session');
    }
    return SshSession(sessionId, this);
  }

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
      malloc.free(hostPtr);
      malloc.free(usernamePtr);
      malloc.free(passwordPtr);
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
    final ptr = malloc.allocate<Uint8>(data.length);
    for (int i = 0; i < data.length; i++) {
      ptr[i] = data[i];
    }
    final result = _sessionWrite(sessionId, ptr, data.length);
    malloc.free(ptr);
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
  int sessionMouseEvent(
    int sessionId,
    TerminalMouseEventType eventType,
    TerminalMouseButton button,
    int col,
    int row,
    bool shift,
    bool meta,
    bool ctrl,
  ) {
    final eventTypeInt = switch (eventType) {
      TerminalMouseEventType.press => 0,
      TerminalMouseEventType.release => 1,
      TerminalMouseEventType.motion => 2,
    };
    final buttonInt = switch (button) {
      TerminalMouseButton.left => 0,
      TerminalMouseButton.middle => 1,
      TerminalMouseButton.right => 2,
      TerminalMouseButton.none => 3,
    };
    return _sessionMouseEvent(
      sessionId,
      eventTypeInt,
      buttonInt,
      col,
      row,
      shift,
      meta,
      ctrl,
    );
  }

  @override
  int sessionReconnect(int sessionId) {
    return _sessionReconnect(sessionId);
  }

  @override
  int sessionReconnectAttempts(int sessionId) {
    return _sessionReconnectAttempts(sessionId);
  }

  @override
  bool sessionCanReconnect(int sessionId) {
    return _sessionCanReconnect(sessionId);
  }

  @override
  String? sessionLastError(int sessionId) {
    final ptr = _sessionLastError(sessionId);
    if (ptr.address == 0) {
      return null;
    }
    return _takeString(ptr);
  }

  @override
  List<PortForwardStatus> sessionPortForwardStatus(int sessionId) {
    final ptr = _sessionPortForwardStatus(sessionId);
    if (ptr.address == 0) return const [];
    final values = jsonDecode(_takeString(ptr)) as List<dynamic>;
    return values
        .map(
          (value) => PortForwardStatus.fromJson(value as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  bool sessionCheckTimeout(int sessionId) {
    return _sessionCheckTimeout(sessionId);
  }

  @override
  void sessionClose(int sessionId) {
    _sessionClose(sessionId);
  }

  @override
  LocalShellSession openLocalShell({
    required String shell,
    String? workingDir,
    int cols = 80,
    int rows = 24,
  }) {
    final shellPtr = _toUtf8(shell);
    final workingDirPtr = workingDir != null ? _toUtf8(workingDir) : nullptr;

    try {
      final sessionId = _localShellOpen(shellPtr, workingDirPtr, cols, rows);
      if (sessionId == 0) {
        throw Exception('Failed to open local shell');
      }
      return LocalShellSession(sessionId, this);
    } finally {
      malloc.free(shellPtr);
      if (workingDirPtr != nullptr) {
        malloc.free(workingDirPtr);
      }
    }
  }

  @override
  TerminalSnapshot? localShellRead(int sessionId) {
    final ptr = _localShellRead(sessionId);
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
  int localShellWrite(int sessionId, List<int> data) {
    final ptr = malloc.allocate<Uint8>(data.length);
    for (int i = 0; i < data.length; i++) {
      ptr[i] = data[i];
    }
    final result = _localShellWrite(sessionId, ptr, data.length);
    malloc.free(ptr);
    return result;
  }

  @override
  int localShellResize(int sessionId, int cols, int rows) {
    return _localShellResize(sessionId, cols, rows);
  }

  @override
  String localShellState(int sessionId) {
    return _takeString(_localShellState(sessionId));
  }

  @override
  void localShellClose(int sessionId) {
    _localShellClose(sessionId);
  }

  @override
  ProtocolSession openProtocol(Map<String, Object?> request) {
    final requestPtr = _toUtf8(jsonEncode(request));
    try {
      final sessionId = _protocolOpen(requestPtr);
      if (sessionId == 0) {
        throw Exception('Failed to open protocol session');
      }
      return ProtocolSession(sessionId, this);
    } finally {
      malloc.free(requestPtr);
    }
  }

  @override
  TerminalSnapshot? protocolRead(int sessionId) {
    final ptr = _protocolRead(sessionId);
    if (ptr.address == 0) {
      return null;
    }
    try {
      return TerminalSnapshot.fromJson(jsonDecode(_takeString(ptr)));
    } on Object {
      return null;
    }
  }

  @override
  int protocolWrite(int sessionId, List<int> data) {
    final ptr = malloc.allocate<Uint8>(data.length);
    try {
      for (int i = 0; i < data.length; i++) {
        ptr[i] = data[i];
      }
      return _protocolWrite(sessionId, ptr, data.length);
    } finally {
      malloc.free(ptr);
    }
  }

  @override
  int protocolResize(int sessionId, int cols, int rows) {
    return _protocolResize(sessionId, cols, rows);
  }

  @override
  String protocolState(int sessionId) {
    return _takeString(_protocolState(sessionId));
  }

  @override
  void protocolClose(int sessionId) {
    _protocolClose(sessionId);
  }

  @override
  List<String> serialListPorts() {
    final ptr = _serialListPorts();
    if (ptr.address == 0) {
      return const <String>[];
    }
    final decoded = jsonDecode(_takeString(ptr)) as List<dynamic>;
    return decoded.cast<String>();
  }

  @override
  String encryptCredential(String plaintext, String password) {
    return _transformCredential(_cryptoEncrypt, plaintext, password);
  }

  @override
  String decryptCredential(String encryptedJson, String password) {
    return _transformCredential(_cryptoDecrypt, encryptedJson, password);
  }

  String _transformCredential(
    _CoreCryptoTransformDart transform,
    String input,
    String password,
  ) {
    final inputPtr = _toUtf8(input);
    final passwordPtr = _toUtf8(password);
    try {
      final result = transform(inputPtr, passwordPtr);
      if (result.address == 0) {
        throw StateError('Credential crypto operation failed');
      }
      return _takeString(result);
    } finally {
      malloc.free(inputPtr);
      malloc.free(passwordPtr);
    }
  }

  @override
  bool keychainSet(String credentialId, String secret) {
    final idPtr = _toUtf8(credentialId);
    final secretPtr = _toUtf8(secret);
    try {
      return _keychainSet(idPtr, secretPtr) == 0;
    } finally {
      malloc.free(idPtr);
      malloc.free(secretPtr);
    }
  }

  @override
  String? keychainGet(String credentialId) {
    final idPtr = _toUtf8(credentialId);
    try {
      final result = _keychainGet(idPtr);
      return result.address == 0 ? null : _takeString(result);
    } finally {
      malloc.free(idPtr);
    }
  }

  @override
  bool keychainDelete(String credentialId) {
    final idPtr = _toUtf8(credentialId);
    try {
      return _keychainDelete(idPtr) == 0;
    } finally {
      malloc.free(idPtr);
    }
  }

  @override
  bool verifyUpdateSignature(
    Uint8List payload,
    String signature,
    String publicKey,
  ) {
    final payloadPtr = malloc.allocate<Uint8>(payload.length);
    final signaturePtr = _toUtf8(signature);
    final publicKeyPtr = _toUtf8(publicKey);
    try {
      payloadPtr.asTypedList(payload.length).setAll(0, payload);
      return _updateVerifySignature(
        payloadPtr,
        payload.length,
        signaturePtr,
        publicKeyPtr,
      );
    } finally {
      malloc.free(payloadPtr);
      malloc.free(signaturePtr);
      malloc.free(publicKeyPtr);
    }
  }

  @override
  bool verifyUpdateSha256(Uint8List data, String expectedHex) {
    final dataPtr = malloc.allocate<Uint8>(data.length);
    final expectedPtr = _toUtf8(expectedHex);
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      return _updateVerifySha256(dataPtr, data.length, expectedPtr);
    } finally {
      malloc.free(dataPtr);
      malloc.free(expectedPtr);
    }
  }

  @override
  bool verifyUpdateFileSha256(String path, String expectedHex) {
    final pathPtr = _toUtf8(path);
    final expectedPtr = _toUtf8(expectedHex);
    try {
      return _updateVerifyFileSha256(pathPtr, expectedPtr);
    } finally {
      malloc.free(pathPtr);
      malloc.free(expectedPtr);
    }
  }

  @override
  SftpSession openSftp(int sessionId) {
    final sftpId = _sftpOpen(sessionId);
    if (sftpId == 0) {
      throw Exception('Failed to open SFTP session');
    }
    return SftpSession(sftpId, this);
  }

  @override
  List<SftpFileInfo> sftpListDir(int sftpId, String path) {
    final pathPtr = _toUtf8(path);
    try {
      final ptr = _sftpListDir(sftpId, pathPtr);
      if (ptr.address == 0) {
        return [];
      }
      final jsonStr = _takeString(ptr);
      final json = jsonDecode(jsonStr) as List;
      return json.map((e) => SftpFileInfo.fromJson(e)).toList();
    } finally {
      malloc.free(pathPtr);
    }
  }

  @override
  SftpFileInfo? sftpStat(int sftpId, String path) {
    final pathPtr = _toUtf8(path);
    try {
      final ptr = _sftpStat(sftpId, pathPtr);
      if (ptr.address == 0) {
        return null;
      }
      final jsonStr = _takeString(ptr);
      final json = jsonDecode(jsonStr);
      return SftpFileInfo.fromJson(json);
    } finally {
      malloc.free(pathPtr);
    }
  }

  @override
  int sftpMkdir(int sftpId, String path, int mode) {
    final pathPtr = _toUtf8(path);
    try {
      return _sftpMkdir(sftpId, pathPtr, mode);
    } finally {
      malloc.free(pathPtr);
    }
  }

  @override
  int sftpUnlink(int sftpId, String path) {
    final pathPtr = _toUtf8(path);
    try {
      return _sftpUnlink(sftpId, pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  @override
  int sftpRmdir(int sftpId, String path) {
    final pathPtr = _toUtf8(path);
    try {
      return _sftpRmdir(sftpId, pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  @override
  int sftpRename(int sftpId, String src, String dst) {
    final srcPtr = _toUtf8(src);
    final dstPtr = _toUtf8(dst);
    try {
      return _sftpRename(sftpId, srcPtr, dstPtr);
    } finally {
      malloc.free(srcPtr);
      malloc.free(dstPtr);
    }
  }

  @override
  int sftpChmod(int sftpId, String path, int mode) {
    final pathPtr = _toUtf8(path);
    try {
      return _sftpChmod(sftpId, pathPtr, mode);
    } finally {
      malloc.free(pathPtr);
    }
  }

  @override
  int sftpUpload(int sftpId, String localPath, String remotePath) {
    final localPtr = _toUtf8(localPath);
    final remotePtr = _toUtf8(remotePath);
    try {
      return _sftpUpload(sftpId, localPtr, remotePtr);
    } finally {
      malloc.free(localPtr);
      malloc.free(remotePtr);
    }
  }

  @override
  int sftpDownload(int sftpId, String remotePath, String localPath) {
    final remotePtr = _toUtf8(remotePath);
    final localPtr = _toUtf8(localPath);
    try {
      return _sftpDownload(sftpId, remotePtr, localPtr);
    } finally {
      malloc.free(remotePtr);
      malloc.free(localPtr);
    }
  }

  @override
  int sftpTransferStart(
    int sftpId,
    String localPath,
    String remotePath,
    bool isUpload,
  ) {
    final localPtr = _toUtf8(localPath);
    final remotePtr = _toUtf8(remotePath);
    try {
      return _sftpTransferStart(sftpId, localPtr, remotePtr, isUpload);
    } finally {
      malloc.free(localPtr);
      malloc.free(remotePtr);
    }
  }

  @override
  SftpTransferTask? sftpTransferStatus(int transferId) {
    final ptr = _sftpTransferStatus(transferId);
    if (ptr.address == 0) return null;
    return SftpTransferTask.fromJson(jsonDecode(_takeString(ptr)));
  }

  @override
  int sftpTransferCancel(int transferId) {
    return _sftpTransferCancel(transferId);
  }

  @override
  void sftpClose(int sftpId) {
    _sftpClose(sftpId);
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
    final ptr = malloc.allocate<Uint8>(units.length + 1).cast<Utf8Char>();
    for (int i = 0; i < units.length; i++) {
      (ptr.cast<Uint8>() + i).value = units[i];
    }
    (ptr.cast<Uint8>() + units.length).value = 0;
    return ptr;
  }
}

// Dart Mock Core 实现（用于无 Rust 库时的开发）
class DartMockCore implements RustCore {
  const DartMockCore();

  static int _nextSessionId = 0;

  @override
  String get version => 'dart fallback core (Rust library not loaded)';

  @override
  SshSession attachSession(int sessionId) {
    return SshSession(sessionId, this);
  }

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
  int sessionMouseEvent(
    int sessionId,
    TerminalMouseEventType eventType,
    TerminalMouseButton button,
    int col,
    int row,
    bool shift,
    bool meta,
    bool ctrl,
  ) {
    // Mock 实现
    return 0;
  }

  @override
  int sessionReconnect(int sessionId) {
    // Mock 实现
    return 0;
  }

  @override
  int sessionReconnectAttempts(int sessionId) {
    // Mock 实现
    return 0;
  }

  @override
  bool sessionCanReconnect(int sessionId) {
    // Mock 实现
    return true;
  }

  @override
  String? sessionLastError(int sessionId) {
    // Mock 实现
    return null;
  }

  @override
  List<PortForwardStatus> sessionPortForwardStatus(int sessionId) {
    return const [];
  }

  @override
  bool sessionCheckTimeout(int sessionId) {
    // Mock 实现
    return false;
  }

  @override
  void sessionClose(int sessionId) {
    // Mock 实现
  }

  @override
  LocalShellSession openLocalShell({
    required String shell,
    String? workingDir,
    int cols = 80,
    int rows = 24,
  }) {
    _nextSessionId++;
    // 返回一个模拟的 session
    return LocalShellSession(_nextSessionId, this);
  }

  @override
  TerminalSnapshot? localShellRead(int sessionId) {
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
  int localShellWrite(int sessionId, List<int> data) {
    return 0;
  }

  @override
  int localShellResize(int sessionId, int cols, int rows) {
    return 0;
  }

  @override
  String localShellState(int sessionId) {
    return 'running';
  }

  @override
  void localShellClose(int sessionId) {
    // Mock 实现
  }

  @override
  ProtocolSession openProtocol(Map<String, Object?> request) {
    _nextSessionId++;
    return ProtocolSession(_nextSessionId, this);
  }

  @override
  TerminalSnapshot? protocolRead(int sessionId) {
    return localShellRead(sessionId);
  }

  @override
  int protocolWrite(int sessionId, List<int> data) => 0;

  @override
  int protocolResize(int sessionId, int cols, int rows) => 0;

  @override
  String protocolState(int sessionId) => 'connected';

  @override
  void protocolClose(int sessionId) {}

  @override
  List<String> serialListPorts() => const <String>[];

  @override
  String encryptCredential(String plaintext, String password) {
    throw StateError('Native credential encryption is unavailable');
  }

  @override
  String decryptCredential(String encryptedJson, String password) {
    throw StateError('Native credential encryption is unavailable');
  }

  @override
  bool keychainSet(String credentialId, String secret) => false;

  @override
  String? keychainGet(String credentialId) => null;

  @override
  bool keychainDelete(String credentialId) => true;

  @override
  bool verifyUpdateSignature(
    Uint8List payload,
    String signature,
    String publicKey,
  ) => false;

  @override
  bool verifyUpdateSha256(Uint8List data, String expectedHex) => false;

  @override
  bool verifyUpdateFileSha256(String path, String expectedHex) => false;

  @override
  SftpSession openSftp(int sessionId) {
    _nextSessionId++;
    return SftpSession(_nextSessionId, this);
  }

  @override
  List<SftpFileInfo> sftpListDir(int sftpId, String path) {
    // Mock 实现
    return [];
  }

  @override
  SftpFileInfo? sftpStat(int sftpId, String path) {
    // Mock 实现
    return null;
  }

  @override
  int sftpMkdir(int sftpId, String path, int mode) {
    return 0;
  }

  @override
  int sftpUnlink(int sftpId, String path) {
    return 0;
  }

  @override
  int sftpRmdir(int sftpId, String path) {
    return 0;
  }

  @override
  int sftpRename(int sftpId, String src, String dst) {
    return 0;
  }

  @override
  int sftpChmod(int sftpId, String path, int mode) {
    return 0;
  }

  @override
  int sftpUpload(int sftpId, String localPath, String remotePath) {
    return 0;
  }

  @override
  int sftpDownload(int sftpId, String remotePath, String localPath) {
    return 0;
  }

  @override
  int sftpTransferStart(
    int sftpId,
    String localPath,
    String remotePath,
    bool isUpload,
  ) {
    _nextSessionId++;
    return _nextSessionId;
  }

  @override
  SftpTransferTask? sftpTransferStatus(int transferId) {
    return SftpTransferTask(
      id: transferId,
      localPath: '',
      remotePath: '',
      isUpload: true,
      state: SftpTransferState.completed,
      totalBytes: 1,
      transferredBytes: 1,
      speed: 0,
    );
  }

  @override
  int sftpTransferCancel(int transferId) => 0;

  @override
  void sftpClose(int sftpId) {
    // Mock 实现
  }
}
