import 'package:flutter/material.dart';

import 'session_profile.dart';

class SessionProfileEditor extends StatefulWidget {
  const SessionProfileEditor({
    super.key,
    required this.profile,
    required this.onSave,
  });

  final SessionProfile profile;
  final ValueChanged<SessionProfile> onSave;

  @override
  State<SessionProfileEditor> createState() => _SessionProfileEditorState();
}

class _SessionProfileEditorState extends State<SessionProfileEditor> {
  late final TextEditingController _name;
  late final TextEditingController _folder;
  late final TextEditingController _tags;
  late final TextEditingController _logPath;
  late final TextEditingController _commands;
  late bool _autoLogin;
  late bool _logging;
  late String _tabColor;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _name = TextEditingController(text: profile.name);
    _folder = TextEditingController(text: profile.folder);
    _tags = TextEditingController(text: profile.tags.join(', '));
    _logPath = TextEditingController(text: profile.logPath);
    _commands = TextEditingController(text: profile.quickCommands.join('\n'));
    _autoLogin = profile.autoLogin;
    _logging = profile.logging;
    _tabColor = profile.tabColor ?? 'default';
  }

  @override
  void dispose() {
    _name.dispose();
    _folder.dispose();
    _tags.dispose();
    _logPath.dispose();
    _commands.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    widget.onSave(
      widget.profile.copyWith(
        name: name,
        folder: _folder.text.trim(),
        tags: _split(_tags.text, ','),
        autoLogin: _autoLogin,
        logging: _logging,
        logPath: _logPath.text.trim(),
        quickCommands: _split(_commands.text, '\n'),
        tabColor: _tabColor,
      ),
    );
    Navigator.of(context).pop();
  }

  List<String> _split(String value, String separator) => value
      .split(separator)
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑会话配置'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _tabColor,
                decoration: const InputDecoration(labelText: 'Tab 颜色'),
                items: const [
                  DropdownMenuItem(value: 'default', child: Text('默认')),
                  DropdownMenuItem(value: 'blue', child: Text('蓝色')),
                  DropdownMenuItem(value: 'green', child: Text('绿色')),
                  DropdownMenuItem(value: 'orange', child: Text('橙色')),
                  DropdownMenuItem(value: 'red', child: Text('红色')),
                  DropdownMenuItem(value: 'purple', child: Text('紫色')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _tabColor = value);
                },
              ),
              TextField(
                controller: _folder,
                decoration: const InputDecoration(labelText: '文件夹'),
              ),
              TextField(
                controller: _tags,
                decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启动时自动登录'),
                subtitle: const Text('仅恢复明确启用此项的 SSH 会话'),
                value: _autoLogin,
                onChanged: (value) => setState(() => _autoLogin = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('记录会话日志'),
                value: _logging,
                onChanged: (value) => setState(() => _logging = value),
              ),
              if (_logging)
                TextField(
                  controller: _logPath,
                  decoration: const InputDecoration(
                    labelText: '日志路径（留空则按会话和日期归档）',
                  ),
                ),
              TextField(
                controller: _commands,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: '快捷命令（每行一条）'),
              ),
            ],
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
}
