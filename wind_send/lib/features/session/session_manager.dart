import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core_bridge/rust_core.dart';

/// 会话类型
enum SessionType {
  ssh,
  localShell,
}

/// 会话信息
class SessionInfo {
  final int id;
  final String name;
  final SessionType type;
  final dynamic session; // SshSession or LocalShellSession
  final TerminalSnapshot? snapshot;
  final String state;

  const SessionInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.session,
    this.snapshot,
    this.state = 'created',
  });

  SessionInfo copyWith({
    int? id,
    String? name,
    SessionType? type,
    dynamic session,
    TerminalSnapshot? snapshot,
    String? state,
  }) {
    return SessionInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      session: session ?? this.session,
      snapshot: snapshot ?? this.snapshot,
      state: state ?? this.state,
    );
  }
}

/// 会话管理器
class SessionManager {
  final RustCore _core;
  final List<SessionInfo> _sessions = [];
  int _activeSessionIndex = -1;
  Timer? _pollTimer;

  final void Function(List<SessionInfo> sessions) onSessionsChanged;
  final void Function(int activeIndex) onActiveSessionChanged;
  final void Function(TerminalSnapshot snapshot) onSnapshotUpdated;

  SessionManager({
    required this._core,
    required this.onSessionsChanged,
    required this.onActiveSessionChanged,
    required this.onSnapshotUpdated,
  });

  List<SessionInfo> get sessions => List.unmodifiable(_sessions);
  int get activeSessionIndex => _activeSessionIndex;
  SessionInfo? get activeSession =>
      _activeSessionIndex >= 0 && _activeSessionIndex < _sessions.length
          ? _sessions[_activeSessionIndex]
          : null;

  /// 添加 SSH 会话
  Future<SessionInfo> addSshSession({
    required String name,
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    final session = _core.openSession(
      host: host,
      port: port,
      username: username,
      password: password,
    );

    final info = SessionInfo(
      id: session.id,
      name: name,
      type: SessionType.ssh,
      session: session,
      state: 'connecting',
    );

    _sessions.add(info);
    _notifySessionsChanged();

    // 如果是第一个会话，自动激活
    if (_sessions.length == 1) {
      setActiveSession(0);
    }

    return info;
  }

  /// 添加本地 Shell 会话
  SessionInfo addLocalShellSession({
    required String name,
    String? shell,
    String? workingDir,
  }) {
    final session = _core.openLocalShell(
      shell: shell ?? (Platform.isWindows ? 'cmd.exe' : '/bin/bash'),
      workingDir: workingDir,
    );

    final info = SessionInfo(
      id: session.id,
      name: name,
      type: SessionType.localShell,
      session: session,
      state: 'running',
    );

    _sessions.add(info);
    _notifySessionsChanged();

    // 如果是第一个会话，自动激活
    if (_sessions.length == 1) {
      setActiveSession(0);
    }

    return info;
  }

  /// 移除会话
  void removeSession(int index) {
    if (index < 0 || index >= _sessions.length) return;

    final session = _sessions[index];
    if (session.type == SessionType.ssh) {
      (session.session as SshSession).close();
    } else {
      (session.session as LocalShellSession).close();
    }

    _sessions.removeAt(index);

    // 调整活动会话索引
    if (_activeSessionIndex >= _sessions.length) {
      _activeSessionIndex = _sessions.length - 1;
    }

    _notifySessionsChanged();
    _notifyActiveSessionChanged();
  }

  /// 设置活动会话
  void setActiveSession(int index) {
    if (index < 0 || index >= _sessions.length) return;
    _activeSessionIndex = index;
    _notifyActiveSessionChanged();
  }

  /// 发送输入到活动会话
  void writeInput(String data) {
    final session = activeSession;
    if (session == null) return;

    if (session.type == SessionType.ssh) {
      (session.session as SshSession).writeInput(data);
    } else {
      (session.session as LocalShellSession).writeInput(data);
    }
  }

  /// 发送原始字节到活动会话
  void writeBytes(Uint8List bytes) {
    final session = activeSession;
    if (session == null) return;

    if (session.type == SessionType.ssh) {
      (session.session as SshSession).writeBytes(bytes);
    } else {
      (session.session as LocalShellSession).writeBytes(bytes);
    }
  }

  /// 发送鼠标事件到活动会话
  void sendMouseEvent({
    required TerminalMouseEventType eventType,
    required TerminalMouseButton button,
    required int col,
    required int row,
    bool shift = false,
    bool meta = false,
    bool ctrl = false,
  }) {
    final session = activeSession;
    if (session == null) return;

    if (session.type == SessionType.ssh) {
      (session.session as SshSession).sendMouseEvent(
        eventType: eventType,
        button: button,
        col: col,
        row: row,
        shift: shift,
        meta: meta,
        ctrl: ctrl,
      );
    }
  }

  /// 调整活动会话终端大小
  void resize(int cols, int rows) {
    final session = activeSession;
    if (session == null) return;

    if (session.type == SessionType.ssh) {
      (session.session as SshSession).resize(cols, rows);
    } else {
      (session.session as LocalShellSession).resize(cols, rows);
    }
  }

  /// 尝试重新连接活动会话
  int reconnect() {
    final session = activeSession;
    if (session == null) return -1;

    if (session.type == SessionType.ssh) {
      return (session.session as SshSession).reconnect();
    }
    return -1;
  }

  /// 开始轮询输出
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _pollOutput();
    });
  }

  /// 停止轮询
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 轮询输出
  void _pollOutput() {
    for (int i = 0; i < _sessions.length; i++) {
      final session = _sessions[i];
      TerminalSnapshot? snapshot;

      if (session.type == SessionType.ssh) {
        snapshot = (session.session as SshSession).readOutput();
      } else {
        snapshot = (session.session as LocalShellSession).readOutput();
      }

      if (snapshot != null) {
        _sessions[i] = session.copyWith(snapshot: snapshot);

        // 如果是活动会话，通知更新
        if (i == _activeSessionIndex) {
          onSnapshotUpdated(snapshot);
        }
      }
    }
  }

  /// 通知会话列表变化
  void _notifySessionsChanged() {
    onSessionsChanged(_sessions);
  }

  /// 通知活动会话变化
  void _notifyActiveSessionChanged() {
    onActiveSessionChanged(_activeSessionIndex);
  }

  /// 释放资源
  void dispose() {
    stopPolling();
    for (final session in _sessions) {
      if (session.type == SessionType.ssh) {
        (session.session as SshSession).close();
      } else {
        (session.session as LocalShellSession).close();
      }
    }
    _sessions.clear();
  }
}
