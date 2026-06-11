import 'package:flutter/material.dart';
import 'network_config.dart';

/// 网络设置页面
class NetworkSettingsPage extends StatefulWidget {
  final NetworkConfig config;
  final void Function(NetworkConfig config) onConfigChanged;

  const NetworkSettingsPage({
    super.key,
    required this.config,
    required this.onConfigChanged,
  });

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  late NetworkConfig _config;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
  }

  void _updateConfig(NetworkConfig newConfig) {
    setState(() {
      _config = newConfig;
    });
    widget.onConfigChanged(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络设置'),
        backgroundColor: const Color(0xff191d25),
      ),
      backgroundColor: const Color(0xff111318),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(title: '代理', children: [_buildProxySettings()]),
          const SizedBox(height: 16),
          _buildSection(
            title: 'ProxyCommand',
            children: [_buildProxyCommandSettings()],
          ),
          const SizedBox(height: 16),
          _buildSection(title: '跳板机', children: [_buildJumpHostSettings()]),
          const SizedBox(height: 16),
          _buildSection(title: '端口转发', children: [_buildPortForwardSettings()]),
          const SizedBox(height: 16),
          _buildSection(
            title: 'Keepalive',
            children: [_buildKeepaliveSettings()],
          ),
          const SizedBox(height: 16),
          _buildSection(title: '重连策略', children: [_buildReconnectSettings()]),
          const SizedBox(height: 16),
          _buildSection(title: '高级', children: [_buildAdvancedSettings()]),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff191d25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff2a303b)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xffd7e0ee),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildProxySettings() {
    final proxy = _config.proxy;
    return Column(
      children: [
        DropdownButtonFormField<ProxyType>(
          initialValue: proxy?.type ?? ProxyType.none,
          dropdownColor: const Color(0xff191d25),
          style: const TextStyle(color: Color(0xffd7e0ee)),
          decoration: const InputDecoration(
            labelText: '代理类型',
            labelStyle: TextStyle(color: Color(0xff8e98a8)),
          ),
          items: const [
            DropdownMenuItem(value: ProxyType.none, child: Text('无')),
            DropdownMenuItem(value: ProxyType.http, child: Text('HTTP')),
            DropdownMenuItem(value: ProxyType.socks5, child: Text('SOCKS5')),
          ],
          onChanged: (value) {
            if (value == ProxyType.none) {
              _updateConfig(_config.copyWith(clearProxy: true));
            } else {
              _updateConfig(
                _config.copyWith(
                  proxy: ProxyConfig(
                    type: value!,
                    host: proxy?.host ?? '',
                    port: proxy?.port ?? 1080,
                    username: proxy?.username,
                    password: proxy?.password,
                  ),
                ),
              );
            }
          },
        ),
        if (proxy != null && proxy.type != ProxyType.none) ...[
          const SizedBox(height: 8),
          TextFormField(
            initialValue: proxy.host,
            style: const TextStyle(color: Color(0xffd7e0ee)),
            decoration: const InputDecoration(
              labelText: '代理主机',
              labelStyle: TextStyle(color: Color(0xff8e98a8)),
            ),
            onChanged: (value) {
              _updateConfig(
                _config.copyWith(
                  proxy: ProxyConfig(
                    type: proxy.type,
                    host: value,
                    port: proxy.port,
                    username: proxy.username,
                    password: proxy.password,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: proxy.port.toString(),
            style: const TextStyle(color: Color(0xffd7e0ee)),
            decoration: const InputDecoration(
              labelText: '代理端口',
              labelStyle: TextStyle(color: Color(0xff8e98a8)),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              _updateConfig(
                _config.copyWith(
                  proxy: ProxyConfig(
                    type: proxy.type,
                    host: proxy.host,
                    port: int.tryParse(value) ?? 1080,
                    username: proxy.username,
                    password: proxy.password,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildProxyCommandSettings() {
    return TextFormField(
      initialValue: _config.proxyCommand,
      style: const TextStyle(color: Color(0xffd7e0ee)),
      decoration: const InputDecoration(
        labelText: '命令',
        hintText: 'cloudflared access ssh --hostname %h',
        helperText: '支持 %h（主机）、%p（端口）、%%（百分号）',
        labelStyle: TextStyle(color: Color(0xff8e98a8)),
      ),
      onChanged: (value) {
        final command = value.trim();
        _updateConfig(
          command.isEmpty
              ? _config.copyWith(clearProxyCommand: true)
              : _config.copyWith(proxyCommand: command),
        );
      },
    );
  }

  Widget _buildJumpHostSettings() {
    return Column(
      children: [
        ..._config.jumpHosts.asMap().entries.map((entry) {
          final index = entry.key;
          final jump = entry.value;
          return Card(
            color: const Color(0xff111318),
            child: ListTile(
              title: Text(
                '${jump.username}@${jump.host}:${jump.port}',
                style: const TextStyle(color: Color(0xffd7e0ee)),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                onPressed: () {
                  final newList = List<JumpHostConfig>.from(_config.jumpHosts);
                  newList.removeAt(index);
                  _updateConfig(_config.copyWith(jumpHosts: newList));
                },
              ),
            ),
          );
        }),
        ElevatedButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加跳板机'),
          onPressed: () {
            _showAddJumpHostDialog();
          },
        ),
      ],
    );
  }

  void _showAddJumpHostDialog() {
    final hostController = TextEditingController();
    final portController = TextEditingController(text: '22');
    final usernameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff191d25),
        title: const Text('添加跳板机', style: TextStyle(color: Color(0xffd7e0ee))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hostController,
              style: const TextStyle(color: Color(0xffd7e0ee)),
              decoration: const InputDecoration(
                labelText: '主机',
                labelStyle: TextStyle(color: Color(0xff8e98a8)),
              ),
            ),
            TextField(
              controller: portController,
              style: const TextStyle(color: Color(0xffd7e0ee)),
              decoration: const InputDecoration(
                labelText: '端口',
                labelStyle: TextStyle(color: Color(0xff8e98a8)),
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: usernameController,
              style: const TextStyle(color: Color(0xffd7e0ee)),
              decoration: const InputDecoration(
                labelText: '用户名',
                labelStyle: TextStyle(color: Color(0xff8e98a8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              final newList = List<JumpHostConfig>.from(_config.jumpHosts);
              newList.add(
                JumpHostConfig(
                  host: hostController.text,
                  port: int.tryParse(portController.text) ?? 22,
                  username: usernameController.text,
                ),
              );
              _updateConfig(_config.copyWith(jumpHosts: newList));
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Widget _buildPortForwardSettings() {
    return Column(
      children: [
        ..._config.portForwards.asMap().entries.map((entry) {
          final index = entry.key;
          final forward = entry.value;
          return Card(
            color: const Color(0xff111318),
            child: ListTile(
              title: Text(
                forward.description,
                style: const TextStyle(color: Color(0xffd7e0ee)),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                onPressed: () {
                  final newList = List<PortForwardConfig>.from(
                    _config.portForwards,
                  );
                  newList.removeAt(index);
                  _updateConfig(_config.copyWith(portForwards: newList));
                },
              ),
            ),
          );
        }),
        ElevatedButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加端口转发'),
          onPressed: () {
            _showAddPortForwardDialog();
          },
        ),
      ],
    );
  }

  void _showAddPortForwardDialog() {
    var type = PortForwardType.local;
    final bindAddressController = TextEditingController(text: 'localhost');
    final bindPortController = TextEditingController();
    final remoteHostController = TextEditingController();
    final remotePortController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff191d25),
          title: const Text(
            '添加端口转发',
            style: TextStyle(color: Color(0xffd7e0ee)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<PortForwardType>(
                initialValue: type,
                dropdownColor: const Color(0xff191d25),
                style: const TextStyle(color: Color(0xffd7e0ee)),
                decoration: const InputDecoration(
                  labelText: '类型',
                  labelStyle: TextStyle(color: Color(0xff8e98a8)),
                ),
                items: const [
                  DropdownMenuItem(
                    value: PortForwardType.local,
                    child: Text('本地转发'),
                  ),
                  DropdownMenuItem(
                    value: PortForwardType.remote,
                    child: Text('远程转发'),
                  ),
                  DropdownMenuItem(
                    value: PortForwardType.dynamic,
                    child: Text('动态转发'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => type = value);
                },
              ),
              TextField(
                controller: bindAddressController,
                style: const TextStyle(color: Color(0xffd7e0ee)),
                decoration: const InputDecoration(
                  labelText: '绑定地址',
                  labelStyle: TextStyle(color: Color(0xff8e98a8)),
                ),
              ),
              TextField(
                controller: bindPortController,
                style: const TextStyle(color: Color(0xffd7e0ee)),
                decoration: const InputDecoration(
                  labelText: '绑定端口',
                  labelStyle: TextStyle(color: Color(0xff8e98a8)),
                ),
                keyboardType: TextInputType.number,
              ),
              if (type != PortForwardType.dynamic) ...[
                TextField(
                  controller: remoteHostController,
                  style: const TextStyle(color: Color(0xffd7e0ee)),
                  decoration: const InputDecoration(
                    labelText: '目标主机',
                    labelStyle: TextStyle(color: Color(0xff8e98a8)),
                  ),
                ),
                TextField(
                  controller: remotePortController,
                  style: const TextStyle(color: Color(0xffd7e0ee)),
                  decoration: const InputDecoration(
                    labelText: '目标端口',
                    labelStyle: TextStyle(color: Color(0xff8e98a8)),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                final newList = List<PortForwardConfig>.from(
                  _config.portForwards,
                );
                newList.add(
                  PortForwardConfig(
                    type: type,
                    bindAddress: bindAddressController.text,
                    bindPort: int.tryParse(bindPortController.text) ?? 0,
                    remoteHost: remoteHostController.text,
                    remotePort: int.tryParse(remotePortController.text),
                  ),
                );
                _updateConfig(_config.copyWith(portForwards: newList));
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeepaliveSettings() {
    final keepalive = _config.keepalive;
    return Column(
      children: [
        SwitchListTile(
          title: const Text(
            '启用 Keepalive',
            style: TextStyle(color: Color(0xffd7e0ee)),
          ),
          value: keepalive.enabled,
          activeThumbColor: const Color(0xff2f6fed),
          onChanged: (value) {
            _updateConfig(
              _config.copyWith(
                keepalive: KeepaliveConfig(
                  enabled: value,
                  intervalSeconds: keepalive.intervalSeconds,
                  maxMisses: keepalive.maxMisses,
                ),
              ),
            );
          },
        ),
        if (keepalive.enabled) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('间隔 (秒)', style: TextStyle(color: Color(0xff8e98a8))),
              const SizedBox(width: 16),
              Expanded(
                child: Slider(
                  value: keepalive.intervalSeconds.toDouble(),
                  min: 10,
                  max: 120,
                  divisions: 11,
                  activeColor: const Color(0xff2f6fed),
                  onChanged: (value) {
                    _updateConfig(
                      _config.copyWith(
                        keepalive: KeepaliveConfig(
                          enabled: keepalive.enabled,
                          intervalSeconds: value.round(),
                          maxMisses: keepalive.maxMisses,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Text(
                '${keepalive.intervalSeconds}s',
                style: const TextStyle(color: Color(0xffd7e0ee)),
              ),
            ],
          ),
          Row(
            children: [
              const Text('最大丢失', style: TextStyle(color: Color(0xff8e98a8))),
              const SizedBox(width: 16),
              Expanded(
                child: Slider(
                  value: keepalive.maxMisses.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  activeColor: const Color(0xff2f6fed),
                  onChanged: (value) {
                    _updateConfig(
                      _config.copyWith(
                        keepalive: KeepaliveConfig(
                          enabled: keepalive.enabled,
                          intervalSeconds: keepalive.intervalSeconds,
                          maxMisses: value.round(),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Text(
                '${keepalive.maxMisses}',
                style: const TextStyle(color: Color(0xffd7e0ee)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildReconnectSettings() {
    final reconnect = _config.reconnect;
    return Column(
      children: [
        SwitchListTile(
          title: const Text(
            '启用自动重连',
            style: TextStyle(color: Color(0xffd7e0ee)),
          ),
          value: reconnect.enabled,
          activeThumbColor: const Color(0xff2f6fed),
          onChanged: (value) {
            _updateConfig(
              _config.copyWith(
                reconnect: ReconnectPolicy(
                  enabled: value,
                  maxAttempts: reconnect.maxAttempts,
                  initialDelayMs: reconnect.initialDelayMs,
                  maxDelayMs: reconnect.maxDelayMs,
                  backoffFactor: reconnect.backoffFactor,
                  jitter: reconnect.jitter,
                ),
              ),
            );
          },
        ),
        if (reconnect.enabled) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('最大尝试', style: TextStyle(color: Color(0xff8e98a8))),
              const SizedBox(width: 16),
              Expanded(
                child: Slider(
                  value: reconnect.maxAttempts.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  activeColor: const Color(0xff2f6fed),
                  onChanged: (value) {
                    _updateConfig(
                      _config.copyWith(
                        reconnect: ReconnectPolicy(
                          enabled: reconnect.enabled,
                          maxAttempts: value.round(),
                          initialDelayMs: reconnect.initialDelayMs,
                          maxDelayMs: reconnect.maxDelayMs,
                          backoffFactor: reconnect.backoffFactor,
                          jitter: reconnect.jitter,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Text(
                '${reconnect.maxAttempts}',
                style: const TextStyle(color: Color(0xffd7e0ee)),
              ),
            ],
          ),
          SwitchListTile(
            title: const Text(
              '指数退避',
              style: TextStyle(color: Color(0xffd7e0ee)),
            ),
            value: reconnect.backoffFactor > 1,
            activeThumbColor: const Color(0xff2f6fed),
            onChanged: (value) {
              _updateConfig(
                _config.copyWith(
                  reconnect: ReconnectPolicy(
                    enabled: reconnect.enabled,
                    maxAttempts: reconnect.maxAttempts,
                    initialDelayMs: reconnect.initialDelayMs,
                    maxDelayMs: reconnect.maxDelayMs,
                    backoffFactor: value ? 2.0 : 1.0,
                    jitter: reconnect.jitter,
                  ),
                ),
              );
            },
          ),
          SwitchListTile(
            title: const Text('抖动', style: TextStyle(color: Color(0xffd7e0ee))),
            subtitle: const Text(
              '添加随机延迟避免重连风暴',
              style: TextStyle(color: Color(0xff4a5568), fontSize: 12),
            ),
            value: reconnect.jitter,
            activeThumbColor: const Color(0xff2f6fed),
            onChanged: (value) {
              _updateConfig(
                _config.copyWith(
                  reconnect: ReconnectPolicy(
                    enabled: reconnect.enabled,
                    maxAttempts: reconnect.maxAttempts,
                    initialDelayMs: reconnect.initialDelayMs,
                    maxDelayMs: reconnect.maxDelayMs,
                    backoffFactor: reconnect.backoffFactor,
                    jitter: value,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildAdvancedSettings() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text(
            'SSH Agent 转发',
            style: TextStyle(color: Color(0xffd7e0ee)),
          ),
          subtitle: const Text(
            '允许使用本地 SSH agent 进行认证',
            style: TextStyle(color: Color(0xff4a5568), fontSize: 12),
          ),
          value: _config.agentForwarding,
          activeThumbColor: const Color(0xff2f6fed),
          onChanged: (value) {
            _updateConfig(_config.copyWith(agentForwarding: value));
          },
        ),
      ],
    );
  }
}
