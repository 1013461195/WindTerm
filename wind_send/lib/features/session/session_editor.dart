import 'package:flutter/material.dart';

/// SSH 连接配置
class SshConfig {
  String host;
  int port;
  String username;
  String password;

  SshConfig({
    this.host = '',
    this.port = 22,
    this.username = '',
    this.password = '',
  });
}

/// SSH 连接编辑器对话框
class SessionEditor extends StatefulWidget {
  final SshConfig? initialConfig;
  final void Function(SshConfig config) onConnect;

  const SessionEditor({
    super.key,
    this.initialConfig,
    required this.onConnect,
  });

  @override
  State<SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<SessionEditor> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig ?? SshConfig();
    _hostController = TextEditingController(text: config.host);
    _portController = TextEditingController(text: config.port.toString());
    _usernameController = TextEditingController(text: config.username);
    _passwordController = TextEditingController(text: config.password);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleConnect() {
    if (_formKey.currentState?.validate() ?? false) {
      final config = SshConfig(
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text) ?? 22,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
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
                validator: (v) => (v == null || v.trim().isEmpty) ? '请输入主机地址' : null,
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
                validator: (v) => (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _passwordController,
                label: '密码',
                hint: '输入密码',
                obscureText: true,
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
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
}
