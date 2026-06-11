/// 代理类型
enum ProxyType {
  none,
  http,
  socks5,
}

/// 代理配置
class ProxyConfig {
  final ProxyType type;
  final String host;
  final int port;
  final String? username;
  final String? password;

  const ProxyConfig({
    required this.type,
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
    };
  }

  factory ProxyConfig.fromJson(Map<String, dynamic> json) {
    return ProxyConfig(
      type: ProxyType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ProxyType.none,
      ),
      host: json['host'] ?? '',
      port: json['port'] ?? 0,
      username: json['username'],
      password: json['password'],
    );
  }
}

/// 跳板配置
class JumpHostConfig {
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKeyPath;

  const JumpHostConfig({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKeyPath,
  });

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'privateKeyPath': privateKeyPath,
    };
  }

  factory JumpHostConfig.fromJson(Map<String, dynamic> json) {
    return JumpHostConfig(
      host: json['host'] ?? '',
      port: json['port'] ?? 22,
      username: json['username'] ?? '',
      password: json['password'],
      privateKeyPath: json['privateKeyPath'],
    );
  }
}

/// 端口转发类型
enum PortForwardType {
  local,
  remote,
  dynamic,
}

/// 端口转发配置
class PortForwardConfig {
  final PortForwardType type;
  final String bindAddress;
  final int bindPort;
  final String? remoteHost;
  final int? remotePort;

  const PortForwardConfig({
    required this.type,
    required this.bindAddress,
    required this.bindPort,
    this.remoteHost,
    this.remotePort,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'bindAddress': bindAddress,
      'bindPort': bindPort,
      'remoteHost': remoteHost,
      'remotePort': remotePort,
    };
  }

  factory PortForwardConfig.fromJson(Map<String, dynamic> json) {
    return PortForwardConfig(
      type: PortForwardType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => PortForwardType.local,
      ),
      bindAddress: json['bindAddress'] ?? 'localhost',
      bindPort: json['bindPort'] ?? 0,
      remoteHost: json['remoteHost'],
      remotePort: json['remotePort'],
    );
  }

  String get description {
    switch (type) {
      case PortForwardType.local:
        return 'L:$bindPort → $remoteHost:$remotePort';
      case PortForwardType.remote:
        return 'R:$bindPort → $remoteHost:$remotePort';
      case PortForwardType.dynamic:
        return 'D:$bindPort';
    }
  }
}

/// Keepalive 配置
class KeepaliveConfig {
  final bool enabled;
  final int intervalSeconds;
  final int maxMisses;

  const KeepaliveConfig({
    this.enabled = true,
    this.intervalSeconds = 30,
    this.maxMisses = 3,
  });

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'intervalSeconds': intervalSeconds,
      'maxMisses': maxMisses,
    };
  }

  factory KeepaliveConfig.fromJson(Map<String, dynamic> json) {
    return KeepaliveConfig(
      enabled: json['enabled'] ?? true,
      intervalSeconds: json['intervalSeconds'] ?? 30,
      maxMisses: json['maxMisses'] ?? 3,
    );
  }
}

/// 重连策略
class ReconnectPolicy {
  final bool enabled;
  final int maxAttempts;
  final int initialDelayMs;
  final int maxDelayMs;
  final double backoffFactor;
  final bool jitter;

  const ReconnectPolicy({
    this.enabled = true,
    this.maxAttempts = 3,
    this.initialDelayMs = 1000,
    this.maxDelayMs = 30000,
    this.backoffFactor = 2.0,
    this.jitter = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'maxAttempts': maxAttempts,
      'initialDelayMs': initialDelayMs,
      'maxDelayMs': maxDelayMs,
      'backoffFactor': backoffFactor,
      'jitter': jitter,
    };
  }

  factory ReconnectPolicy.fromJson(Map<String, dynamic> json) {
    return ReconnectPolicy(
      enabled: json['enabled'] ?? true,
      maxAttempts: json['maxAttempts'] ?? 3,
      initialDelayMs: json['initialDelayMs'] ?? 1000,
      maxDelayMs: json['maxDelayMs'] ?? 30000,
      backoffFactor: (json['backoffFactor'] ?? 2.0).toDouble(),
      jitter: json['jitter'] ?? true,
    );
  }
}

/// 网络配置
class NetworkConfig {
  final ProxyConfig? proxy;
  final List<JumpHostConfig> jumpHosts;
  final List<PortForwardConfig> portForwards;
  final KeepaliveConfig keepalive;
  final ReconnectPolicy reconnect;
  final bool agentForwarding;

  const NetworkConfig({
    this.proxy,
    this.jumpHosts = const [],
    this.portForwards = const [],
    this.keepalive = const KeepaliveConfig(),
    this.reconnect = const ReconnectPolicy(),
    this.agentForwarding = false,
  });

  NetworkConfig copyWith({
    ProxyConfig? proxy,
    List<JumpHostConfig>? jumpHosts,
    List<PortForwardConfig>? portForwards,
    KeepaliveConfig? keepalive,
    ReconnectPolicy? reconnect,
    bool? agentForwarding,
  }) {
    return NetworkConfig(
      proxy: proxy ?? this.proxy,
      jumpHosts: jumpHosts ?? this.jumpHosts,
      portForwards: portForwards ?? this.portForwards,
      keepalive: keepalive ?? this.keepalive,
      reconnect: reconnect ?? this.reconnect,
      agentForwarding: agentForwarding ?? this.agentForwarding,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'proxy': proxy?.toJson(),
      'jumpHosts': jumpHosts.map((e) => e.toJson()).toList(),
      'portForwards': portForwards.map((e) => e.toJson()).toList(),
      'keepalive': keepalive.toJson(),
      'reconnect': reconnect.toJson(),
      'agentForwarding': agentForwarding,
    };
  }

  factory NetworkConfig.fromJson(Map<String, dynamic> json) {
    return NetworkConfig(
      proxy: json['proxy'] != null
          ? ProxyConfig.fromJson(json['proxy'])
          : null,
      jumpHosts: (json['jumpHosts'] as List?)
              ?.map((e) => JumpHostConfig.fromJson(e))
              .toList() ??
          [],
      portForwards: (json['portForwards'] as List?)
              ?.map((e) => PortForwardConfig.fromJson(e))
              .toList() ??
          [],
      keepalive: json['keepalive'] != null
          ? KeepaliveConfig.fromJson(json['keepalive'])
          : const KeepaliveConfig(),
      reconnect: json['reconnect'] != null
          ? ReconnectPolicy.fromJson(json['reconnect'])
          : const ReconnectPolicy(),
      agentForwarding: json['agentForwarding'] ?? false,
    );
  }
}
