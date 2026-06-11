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
            children: [
              _buildSecurityLevelSelector(),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '凭据存储',
            children: [
              _buildCredentialStorageSettings(),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: 'Host Key',
            children: [
              _buildHostKeySettings(),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '审计日志',
            children: [
              _buildAuditLogSettings(),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '终端安全',
            children: [
              _buildTerminalSecuritySettings(),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '剪贴板',
            children: [
              _buildClipboardSettings(),
            ],
          ),
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
    return Column(
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
              color: isSelected ? const Color(0xff2f6fed) : const Color(0xffd7e0ee),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            description,
            style: const TextStyle(color: Color(0xff4a5568), fontSize: 12),
          ),
          value: level,
          groupValue: _config.level,
          activeColor: const Color(0xff2f6fed),
          onChanged: (value) {
            if (value != null) {
              _updateConfig(_config.copyWith(level: value));
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildCredentialStorageSettings() {
    return Column(
      children: [
        DropdownButtonFormField<CredentialStorage>(
          value: _config.credentialStorage,
          dropdownColor: const Color(0xff191d25),
          style: const TextStyle(color: Color(0xffd7e0ee)),
          decoration: const InputDecoration(
            labelText: '存储方式',
            labelStyle: TextStyle(color: Color(0xff8e98a8)),
          ),
          items: const [
            DropdownMenuItem(
              value: CredentialStorage.none,
              child: Text('不保存'),
            ),
            DropdownMenuItem(
              value: CredentialStorage.platform,
              child: Text('平台 Keychain'),
            ),
            DropdownMenuItem(
              value: CredentialStorage.vault,
              child: Text('主密码加密'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              _updateConfig(_config.copyWith(credentialStorage: value));
            }
          },
        ),
        if (_config.credentialStorage == CredentialStorage.vault) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text(
              '启用主密码',
              style: TextStyle(color: Color(0xffd7e0ee)),
            ),
            subtitle: const Text(
              '使用主密码加密所有凭据',
              style: TextStyle(color: Color(0xff4a5568), fontSize: 12),
            ),
            value: _config.masterPasswordEnabled,
            activeColor: const Color(0xff2f6fed),
            onChanged: (value) {
              _updateConfig(_config.copyWith(masterPasswordEnabled: value));
            },
          ),
        ],
      ],
    );
  }

  Widget _buildHostKeySettings() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text(
            'Host Key 固定',
            style: TextStyle(color: Color(0xffd7e0ee)),
          ),
          subtitle: const Text(
            '验证并记录服务器 Host Key，检测中间人攻击',
            style: TextStyle(color: Color(0xff4a5568), fontSize: 12),
          ),
          value: _config.hostKeyPinning,
          activeColor: const Color(0xff2f6fed),
          onChanged: (value) {
            _updateConfig(_config.copyWith(hostKeyPinning: value));
          },
        ),
      ],
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
          activeColor: const Color(0xff2f6fed),
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
          activeColor: const Color(0xff2f6fed),
          onChanged: (value) {
            _updateConfig(_config.copyWith(osc52Disabled: value));
          },
        ),
        SwitchListTile(
          title: const Text(
            '粘贴确认',
            style: TextStyle(color: Color(0xffd7e0ee)),
          ),
          subtitle: const Text(
            '大量粘贴时显示确认对话框',
            style: TextStyle(color: Color(0xff4a5568), fontSize: 12),
          ),
          value: _config.pasteConfirmation,
          activeColor: const Color(0xff2f6fed),
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
          activeColor: const Color(0xff2f6fed),
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
                    _updateConfig(_config.copyWith(
                      clipboardAutoClearSeconds: value.round(),
                    ));
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
