import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core_bridge/rust_core.dart';
import 'features/network/network_config.dart';
import 'features/network/network_settings_page.dart';
import 'features/protocol/protocol_config.dart';
import 'features/security/security_config.dart';
import 'features/security/security_settings_page.dart';
import 'features/security/auth_identity.dart';
import 'features/security/auth_identity_manager.dart';
import 'features/session/connection_hub.dart';
import 'features/session/session_editor.dart';
import 'features/session/session_manager.dart';
import 'features/session/session_productivity.dart';
import 'features/session/session_profile.dart';
import 'features/session/ssh_profile_editor.dart';
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
  const WindSendApp({super.key, this.requireSecuritySetup = true});

  final bool requireSecuritySetup;

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
      home: ShellWorkspace(requireSecuritySetup: requireSecuritySetup),
    );
  }
}

class ShellWorkspace extends StatefulWidget {
  const ShellWorkspace({super.key, this.requireSecuritySetup = true});

  final bool requireSecuritySetup;

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
  late final AuthIdentityStore _identityStore;
  late final UpdateService _updateService;
  String? _masterPassword;
  String? _unlockVerifier;
  bool _securityReady = false;
  bool _restoringWorkspace = false;
  final Set<int> _reconnectInFlight = {};
  bool _splitPane = false;
  bool _syncInput = false;
  bool _showConnectionHub = true;
  List<String> _connectionGroups = <String>[];

