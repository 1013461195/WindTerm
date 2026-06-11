/// 安全级别
enum SecurityLevel {
  low,
  medium,
  high,
  maximum,
}

/// 凭据存储方式
enum CredentialStorage {
  none, // 不保存
  platform, // 平台 keychain
  vault, // 主密码加密 vault
}

/// 安全配置
class SecurityConfig {
  final CredentialStorage credentialStorage;
  final bool masterPasswordEnabled;
  final bool hostKeyPinning;
  final bool auditLogEnabled;
  final String? auditLogPath;
  final SecurityLevel level;
  final bool clipboardAutoClear;
  final int clipboardAutoClearSeconds;
  final bool osc52Disabled;
  final bool pasteConfirmation;

  const SecurityConfig({
    this.credentialStorage = CredentialStorage.none,
    this.masterPasswordEnabled = false,
    this.hostKeyPinning = true,
    this.auditLogEnabled = false,
    this.auditLogPath,
    this.level = SecurityLevel.medium,
    this.clipboardAutoClear = false,
    this.clipboardAutoClearSeconds = 30,
    this.osc52Disabled = true,
    this.pasteConfirmation = true,
  });

  SecurityConfig copyWith({
    CredentialStorage? credentialStorage,
    bool? masterPasswordEnabled,
    bool? hostKeyPinning,
    bool? auditLogEnabled,
    String? auditLogPath,
    SecurityLevel? level,
    bool? clipboardAutoClear,
    int? clipboardAutoClearSeconds,
    bool? osc52Disabled,
    bool? pasteConfirmation,
  }) {
    return SecurityConfig(
      credentialStorage: credentialStorage ?? this.credentialStorage,
      masterPasswordEnabled: masterPasswordEnabled ?? this.masterPasswordEnabled,
      hostKeyPinning: hostKeyPinning ?? this.hostKeyPinning,
      auditLogEnabled: auditLogEnabled ?? this.auditLogEnabled,
      auditLogPath: auditLogPath ?? this.auditLogPath,
      level: level ?? this.level,
      clipboardAutoClear: clipboardAutoClear ?? this.clipboardAutoClear,
      clipboardAutoClearSeconds: clipboardAutoClearSeconds ?? this.clipboardAutoClearSeconds,
      osc52Disabled: osc52Disabled ?? this.osc52Disabled,
      pasteConfirmation: pasteConfirmation ?? this.pasteConfirmation,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'credentialStorage': credentialStorage.name,
      'masterPasswordEnabled': masterPasswordEnabled,
      'hostKeyPinning': hostKeyPinning,
      'auditLogEnabled': auditLogEnabled,
      'auditLogPath': auditLogPath,
      'level': level.name,
      'clipboardAutoClear': clipboardAutoClear,
      'clipboardAutoClearSeconds': clipboardAutoClearSeconds,
      'osc52Disabled': osc52Disabled,
      'pasteConfirmation': pasteConfirmation,
    };
  }

  factory SecurityConfig.fromJson(Map<String, dynamic> json) {
    return SecurityConfig(
      credentialStorage: CredentialStorage.values.firstWhere(
        (e) => e.name == json['credentialStorage'],
        orElse: () => CredentialStorage.none,
      ),
      masterPasswordEnabled: json['masterPasswordEnabled'] ?? false,
      hostKeyPinning: json['hostKeyPinning'] ?? true,
      auditLogEnabled: json['auditLogEnabled'] ?? false,
      auditLogPath: json['auditLogPath'],
      level: SecurityLevel.values.firstWhere(
        (e) => e.name == json['level'],
        orElse: () => SecurityLevel.medium,
      ),
      clipboardAutoClear: json['clipboardAutoClear'] ?? false,
      clipboardAutoClearSeconds: json['clipboardAutoClearSeconds'] ?? 30,
      osc52Disabled: json['osc52Disabled'] ?? true,
      pasteConfirmation: json['pasteConfirmation'] ?? true,
    );
  }
}

/// Host Key 状态
enum HostKeyStatus {
  ok,
  unknown,
  changed,
  otherAlgorithm,
  notFound,
  error,
}

/// Host Key 信息
class HostKeyInfo {
  final String host;
  final int port;
  final String algorithm;
  final String fingerprintSha256;
  final String? fingerprintMd5;
  final HostKeyStatus status;
  final DateTime? lastSeen;

  const HostKeyInfo({
    required this.host,
    required this.port,
    required this.algorithm,
    required this.fingerprintSha256,
    this.fingerprintMd5,
    required this.status,
    this.lastSeen,
  });

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'algorithm': algorithm,
      'fingerprintSha256': fingerprintSha256,
      'fingerprintMd5': fingerprintMd5,
      'status': status.name,
      'lastSeen': lastSeen?.toIso8601String(),
    };
  }

  factory HostKeyInfo.fromJson(Map<String, dynamic> json) {
    return HostKeyInfo(
      host: json['host'] ?? '',
      port: json['port'] ?? 22,
      algorithm: json['algorithm'] ?? '',
      fingerprintSha256: json['fingerprintSha256'] ?? '',
      fingerprintMd5: json['fingerprintMd5'],
      status: HostKeyStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => HostKeyStatus.unknown,
      ),
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'])
          : null,
    );
  }
}

/// 审计日志条目
class AuditLogEntry {
  final DateTime timestamp;
  final String sessionId;
  final String action;
  final String? detail;
  final String? user;
  final String? host;

  const AuditLogEntry({
    required this.timestamp,
    required this.sessionId,
    required this.action,
    this.detail,
    this.user,
    this.host,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'sessionId': sessionId,
      'action': action,
      'detail': detail,
      'user': user,
      'host': host,
    };
  }

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      timestamp: DateTime.parse(json['timestamp']),
      sessionId: json['sessionId'] ?? '',
      action: json['action'] ?? '',
      detail: json['detail'],
      user: json['user'],
      host: json['host'],
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('[${timestamp.toIso8601String()}] ');
    buffer.write('$action ');
    if (user != null) buffer.write('user=$user ');
    if (host != null) buffer.write('host=$host ');
    buffer.write('session=$sessionId');
    if (detail != null) buffer.write(' $detail');
    return buffer.toString();
  }
}
