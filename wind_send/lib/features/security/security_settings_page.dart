import 'package:flutter/material.dart';
import 'security_config.dart';

/// 安全设置页面
class SecuritySettingsPage extends StatefulWidget {
  final SecurityConfig config;
  final void Function(SecurityConfig config) onConfigChanged;

  const SecuritySettingsPage({
    super.key,
    required this.config,
    required this.onConfigChanged,
  });

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  late SecurityConfig _config;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
  }

  void _updateConfig(SecurityConfig newConfig) {
    setState(() {
      _config = newConfig;
    });
    widget.onConfigChanged(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('安全设置'),
        backgroundColor: const Color(0xff191d25),
      ),
      backgroundColor: const Color(0xff111318),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            title: '安全级别',
            children: [_buildSecurityLevelSelector()],
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '凭据存储',
            children: [_buildCredentialStorageSettings()],
          ),
          const SizedBox(height: 16),
          _buildSection(title: 'Host Key', children: [_buildHostKeySettings()]),
          const SizedBox(height: 16),
          _buildSection(title: '审计日志', children: [_buildAuditLogSettings()]),
          const SizedBox(height: 16),
          _buildSection(
            title: '终端安全',
            children: [_buildTerminalSecuritySettings()],
          ),
          const SizedBox(height: 16),
          _buildSection(title: '剪贴板', children: [_buildClipboardSettings()]),
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

  Widget _buildSecurityLevelSelector() {
    return RadioGroup<SecurityLevel>(
      groupValue: _config.level,
      onChanged: (value) {
        _updateConfig(_config.copyWith(level: value));
      },
      child: Column(
        children: SecurityLevel.values.map((level) {
          final isSelected = level == _config.level;
          final (label, description) = switch (level) {
            SecurityLevel.low => ('低', '基本安全，适合受信任环境'),
            SecurityLevel.medium => ('中', '平衡安全与便利性'),
            SecurityLevel.high => ('高', '增强安全，适合生产环境'),
            SecurityLevel.maximum => ('最高', '最大安全，可能影响便利性'),
          };

          return RadioListTile<SecurityLevel>(
            title: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xff2f6fed)
                    : const Color(0xffd7e0ee),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              description,
              style: const TextStyle(color: Color(0xff4a5568), fontSize: 12),
            ),
            value: level,
            activeColor: const Color(0xff2f6fed),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCredentialStorageSettings() {
    return const ListTile(
      leading: Icon(Icons.lock_rounded, color: Color(0xff8ae234)),
      title: Text('操作系统安全存储', style: TextStyle(color: Color(0xffd7e0ee))),
      subtitle: Text(
        'macOS 使用钥匙串，Windows 使用凭据管理器，Linux 使用 Secret Service。'
        '应用启动时还需要主密码解锁。',
        style: TextStyle(color: Color(0xff8e98a8), fontSize: 12),
      ),
    );
  }

  Widget _buildHostKeySettings() {
    return const ListTile(
      leading: Icon(Icons.verified_user_rounded, color: Color(0xff8ae234)),
      title: Text(
        'Host Key 固定已强制启用',
        style: TextStyle(color: Color(0xffd7e0ee)),
      ),
      subtitle: Text(
        '未知密钥必须确认后保存，密钥变更始终阻止连接',
        style: TextStyle(color: Color(0xff4a5568), fontSize: 12),
      ),
    );
  }

  Widget _buildAuditLogSettings() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text(
            '启用审计日志',
            style: TextStyle(color: Color(0xffd7e0ee)),
          ),
          subtitle: const Text(
            '记录所有连接、认证、操作事件',
            style: TextStyle(color: Color(0xff4a5568), fontSize: 12),
          ),
          value: _config.auditLogEnabled,
          activeThumbColor: const Color(0xff2f6fed),
          onChanged: (value) {
            _updateConfig(_config.copyWith(auditLogEnabled: value));
          },
        ),
      ],
    );
  }

  Widget _buildTerminalSecuritySettings() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text(
            '禁用 OSC 52',
            style: TextStyle(color: Color(0xffd7e0ee)),
          ),
          subtitle: const Text(
            '禁止远程程序访问剪贴板',
            style: TextStyle(color: Color(0xff4a5568), fontSize: 12),
          ),
          value: _config.osc52Disabled,
          activeThumbColor: const Color(0xff2f6fed),
          onChanged: (value) {
            _updateConfig(_config.copyWith(osc52Disabled: value));
          },
        ),
        SwitchListTile(
          title: const Text('粘贴确认', style: TextStyle(color: Color(0xffd7e0ee))),
          subtitle: const Text(
            '大量粘贴时显示确认对话框',
            style: TextStyle(color: Color(0xff4a5568), fontSize: 12),
          ),
          value: _config.pasteConfirmation,
          activeThumbColor: const Color(0xff2f6fed),
          onChanged: (value) {
            _updateConfig(_config.copyWith(pasteConfirmation: value));
          },
        ),
      ],
    );
  }

  Widget _buildClipboardSettings() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text(
            '剪贴板自动清除',
            style: TextStyle(color: Color(0xffd7e0ee)),
          ),
          subtitle: const Text(
            '复制后自动清除剪贴板内容',
            style: TextStyle(color: Color(0xff4a5568), fontSize: 12),
          ),
          value: _config.clipboardAutoClear,
          activeThumbColor: const Color(0xff2f6fed),
          onChanged: (value) {
            _updateConfig(_config.copyWith(clipboardAutoClear: value));
          },
        ),
        if (_config.clipboardAutoClear) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                '清除延迟 (秒)',
                style: TextStyle(color: Color(0xff8e98a8)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Slider(
                  value: _config.clipboardAutoClearSeconds.toDouble(),
                  min: 10,
                  max: 120,
                  divisions: 11,
                  activeColor: const Color(0xff2f6fed),
                  onChanged: (value) {
                    _updateConfig(
                      _config.copyWith(
                        clipboardAutoClearSeconds: value.round(),
                      ),
                    );
                  },
                ),
              ),
              Text(
                '${_config.clipboardAutoClearSeconds}s',
                style: const TextStyle(color: Color(0xffd7e0ee)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
