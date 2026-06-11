import 'dart:convert';
import 'dart:io';

/// 会话配置类型
enum SessionProfileType { ssh, localShell }

/// SSH 认证方式
enum SshAuthType { password, privateKey, keyboardInteractive }

/// 会话配置
class SessionProfile {
  final String id;
  final String name;
  final SessionProfileType type;
  final String? folder;
  final List<String> tags;

  // SSH 配置
  final String? host;
  final int? port;
  final String? username;
  final SshAuthType? authType;
  final String? privateKeyPath;
  final String? credentialId;
  final String? credentialStorage;

  // 本地 Shell 配置
  final String? shell;
  final String? workingDir;

  // 终端配置
  final String? term;
  final int? cols;
  final int? rows;
  final String? encoding;

  // 自动登录
  final bool autoLogin;

  // 日志
  final bool logging;
  final String? logPath;

  // 快捷命令
  final List<String> quickCommands;
  final String? tabColor;

  const SessionProfile({
    required this.id,
    required this.name,
    required this.type,
    this.folder,
    this.tags = const [],
    this.host,
    this.port,
    this.username,
    this.authType,
    this.privateKeyPath,
    this.credentialId,
    this.credentialStorage,
    this.shell,
    this.workingDir,
    this.term,
    this.cols,
    this.rows,
    this.encoding,
    this.autoLogin = false,
    this.logging = false,
    this.logPath,
    this.quickCommands = const [],
    this.tabColor,
  });

  SessionProfile copyWith({
    String? id,
    String? name,
    SessionProfileType? type,
    String? folder,
    List<String>? tags,
    String? host,
    int? port,
    String? username,
    SshAuthType? authType,
    String? privateKeyPath,
    String? credentialId,
    String? credentialStorage,
    String? shell,
    String? workingDir,
    String? term,
    int? cols,
    int? rows,
    String? encoding,
    bool? autoLogin,
    bool? logging,
    String? logPath,
    List<String>? quickCommands,
    String? tabColor,
  }) {
    return SessionProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      folder: folder ?? this.folder,
      tags: tags ?? this.tags,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      privateKeyPath: privateKeyPath ?? this.privateKeyPath,
      credentialId: credentialId ?? this.credentialId,
      credentialStorage: credentialStorage ?? this.credentialStorage,
      shell: shell ?? this.shell,
      workingDir: workingDir ?? this.workingDir,
      term: term ?? this.term,
      cols: cols ?? this.cols,
      rows: rows ?? this.rows,
      encoding: encoding ?? this.encoding,
      autoLogin: autoLogin ?? this.autoLogin,
      logging: logging ?? this.logging,
      logPath: logPath ?? this.logPath,
      quickCommands: quickCommands ?? this.quickCommands,
      tabColor: tabColor ?? this.tabColor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'folder': folder,
      'tags': tags,
      'host': host,
      'port': port,
      'username': username,
      'authType': authType?.name,
      'privateKeyPath': privateKeyPath,
      'credentialId': credentialId,
      'credentialStorage': credentialStorage,
      'shell': shell,
      'workingDir': workingDir,
      'term': term,
      'cols': cols,
      'rows': rows,
      'encoding': encoding,
      'autoLogin': autoLogin,
      'logging': logging,
      'logPath': logPath,
      'quickCommands': quickCommands,
      'tabColor': tabColor,
    };
  }

  factory SessionProfile.fromJson(Map<String, dynamic> json) {
    return SessionProfile(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: SessionProfileType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SessionProfileType.ssh,
      ),
      folder: json['folder'],
      tags: List<String>.from(json['tags'] ?? []),
      host: json['host'],
      port: json['port'],
      username: json['username'],
      authType: json['authType'] != null
          ? SshAuthType.values.firstWhere(
              (e) => e.name == json['authType'],
              orElse: () => SshAuthType.password,
            )
          : null,
      privateKeyPath: json['privateKeyPath'],
      credentialId: json['credentialId'],
      credentialStorage: json['credentialStorage'],
      shell: json['shell'],
      workingDir: json['workingDir'],
      term: json['term'],
      cols: json['cols'],
      rows: json['rows'],
      encoding: json['encoding'],
      autoLogin: json['autoLogin'] ?? false,
      logging: json['logging'] ?? false,
      logPath: json['logPath'],
      quickCommands: List<String>.from(json['quickCommands'] ?? []),
      tabColor: json['tabColor'],
    );
  }
}

/// 会话配置存储管理
class SessionProfileStore {
  static const String _fileName = 'profiles.json';
  final String _dataDir;
  List<SessionProfile> _profiles = [];

  SessionProfileStore(this._dataDir);

  /// 加载配置
  Future<void> load() async {
    final file = File('$_dataDir/$_fileName');
    if (!await file.exists()) {
      _profiles = [];
      return;
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as List;
      _profiles = json.map((e) => SessionProfile.fromJson(e)).toList();
    } catch (e) {
      _profiles = [];
    }
  }

  /// 保存配置
  Future<void> save() async {
    final file = File('$_dataDir/$_fileName');
    await file.create(recursive: true);
    final json = _profiles.map((e) => e.toJson()).toList();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  /// 获取所有配置
  List<SessionProfile> get profiles => List.unmodifiable(_profiles);

  /// 获取文件夹列表
  List<String> get folders {
    final folderSet = <String>{};
    for (final profile in _profiles) {
      if (profile.folder != null) {
        folderSet.add(profile.folder!);
      }
    }
    return folderSet.toList()..sort();
  }

  /// 获取标签列表
  List<String> get tags {
    final tagSet = <String>{};
    for (final profile in _profiles) {
      tagSet.addAll(profile.tags);
    }
    return tagSet.toList()..sort();
  }

  /// 添加配置
  void add(SessionProfile profile) {
    _profiles.add(profile);
  }

  /// 更新配置
  void update(String id, SessionProfile profile) {
    final index = _profiles.indexWhere((p) => p.id == id);
    if (index >= 0) {
      _profiles[index] = profile;
    }
  }

  /// 删除配置
  void delete(String id) {
    _profiles.removeWhere((p) => p.id == id);
  }

  /// 获取配置
  SessionProfile? get(String id) {
    try {
      return _profiles.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 按文件夹分组
  Map<String?, List<SessionProfile>> getByFolder() {
    final map = <String?, List<SessionProfile>>{};
    for (final profile in _profiles) {
      final folder = profile.folder;
      map.putIfAbsent(folder, () => []).add(profile);
    }
    return map;
  }

  /// 按标签筛选
  List<SessionProfile> getByTag(String tag) {
    return _profiles.where((p) => p.tags.contains(tag)).toList();
  }

  /// 搜索配置
  List<SessionProfile> search(String query) {
    final lowerQuery = query.toLowerCase();
    return _profiles.where((p) {
      return p.name.toLowerCase().contains(lowerQuery) ||
          (p.host?.toLowerCase().contains(lowerQuery) ?? false) ||
          (p.username?.toLowerCase().contains(lowerQuery) ?? false) ||
          p.tags.any((t) => t.toLowerCase().contains(lowerQuery));
    }).toList();
  }
}
