import 'package:flutter/material.dart';

import '../security/auth_identity.dart';
import 'session_profile.dart';

class SshProfileEditor extends StatefulWidget {
  const SshProfileEditor({
    super.key,
    required this.groups,
    required this.identities,
    required this.onSave,
    required this.onTest,
    this.profile,
  });

  final List<String> groups;
  final List<AuthIdentity> identities;
  final SessionProfile? profile;
  final ValueChanged<SessionProfile> onSave;
  final Future<String?> Function(SessionProfile profile) onTest;

  @override
  State<SshProfileEditor> createState() => _SshProfileEditorState();
}

class _SshProfileEditorState extends State<SshProfileEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _note;
  late final TextEditingController _timeout;
  late final TextEditingController _keepalive;
  late final TextEditingController _proxyHost;
  late final TextEditingController _proxyPort;
  late final TextEditingController _defaultPath;
  late final TextEditingController _initialCommand;
  late String? _group;
  late String? _identityId;
  late SshAuthType _authType;
  late String _terminalType;
  late String _encoding;
  late String _proxyType;
  late bool _disableProxy;
  late bool _agentForwarding;
  late bool _disableBracketedPaste;
  late bool _disablePwdSync;
  int _section = 0;
  bool _testing = false;
  late List<Map<String, Object?>> _jumpHosts;

  Map<String, Object?> get _options => widget.profile?.sshOptions ?? const {};

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _name = TextEditingController(text: profile?.name);
    _host = TextEditingController(text: profile?.host);
    _port = TextEditingController(text: '${profile?.port ?? 22}');
    _username = TextEditingController(text: profile?.username);
    _note = TextEditingController(text: _options['note'] as String?);
    _timeout = TextEditingController(
      text: '${_options['connectTimeoutMs'] ?? 15000}',
    );
    _keepalive = TextEditingController(
      text: '${_options['keepaliveIntervalMs'] ?? 5000}',
    );
    _proxyHost = TextEditingController(text: _options['proxyHost'] as String?);
    _proxyPort = TextEditingController(
      text: '${_options['proxyPort'] ?? 1080}',
    );
    _defaultPath = TextEditingController(
      text: _options['defaultPath'] as String? ?? '~',
    );
    _initialCommand = TextEditingController(
      text: _options['initialCommand'] as String?,
    );
    _group = profile?.folder;
    _identityId = profile?.authIdentityId;
    _authType = profile?.authType ?? SshAuthType.password;
    _terminalType = _options['terminalType'] as String? ?? 'xterm-256color';
    _encoding = _options['encoding'] as String? ?? 'UTF-8';
    _proxyType = _options['proxyType'] as String? ?? 'none';
    _disableProxy = _options['disableProxy'] == true;
    _agentForwarding = _options['agentForwarding'] == true;
    _disableBracketedPaste = _options['disableBracketedPaste'] == true;
    _disablePwdSync = _options['disablePwdSync'] == true;
    _jumpHosts = ((_options['jumpHosts'] as List?) ?? const [])
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
        .toList();
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _name,
      _host,
      _port,
      _username,
      _note,
      _timeout,
      _keepalive,
      _proxyHost,
      _proxyPort,
      _defaultPath,
      _initialCommand,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  SessionProfile? _buildProfile() {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    return SessionProfile(
      id:
          widget.profile?.id ??
          'profile-${DateTime.now().microsecondsSinceEpoch}',
      name: _name.text.trim(),
      type: SessionProfileType.ssh,
      folder: _group,
      tags: widget.profile?.tags ?? const [],
      host: _host.text.trim(),
      port: int.parse(_port.text),
      username: _username.text.trim().isEmpty ? null : _username.text.trim(),
      authType: _authType,
      privateKeyPath: widget.profile?.privateKeyPath,
      credentialId: widget.profile?.credentialId,
      credentialStorage: widget.profile?.credentialStorage,
      authIdentityId: _identityId,
      sshOptions: <String, Object?>{
        'note': _note.text.trim(),
        'connectTimeoutMs': int.tryParse(_timeout.text) ?? 15000,
        'keepaliveIntervalMs': int.tryParse(_keepalive.text) ?? 5000,
        'terminalType': _terminalType,
        'encoding': _encoding,
        'proxyType': _proxyType,
        'proxyHost': _proxyHost.text.trim(),
        'proxyPort': int.tryParse(_proxyPort.text) ?? 1080,
        'disableProxy': _disableProxy,
        'agentForwarding': _agentForwarding,
        'disableBracketedPaste': _disableBracketedPaste,
        'disablePwdSync': _disablePwdSync,
        'defaultPath': _defaultPath.text.trim(),
        'initialCommand': _initialCommand.text,
        'jumpHosts': _jumpHosts,
      },
      autoLogin: widget.profile?.autoLogin ?? false,
      logging: widget.profile?.logging ?? false,
      logPath: widget.profile?.logPath,
      quickCommands: widget.profile?.quickCommands ?? const [],
      tabColor: widget.profile?.tabColor,
    );
  }

  Future<void> _test() async {
    final profile = _buildProfile();
    if (profile == null) return;
    setState(() => _testing = true);
    final error = await widget.onTest(profile);
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error == null ? '连接测试成功' : '连接测试失败：$error'),
        backgroundColor: error == null ? Colors.green : Colors.redAccent,
      ),
    );
  }

  void _save() {
    final profile = _buildProfile();
    if (profile == null) return;
    widget.onSave(profile);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      child: SizedBox(
        width: 900,
        height: 720,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 10, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.profile == null ? '新建 SSH 连接' : '编辑 SSH 连接',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 170,
                    child: ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        _nav(0, Icons.link_rounded, '基本信息'),
                        _nav(1, Icons.cable_rounded, '连接设置'),
                        _nav(2, Icons.account_tree_outlined, '跳板机'),
                        _nav(3, Icons.public_rounded, '代理设置'),
                        _nav(4, Icons.tune_rounded, '其他设置'),
                        _nav(5, Icons.description_outlined, '初始化'),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: _buildSection(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: _testing ? null : _test,
                    child: Text(_testing ? '测试中...' : '测试连接'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _save, child: const Text('保存')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nav(int index, IconData icon, String label) {
    return ListTile(
      dense: true,
      selected: _section == index,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(icon, size: 18),
      title: Text(label),
      onTap: () => setState(() => _section = index),
    );
  }

  Widget _buildSection() {
    return switch (_section) {
      0 => _basicSection(),
      1 => _connectionSection(),
      2 => _jumpHostSection(),
      3 => _proxySection(),
      4 => _otherSection(),
      _ => _initializationSection(),
    };
  }

  Widget _basicSection() {
    return Column(
      children: [
        _card([
          _fieldRow('名称', _name, validator: _required),
          _groupRow(),
          _addressRow(),
        ]),
        _card([
          _identityRow(),
          _fieldRow('用户名', _username, validator: _required),
          _authRow(),
          _multilineRow('主机备注', _note, maxLines: 3),
        ]),
      ],
    );
  }

  Widget _connectionSection() {
    return Column(
      children: [
        _card([
          _fieldRow(
            '连接超时（毫秒）',
            _timeout,
            numeric: true,
            validator: _positiveNumber,
          ),
          _fieldRow(
            '心跳间隔（毫秒）',
            _keepalive,
            numeric: true,
            validator: _positiveNumber,
          ),
          _dropdownRow('终端显示编码', _encoding, const [
            'UTF-8',
            'GB18030',
            'Big5',
          ], (value) => setState(() => _encoding = value)),
        ]),
        _card([
          _dropdownRow('终端类型', _terminalType, const [
            'xterm-256color',
            'xterm',
            'vt100',
            'screen-256color',
          ], (value) => setState(() => _terminalType = value)),
          _switchRow(
            'SSH Agent 转发',
            '允许远端通过本机会话使用 SSH Agent。',
            _agentForwarding,
            (value) => setState(() => _agentForwarding = value),
          ),
        ]),
      ],
    );
  }

  Widget _jumpHostSection() {
    return Column(
      children: [
        _card([
          for (var index = 0; index < _jumpHosts.length; index++)
            ListTile(
              leading: CircleAvatar(radius: 14, child: Text('${index + 1}')),
              title: Text(
                '${_jumpHosts[index]['host']}:${_jumpHosts[index]['port']}',
              ),
              subtitle: Text(_jumpIdentityLabel(_jumpHosts[index])),
              trailing: IconButton(
                onPressed: () => setState(() => _jumpHosts.removeAt(index)),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addJumpHost,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加跳板机'),
              ),
            ),
          ),
        ]),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            '按列表顺序连接，第一个跳板机会最先建立。认证信息来自系统安全存储。',
            style: TextStyle(color: Color(0xff8e98a8)),
          ),
        ),
      ],
    );
  }

  Widget _proxySection() {
    return Column(
      children: [
        _card([
          _dropdownRow(
            '代理类型',
            _proxyType,
            const ['none', 'http', 'socks5'],
            (value) => setState(() => _proxyType = value),
            labels: const {'none': '不使用', 'http': 'HTTP', 'socks5': 'SOCKS5'},
          ),
          if (_proxyType != 'none') ...[
            _fieldRow('代理主机', _proxyHost, validator: _required),
            _fieldRow(
              '代理端口',
              _proxyPort,
              numeric: true,
              validator: _portValidator,
            ),
          ],
          _switchRow(
            '禁用全局代理',
            '此连接忽略应用全局代理设置。',
            _disableProxy,
            (value) => setState(() => _disableProxy = value),
          ),
        ]),
      ],
    );
  }

  Widget _otherSection() {
    return Column(
      children: [
        _card([
          _switchRow(
            '禁止列表监控开启',
            '关闭终端的 bracketed paste 模式处理。',
            _disableBracketedPaste,
            (value) => setState(() => _disableBracketedPaste = value),
          ),
          _switchRow(
            '禁用 pwd 自动跳转',
            '不根据远端 pwd 输出联动 SFTP 当前目录。',
            _disablePwdSync,
            (value) => setState(() => _disablePwdSync = value),
          ),
        ]),
        _card([
          const ListTile(
            title: Text('X11 转发'),
            subtitle: Text('当前 ssh2/libssh2 核心暂未接入，升级核心后开放。'),
            trailing: Switch(value: false, onChanged: null),
          ),
          const ListTile(
            title: Text('SSH 算法顺序'),
            subtitle: Text('当前由 libssh2 安全默认值协商，暂不允许手动降级算法。'),
            trailing: Icon(Icons.lock_outline),
          ),
        ]),
      ],
    );
  }

  Widget _initializationSection() {
    return Column(
      children: [
        _card([
          _fieldRow('默认路径', _defaultPath),
          _multilineRow('初始执行', _initialCommand, maxLines: 7),
        ]),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            '连接成功后将发送初始命令；多条命令请按行填写。',
            style: TextStyle(color: Color(0xff8e98a8)),
          ),
        ),
      ],
    );
  }

  Widget _card(List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _fieldRow(
    String label,
    TextEditingController controller, {
    bool numeric = false,
    String? Function(String?)? validator,
  }) {
    return ListTile(
      title: Text(label),
      trailing: SizedBox(
        width: 300,
        child: TextFormField(
          controller: controller,
          keyboardType: numeric ? TextInputType.number : null,
          validator: validator,
          decoration: const InputDecoration(isDense: true),
        ),
      ),
    );
  }

  Widget _multilineRow(
    String label,
    TextEditingController controller, {
    required int maxLines,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label)),
          Expanded(
            child: TextFormField(
              controller: controller,
              maxLines: maxLines,
              decoration: const InputDecoration(isDense: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addressRow() {
    return ListTile(
      title: const Text('地址'),
      trailing: SizedBox(
        width: 390,
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _host,
                validator: _required,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '主机地址',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 82,
              child: TextFormField(
                controller: _port,
                validator: _portValidator,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '端口',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupRow() {
    return ListTile(
      title: const Text('分组'),
      trailing: SizedBox(
        width: 300,
        child: DropdownButtonFormField<String?>(
          initialValue: _group,
          items: [
            const DropdownMenuItem(value: null, child: Text('未分组')),
            ...widget.groups.map(
              (group) => DropdownMenuItem(value: group, child: Text(group)),
            ),
          ],
          onChanged: (value) => setState(() => _group = value),
          decoration: const InputDecoration(isDense: true),
        ),
      ),
    );
  }

  Widget _identityRow() {
    return ListTile(
      title: const Text('认证身份'),
      subtitle: const Text('选择已保存身份，或使用下方手动认证配置。'),
      trailing: SizedBox(
        width: 300,
        child: DropdownButtonFormField<String?>(
          initialValue: _identityId,
          items: [
            const DropdownMenuItem(value: null, child: Text('手动输入')),
            ...widget.identities.map(
              (identity) => DropdownMenuItem(
                value: identity.id,
                child: Text(identity.name),
              ),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _identityId = value;
              final identity = widget.identities
                  .where((candidate) => candidate.id == value)
                  .firstOrNull;
              if (identity != null) {
                _username.text = identity.username;
                _authType = identity.authType;
              }
            });
          },
          decoration: const InputDecoration(isDense: true),
        ),
      ),
    );
  }

  Widget _authRow() {
    return ListTile(
      title: const Text('验证方式'),
      trailing: SizedBox(
        width: 300,
        child: DropdownButtonFormField<SshAuthType>(
          initialValue: _authType == SshAuthType.keyboardInteractive
              ? SshAuthType.password
              : _authType,
          items: const [
            DropdownMenuItem(value: SshAuthType.password, child: Text('密码')),
            DropdownMenuItem(value: SshAuthType.privateKey, child: Text('私钥')),
            DropdownMenuItem(
              value: SshAuthType.keyboardInteractive,
              enabled: false,
              child: Text('交互认证（当前核心暂不支持）'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _authType = value);
          },
          decoration: const InputDecoration(isDense: true),
        ),
      ),
    );
  }

  Widget _dropdownRow(
    String label,
    String value,
    List<String> values,
    ValueChanged<String> onChanged, {
    Map<String, String> labels = const {},
  }) {
    return ListTile(
      title: Text(label),
      trailing: SizedBox(
        width: 300,
        child: DropdownButtonFormField<String>(
          initialValue: value,
          items: values
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(labels[item] ?? item),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
          decoration: const InputDecoration(isDense: true),
        ),
      ),
    );
  }

  Widget _switchRow(
    String label,
    String description,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      title: Text(label),
      subtitle: Text(description),
      value: value,
      onChanged: onChanged,
    );
  }

  Future<void> _addJumpHost() async {
    var host = '';
    var port = '22';
    String? identityId = widget.identities.firstOrNull?.id;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加跳板机'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                onChanged: (value) => host = value,
                decoration: const InputDecoration(labelText: '主机地址'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: port,
                onChanged: (value) => port = value,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '端口'),
              ),
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (context, setDialogState) =>
                    DropdownButtonFormField<String?>(
                      initialValue: identityId,
                      items: widget.identities
                          .map(
                            (identity) => DropdownMenuItem(
                              value: identity.id,
                              child: Text(identity.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => identityId = value),
                      decoration: const InputDecoration(labelText: '认证身份'),
                    ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parsedPort = int.tryParse(port);
              if (host.trim().isEmpty ||
                  parsedPort == null ||
                  identityId == null) {
                return;
              }
              Navigator.of(context).pop(<String, Object?>{
                'host': host.trim(),
                'port': parsedPort,
                'identityId': identityId,
              });
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result != null) setState(() => _jumpHosts.add(result));
  }

  String _jumpIdentityLabel(Map<String, Object?> jump) {
    final id = jump['identityId'];
    return widget.identities
            .where((identity) => identity.id == id)
            .map((identity) => identity.name)
            .firstOrNull ??
        '认证身份已删除';
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '此项不能为空' : null;

  String? _positiveNumber(String? value) {
    final number = int.tryParse(value ?? '');
    return number == null || number <= 0 ? '请输入正整数' : null;
  }

  String? _portValidator(String? value) {
    final port = int.tryParse(value ?? '');
    return port == null || port < 1 || port > 65535 ? '端口无效' : null;
  }
}