  @override
  void initState() {
    super.initState();
    _securityReady = !widget.requireSecuritySetup;
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
    _identityStore = AuthIdentityStore(_dataDirectory);
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
      final connectionGroups = settings['connectionGroups'];
      final securityBootstrap = settings['securityBootstrap'];
      if (terminal is Map<String, dynamic>) {
        _settings = TerminalSettings.fromJson(terminal);
        unawaited(_applyWindowOpacity(_settings.windowOpacity));
      }
      if (security is Map<String, dynamic>) {
        _securityConfig = SecurityConfig.fromJson(security);
        _auditLogger.configure(_securityConfig);
      }
      if (connectionGroups is List) {
        _connectionGroups =
            connectionGroups
                .whereType<String>()
                .map((group) => group.trim())
                .where((group) => group.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
      }
      if (securityBootstrap is Map<String, dynamic>) {
        _unlockVerifier = securityBootstrap['verifier'] as String?;
      }
      if (!widget.requireSecuritySetup) {
        _securityReady = true;
      } else {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        await _unlockApplication();
        if (!_securityReady) return;
      }
      await _profileStore.load();
      await _identityStore.load();
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
      'connectionGroups': _connectionGroups,
      'securityBootstrap': <String, Object?>{'verifier': _unlockVerifier},
    });
  }

  List<String> get _allConnectionGroups {
    final groups = <String>{
      ..._connectionGroups,
      ..._profileStore.profiles
          .map((profile) => profile.folder)
          .whereType<String>(),
    }.where((group) => group.trim().isNotEmpty).toList()..sort();
    return groups;
  }

  Future<void> _applyWindowOpacity(double opacity) async {
    try {
      await _windowChannel.invokeMethod<void>('setOpacity', opacity);
    } on MissingPluginException {
      // Tests and unsupported platforms do not expose a native window channel.
    }
  }

  Future<void> _unlockApplication() async {
    if (_unlockVerifier == null) {
      await _setInitialPassword();
      return;
    }
    while (mounted && !_securityReady) {
      var password = '';
      String? errorText;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('解锁 WindSend'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('请输入应用主密码后加载连接与认证身份。'),
                    const SizedBox(height: 16),
                    TextField(
                      autofocus: true,
                      obscureText: true,
                      onChanged: (value) => password = value,
                      decoration: InputDecoration(
                        labelText: '主密码',
                        errorText: errorText,
                      ),
                      onSubmitted: (_) {
                        _verifyUnlockPassword(
                          password,
                          setDialogState: setDialogState,
                          setError: (value) => errorText = value,
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    _verifyUnlockPassword(
                      password,
                      setDialogState: setDialogState,
                      setError: (value) => errorText = value,
                    );
                  },
                  child: const Text('解锁'),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _verifyUnlockPassword(
    String password, {
    required StateSetter setDialogState,
    required ValueChanged<String?> setError,
  }) {
    if (password.isEmpty) {
      setDialogState(() => setError('请输入主密码'));
      return;
    }
    try {
      final marker = _core.decryptCredential(_unlockVerifier!, password);
      if (marker != 'wind-send-unlock-v1') {
        throw StateError('invalid marker');
      }
      _masterPassword = password;
      _securityReady = true;
      Navigator.of(context).pop();
    } on Object {
      setDialogState(() => setError('密码错误'));
    }
  }

  Future<void> _setInitialPassword() async {
    var password = '';
    var confirmation = '';
    String? errorText;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('初始化安全存储'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '首次启动需要设置应用主密码。敏感凭据将保存到'
                    '${Platform.isMacOS
                        ? ' macOS 钥匙串'
                        : Platform.isWindows
                        ? ' Windows 凭据管理器'
                        : ' Linux Secret Service'}，'
                    '配置文件只保留不可用的引用 ID。',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    autofocus: true,
                    obscureText: true,
                    onChanged: (value) => password = value,
                    decoration: InputDecoration(
                      labelText: '主密码（至少 8 位）',
                      errorText: errorText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    obscureText: true,
                    onChanged: (value) => confirmation = value,
                    decoration: const InputDecoration(labelText: '确认主密码'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '主密码不会以明文保存。忘记主密码后无法在应用内恢复。',
                    style: TextStyle(color: Color(0xff8e98a8), fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () async {
                  if (password.length < 8) {
                    setDialogState(() => errorText = '主密码至少需要 8 位');
                    return;
                  }
                  if (password != confirmation) {
                    setDialogState(() => errorText = '两次输入的密码不一致');
                    return;
                  }
                  _masterPassword = password;
                  _unlockVerifier = _core.encryptCredential(
                    'wind-send-unlock-v1',
                    password,
                  );
                  _securityConfig = _securityConfig.copyWith(
                    credentialStorage: CredentialStorage.platform,
                    masterPasswordEnabled: true,
                  );
                  _securityReady = true;
                  await _saveAppConfig();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('创建并进入'),
              ),
            ],
          ),
        ),
      ),
    );
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
    _sftpSession?.close();
    _sftpSession = null;
    _showSftp = false;
    setState(() {
      _snapshot = _sessionManager.activeSession?.snapshot;
    });
    if (_sessionManager.activeSession?.type == SessionType.ssh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_showConnectionHub &&
            _sessionManager.activeSession?.type == SessionType.ssh) {
          _openSftpForActiveSession(showError: false);
        }
      });
    }
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
        identities: _identityStore.identities,
        onLoadIdentity: _loadIdentitySecret,
        onManageIdentities: _openIdentityManager,
        onConnect: (config) {
          Navigator.of(context).pop();
          _connect(config);
        },
      ),
    );
  }

  void _afterProtocolConnected() {
    setState(() => _showConnectionHub = false);
    _sessionManager.startPolling();
    _focusNode.requestFocus();
    if (_lastCols > 0 && _lastRows > 0) {
      _sessionManager.resize(_lastCols, _lastRows);
    }
  }

  Future<void> _connect(
    SshConfig config, {
    SessionProfile? profile,
    NetworkConfig? networkConfig,
  }) async {
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
            jsonEncode(
              config.toJson(
                network: (networkConfig ?? _networkConfig).toJson(),
              ),
            ),
          ).timeout(
            Duration(milliseconds: config.connectTimeoutMs + 1000),
            onTimeout: () =>
                throw TimeoutException('连接超时 (${config.connectTimeoutMs}毫秒)'),
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
            await _connect(
              config,
              profile: profile,
              networkConfig: networkConfig,
            );
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
          'autoReconnect': (networkConfig ?? _networkConfig).reconnect.enabled,
        },
      );
      _sessionManager.setActiveSession(_sessionManager.sessions.length - 1);
      unawaited(
        _auditLogger.write(
          action: 'session_connected',
          sessionId: sessionId.toString(),
          user: config.username,
          host: config.host,
        ),
      );

      setState(() => _connecting = false);
      setState(() => _showConnectionHub = false);

      // 启动轮询
      _sessionManager.startPolling();

      // 获取焦点以便接收键盘输入
      _focusNode.requestFocus();

      // 连接成功后发送初始终端大小（如果 LayoutBuilder 已经触发过）
      if (_lastCols > 0 && _lastRows > 0) {
        _sessionManager.resize(_lastCols, _lastRows);
      }
      if (profile != null) {
        final options = profile.sshOptions;
        final defaultPath = options['defaultPath'] as String?;
        final initialCommand = options['initialCommand'] as String?;
        final commands = <String>[];
        if (defaultPath != null &&
            defaultPath.trim().isNotEmpty &&
            defaultPath.trim() != '~') {
          final escaped = defaultPath.trim().replaceAll("'", "'\\''");
          commands.add("cd -- '$escaped'");
        }
        if (initialCommand != null && initialCommand.trim().isNotEmpty) {
          commands.add(initialCommand.trim());
        }
        if (commands.isNotEmpty) {
          _sessionManager.writeInput('${commands.join('\n')}\n');
        }
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
    var enteredPassword = '';
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('输入主密码'),
        content: TextField(
          obscureText: true,
          autofocus: true,
          onChanged: (value) => enteredPassword = value,
          decoration: const InputDecoration(labelText: '主密码'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (enteredPassword.isNotEmpty) {
                Navigator.of(context).pop(enteredPassword);
              }
            },
            child: const Text('解锁'),
          ),
        ],
      ),
    );
    if (password != null) _masterPassword = password;
    return password;
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
    if (_sessionManager.sessions.isEmpty) {
      setState(() => _showConnectionHub = true);
    }
  }

  void _addLocalShell() {
    _sessionManager.addLocalShellSession(
      name: '本地 Shell ${_sessionManager.sessions.length + 1}',
    );
    _sessionManager.setActiveSession(_sessionManager.sessions.length - 1);
    setState(() => _showConnectionHub = false);
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

  bool _openSftpForActiveSession({bool showError = true}) {
    final active = _sessionManager.activeSession;
    if (active?.type != SessionType.ssh) return false;
    try {
      final sftp = _core.openSftp(active!.id);
      setState(() {
        _sftpSession = sftp;
        _showSftp = true;
      });
    } catch (error) {
      if (showError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打开 SFTP 失败: $error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
    return true;
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

  Future<AuthIdentitySecret?> _loadIdentitySecret(AuthIdentity identity) async {
    try {
      final storage = CredentialStorage.values.firstWhere(
        (value) => value.name == identity.credentialStorage,
        orElse: () => CredentialStorage.platform,
      );
      final value = await _credentialStore.load(
        storage: storage,
        credentialId: identity.secretId,
        masterPassword: _masterPassword,
      );
      return value == null ? null : AuthIdentitySecret.decode(value);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('读取认证身份失败: $error')));
      }
      return null;
    }
  }

  Future<void> _openIdentityManager() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AuthIdentityManager(
          identities: _identityStore.identities,
          onCreate: () {
            _openIdentityEditor(onChanged: () => setDialogState(() {}));
          },
          onEdit: (identity) {
            _openIdentityEditor(
              identity: identity,
              onChanged: () => setDialogState(() {}),
            );
          },
          onDelete: (identity) {
            unawaited(
              _deleteIdentity(identity, onChanged: () => setDialogState(() {})),
            );
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _openIdentityEditor({
    AuthIdentity? identity,
    required VoidCallback onChanged,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AuthIdentityEditor(
        identity: identity,
        onSave:
            ({
              required name,
              required username,
              required authType,
              required privateKeyPath,
              required password,
              required passphrase,
            }) {
              unawaited(
                _saveIdentity(
                  identity: identity,
                  name: name,
                  username: username,
                  authType: authType,
                  privateKeyPath: privateKeyPath,
                  password: password,
                  passphrase: passphrase,
                  onChanged: onChanged,
                  dialogContext: dialogContext,
                ),
              );
            },
      ),
    );
  }

  Future<void> _saveIdentity({
    required AuthIdentity? identity,
    required String name,
    required String username,
    required SshAuthType authType,
    required String privateKeyPath,
    required String password,
    required String passphrase,
    required VoidCallback onChanged,
    required BuildContext dialogContext,
  }) async {
    try {
      var secret = AuthIdentitySecret(
        password: password,
        passphrase: passphrase,
      );
      if (identity != null && password.isEmpty && passphrase.isEmpty) {
        secret =
            await _loadIdentitySecret(identity) ?? const AuthIdentitySecret();
      }
      final secretId = await _credentialStore.save(
        storage: CredentialStorage.platform,
        secret: secret.encode(),
      );
      final updated = AuthIdentity(
        id: identity?.id ?? 'identity-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        username: username,
        authType: authType,
        secretId: secretId,
        credentialStorage: CredentialStorage.platform.name,
        privateKeyPath: authType == SshAuthType.privateKey
            ? privateKeyPath
            : null,
      );
      _identityStore.upsert(updated);
      await _identityStore.save();
      if (identity != null) {
        await _credentialStore.delete(
          storage: CredentialStorage.values.firstWhere(
            (value) => value.name == identity.credentialStorage,
            orElse: () => CredentialStorage.platform,
          ),
          credentialId: identity.secretId,
        );
      }
      onChanged();
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存认证身份失败: $error')));
      }
    }
  }

  Future<void> _deleteIdentity(
    AuthIdentity identity, {
    required VoidCallback onChanged,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除认证身份'),
        content: Text('确定删除“${identity.name}”及其安全存储凭据吗？'),
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
    await _credentialStore.delete(
      storage: CredentialStorage.values.firstWhere(
        (value) => value.name == identity.credentialStorage,
        orElse: () => CredentialStorage.platform,
      ),
      credentialId: identity.secretId,
    );
    _identityStore.delete(identity.id);
    await _identityStore.save();
    onChanged();
  }

  Future<void> _createConnectionGroup() async {
    var enteredName = '';
    final group = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          autofocus: true,
          onChanged: (value) => enteredName = value,
          decoration: const InputDecoration(
            labelText: '分组名称',
            hintText: '例如：生产环境',
          ),
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isNotEmpty) Navigator.of(context).pop(name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = enteredName.trim();
              if (name.isNotEmpty) Navigator.of(context).pop(name);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (group == null || group.isEmpty) return;
    if (!_connectionGroups.contains(group)) {
      setState(() {
        _connectionGroups = <String>[..._connectionGroups, group]..sort();
      });
      await _saveAppConfig();
    }
  }

  void _openConnectionEditor(
    SessionProfileType type, {
    SessionProfile? profile,
  }) {
    if (type == SessionProfileType.ssh) {
      showDialog<void>(
        context: context,
        builder: (context) => SshProfileEditor(
          groups: _allConnectionGroups,
          identities: _identityStore.identities,
          profile: profile,
          onTest: _testSshProfile,
          onSave: (updated) => _saveConnectionProfile(profile, updated),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => ConnectionProfileEditor(
        groups: _allConnectionGroups,
        initialType: type,
        profile: profile,
        onSave: (updated) => _saveConnectionProfile(profile, updated),
      ),
    );
  }

  void _saveConnectionProfile(
    SessionProfile? previous,
    SessionProfile updated,
  ) {
    if (previous == null) {
      _profileStore.add(updated);
    } else {
      _profileStore.update(previous.id, updated);
    }
    final group = updated.folder;
    if (group != null && !_connectionGroups.contains(group)) {
      _connectionGroups = <String>[..._connectionGroups, group]..sort();
      unawaited(_saveAppConfig());
    }
    unawaited(_profileStore.save());
    setState(() {});
  }

  void _editProfile(SessionProfile profile) {
    _openConnectionEditor(profile.type, profile: profile);
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
    var enteredCommand = '';
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
                autofocus: commands.isEmpty,
                onChanged: (value) => enteredCommand = value,
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
            onPressed: () => Navigator.of(context).pop(enteredCommand.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
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

  Future<(SshConfig, NetworkConfig)> _resolveSshProfile(
    SessionProfile profile,
  ) async {
    var username = profile.username ?? '';
    var authType = profile.authType ?? SshAuthType.password;
    var password = '';
    var passphrase = '';
    var privateKeyPath = profile.privateKeyPath ?? '';

    final identityId = profile.authIdentityId;
    if (identityId != null) {
      final identity = _identityStore.identities
          .where((value) => value.id == identityId)
          .firstOrNull;
      if (identity == null) {
        throw StateError('所选认证身份已不存在');
      }
      final secret = await _loadIdentitySecret(identity);
      if (secret == null) throw StateError('无法读取认证身份');
      username = identity.username;
      authType = identity.authType;
      password = secret.password;
      passphrase = secret.passphrase;
      privateKeyPath = identity.privateKeyPath ?? '';
    } else if (profile.credentialId != null) {
      final storage = CredentialStorage.values.firstWhere(
        (value) => value.name == profile.credentialStorage,
        orElse: () => CredentialStorage.none,
      );
      final secret =
          await _credentialStore.load(
            storage: storage,
            credentialId: profile.credentialId!,
            masterPassword: _masterPassword,
          ) ??
          '';
      if (authType == SshAuthType.privateKey) {
        passphrase = secret;
      } else {
        password = secret;
      }
    } else {
      throw StateError('请选择认证身份，或连接时手动输入凭据');
    }

    final options = profile.sshOptions;
    final jumpHosts = <JumpHostConfig>[];
    for (final value in (options['jumpHosts'] as List? ?? const [])) {
      if (value is! Map) continue;
      final jump = Map<String, Object?>.from(value);
      final jumpIdentityId = jump['identityId'] as String?;
      final identity = _identityStore.identities
          .where((candidate) => candidate.id == jumpIdentityId)
          .firstOrNull;
      if (identity == null) throw StateError('跳板机认证身份已不存在');
      final secret = await _loadIdentitySecret(identity);
      if (secret == null) throw StateError('无法读取跳板机认证身份');
      jumpHosts.add(
        JumpHostConfig(
          host: jump['host'] as String? ?? '',
          port: jump['port'] as int? ?? 22,
          username: identity.username,
          password: identity.authType == SshAuthType.password
              ? secret.password
              : secret.passphrase,
          privateKeyPath: identity.authType == SshAuthType.privateKey
              ? identity.privateKeyPath
              : null,
        ),
      );
    }

    final disableProxy = options['disableProxy'] == true;
    final proxyType = options['proxyType'] as String? ?? 'none';
    ProxyConfig? proxy;
    if (!disableProxy && proxyType != 'none') {
      proxy = ProxyConfig(
        type: proxyType == 'http' ? ProxyType.http : ProxyType.socks5,
        host: options['proxyHost'] as String? ?? '',
        port: options['proxyPort'] as int? ?? 1080,
      );
    } else if (!disableProxy && jumpHosts.isEmpty) {
      proxy = _networkConfig.proxy;
    }
    final keepaliveMs = options['keepaliveIntervalMs'] as int? ?? 5000;
    final network = _networkConfig.copyWith(
      proxy: proxy,
      clearProxy: disableProxy || (proxyType == 'none' && jumpHosts.isNotEmpty),
      jumpHosts: jumpHosts.isEmpty ? _networkConfig.jumpHosts : jumpHosts,
      keepalive: KeepaliveConfig(
        enabled: keepaliveMs > 0,
        intervalSeconds: (keepaliveMs / 1000).round().clamp(1, 3600),
        maxMisses: _networkConfig.keepalive.maxMisses,
      ),
      agentForwarding: options['agentForwarding'] == true,
    );
    final privateKey = authType == SshAuthType.privateKey;
    return (
      SshConfig(
        host: profile.host ?? '',
        port: profile.port ?? 22,
        username: username,
        authentication: privateKey
            ? SshAuthentication.privateKey
            : SshAuthentication.password,
        password: privateKey ? '' : password,
        privateKeyPath: privateKeyPath,
        passphrase: privateKey ? passphrase : '',
        connectTimeoutMs: options['connectTimeoutMs'] as int? ?? 15000,
        terminalType: options['terminalType'] as String? ?? 'xterm-256color',
      ),
      network,
    );
  }

  Future<String?> _testSshProfile(SessionProfile profile) async {
    try {
      final resolved = await _resolveSshProfile(profile);
      final result = await _openSessionIsolate(
        RustCore.libraryCandidates(),
        jsonEncode(resolved.$1.toJson(network: resolved.$2.toJson())),
      ).timeout(Duration(milliseconds: resolved.$1.connectTimeoutMs + 1000));
      if (result.$1 == 0) return result.$2 ?? '未知连接错误';
      _core.attachSession(result.$1).close();
      return null;
    } on Object catch (error) {
      return error.toString();
    }
  }

  Future<void> _connectFromProfile(SessionProfile profile) async {
    try {
      if (profile.type == SessionProfileType.ssh && profile.host != null) {
        if (profile.authIdentityId != null || profile.credentialId != null) {
          final resolved = await _resolveSshProfile(profile);
          await _connect(
            resolved.$1,
            profile: profile,
            networkConfig: resolved.$2,
          );
          return;
        }
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => SessionEditor(
            initialConfig: SshConfig(
              host: profile.host!,
              port: profile.port ?? 22,
              username: profile.username ?? '',
              authentication: profile.authType == SshAuthType.privateKey
                  ? SshAuthentication.privateKey
                  : SshAuthentication.password,
              privateKeyPath: profile.privateKeyPath ?? '',
              connectTimeoutMs:
                  profile.sshOptions['connectTimeoutMs'] as int? ?? 15000,
              terminalType:
                  profile.sshOptions['terminalType'] as String? ??
                  'xterm-256color',
            ),
            identities: _identityStore.identities,
            onLoadIdentity: _loadIdentitySecret,
            onManageIdentities: _openIdentityManager,
            onConnect: (config) {
              Navigator.of(context).pop();
              unawaited(_connect(config, profile: profile));
            },
          ),
        );
        return;
      } else if (profile.type == SessionProfileType.telnet &&
          profile.host != null) {
        _sessionManager.addTelnetSession(
          name: profile.name,
          config: TelnetConfig(host: profile.host!, port: profile.port ?? 23),
        );
        final index = _sessionManager.sessions.length - 1;
        _sessionManager.updateProfileConfig(index, <String, Object?>{
          'profileId': profile.id,
          'host': profile.host,
          'port': profile.port ?? 23,
          'username': profile.username,
          'tabColor': profile.tabColor,
        });
        _sessionManager.setActiveSession(index);
        _afterProtocolConnected();
      } else if (profile.type == SessionProfileType.rdp ||
          profile.type == SessionProfileType.vnc ||
          profile.type == SessionProfileType.tunnel) {
        final type = switch (profile.type) {
          SessionProfileType.rdp => SessionType.rdp,
          SessionProfileType.vnc => SessionType.vnc,
          SessionProfileType.tunnel => SessionType.tunnel,
          _ => throw StateError('Unsupported virtual session type'),
        };
        _sessionManager.addVirtualSession(
          name: profile.name,
          type: type,
          profileConfig: <String, Object?>{
            'profileId': profile.id,
            'host': profile.host,
            'port': profile.port,
            'username': profile.username,
            'targetHost': profile.targetHost,
            'targetPort': profile.targetPort,
            'tabColor': profile.tabColor,
          },
        );
        setState(() => _showConnectionHub = false);
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
    if (session != null &&
        (session.type == SessionType.rdp ||
            session.type == SessionType.vnc ||
            session.type == SessionType.tunnel)) {
      return _ConfiguredProtocolPane(
        session: session,
        onEdit: () {
          final profileId = session.profileConfig?['profileId'] as String?;
          final profile = profileId == null
              ? null
              : _profileStore.get(profileId);
          if (profile != null) _editProfile(profile);
        },
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

  Widget _buildSessionWorkspace() {
    return Column(
      children: <Widget>[
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
              if (_showSftp && _sftpSession != null)
                SizedBox(
                  width: 380,
                  child: SftpPanel(sftpSession: _sftpSession),
                ),
              if (_showSftp && _sftpSession != null)
                const VerticalDivider(width: 1, color: Color(0xff27313b)),
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
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_securityReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TabBar(
              sessions: _sessionManager.sessions,
              activeIndex: _sessionManager.activeSessionIndex,
              homeSelected: _showConnectionHub,
              onHomeSelected: () => setState(() => _showConnectionHub = true),
              onTabSelected: (index) {
                setState(() => _showConnectionHub = false);
                _sessionManager.setActiveSession(index);
                _focusNode.requestFocus();
              },
              onTabClosed: _closeSessionAt,
            ),
            Expanded(
              child: _showConnectionHub
                  ? ConnectionHub(
                      profiles: _profileStore.profiles,
                      groups: _allConnectionGroups,
                      onOpen: (profile) {
                        unawaited(_connectFromProfile(profile));
                      },
                      onCreate: (type) => _openConnectionEditor(type),
                      onEdit: _editProfile,
                      onDuplicate: _duplicateProfile,
                      onDelete: (profile) {
                        unawaited(_deleteProfile(profile));
                      },
                      onCreateGroup: () {
                        unawaited(_createConnectionGroup());
                      },
                      onManageIdentities: _openIdentityManager,
                      onSettings: _openSettings,
                      onNetworkSettings: _openNetworkSettings,
                      onSecuritySettings: _openSecuritySettings,
                    )
                  : _buildSessionWorkspace(),
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
  final bool homeSelected;
  final VoidCallback onHomeSelected;
  final void Function(int index) onTabSelected;
  final void Function(int index) onTabClosed;

  const _TabBar({
    required this.sessions,
    required this.activeIndex,
    required this.homeSelected,
    required this.onHomeSelected,
    required this.onTabSelected,
    required this.onTabClosed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: const BoxDecoration(
        color: Color(0xff191d25),
        border: Border(bottom: BorderSide(color: Color(0xff2a303b))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _WorkspaceTab(
            label: '连接中心',
            icon: Icons.hub_outlined,
            selected: homeSelected,
            onTap: onHomeSelected,
          ),
          ...sessions.asMap().entries.map((entry) {
            final index = entry.key;
            final session = entry.value;
            return _WorkspaceTab(
              label: session.name,
              icon: _sessionTypeIcon(session.type),
              selected: !homeSelected && index == activeIndex,
              accentColor: _tabColor(session.profileConfig?['tabColor']),
              onTap: () => onTabSelected(index),
              onClose: () => onTabClosed(index),
            );
          }),
        ],
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

IconData _sessionTypeIcon(SessionType type) {
  return switch (type) {
    SessionType.ssh => Icons.terminal_rounded,
    SessionType.rdp => Icons.desktop_windows_outlined,
    SessionType.telnet => Icons.settings_ethernet_rounded,
    SessionType.tunnel => Icons.route_outlined,
    SessionType.vnc => Icons.monitor_outlined,
    SessionType.localShell => Icons.code_rounded,
    SessionType.rawTcp => Icons.cable_rounded,
    SessionType.serial => Icons.usb_rounded,
  };
}

class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.onClose,
    this.accentColor,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 132, maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff263247) : Colors.transparent,
          border: Border(
            top: BorderSide(
              color:
                  accentColor ??
                  (selected ? const Color(0xff72c991) : Colors.transparent),
              width: 2,
            ),
            right: const BorderSide(color: Color(0xff2a303b)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: const Color(0xff8fb6ff)),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: selected
                      ? const Color(0xffd7e0ee)
                      : const Color(0xff8e98a8),
                ),
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 7),
              InkWell(
                onTap: onClose,
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Color(0xff8e98a8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConfiguredProtocolPane extends StatelessWidget {
  const _ConfiguredProtocolPane({required this.session, required this.onEdit});

  final SessionInfo session;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final config = session.profileConfig ?? const <String, Object?>{};
    final host = config['host'] as String?;
    final port = config['port'] as int?;
    final targetHost = config['targetHost'] as String?;
    final targetPort = config['targetPort'] as int?;
    final protocol = switch (session.type) {
      SessionType.rdp => 'RDP',
      SessionType.vnc => 'VNC',
      SessionType.tunnel => 'SSH 隧道',
      _ => session.type.name.toUpperCase(),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _sessionTypeIcon(session.type),
                      size: 32,
                      color: const Color(0xff72c991),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '$protocol · ${host ?? '-'}:${port ?? '-'}',
                            style: const TextStyle(color: Color(0xff9aa7b5)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (targetHost != null) ...[
                  const SizedBox(height: 18),
                  Text('目标地址：$targetHost:${targetPort ?? '-'}'),
                ],
                const SizedBox(height: 22),
                const Text(
                  '连接配置已经保存并作为独立标签打开。当前版本尚未接入该协议的传输与画面渲染核心，因此不会伪装为已连接状态。',
                  style: TextStyle(height: 1.5, color: Color(0xffb7c0cc)),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑连接配置'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
