import 'package:flutter/material.dart';

enum SshAuthentication { password, privateKey }

/// SSH 连接配置
class SshConfig {
  String host;
  int port;
  String username;
  String password;
  SshAuthentication authentication;
  String privateKeyPath;
  String passphrase;
  bool acceptUnknownHost;
  bool rememberCredential;

  SshConfig({
    this.host = '',
    this.port = 22,
    this.username = '',
    this.password = '',
    this.authentication = SshAuthentication.password,
    this.privateKeyPath = '',
    this.passphrase = '',
    this.acceptUnknownHost = false,
    this.rememberCredential = false,
  });

  Map<String, Object?> toJson({
    Map<String, dynamic>? network,
  }) => <String, Object?>{
    'host': host,
    'port': port,
    'username': username,
    'password': authentication == SshAuthentication.password ? password : null,
    'private_key_path': authentication == SshAuthentication.privateKey
        ? privateKeyPath
        : null,
    'passphrase':
        authentication == SshAuthentication.privateKey && passphrase.isNotEmpty
        ? passphrase
        : null,
    'known_hosts_path': null,
    'accept_unknown_host': acceptUnknownHost,
    'network': network,
  };
}

/// SSH 连接编辑器对话框
class SessionEditor extends StatefulWidget {
  final SshConfig? initialConfig;
  final void Function(SshConfig config) onConnect;

  const SessionEditor({super.key, this.initialConfig, required this.onConnect});

  @override
  State<SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<SessionEditor> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _privateKeyController;
  late final TextEditingController _passphraseController;
  late SshAuthentication _authentication;
  late bool _rememberCredential;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig ?? SshConfig();
    _hostController = TextEditingController(text: config.host);
    _portController = TextEditingController(text: config.port.toString());
    _usernameController = TextEditingController(text: config.username);
    _passwordController = TextEditingController(text: config.password);
    _privateKeyController = TextEditingController(text: config.privateKeyPath);
    _passphraseController = TextEditingController(text: config.passphrase);
    _authentication = config.authentication;
    _rememberCredential = config.rememberCredential;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  void _handleConnect() {
    if (_formKey.currentState?.validate() ?? false) {
      final config = SshConfig(
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text) ?? 22,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        authentication: _authentication,
        privateKeyPath: _privateKeyController.text.trim(),
        passphrase: _passphraseController.text,
        acceptUnknownHost: false,
        rememberCredential: _rememberCredential,
      );
      widget.onConnect(config);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xff191d25),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '新建 SSH 连接',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xffd7e0ee),
                ),
              ),
              const SizedBox(height: 24),
              _buildTextField(
                controller: _hostController,
                label: '主机',
                hint: '例如: 192.168.1.100 或 example.com',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入主机地址' : null,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _portController,
                label: '端口',
                hint: '22',
                keyboardType: TextInputType.number,
                validator: (v) {
                  final port = int.tryParse(v ?? '');
                  if (port == null || port < 1 || port > 65535) {
                    return '请输入有效端口 (1-65535)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _usernameController,
                label: '用户名',
                hint: '例如: root',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SshAuthentication>(
                initialValue: _authentication,
                decoration: _inputDecoration('认证方式'),
                items: const [
                  DropdownMenuItem(
                    value: SshAuthentication.password,
                    child: Text('密码'),
                  ),
                  DropdownMenuItem(
                    value: SshAuthentication.privateKey,
                    child: Text('私钥'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _authentication = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              if (_authentication == SshAuthentication.password)
                _buildTextField(
                  controller: _passwordController,
                  label: '密码',
                  hint: '输入密码',
                  obscureText: true,
                )
              else ...[
                _buildTextField(
                  controller: _privateKeyController,
                  label: '私钥路径',
                  hint: '~/.ssh/id_ed25519',
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入私钥路径' : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _passphraseController,
                  label: '私钥口令',
                  hint: '没有口令可留空',
                  obscureText: true,
                ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _rememberCredential,
                onChanged: (value) {
                  setState(() => _rememberCredential = value ?? false);
                },
                title: const Text('保存凭据'),
                subtitle: const Text('按安全设置保存到平台 Keychain 或加密 Vault'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      '取消',
                      style: TextStyle(color: Color(0xff8e98a8)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _handleConnect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff2f6fed),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('连接'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Color(0xffd7e0ee)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xff8e98a8)),
        hintStyle: const TextStyle(color: Color(0xff4a5568)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xff2a303b)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xff2f6fed)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        filled: true,
        fillColor: const Color(0xff111318),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xff8e98a8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xff2a303b)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xff2f6fed)),
      ),
      filled: true,
      fillColor: const Color(0xff111318),
    );
  }
}
