import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core_bridge/rust_core.dart';
import 'features/session/session_editor.dart';
import 'features/terminal/terminal_painter.dart';
import 'features/terminal/terminal_input.dart';

// ── FFI 类型签名（与 rust_core.dart 保持一致） ──

typedef _SessionOpenNative = Uint64 Function(
  Pointer<Utf8Char> host, Uint16 port,
  Pointer<Utf8Char> username, Pointer<Utf8Char> password,
);
typedef _SessionOpenDart = int Function(
  Pointer<Utf8Char> host, int port,
  Pointer<Utf8Char> username, Pointer<Utf8Char> password,
);

typedef _StringFreeNative = Void Function(Pointer<Utf8Char>);
typedef _StringFreeDart = void Function(Pointer<Utf8Char>);

/// 在后台 Isolate 中执行阻塞的 SSH 连接
Future<int> _openSessionIsolate(
  List<String> libCandidates, String host, int port,
  String username, String password,
) {
  return Isolate.run(() {
    // 每个 Isolate 需要自行打开动态库
    DynamicLibrary? lib;
    for (final path in libCandidates) {
      try { lib = DynamicLibrary.open(path); break; } on Object { continue; }
    }
    if (lib == null) return 0;

    final sessionOpen = lib.lookupFunction<_SessionOpenNative, _SessionOpenDart>('core_session_open');
    final stringFree  = lib.lookupFunction<_StringFreeNative,  _StringFreeDart>('core_string_free');

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
  SshSession? _currentSession;
  TerminalSnapshot? _snapshot;
  Timer? _pollTimer;
  late final TerminalInputHandler _inputHandler;
  final _focusNode = FocusNode();
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _inputHandler = TerminalInputHandler(onInput: _handleInput);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _currentSession?.close();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleInput(Uint8List data) {
    if (_currentSession != null) {
      _currentSession!.writeBytes(data);
    }
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

  Future<void> _connect(SshConfig config) async {
    setState(() => _connecting = true);

    try {
      // 在后台 Isolate 执行阻塞的 SSH 连接，避免冻结 UI
      final sessionId = await _openSessionIsolate(
        RustCore.libraryCandidates(),
        config.host,
        config.port,
        config.username,
        config.password,
      );

      if (sessionId == 0) {
        throw Exception('连接失败: 返回会话 ID 为 0');
      }

      final session = SshSession(sessionId, _core);

      setState(() {
        _currentSession = session;
        _connecting = false;
      });

      // 启动轮询
      _startPolling();

      // 获取焦点以便接收键盘输入
      _focusNode.requestFocus();
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

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_currentSession == null) return;

      final snapshot = _currentSession!.readOutput();
      if (snapshot != null) {
        setState(() {
          _snapshot = snapshot;
        });
      }
    });
  }

  void _disconnect() {
    _pollTimer?.cancel();
    _currentSession?.close();
    setState(() {
      _currentSession = null;
      _snapshot = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: <Widget>[
          _SessionRail(
            currentSession: _currentSession,
            onNewSession: _openSessionEditor,
            onDisconnect: _disconnect,
            connecting: _connecting,
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                _TopBar(
                  core: _core,
                  session: _currentSession,
                  connecting: _connecting,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _connecting
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Color(0xff2f6fed)),
                                SizedBox(height: 16),
                                Text('正在连接...', style: TextStyle(color: Color(0xff8e98a8))),
                              ],
                            ),
                          )
                        : KeyboardListener(
                            focusNode: _focusNode,
                            onKeyEvent: _inputHandler.handleKeyEvent,
                            child: TerminalView(snapshot: _snapshot),
                          ),
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
  final SshSession? currentSession;
  final VoidCallback onNewSession;
  final VoidCallback onDisconnect;
  final bool connecting;

  const _SessionRail({
    this.currentSession,
    required this.onNewSession,
    required this.onDisconnect,
    this.connecting = false,
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
              label: connecting ? '连接中...' : '新建连接',
              selected: false,
              onTap: connecting ? () {} : onNewSession,
            ),
            if (currentSession != null) ...[
              const Divider(color: Color(0xff2a303b), height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  '当前会话',
                  style: TextStyle(color: Color(0xff8e98a8), fontSize: 12),
                ),
              ),
              _NavItem(
                icon: Icons.terminal_rounded,
                label: 'SSH Session #${currentSession!.id}',
                selected: true,
                onTap: () {},
              ),
              _NavItem(
                icon: Icons.close_rounded,
                label: '断开连接',
                selected: false,
                onTap: onDisconnect,
              ),
            ],
            const Divider(color: Color(0xff2a303b), height: 28),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'Phase 1 - SSH MVP',
                style: TextStyle(color: Color(0xff8e98a8), fontSize: 12),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Text(
                'Rust SSH → VTE Terminal → Flutter',
                style: TextStyle(color: Color(0xffc4cad4), height: 1.35),
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

class _TopBar extends StatelessWidget {
  final RustCore core;
  final SshSession? session;
  final bool connecting;

  const _TopBar({required this.core, this.session, this.connecting = false});

  @override
  Widget build(BuildContext context) {
    final String statusText;
    if (connecting) {
      statusText = 'connecting...';
    } else if (session != null) {
      statusText = session!.getState();
    } else {
      statusText = 'disconnected';
    }

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          const Icon(Icons.memory_rounded, size: 18, color: Color(0xff8fb6ff)),
          const SizedBox(width: 10),
          Text(
            session != null ? 'SSH Session #${session!.id}' : 'Rust core bridge',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
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
