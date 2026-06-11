import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core_bridge/rust_core.dart';
import 'features/network/network_config.dart';
import 'features/network/network_settings_page.dart';
import 'features/security/security_config.dart';
import 'features/security/security_settings_page.dart';
import 'features/session/session_editor.dart';
import 'features/session/session_manager.dart';
import 'features/session/session_profile.dart';
import 'features/session/session_tree.dart';
import 'features/session/command_palette.dart';
import 'features/sftp/sftp_panel.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/terminal_settings.dart';
import 'features/terminal/terminal_painter.dart';
import 'features/terminal/terminal_input.dart';
import 'features/terminal/terminal_search.dart';

// ── FFI 类型签名（与 rust_core.dart 保持一致） ──

typedef _SessionOpenNative =
    Uint64 Function(
      Pointer<Utf8Char> host,
      Uint16 port,
      Pointer<Utf8Char> username,
      Pointer<Utf8Char> password,
    );
typedef _SessionOpenDart =
    int Function(
      Pointer<Utf8Char> host,
      int port,
      Pointer<Utf8Char> username,
      Pointer<Utf8Char> password,
    );

typedef _StringFreeNative = Void Function(Pointer<Utf8Char>);
typedef _StringFreeDart = void Function(Pointer<Utf8Char>);

/// 在后台 Isolate 中执行阻塞的 SSH 连接
Future<int> _openSessionIsolate(
  List<String> libCandidates,
  String host,
  int port,
  String username,
  String password,
) {
  return Isolate.run(() {
    // 每个 Isolate 需要自行打开动态库
    DynamicLibrary? lib;
    for (final path in libCandidates) {
      try {
        lib = DynamicLibrary.open(path);
        break;
      } on Object {
        continue;
      }
    }
    if (lib == null) return 0;

    final sessionOpen = lib
        .lookupFunction<_SessionOpenNative, _SessionOpenDart>(
          'core_session_open',
        );
    final stringFree = lib.lookupFunction<_StringFreeNative, _StringFreeDart>(
      'core_string_free',
    );

    Pointer<Utf8Char> toUtf8(String s) {
      final units = utf8.encode(s);
      final p = malloc.allocate<Uint8>(units.length + 1).cast<Utf8Char>();
      for (var i = 0; i < units.length; i++) {
        (p.cast<Uint8>() + i).value = units[i];
      }
      (p.cast<Uint8>() + units.length).value = 0;
      return p;
    }

    final h = toUtf8(host);
    final u = toUtf8(username);
    final pw = toUtf8(password);
    try {
      return sessionOpen(h, port, u, pw);
    } finally {
      stringFree(h);
      stringFree(u);
      stringFree(pw);
    }
  });
}

void main() {
  runApp(const WindSendApp());
}

class WindSendApp extends StatelessWidget {
  const WindSendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WindSend',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2f6fed),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff111318),
        useMaterial3: true,
      ),
      home: const ShellWorkspace(),
    );
  }
}

class ShellWorkspace extends StatefulWidget {
  const ShellWorkspace({super.key});

  @override
  State<ShellWorkspace> createState() => _ShellWorkspaceState();
}

class _ShellWorkspaceState extends State<ShellWorkspace> {
  final RustCore _core = RustCore.load();
  late final SessionManager _sessionManager;
  TerminalSnapshot? _snapshot;
  late final TerminalInputHandler _inputHandler;
  final _focusNode = FocusNode();
  bool _connecting = false;
  int _lastCols = 0;
  int _lastRows = 0;
  String? _selectedText;
  TerminalSettings _settings = const TerminalSettings();
  bool _showSearch = false;
  SearchResult? _searchResult;
  bool _showSftp = false;
  SftpSession? _sftpSession;
  final SessionProfileStore _profileStore = SessionProfileStore('.');
  NetworkConfig _networkConfig = const NetworkConfig();
  SecurityConfig _securityConfig = const SecurityConfig();

