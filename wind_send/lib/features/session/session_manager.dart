import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core_bridge/rust_core.dart';
import '../protocol/protocol_config.dart';

/// 会话类型
enum SessionType { ssh, rdp, telnet, tunnel, vnc, localShell, rawTcp, serial }

/// 会话信息
class SessionInfo {
  final int id;
  final String name;
  final SessionType type;
  final dynamic session; // SshSession or LocalShellSession
  final Map<String, Object?>? profileConfig;
  final TerminalSnapshot? snapshot;
  final String state;

  const SessionInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.session,
    this.profileConfig,
    this.snapshot,
    this.state = 'created',
  });

  SessionInfo copyWith({
    int? id,
    String? name,
    SessionType? type,
    dynamic session,
    Map<String, Object?>? profileConfig,
    TerminalSnapshot? snapshot,
    String? state,
  }) {
    return SessionInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      session: session ?? this.session,
      profileConfig: profileConfig ?? this.profileConfig,
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
  bool _syncInput = false;

  final void Function(List<SessionInfo> sessions) onSessionsChanged;
  final void Function(int activeIndex) onActiveSessionChanged;
  final void Function(TerminalSnapshot snapshot) onSnapshotUpdated;
  final void Function(SessionInfo session, TerminalSnapshot snapshot)?
  onSessionOutput;
  final void Function(SessionInfo session)? onReconnectRequired;

  SessionManager({
    required this._core,
    required this.onSessionsChanged,
    required this.onActiveSessionChanged,
    required this.onSnapshotUpdated,
    this.onSessionOutput,
    this.onReconnectRequired,
  });

  List<SessionInfo> get sessions => List.unmodifiable(_sessions);
  int get activeSessionIndex => _activeSessionIndex;
  SessionInfo? get activeSession =>
      _activeSessionIndex >= 0 && _activeSessionIndex < _sessions.length
      ? _sessions[_activeSessionIndex]
      : null;
  bool get syncInput => _syncInput;

  void setSyncInput(bool enabled) {
    _syncInput = enabled;
  }

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

  /// 接管已经由后台 Isolate 建立的 SSH 会话。
  SessionInfo addExistingSshSession({
    required int sessionId,
    required String name,
    Map<String, Object?>? profileConfig,
  }) {
    final session = _core.attachSession(sessionId);
    final info = SessionInfo(
      id: session.id,
      name: name,
      type: SessionType.ssh,
      session: session,
      profileConfig: profileConfig,
      state: session.getState(),
    );

    _sessions.add(info);
    _notifySessionsChanged();
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
      shell:
          shell ??
          (Platform.isWindows
              ? (Platform.environment['COMSPEC'] ?? 'cmd.exe')
              : (Platform.environment['SHELL'] ?? '/bin/sh')),
      workingDir: workingDir,
    );

    final info = SessionInfo(
      id: session.id,
      name: name,
      type: SessionType.localShell,
      session: session,
      profileConfig: <String, Object?>{
        'shell': shell,
        'workingDir': workingDir,
      },
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

  SessionInfo addTelnetSession({
    required String name,
    required TelnetConfig config,
  }) {
    return _addProtocolSession(
      name: name,
      type: SessionType.telnet,
      request: <String, Object?>{'type': 'telnet', 'config': config.toJson()},
    );
  }

  SessionInfo addRawTcpSession({
    required String name,
    required RawTcpConfig config,
  }) {
    return _addProtocolSession(
      name: name,
      type: SessionType.rawTcp,
      request: <String, Object?>{'type': 'raw_tcp', 'config': config.toJson()},
    );
  }

  SessionInfo addSerialSession({
    required String name,
    required SerialConfig config,
  }) {
    return _addProtocolSession(
      name: name,
      type: SessionType.serial,
      request: <String, Object?>{'type': 'serial', 'config': config.toJson()},
    );
  }

  SessionInfo _addProtocolSession({
    required String name,
    required SessionType type,
    required Map<String, Object?> request,
  }) {
    final session = _core.openProtocol(request);
    final info = SessionInfo(
      id: session.id,
      name: name,
      type: type,
      session: session,
      state: session.getState(),
    );
    _sessions.add(info);
    _notifySessionsChanged();
    if (_sessions.length == 1) {
      setActiveSession(0);
    }
    return info;
  }

  SessionInfo addVirtualSession({
    required String name,
    required SessionType type,
    required Map<String, Object?> profileConfig,
  }) {
    final info = SessionInfo(
      id: DateTime.now().microsecondsSinceEpoch,
      name: name,
      type: type,
      session: null,
      profileConfig: profileConfig,
      state: 'saved',
    );
    _sessions.add(info);
    _notifySessionsChanged();
    setActiveSession(_sessions.length - 1);
    return info;
  }

  /// 移除会话
  void removeSession(int index) {
    if (index < 0 || index >= _sessions.length) return;

    final session = _sessions[index];
    _closeSession(session);

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

  void updateProfileConfig(int index, Map<String, Object?> profileConfig) {
    if (index < 0 || index >= _sessions.length) return;
    _sessions[index] = _sessions[index].copyWith(profileConfig: profileConfig);
    _notifySessionsChanged();
  }

  /// 发送输入到活动会话
  void writeInput(String data) {
    final current = activeSession;
    if (current == null) return;
    final targets = _syncInput ? _sessions : <SessionInfo>[current];
    for (final session in targets) {
      switch (session.type) {
        case SessionType.ssh:
          (session.session as SshSession).writeInput(data);
        case SessionType.rdp:
        case SessionType.tunnel:
        case SessionType.vnc:
          break;
        case SessionType.localShell:
          (session.session as LocalShellSession).writeInput(data);
        case SessionType.telnet:
        case SessionType.rawTcp:
        case SessionType.serial:
          (session.session as ProtocolSession).writeInput(data);
      }
    }
  }

  /// 发送原始字节到活动会话
  void writeBytes(Uint8List bytes) {
    final current = activeSession;
    if (current == null) return;
    final targets = _syncInput ? _sessions : <SessionInfo>[current];
    for (final session in targets) {
      switch (session.type) {
        case SessionType.ssh:
          (session.session as SshSession).writeBytes(bytes);
        case SessionType.rdp:
        case SessionType.tunnel:
        case SessionType.vnc:
          break;
        case SessionType.localShell:
          (session.session as LocalShellSession).writeBytes(bytes);
        case SessionType.telnet:
        case SessionType.rawTcp:
        case SessionType.serial:
          (session.session as ProtocolSession).writeBytes(bytes);
      }
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

    switch (session.type) {
      case SessionType.ssh:
        (session.session as SshSession).sendMouseEvent(
          eventType: eventType,
          button: button,
          col: col,
          row: row,
          shift: shift,
          meta: meta,
          ctrl: ctrl,
        );
      case SessionType.rdp:
      case SessionType.tunnel:
      case SessionType.vnc:
        break;
      case SessionType.localShell:
        (session.session as LocalShellSession).sendMouseEvent(
          eventType: eventType,
          button: button,
          col: col,
          row: row,
          shift: shift,
          meta: meta,
          ctrl: ctrl,
        );
      case SessionType.telnet:
      case SessionType.rawTcp:
      case SessionType.serial:
        (session.session as ProtocolSession).sendMouseEvent(
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

    switch (session.type) {
      case SessionType.ssh:
        (session.session as SshSession).resize(cols, rows);
      case SessionType.rdp:
      case SessionType.tunnel:
      case SessionType.vnc:
        break;
      case SessionType.localShell:
        (session.session as LocalShellSession).resize(cols, rows);
      case SessionType.telnet:
      case SessionType.rawTcp:
      case SessionType.serial:
        (session.session as ProtocolSession).resize(cols, rows);
    }
  }

  void resizeSession(int sessionId, int cols, int rows) {
    final index = _sessions.indexWhere((session) => session.id == sessionId);
    if (index < 0) return;
    final previous = _activeSessionIndex;
    _activeSessionIndex = index;
    resize(cols, rows);
    _activeSessionIndex = previous;
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

      switch (session.type) {
        case SessionType.ssh:
          final ssh = session.session as SshSession;
          snapshot = ssh.readOutput();
          final state = ssh.getState();
          if (state != session.state) {
            _sessions[i] = session.copyWith(state: state);
            _notifySessionsChanged();
          }
          if (state == 'disconnected' &&
              session.profileConfig?['autoReconnect'] == true &&
              ssh.canReconnect()) {
            onReconnectRequired?.call(_sessions[i]);
          }
        case SessionType.rdp:
        case SessionType.tunnel:
        case SessionType.vnc:
          snapshot = null;
        case SessionType.localShell:
          snapshot = (session.session as LocalShellSession).readOutput();
        case SessionType.telnet:
        case SessionType.rawTcp:
        case SessionType.serial:
          snapshot = (session.session as ProtocolSession).readOutput();
      }

      if (snapshot != null) {
        final updated = _sessions[i].copyWith(snapshot: snapshot);
        _sessions[i] = updated;
        onSessionOutput?.call(updated, snapshot);

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
      _closeSession(session);
    }
    _sessions.clear();
  }

  void _closeSession(SessionInfo session) {
    switch (session.type) {
      case SessionType.ssh:
        (session.session as SshSession).close();
      case SessionType.rdp:
      case SessionType.tunnel:
      case SessionType.vnc:
        break;
      case SessionType.localShell:
        (session.session as LocalShellSession).close();
      case SessionType.telnet:
      case SessionType.rawTcp:
      case SessionType.serial:
        (session.session as ProtocolSession).close();
    }
  }
}
