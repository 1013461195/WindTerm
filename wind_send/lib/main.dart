import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core_bridge/rust_core.dart';
import 'features/network/network_config.dart';
import 'features/network/network_settings_page.dart';
import 'features/protocol/protocol_session_editor.dart';
import 'features/security/security_config.dart';
import 'features/security/security_settings_page.dart';
import 'features/session/session_editor.dart';
import 'features/session/session_manager.dart';
import 'features/session/session_productivity.dart';
import 'features/session/session_profile.dart';
import 'features/session/session_profile_editor.dart';
import 'features/session/session_tree.dart';
import 'features/session/command_palette.dart';
import 'features/sftp/sftp_panel.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/terminal_settings.dart';
import 'features/terminal/terminal_painter.dart';
import 'features/terminal/terminal_input.dart';
import 'features/terminal/terminal_search.dart';
import 'features/update/update_service.dart';

// ── FFI 类型签名（与 rust_core.dart 保持一致） ──

typedef _SessionOpenJsonNative = Uint64 Function(Pointer<Utf8Char> requestJson);
typedef _SessionOpenJsonDart = int Function(Pointer<Utf8Char> requestJson);
typedef _SessionReconnectNative = Int32 Function(Uint64 sessionId);
typedef _SessionReconnectDart = int Function(int sessionId);
typedef _LastOpenErrorNative = Pointer<Utf8Char> Function();
typedef _LastOpenErrorDart = Pointer<Utf8Char> Function();
typedef _StringFreeNative = Void Function(Pointer<Utf8Char> value);
typedef _StringFreeDart = void Function(Pointer<Utf8Char> value);

/// 在后台 Isolate 中执行阻塞的 SSH 连接
Future<(int, String?)> _openSessionIsolate(
  List<String> libCandidates,
  String requestJson,
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
    if (lib == null) return (0, '无法加载 Rust Core 动态库');

    final sessionOpen = lib
        .lookupFunction<_SessionOpenJsonNative, _SessionOpenJsonDart>(
          'core_session_open_json',
        );
    final lastError = lib
        .lookupFunction<_LastOpenErrorNative, _LastOpenErrorDart>(
          'core_session_last_open_error',
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

    final request = toUtf8(requestJson);
    try {
      final id = sessionOpen(request);
      if (id != 0) return (id, null);
      final errorPointer = lastError();
      if (errorPointer.address == 0) return (0, 'SSH 连接失败');
      final bytes = <int>[];
      for (var offset = 0; ; offset++) {
        final value = (errorPointer.cast<Uint8>() + offset).value;
        if (value == 0) break;
        bytes.add(value);
      }
      final error = utf8.decode(bytes, allowMalformed: true);
      stringFree(errorPointer);
      return (0, error);
    } finally {
      malloc.free(request);
    }
  });
}

Future<int> _reconnectSessionIsolate(
  List<String> libCandidates,
  int sessionId,
) {
  return Isolate.run(() {
    for (final path in libCandidates) {
      try {
        final library = DynamicLibrary.open(path);
        final reconnect = library
            .lookupFunction<_SessionReconnectNative, _SessionReconnectDart>(
              'core_session_reconnect',
            );
        return reconnect(sessionId);
      } on Object {
        continue;
      }
    }
    return -1;
  });
}