  @override
  void initState() {
    super.initState();
    _sessionManager = SessionManager(
      core: _core,
      onSessionsChanged: _onSessionsChanged,
      onActiveSessionChanged: _onActiveSessionChanged,
      onSnapshotUpdated: _onSnapshotUpdated,
    );
    _inputHandler = TerminalInputHandler(
      onInput: _handleInput,
      onCopy: _handleCopy,
      onPaste: _handlePaste,
    );
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      await _profileStore.load();
      setState(() {});
    } catch (e) {
      // 忽略加载错误
    }
  }

  @override
  void dispose() {
    _sessionManager.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleInput(Uint8List data) {
    _sessionManager.writeBytes(data);
  }

  void _handleCopy() {
    final text = _selectedText;
    if (text != null && text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _sessionManager.writeInput(data!.text!);
    }
  }

  void _onSelectionChanged(String text) {
    _selectedText = text;
  }

  void _onMouseEvent(
    TerminalMouseEventType eventType,
    TerminalMouseButton button,
    int col,
    int row,
    bool shift,
    bool meta,
    bool ctrl,
  ) {
    _sessionManager.sendMouseEvent(
      eventType: eventType,
      button: button,
      col: col,
      row: row,
      shift: shift,
      meta: meta,
      ctrl: ctrl,
    );
  }

  void _onSessionsChanged(List<SessionInfo> sessions) {
    setState(() {});
  }

  void _onActiveSessionChanged(int activeIndex) {
    setState(() {
      _snapshot = _sessionManager.activeSession?.snapshot;
    });
  }

  void _onSnapshotUpdated(TerminalSnapshot snapshot) {
    setState(() {
      _snapshot = snapshot;
    });
  }

  void _openSessionEditor() {
    showDialog(
      context: context,
      builder: (context) => SessionEditor(
        onConnect: (config) {
          Navigator.of(context).pop();
          _connect(config);
        },
      ),
    );
  }

  /// 终端区域大小变化时，计算新的行列数并通知 Rust 调整 PTY 大小
  void _onTerminalResize(double width, double height) {
    // 与 terminal_painter.dart 中的常量保持一致
    const cellWidth = 8.0;
    const cellHeight = 16.0;
    const leftPadding = 4.0;
    const topPadding = 4.0;

    final cols = ((width - leftPadding * 2) / cellWidth).floor();
    final rows = ((height - topPadding * 2) / cellHeight).floor();

    if (cols > 0 && rows > 0 && (cols != _lastCols || rows != _lastRows)) {
      _lastCols = cols;
      _lastRows = rows;
      _sessionManager.resize(cols, rows);
    }
  }

  Future<void> _connect(SshConfig config) async {
    setState(() => _connecting = true);

    try {
      // 在后台 Isolate 执行阻塞的 SSH 连接，避免冻结 UI
      // 设置 15 秒超时
      final sessionId =
          await _openSessionIsolate(
            RustCore.libraryCandidates(),
            config.host,
            config.port,
            config.username,
            config.password,
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('连接超时 (15秒)'),
          );

      if (sessionId == 0) {
        throw Exception('连接失败: 返回会话 ID 为 0');
      }

      // 添加到会话管理器
      await _sessionManager.addSshSession(
        name: '${config.username}@${config.host}',
        host: config.host,
        port: config.port,
        username: config.username,
        password: config.password,
      );

      setState(() => _connecting = false);

      // 启动轮询
      _sessionManager.startPolling();

      // 获取焦点以便接收键盘输入
      _focusNode.requestFocus();

      // 连接成功后发送初始终端大小（如果 LayoutBuilder 已经触发过）
      if (_lastCols > 0 && _lastRows > 0) {
        _sessionManager.resize(_lastCols, _lastRows);
      }
    } catch (e) {
      setState(() => _connecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接失败: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _disconnect() {
    _sessionManager.removeSession(_sessionManager.activeSessionIndex);
  }

  void _addLocalShell() {
    _sessionManager.addLocalShellSession(
      name: '本地 Shell ${_sessionManager.sessions.length + 1}',
    );
    _sessionManager.startPolling();
    _focusNode.requestFocus();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          settings: _settings,
          onSettingsChanged: (newSettings) {
            setState(() {
              _settings = newSettings;
            });
          },
        ),
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchResult = null;
      }
    });
  }

  void _onSearchResult(SearchResult? result) {
    setState(() {
      _searchResult = result;
    });
  }

  void _closeSearch() {
    setState(() {
      _showSearch = false;
      _searchResult = null;
    });
  }

  void _toggleSftp() {
    if (_showSftp) {
      setState(() {
        _showSftp = false;
        _sftpSession?.close();
        _sftpSession = null;
      });
    } else {
      // 打开 SFTP 面板（需要已连接的 SSH 会话）
      if (_sessionManager.activeSession?.type == SessionType.ssh) {
        try {
          final sftp = _core.openSftp(_sessionManager.activeSession!.id);
          setState(() {
            _sftpSession = sftp;
            _showSftp = true;
          });
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('打开 SFTP 失败: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先连接 SSH 会话'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    }
  }

  void _openCommandPalette() {
    showDialog(
      context: context,
      builder: (context) => CommandPalette(
        profiles: _profileStore.profiles,
        onSessionSelected: (profile) {
          // 从配置启动会话
          if (profile.type == SessionProfileType.ssh && profile.host != null) {
            _openSessionEditor();
          } else if (profile.type == SessionProfileType.localShell) {
            _addLocalShell();
          }
        },
        onCommand: (command) {
          switch (command) {
            case 'new_ssh':
              _openSessionEditor();
              break;
            case 'new_shell':
              _addLocalShell();
              break;
            case 'settings':
              _openSettings();
              break;
          }
        },
      ),
    );
  }

  void _openNetworkSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NetworkSettingsPage(
          config: _networkConfig,
          onConfigChanged: (newConfig) {
            setState(() {
              _networkConfig = newConfig;
            });
          },
        ),
      ),
    );
  }

  void _openSecuritySettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SecuritySettingsPage(
          config: _securityConfig,
          onConfigChanged: (newConfig) {
            setState(() {
              _securityConfig = newConfig;
            });
          },
        ),
      ),
    );
  }

  void _saveSessionAsProfile(SessionInfo session) {
    final profile = SessionProfile(
      id: session.id.toString(),
      name: session.name,
      type: session.type == SessionType.ssh
          ? SessionProfileType.ssh
          : SessionProfileType.localShell,
    );
    _profileStore.add(profile);
    _profileStore.save();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('会话已保存: ${session.name}')),
    );
  }

  void _connectFromProfile(SessionProfile profile) {
    if (profile.type == SessionProfileType.ssh && profile.host != null) {
      _openSessionEditor();
    } else if (profile.type == SessionProfileType.localShell) {
      _addLocalShell();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: <Widget>[
          _SessionRail(
            sessions: _sessionManager.sessions,
            activeSessionIndex: _sessionManager.activeSessionIndex,
            savedProfiles: _profileStore.profiles,
            onNewSession: _openSessionEditor,
            onNewLocalShell: _addLocalShell,
            onDisconnect: _disconnect,
            onSessionSelected: (index) {
              _sessionManager.setActiveSession(index);
              _focusNode.requestFocus();
            },
            onProfileTap: _connectFromProfile,
            onSettings: _openSettings,
            onNetworkSettings: _openNetworkSettings,
            onSecuritySettings: _openSecuritySettings,
            onSftp: _toggleSftp,
            connecting: _connecting,
            showSftp: _showSftp,
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                _TabBar(
                  sessions: _sessionManager.sessions,
                  activeIndex: _sessionManager.activeSessionIndex,
                  onTabSelected: (index) {
                    _sessionManager.setActiveSession(index);
                    _focusNode.requestFocus();
                  },
                  onTabClosed: (index) {
                    _sessionManager.removeSession(index);
                  },
                ),
                _TopBar(
                  core: _core,
                  session: _sessionManager.activeSession,
                  connecting: _connecting,
                  onSearch: _toggleSearch,
                ),
                if (_showSearch)
                  TerminalSearchBar(
                    snapshot: _snapshot,
                    onSearchResult: _onSearchResult,
                    onClose: _closeSearch,
                  ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: _connecting
                              ? const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(
                                        color: Color(0xff2f6fed),
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        '正在连接...',
                                        style: TextStyle(color: Color(0xff8e98a8)),
                                      ),
                                    ],
                                  ),
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    // 终端区域大小变化时，调整 PTY 大小
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      _onTerminalResize(
                                        constraints.maxWidth,
                                        constraints.maxHeight,
                                      );
                                    });
                                    return KeyboardListener(
                                      focusNode: _focusNode,
                                      onKeyEvent: (event) {
                                        // Ctrl+P 打开命令面板
                                        if (event is KeyDownEvent &&
                                            event.logicalKey == LogicalKeyboardKey.keyP &&
                                            HardwareKeyboard.instance.isControlPressed) {
                                          _openCommandPalette();
                                          return;
                                        }
                                        _inputHandler.handleKeyEvent(event);
                                      },
                                      child: TerminalView(
                                        snapshot: _snapshot,
                                        onSelectionChanged: _onSelectionChanged,
                                        onMouseEvent: _onMouseEvent,
                                        settings: _settings,
                                        searchResult: _searchResult,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      if (_showSftp && _sftpSession != null)
                        SizedBox(
                          width: 320,
                          child: SftpPanel(
                            sftpSession: _sftpSession,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRail extends StatelessWidget {
  final List<SessionInfo> sessions;
  final int activeSessionIndex;
  final List<SessionProfile> savedProfiles;
  final VoidCallback onNewSession;
  final VoidCallback onNewLocalShell;
  final VoidCallback onDisconnect;
  final void Function(int index) onSessionSelected;
  final void Function(SessionProfile profile) onProfileTap;
  final VoidCallback onSettings;
  final VoidCallback onNetworkSettings;
  final VoidCallback onSecuritySettings;
  final VoidCallback onSftp;
  final bool connecting;
  final bool showSftp;

  const _SessionRail({
    required this.sessions,
    required this.activeSessionIndex,
    required this.savedProfiles,
    required this.onNewSession,
    required this.onNewLocalShell,
    required this.onDisconnect,
    required this.onSessionSelected,
    required this.onProfileTap,
    required this.onSettings,
    required this.onNetworkSettings,
    required this.onSecuritySettings,
    required this.onSftp,
    this.connecting = false,
    this.showSftp = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: Color(0xff191d25),
        border: Border(right: BorderSide(color: Color(0xff2a303b))),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Text(
                'WindSend',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            _NavItem(
              icon: Icons.add_rounded,
              label: connecting ? '连接中...' : '新建 SSH 连接',
              selected: false,
              onTap: connecting ? () {} : onNewSession,
            ),
            _NavItem(
              icon: Icons.terminal_rounded,
              label: '新建本地 Shell',
              selected: false,
              onTap: onNewLocalShell,
            ),
            if (sessions.isNotEmpty) ...[
              const Divider(color: Color(0xff2a303b), height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  '活动会话 (${sessions.length})',
                  style: TextStyle(color: Color(0xff8e98a8), fontSize: 12),
                ),
              ),
              ...sessions.asMap().entries.map((entry) {
                final index = entry.key;
                final session = entry.value;
                final isActive = index == activeSessionIndex;
                final icon = session.type == SessionType.ssh
                    ? Icons.cloud_rounded
                    : Icons.terminal_rounded;
                return _NavItem(
                  icon: icon,
                  label: session.name,
                  selected: isActive,
                  onTap: () => onSessionSelected(index),
                );
              }),
              if (activeSessionIndex >= 0)
                _NavItem(
                  icon: Icons.close_rounded,
                  label: '关闭当前会话',
                  selected: false,
                  onTap: onDisconnect,
                ),
            ],
            if (savedProfiles.isNotEmpty) ...[
              const Divider(color: Color(0xff2a303b), height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  '已保存会话 (${savedProfiles.length})',
                  style: TextStyle(color: Color(0xff8e98a8), fontSize: 12),
                ),
              ),
              Expanded(
                child: SessionTree(
                  profiles: savedProfiles,
                  onSessionTap: onProfileTap,
                  onSessionEdit: (profile) {},
                  onSessionDelete: (profile) {},
                ),
              ),
            ],
            const Divider(color: Color(0xff2a303b), height: 28),
            _NavItem(
              icon: Icons.folder_rounded,
              label: showSftp ? '关闭 SFTP' : 'SFTP 文件管理',
              selected: showSftp,
              onTap: onSftp,
            ),
            _NavItem(
              icon: Icons.settings_rounded,
              label: '终端设置',
              selected: false,
              onTap: onSettings,
            ),
            _NavItem(
              icon: Icons.wifi_rounded,
              label: '网络设置',
              selected: false,
              onTap: onNetworkSettings,
            ),
            _NavItem(
              icon: Icons.security_rounded,
              label: '安全设置',
              selected: false,
              onTap: onSecuritySettings,
            ),
            const Divider(color: Color(0xff2a303b), height: 28),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'Ctrl+P 命令面板',
                style: TextStyle(color: Color(0xff4a5568), fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 42,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff263247) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: const Color(0xff8fb6ff)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final List<SessionInfo> sessions;
  final int activeIndex;
  final void Function(int index) onTabSelected;
  final void Function(int index) onTabClosed;

  const _TabBar({
    required this.sessions,
    required this.activeIndex,
    required this.onTabSelected,
    required this.onTabClosed,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xff191d25),
        border: Border(bottom: BorderSide(color: Color(0xff2a303b))),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
          final isActive = index == activeIndex;
          final icon = session.type == SessionType.ssh
              ? Icons.cloud_rounded
              : Icons.terminal_rounded;

          return GestureDetector(
            onTap: () => onTabSelected(index),
            child: Container(
              constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xff263247)
                    : Colors.transparent,
                border: Border(
                  right: BorderSide(color: const Color(0xff2a303b)),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: const Color(0xff8fb6ff)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      session.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isActive
                            ? const Color(0xffd7e0ee)
                            : const Color(0xff8e98a8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => onTabClosed(index),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: const Color(0xff8e98a8),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final RustCore core;
  final SessionInfo? session;
  final bool connecting;
  final VoidCallback? onSearch;

  const _TopBar({
    required this.core,
    this.session,
    this.connecting = false,
    this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final String statusText;
    if (connecting) {
      statusText = 'connecting...';
    } else if (session != null) {
      statusText = session!.state;
    } else {
      statusText = 'disconnected';
    }

    final String sessionName;
    if (session != null) {
      sessionName = session!.name;
    } else {
      sessionName = 'Rust core bridge';
    }

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          const Icon(Icons.memory_rounded, size: 18, color: Color(0xff8fb6ff)),
          const SizedBox(width: 10),
          Text(
            sessionName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (onSearch != null)
            IconButton(
              icon: const Icon(Icons.search_rounded, size: 18),
              color: const Color(0xff8e98a8),
              onPressed: onSearch,
              tooltip: '搜索',
            ),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xff3a4657)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              statusText,
              style: const TextStyle(color: Color(0xffaeb8c8), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
