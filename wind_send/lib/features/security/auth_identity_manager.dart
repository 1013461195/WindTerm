import 'package:flutter/material.dart';

import '../session/session_profile.dart';
import 'auth_identity.dart';

class AuthIdentityManager extends StatelessWidget {
  const AuthIdentityManager({
    super.key,
    required this.identities,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final List<AuthIdentity> identities;
  final VoidCallback onCreate;
  final ValueChanged<AuthIdentity> onEdit;
  final ValueChanged<AuthIdentity> onDelete;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('认证身份'),
      content: SizedBox(
        width: 620,
        height: 420,
        child: identities.isEmpty
            ? const Center(
                child: Text(
                  '还没有保存认证身份。\n可保存账号密码或账号、私钥路径和私钥口令。',
                  textAlign: TextAlign.center,
                ),
              )
            : ListView.separated(
                itemCount: identities.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final identity = identities[index];
                  return ListTile(
                    leading: Icon(
                      identity.authType == SshAuthType.password
                          ? Icons.password_rounded
                          : Icons.key_rounded,
                    ),
                    title: Text(identity.name),
                    subtitle: Text(
                      '${identity.username} · '
                      '${identity.authType == SshAuthType.password ? '密码' : '私钥'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => onEdit(identity),
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: '编辑',
                        ),
                        IconButton(
                          onPressed: () => onDelete(identity),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '删除',
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded),
          label: const Text('新建身份'),
        ),
      ],
    );
  }
}

class AuthIdentityEditor extends StatefulWidget {
  const AuthIdentityEditor({super.key, required this.onSave, this.identity});

  final AuthIdentity? identity;
  final void Function({
    required String name,
    required String username,
    required SshAuthType authType,
    required String privateKeyPath,
    required String password,
    required String passphrase,
  })
  onSave;

  @override
  State<AuthIdentityEditor> createState() => _AuthIdentityEditorState();
}

class _AuthIdentityEditorState extends State<AuthIdentityEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _privateKeyPath;
  late final TextEditingController _passphrase;
  late SshAuthType _authType;

  @override
  void initState() {
    super.initState();
    final identity = widget.identity;
    _name = TextEditingController(text: identity?.name);
    _username = TextEditingController(text: identity?.username);
    _password = TextEditingController();
    _privateKeyPath = TextEditingController(text: identity?.privateKeyPath);
    _passphrase = TextEditingController();
    _authType = identity?.authType ?? SshAuthType.password;
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _privateKeyPath.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onSave(
      name: _name.text.trim(),
      username: _username.text.trim(),
      authType: _authType,
      privateKeyPath: _privateKeyPath.text.trim(),
      password: _password.text,
      passphrase: _passphrase.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.identity == null ? '新建认证身份' : '编辑认证身份'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: '身份名称'),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: '账号'),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<SshAuthType>(
                  initialValue: _authType,
                  decoration: const InputDecoration(labelText: '认证方式'),
                  items: const [
                    DropdownMenuItem(
                      value: SshAuthType.password,
                      child: Text('账号 + 密码'),
                    ),
                    DropdownMenuItem(
                      value: SshAuthType.privateKey,
                      child: Text('账号 + 私钥'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _authType = value);
                  },
                ),
                const SizedBox(height: 14),
                if (_authType == SshAuthType.password)
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: widget.identity == null
                          ? '密码'
                          : '新密码（留空表示不修改）',
                    ),
                    validator: widget.identity == null ? _required : null,
                  )
                else ...[
                  TextFormField(
                    controller: _privateKeyPath,
                    decoration: const InputDecoration(labelText: '私钥路径'),
                    validator: _required,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passphrase,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: widget.identity == null
                          ? '私钥口令（可选）'
                          : '新私钥口令（留空表示不修改）',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  '密码和私钥口令只会写入操作系统安全存储。',
                  style: TextStyle(color: Color(0xff8e98a8), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? '此项不能为空' : null;
  }
}