void main() {
  final crashReporter = CrashReporter(windSendDataDirectory());
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      crashReporter.record(details.exception, details.stack, source: 'flutter'),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(crashReporter.record(error, stack, source: 'platform'));
    return true;
  };
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
  static const MethodChannel _windowChannel = MethodChannel('wind_send/window');
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
  final String _dataDirectory = windSendDataDirectory();
  late final SessionProfileStore _profileStore;
  late final WorkspaceStore _workspaceStore;
  late final AppConfigStore _appConfigStore;
  late final SessionLogWriter _sessionLogWriter;
  NetworkConfig _networkConfig = const NetworkConfig();
  SecurityConfig _securityConfig = const SecurityConfig();
  late final AuditLogger _auditLogger;
  late final CredentialStore _credentialStore;
  late final UpdateService _updateService;
  String? _masterPassword;
  bool _restoringWorkspace = false;
  final Set<int> _reconnectInFlight = {};
  bool _splitPane = false;
  bool _syncInput = false;

  @override
  void initState() {
    super.initState();
    _profileStore = SessionProfileStore(_dataDirectory);
    _workspaceStore = WorkspaceStore(_dataDirectory);
    _appConfigStore = AppConfigStore(_dataDirectory);
    _sessionLogWriter = SessionLogWriter(_dataDirectory);
    _auditLogger = AuditLogger(_dataDirectory);
    _sessionManager = SessionManager(
      core: _core,
      onSessionsChanged: _onSessionsChanged,
      onActiveSessionChanged: _onActiveSessionChanged,
      onSnapshotUpdated: _onSnapshotUpdated,
      onSessionOutput: (session, snapshot) {
        unawaited(_sessionLogWriter.append(session, snapshot));
      },
      onReconnectRequired: (session) {
        unawaited(_autoReconnect(session));
      },
    );
    _credentialStore = CredentialStore(
      _core,
      vaultDirectory: '$_dataDirectory/vault',
    );
    _updateService = UpdateService(_core, dataDirectory: _dataDirectory);
    _inputHandler = TerminalInputHandler(
      onInput: _handleInput,
      onCopy: _handleCopy,
      onPaste: _handlePaste,
    );
    _loadProfiles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForUpdates(silent: true));
    });
  }

  Future<void> _loadProfiles() async {
    try {
      final settings = await _appConfigStore.load();
      final terminal = settings['terminal'];
      final security = settings['security'];
      if (terminal is Map<String, dynamic>) {
        _settings = TerminalSettings.fromJson(terminal);
        unawaited(_applyWindowOpacity(_settings.windowOpacity));
      }
      if (security is Map<String, dynamic>) {
        _securityConfig = SecurityConfig.fromJson(security);
        _auditLogger.configure(_securityConfig);
      }
      await _profileStore.load();
      await _restoreWorkspace();
      setState(() {});
    } catch (e) {
      // 忽略加载错误
    }
  }

  Future<void> _saveAppConfig() {
    return _appConfigStore.save(<String, Object?>{
      'terminal': _settings.toJson(),
      'security': _securityConfig.toJson(),
    });
  }

  Future<void> _applyWindowOpacity(double opacity) async {
    try {
      await _windowChannel.invokeMethod<void>('setOpacity', opacity);
    } on MissingPluginException {
      // Tests and unsupported platforms do not expose a native window channel.
    }
  }

  Future<void> _checkForUpdates({required bool silent}) async {
    if (!_updateService.configured) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前构建未配置签名更新源')));
      }
      return;
    }
    try {
      final update = await _updateService.check();
      if (!mounted) return;
      if (update == null) {
        if (!silent) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
        }
        return;
      }
      final install = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('发现 WindSend ${update.version}'),
          content: SingleChildScrollView(
            child: Text(update.notes.isEmpty ? '已验证更新清单签名。' : update.notes),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('下载'),
            ),
          ],
        ),
      );
      if (install != true) return;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('正在下载并校验更新包...')));
      }
      final installer = await _updateService.download(update);
      await _updateService.openInstaller(installer);
    } on Object catch (error) {
      unawaited(
        _auditLogger.write(action: 'update_failed', detail: error.toString()),
      );
      if (!silent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('检查更新失败: $error')));
      }
    }
  }

  Future<void> _autoReconnect(SessionInfo session) async {
    if (!_reconnectInFlight.add(session.id)) return;
    try {
      final result = await _reconnectSessionIsolate(
        RustCore.libraryCandidates(),
        session.id,
      );
      if (result == 0 && _lastCols > 0 && _lastRows > 0) {
        _sessionManager.resizeSession(session.id, _lastCols, _lastRows);
      }
    } finally {
      _reconnectInFlight.remove(session.id);
    }
  }

  Future<void> _restoreWorkspace() async {
    final workspace = await _workspaceStore.load();
    _restoringWorkspace = true;
    try {
      for (final shell in workspace.localShells) {
        _sessionManager.addLocalShellSession(
          name: shell['name'] as String? ?? '本地 Shell',
          shell: shell['shell'] as String?,
          workingDir: shell['workingDir'] as String?,
        );
      }
      for (final profileId in workspace.profileIds) {
        final profile = _profileStore.get(profileId);
        if (profile?.autoLogin == true) {
          await _connectFromProfile(profile!);
        }
      }
      if (_sessionManager.sessions.isNotEmpty) {
        final index = workspace.activeIndex.clamp(
          0,
          _sessionManager.sessions.length - 1,
        );
        _sessionManager.setActiveSession(index);
        _sessionManager.startPolling();
      }
    } finally {
      _restoringWorkspace = false;
      await _workspaceStore.save(
        _sessionManager.sessions,
        _sessionManager.activeSessionIndex,
      );
    }
  }

  @override
  void dispose() {
    _sessionManager.dispose();
    unawaited(_sessionLogWriter.dispose());
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
      if (_securityConfig.clipboardAutoClear) {
        Timer(
          Duration(seconds: _securityConfig.clipboardAutoClearSeconds),
          () async {
            final current = await Clipboard.getData(Clipboard.kTextPlain);
            if (current?.text == text) {
              await Clipboard.setData(const ClipboardData(text: ''));
            }
          },
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    if (!mounted) return;
    var slowPaste = false;
    var delayMs = 20;
    if (_securityConfig.pasteConfirmation &&
        (text.length >= 200 || text.contains('\n') || text.contains('\r'))) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('确认粘贴'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('即将向会话发送 ${text.length} 个字符。'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('慢速粘贴'),
                  subtitle: const Text('逐字符发送，降低设备或远端程序丢字符风险'),
                  value: slowPaste,
                  onChanged: (value) {
                    setDialogState(() => slowPaste = value);
                  },
                ),
                if (slowPaste)
                  DropdownButtonFormField<int>(
                    initialValue: delayMs,
                    decoration: const InputDecoration(labelText: '字符间隔'),
                    items: const [
                      DropdownMenuItem(value: 10, child: Text('10 ms')),
                      DropdownMenuItem(value: 20, child: Text('20 ms')),
                      DropdownMenuItem(value: 50, child: Text('50 ms')),
                      DropdownMenuItem(value: 100, child: Text('100 ms')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => delayMs = value);
                      }
                    },
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('粘贴'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
    }
    if (!slowPaste) {
      _sessionManager.writeInput(
        _snapshot?.bracketedPaste == true ? '\x1b[200~$text\x1b[201~' : text,
      );
      return;
    }
    if (_snapshot?.bracketedPaste == true) {
      _sessionManager.writeInput('\x1b[200~');
    }
    for (final character in text.runes) {
      if (!mounted || _sessionManager.activeSession == null) return;
      _sessionManager.writeInput(String.fromCharCode(character));
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
    if (_snapshot?.bracketedPaste == true) {
      _sessionManager.writeInput('\x1b[201~');
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
    if (sessions.length < 2 && (_splitPane || _syncInput)) {
      _splitPane = false;
      _syncInput = false;
      _sessionManager.setSyncInput(false);
    }
    setState(() {});
    if (!_restoringWorkspace) {
      unawaited(
        _workspaceStore.save(sessions, _sessionManager.activeSessionIndex),
      );
    }
  }

  void _onActiveSessionChanged(int activeIndex) {
    setState(() {
      _snapshot = _sessionManager.activeSession?.snapshot;
    });
    if (!_restoringWorkspace) {
      unawaited(
        _workspaceStore.save(
          _sessionManager.sessions,
          _sessionManager.activeSessionIndex,
        ),
      );
    }
  }

  void _onSnapshotUpdated(TerminalSnapshot snapshot) {
    _inputHandler.applicationCursorMode = snapshot.applicationCursorMode;
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

  void _openProtocolSessionEditor() {
    showDialog<void>(
      context: context,
      builder: (context) => ProtocolSessionEditor(
        serialPorts: _core.serialListPorts(),
        onTelnet: (config) {
          Navigator.of(context).pop();
          _sessionManager.addTelnetSession(
            name: 'Telnet ${config.host}:${config.port}',
            config: config,
          );
          _afterProtocolConnected();
        },
        onRawTcp: (config) {
          Navigator.of(context).pop();
          _sessionManager.addRawTcpSession(
            name: 'TCP ${config.host}:${config.port}',
            config: config,
          );
          _afterProtocolConnected();
        },
        onSerial: (config) {
          Navigator.of(context).pop();
          _sessionManager.addSerialSession(
            name: 'Serial ${config.port}',
            config: config,
          );
          _afterProtocolConnected();
        },
      ),
    );
  }

  void _afterProtocolConnected() {
    _sessionManager.startPolling();
    _focusNode.requestFocus();
    if (_lastCols > 0 && _lastRows > 0) {
      _sessionManager.resize(_lastCols, _lastRows);
    }
  }

  Future<void> _connect(SshConfig config, {SessionProfile? profile}) async {
    if (config.rememberCredential &&
        _securityConfig.credentialStorage == CredentialStorage.vault &&
        await _ensureMasterPassword() == null) {
      return;
    }
    setState(() => _connecting = true);

    try {
      // 在后台 Isolate 执行阻塞的 SSH 连接，避免冻结 UI
      // 设置 15 秒超时
      final openResult =
          await _openSessionIsolate(
            RustCore.libraryCandidates(),
            jsonEncode(config.toJson(network: _networkConfig.toJson())),
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('连接超时 (15秒)'),
          );
      final sessionId = openResult.$1;

      if (sessionId == 0) {
        final error = openResult.$2 ?? '未知连接错误';
        if (error.startsWith('HOST_KEY_UNKNOWN:') && mounted) {
          final accepted = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('确认未知主机密钥'),
              content: SelectableText(error),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('拒绝'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('接受并保存'),
                ),
              ],
            ),
          );
          if (accepted == true) {
            setState(() => _connecting = false);
            config.acceptUnknownHost = true;
            await _connect(config, profile: profile);
            return;
          }
        }
        throw Exception(error);
      }

      // 接管后台 Isolate 已经建立的会话，避免重复连接和泄漏。
      String? credentialId;
      if (config.rememberCredential &&
          _securityConfig.credentialStorage != CredentialStorage.none) {
        final secret = config.authentication == SshAuthentication.password
            ? config.password
            : config.passphrase;
        if (secret.isNotEmpty) {
          try {
            credentialId = await _credentialStore.save(
              storage: _securityConfig.credentialStorage,
              secret: secret,
              masterPassword: _masterPassword,
            );
          } on Object catch (error) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('凭据保存失败: $error')));
            }
          }
        }
      }
      _sessionManager.addExistingSshSession(
        sessionId: sessionId,
        name: '${config.username}@${config.host}',
        profileConfig: <String, Object?>{
          'profileId': profile?.id,
          'host': config.host,
          'port': config.port,
          'username': config.username,
          'authType': config.authentication.name,
          'privateKeyPath': config.privateKeyPath.isEmpty
              ? null
              : config.privateKeyPath,
          'credentialStorage': credentialId == null
              ? profile?.credentialStorage
              : _securityConfig.credentialStorage.name,
          'credentialId': credentialId ?? profile?.credentialId,
          'logging': profile?.logging ?? false,
          'logPath': profile?.logPath,
          'quickCommands': profile?.quickCommands ?? const <String>[],
          'tabColor': profile?.tabColor,
          'autoReconnect': _networkConfig.reconnect.enabled,
        },
      );
      unawaited(
        _auditLogger.write(
          action: 'session_connected',
          sessionId: sessionId.toString(),
          user: config.username,
          host: config.host,
        ),
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
      unawaited(
        _auditLogger.write(
          action: 'session_connect_failed',
          detail: e.toString(),
          user: config.username,
          host: config.host,
        ),
      );
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

  Future<String?> _ensureMasterPassword() async {
    if (_masterPassword?.isNotEmpty == true) return _masterPassword;
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('输入主密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: '主密码'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text;
              if (value.isNotEmpty) Navigator.of(context).pop(value);
            },
            child: const Text('解锁'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (password != null) _masterPassword = password;
    return password;
  }

  void _disconnect() {
    _closeSessionAt(_sessionManager.activeSessionIndex);
  }

  void _closeSessionAt(int index) {
    if (index < 0 || index >= _sessionManager.sessions.length) return;
    final session = _sessionManager.sessions[index];
    unawaited(
      _auditLogger.write(
        action: 'session_closed',
        sessionId: session.id.toString(),
        detail: session.type.name,
      ),
    );
    _sessionLogWriter.close(session.id);
    final config = session.profileConfig;
    final credentialId = config?['credentialId'] as String?;
    if (config?['profileId'] == null && credentialId != null) {
      final storage = CredentialStorage.values.firstWhere(
        (value) => value.name == config?['credentialStorage'],
        orElse: () => CredentialStorage.none,
      );
      unawaited(
        _credentialStore.delete(storage: storage, credentialId: credentialId),
      );
    }
    _sessionManager.removeSession(index);
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
            unawaited(_applyWindowOpacity(newSettings.windowOpacity));
            unawaited(_saveAppConfig());
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
          unawaited(_connectFromProfile(profile));
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
            case 'check_updates':
              unawaited(_checkForUpdates(silent: false));
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
              _auditLogger.configure(newConfig);
            });
            unawaited(_saveAppConfig());
          },
        ),
      ),
    );
  }

  void _saveSessionAsProfile(SessionInfo session) {
    final config = session.profileConfig ?? const <String, Object?>{};
    final profile = SessionProfile(
      id: 'profile-${DateTime.now().microsecondsSinceEpoch}',
      name: session.name,
      type: session.type == SessionType.ssh
          ? SessionProfileType.ssh
          : SessionProfileType.localShell,
      host: config['host'] as String?,
      port: config['port'] as int?,
      username: config['username'] as String?,
      authType: config['authType'] == SshAuthentication.privateKey.name
          ? SshAuthType.privateKey
          : SshAuthType.password,
      privateKeyPath: config['privateKeyPath'] as String?,
      credentialId: config['credentialId'] as String?,
      credentialStorage: config['credentialStorage'] as String?,
      shell: config['shell'] as String?,
      workingDir: config['workingDir'] as String?,
      logging: config['logging'] == true,
      logPath: config['logPath'] as String?,
      quickCommands: List<String>.from(
        config['quickCommands'] as List<dynamic>? ?? const [],
      ),
      tabColor: config['tabColor'] as String?,
    );
    _profileStore.add(profile);
    unawaited(_profileStore.save());
    _sessionManager.updateProfileConfig(
      _sessionManager.activeSessionIndex,
      <String, Object?>{...config, 'profileId': profile.id},
    );
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('会话已保存: ${session.name}')));
  }

  void _editProfile(SessionProfile profile) {
    showDialog<void>(
      context: context,
      builder: (context) => SessionProfileEditor(
        profile: profile,
        onSave: (updated) {
          _profileStore.update(profile.id, updated);
          unawaited(_profileStore.save());
          setState(() {});
        },
      ),
    );
  }

  void _duplicateProfile(SessionProfile profile) {
    _profileStore.add(
      profile.copyWith(
        id: 'profile-${DateTime.now().microsecondsSinceEpoch}',
        name: '${profile.name} 副本',
        autoLogin: false,
      ),
    );
    unawaited(_profileStore.save());
    setState(() {});
  }

  Future<void> _deleteProfile(SessionProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话配置'),
        content: Text('确定删除“${profile.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final credentialId = profile.credentialId;
    if (credentialId != null) {
      final storage = CredentialStorage.values.firstWhere(
        (value) => value.name == profile.credentialStorage,
        orElse: () => CredentialStorage.none,
      );
      await _credentialStore.delete(
        storage: storage,
        credentialId: credentialId,
      );
    }
    _profileStore.delete(profile.id);
    await _profileStore.save();
    if (mounted) setState(() {});
  }

  Future<void> _openQuickCommands() async {
    final session = _sessionManager.activeSession;
    if (session == null) return;
    final commands = List<String>.from(
      session.profileConfig?['quickCommands'] as List<dynamic>? ?? const [],
    );
    final controller = TextEditingController();
    final command = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('快捷命令'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (commands.isNotEmpty)
                ...commands.map(
                  (value) => ListTile(
                    dense: true,
                    title: Text(value),
                    trailing: const Icon(Icons.send_rounded, size: 18),
                    onTap: () => Navigator.of(context).pop(value),
                  ),
                ),
              TextField(
                controller: controller,
                autofocus: commands.isEmpty,
                decoration: const InputDecoration(labelText: '临时命令'),
                onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (command != null && command.isNotEmpty) {
      _sessionManager.writeInput('$command\n');
    }
  }

  Future<void> _showPortForwardStatus() async {
    final active = _sessionManager.activeSession;
    if (active?.type != SessionType.ssh) return;
    var statuses = (active!.session as SshSession).portForwardStatus();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('端口转发状态'),
          content: SizedBox(
            width: 620,
            child: statuses.isEmpty
                ? const Text('当前会话没有配置端口转发')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: statuses.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final status = statuses[index];
                      final target = status.type == 'dynamic'
                          ? 'SOCKS5'
                          : '${status.remoteHost}:${status.remotePort}';
                      return ListTile(
                        leading: Icon(
                          status.state == 'running'
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded,
                          color: status.state == 'running'
                              ? Colors.green
                              : Colors.redAccent,
                        ),
                        title: Text(
                          '${status.type.toUpperCase()} '
                          '${status.bindAddress}:${status.bindPort} → $target',
                        ),
                        subtitle: Text(
                          '状态 ${status.state} · 活动 ${status.activeConnections} · '
                          '累计 ${status.totalConnections}\n'
                          '上传 ${_formatBytes(status.uploadedBytes)} · '
                          '下载 ${_formatBytes(status.downloadedBytes)}'
                          '${status.lastError == null ? '' : '\n${status.lastError}'}',
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() {
                  statuses = (active.session as SshSession).portForwardStatus();
                });
              },
              child: const Text('刷新'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _toggleSyncInput() async {
    if (!_syncInput) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('启用同步输入'),
          content: Text(
            '后续键盘输入和粘贴将同时发送到 '
            '${_sessionManager.sessions.length} 个活动会话。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('启用'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _syncInput = !_syncInput);
    _sessionManager.setSyncInput(_syncInput);
  }

  Future<void> _connectFromProfile(SessionProfile profile) async {
    try {
      if (profile.type == SessionProfileType.ssh && profile.host != null) {
        String secret = '';
        final credentialId = profile.credentialId;
        if (credentialId != null) {
          final storage = CredentialStorage.values.firstWhere(
            (value) => value.name == profile.credentialStorage,
            orElse: () => CredentialStorage.none,
          );
          if (storage == CredentialStorage.vault &&
              await _ensureMasterPassword() == null) {
            return;
          }
          secret =
              await _credentialStore.load(
                storage: storage,
                credentialId: credentialId,
                masterPassword: _masterPassword,
              ) ??
              '';
        }
        final privateKey = profile.authType == SshAuthType.privateKey;
        await _connect(
          SshConfig(
            host: profile.host!,
            port: profile.port ?? 22,
            username: profile.username ?? '',
            authentication: privateKey
                ? SshAuthentication.privateKey
                : SshAuthentication.password,
            password: privateKey ? '' : secret,
            privateKeyPath: profile.privateKeyPath ?? '',
            passphrase: privateKey ? secret : '',
            acceptUnknownHost: false,
          ),
          profile: profile,
        );
      } else if (profile.type == SessionProfileType.localShell) {
        _sessionManager.addLocalShellSession(
          name: profile.name,
          shell: profile.shell,
          workingDir: profile.workingDir,
        );
        final session = _sessionManager.sessions.last;
        _sessionManager.updateProfileConfig(
          _sessionManager.sessions.length - 1,
          <String, Object?>{
            ...?session.profileConfig,
            'profileId': profile.id,
            'logging': profile.logging,
            'logPath': profile.logPath,
            'quickCommands': profile.quickCommands,
            'tabColor': profile.tabColor,
          },
        );
        _afterProtocolConnected();
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开会话失败: $error')));
      }
    }
  }

  SessionInfo? get _secondarySession {
    final active = _sessionManager.activeSession;
    for (final session in _sessionManager.sessions) {
      if (session.id != active?.id) return session;
    }
    return null;
  }

  Widget _buildTerminalPane(SessionInfo? session, {required bool interactive}) {
    if (_connecting && interactive) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xff2f6fed)),
            SizedBox(height: 16),
            Text('正在连接...', style: TextStyle(color: Color(0xff8e98a8))),
          ],
        ),
      );
    }
    Widget terminal = TerminalView(
      snapshot: session?.snapshot,
      onSelectionChanged: interactive ? _onSelectionChanged : null,
      onMouseEvent: interactive ? _onMouseEvent : null,
      settings: _settings,
      searchResult: interactive ? _searchResult : null,
    );
    if (!interactive && session != null) {
      terminal = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          final index = _sessionManager.sessions.indexWhere(
            (candidate) => candidate.id == session.id,
          );
          if (index >= 0) {
            _sessionManager.setActiveSession(index);
            _focusNode.requestFocus();
          }
        },
        child: terminal,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          const horizontalPadding = 8.0;
          const verticalPadding = 8.0;
          final cols =
              ((constraints.maxWidth - horizontalPadding) / _settings.cellWidth)
                  .floor();
          final rows =
              ((constraints.maxHeight - verticalPadding) / _settings.cellHeight)
                  .floor();
          if (session != null && cols > 0 && rows > 0) {
            _sessionManager.resizeSession(session.id, cols, rows);
            if (interactive) {
              _lastCols = cols;
              _lastRows = rows;
            }
          }
        });
        if (!interactive) return terminal;
        return KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: (event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.keyP &&
                HardwareKeyboard.instance.isControlPressed) {
              _openCommandPalette();
              return;
            }
            _inputHandler.handleKeyEvent(event);
          },
          child: terminal,
        );
      },
    );
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
            onNewProtocol: _openProtocolSessionEditor,
            onNewLocalShell: _addLocalShell,
            onDisconnect: _disconnect,
            onSaveProfile: () {
              final session = _sessionManager.activeSession;
              if (session != null &&
                  (session.type == SessionType.ssh ||
                      session.type == SessionType.localShell)) {
                _saveSessionAsProfile(session);
              }
            },
            onSessionSelected: (index) {
              _sessionManager.setActiveSession(index);
              _focusNode.requestFocus();
            },
            onProfileTap: _connectFromProfile,
            onProfileEdit: _editProfile,
            onProfileDuplicate: _duplicateProfile,
            onProfileDelete: (profile) {
              unawaited(_deleteProfile(profile));
            },
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
                    _closeSessionAt(index);
                  },
                ),
                _TopBar(
                  core: _core,
                  session: _sessionManager.activeSession,
                  connecting: _connecting,
                  onSearch: _toggleSearch,
                  onQuickCommands: _sessionManager.activeSession == null
                      ? null
                      : _openQuickCommands,
                  onPortForwardStatus:
                      _sessionManager.activeSession?.type == SessionType.ssh
                      ? _showPortForwardStatus
                      : null,
                  splitPane: _splitPane,
                  syncInput: _syncInput,
                  onToggleSplit: _sessionManager.sessions.length < 2
                      ? null
                      : () => setState(() => _splitPane = !_splitPane),
                  onToggleSyncInput: _sessionManager.sessions.length < 2
                      ? null
                      : () => unawaited(_toggleSyncInput()),
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
                          child: _splitPane && _secondarySession != null
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: _buildTerminalPane(
                                        _sessionManager.activeSession,
                                        interactive: true,
                                      ),
                                    ),
                                    const VerticalDivider(width: 1),
                                    Expanded(
                                      child: _buildTerminalPane(
                                        _secondarySession,
                                        interactive: false,
                                      ),
                                    ),
                                  ],
                                )
                              : _buildTerminalPane(
                                  _sessionManager.activeSession,
                                  interactive: true,
                                ),
                        ),
                      ),
                      if (_showSftp && _sftpSession != null)
                        SizedBox(
                          width: 520,
                          child: SftpPanel(sftpSession: _sftpSession),
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
  final VoidCallback onNewProtocol;
  final VoidCallback onNewLocalShell;
  final VoidCallback onDisconnect;
  final VoidCallback onSaveProfile;
  final void Function(int index) onSessionSelected;
  final void Function(SessionProfile profile) onProfileTap;
  final void Function(SessionProfile profile) onProfileEdit;
  final void Function(SessionProfile profile) onProfileDuplicate;
  final void Function(SessionProfile profile) onProfileDelete;
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
    required this.onNewProtocol,
    required this.onNewLocalShell,
    required this.onDisconnect,
    required this.onSaveProfile,
    required this.onSessionSelected,
    required this.onProfileTap,
    required this.onProfileEdit,
    required this.onProfileDuplicate,
    required this.onProfileDelete,
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
            _NavItem(
              icon: Icons.cable_rounded,
              label: '新建 Telnet / TCP / Serial',
              selected: false,
              onTap: onNewProtocol,
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
                  icon: Icons.bookmark_add_rounded,
                  label: '保存当前会话',
                  selected: false,
                  onTap: onSaveProfile,
                ),
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
                  onSessionEdit: onProfileEdit,
                  onSessionDuplicate: onProfileDuplicate,
                  onSessionDelete: onProfileDelete,
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
          final tabColor = _tabColor(session.profileConfig?['tabColor']);

          return GestureDetector(
            onTap: () => onTabSelected(index),
            child: Container(
              constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xff263247) : Colors.transparent,
                border: Border(
                  top: BorderSide(
                    color: tabColor ?? Colors.transparent,
                    width: 2,
                  ),
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

  Color? _tabColor(Object? value) {
    return switch (value) {
      'blue' => const Color(0xff2f6fed),
      'green' => const Color(0xff4e9a06),
      'orange' => Colors.orangeAccent,
      'red' => Colors.redAccent,
      'purple' => const Color(0xffad7fa8),
      _ => null,
    };
  }
}

class _TopBar extends StatelessWidget {
  final RustCore core;
  final SessionInfo? session;
  final bool connecting;
  final VoidCallback? onSearch;
  final VoidCallback? onQuickCommands;
  final VoidCallback? onPortForwardStatus;
  final bool splitPane;
  final bool syncInput;
  final VoidCallback? onToggleSplit;
  final VoidCallback? onToggleSyncInput;

  const _TopBar({
    required this.core,
    this.session,
    this.connecting = false,
    this.onSearch,
    this.onQuickCommands,
    this.onPortForwardStatus,
    this.splitPane = false,
    this.syncInput = false,
    this.onToggleSplit,
    this.onToggleSyncInput,
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
          if (onQuickCommands != null)
            IconButton(
              icon: const Icon(Icons.bolt_rounded, size: 18),
              color: const Color(0xff8e98a8),
              onPressed: onQuickCommands,
              tooltip: '快捷命令',
            ),
          if (onPortForwardStatus != null)
            IconButton(
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              color: const Color(0xff8e98a8),
              onPressed: onPortForwardStatus,
              tooltip: '端口转发状态',
            ),
          if (onToggleSplit != null)
            IconButton(
              icon: Icon(
                Icons.vertical_split_rounded,
                size: 18,
                color: splitPane
                    ? const Color(0xff8fb6ff)
                    : const Color(0xff8e98a8),
              ),
              onPressed: onToggleSplit,
              tooltip: splitPane ? '关闭分屏' : '双会话分屏',
            ),
          if (onToggleSyncInput != null)
            IconButton(
              icon: Icon(
                Icons.sync_alt_rounded,
                size: 18,
                color: syncInput
                    ? Colors.orangeAccent
                    : const Color(0xff8e98a8),
              ),
              onPressed: onToggleSyncInput,
              tooltip: syncInput ? '关闭同步输入' : '向全部会话同步输入',
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
