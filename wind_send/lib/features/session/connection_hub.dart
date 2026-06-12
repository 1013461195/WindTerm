import 'package:flutter/material.dart';

import 'session_profile.dart';

class ConnectionHub extends StatefulWidget {
  const ConnectionHub({
    super.key,
    required this.profiles,
    required this.groups,
    required this.onOpen,
    required this.onCreate,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onCreateGroup,
    required this.onManageIdentities,
    required this.onSettings,
    required this.onNetworkSettings,
    required this.onSecuritySettings,
  });

  final List<SessionProfile> profiles;
  final List<String> groups;
  final ValueChanged<SessionProfile> onOpen;
  final ValueChanged<SessionProfileType> onCreate;
  final ValueChanged<SessionProfile> onEdit;
  final ValueChanged<SessionProfile> onDuplicate;
  final ValueChanged<SessionProfile> onDelete;
  final VoidCallback onCreateGroup;
  final VoidCallback onManageIdentities;
  final VoidCallback onSettings;
  final VoidCallback onNetworkSettings;
  final VoidCallback onSecuritySettings;

  @override
  State<ConnectionHub> createState() => _ConnectionHubState();
}

class _ConnectionHubState extends State<ConnectionHub> {
  SessionProfileType? _type;
  String? _group;
  String _query = '';

  List<SessionProfile> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.profiles.where((profile) {
      if (_type != null && profile.type != _type) return false;
      if (_group != null && profile.folder != _group) return false;
      return query.isEmpty ||
          profile.name.toLowerCase().contains(query) ||
          (profile.host?.toLowerCase().contains(query) ?? false) ||
          (profile.username?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xff0d1117),
      child: Column(
        children: [
          _buildProtocolBar(),
          Expanded(
            child: Row(
              children: [
                _buildGroupRail(),
                const VerticalDivider(width: 1, color: Color(0xff27313b)),
                Expanded(child: _buildConnectionList()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProtocolBar() {
    const types = <SessionProfileType>[
      SessionProfileType.ssh,
      SessionProfileType.rdp,
      SessionProfileType.telnet,
      SessionProfileType.tunnel,
      SessionProfileType.vnc,
    ];
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xff151b23),
        border: Border(bottom: BorderSide(color: Color(0xff27313b))),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub_rounded, color: Color(0xff72c991)),
          const SizedBox(width: 12),
          const Text(
            '连接中心',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 24),
          _ProtocolButton(
            label: '全部',
            selected: _type == null,
            onTap: () => setState(() => _type = null),
          ),
          for (final type in types)
            _ProtocolButton(
              label: connectionTypeLabel(type),
              selected: _type == type,
              onTap: () => setState(() => _type = type),
            ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onSelected: (value) {
              if (value == 'terminal') widget.onSettings();
              if (value == 'network') widget.onNetworkSettings();
              if (value == 'security') widget.onSecuritySettings();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'terminal', child: Text('终端设置')),
              PopupMenuItem(value: 'network', child: Text('网络设置')),
              PopupMenuItem(value: 'security', child: Text('安全设置')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupRail() {
    return SizedBox(
      width: 250,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '分组',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: widget.onCreateGroup,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 19),
                  tooltip: '新建分组',
                ),
              ],
            ),
          ),
          _GroupTile(
            label: '全部连接',
            count: widget.profiles.length,
            selected: _group == null,
            icon: Icons.dns_outlined,
            onTap: () => setState(() => _group = null),
          ),
          Expanded(
            child: ListView(
              children: widget.groups.map((group) {
                return _GroupTile(
                  label: group,
                  count: widget.profiles
                      .where((profile) => profile.folder == group)
                      .length,
                  selected: _group == group,
                  icon: Icons.folder_outlined,
                  onTap: () => setState(() => _group = group),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionList() {
    final profiles = _filtered;
    return Column(
      children: [
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: widget.onCreateGroup,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('分组'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.onManageIdentities,
                icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                label: const Text('认证身份'),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<SessionProfileType>(
                onSelected: widget.onCreate,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: SessionProfileType.ssh,
                    child: Text('新建 SSH'),
                  ),
                  PopupMenuItem(
                    value: SessionProfileType.rdp,
                    child: Text('新建 RDP'),
                  ),
                  PopupMenuItem(
                    value: SessionProfileType.telnet,
                    child: Text('新建 Telnet'),
                  ),
                  PopupMenuItem(
                    value: SessionProfileType.tunnel,
                    child: Text('新建隧道'),
                  ),
                  PopupMenuItem(
                    value: SessionProfileType.vnc,
                    child: Text('新建 VNC'),
                  ),
                ],
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xff72c991),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: Color(0xff07130c),
                      ),
                      SizedBox(width: 6),
                      Text(
                        '新建连接',
                        style: TextStyle(
                          color: Color(0xff07130c),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 19),
                    hintText: '搜索名称、地址或用户',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const _ConnectionHeader(),
        Expanded(
          child: profiles.isEmpty
              ? _EmptyConnections(onCreate: widget.onCreate)
              : ListView.builder(
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    return _ConnectionRow(
                      profile: profile,
                      onOpen: () => widget.onOpen(profile),
                      onEdit: () => widget.onEdit(profile),
                      onDuplicate: () => widget.onDuplicate(profile),
                      onDelete: () => widget.onDelete(profile),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class ConnectionProfileEditor extends StatefulWidget {
  const ConnectionProfileEditor({
    super.key,
    required this.groups,
    required this.onSave,
    this.initialType = SessionProfileType.ssh,
    this.profile,
  });

  final List<String> groups;
  final SessionProfileType initialType;
  final SessionProfile? profile;
  final ValueChanged<SessionProfile> onSave;

  @override
  State<ConnectionProfileEditor> createState() =>
      _ConnectionProfileEditorState();
}

class _ConnectionProfileEditorState extends State<ConnectionProfileEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _targetHost;
  late final TextEditingController _targetPort;
  late SessionProfileType _type;
  String? _group;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _type = profile?.type ?? widget.initialType;
    _name = TextEditingController(text: profile?.name);
    _host = TextEditingController(text: profile?.host);
    _port = TextEditingController(
      text: (profile?.port ?? defaultPortForProfile(_type)).toString(),
    );
    _username = TextEditingController(text: profile?.username);
    _targetHost = TextEditingController(text: profile?.targetHost);
    _targetPort = TextEditingController(
      text: profile?.targetPort?.toString() ?? '',
    );
    _group = profile?.folder;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _targetHost.dispose();
    _targetPort.dispose();
    super.dispose();
  }

  void _changeType(SessionProfileType? value) {
    if (value == null) return;
    setState(() {
      _type = value;
      _port.text = defaultPortForProfile(value).toString();
    });
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final previous = widget.profile;
    widget.onSave(
      SessionProfile(
        id: previous?.id ?? 'profile-${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim(),
        type: _type,
        folder: _group,
        tags: previous?.tags ?? const [],
        host: _host.text.trim(),
        port: int.parse(_port.text),
        username: _username.text.trim().isEmpty ? null : _username.text.trim(),
        authType: previous?.authType ?? SshAuthType.password,
        privateKeyPath: previous?.privateKeyPath,
        credentialId: previous?.credentialId,
        credentialStorage: previous?.credentialStorage,
        authIdentityId: previous?.authIdentityId,
        targetHost: _targetHost.text.trim().isEmpty
            ? null
            : _targetHost.text.trim(),
        targetPort: int.tryParse(_targetPort.text),
        sshOptions: previous?.sshOptions ?? const <String, Object?>{},
        autoLogin: previous?.autoLogin ?? false,
        logging: previous?.logging ?? false,
        logPath: previous?.logPath,
        quickCommands: previous?.quickCommands ?? const [],
        tabColor: previous?.tabColor,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.profile == null ? '新建连接' : '编辑连接'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<SessionProfileType>(
                        initialValue: _type,
                        decoration: const InputDecoration(labelText: '协议'),
                        items: const [
                          DropdownMenuItem(
                            value: SessionProfileType.ssh,
                            child: Text('SSH'),
                          ),
                          DropdownMenuItem(
                            value: SessionProfileType.rdp,
                            child: Text('RDP'),
                          ),
                          DropdownMenuItem(
                            value: SessionProfileType.telnet,
                            child: Text('Telnet'),
                          ),
                          DropdownMenuItem(
                            value: SessionProfileType.tunnel,
                            child: Text('隧道'),
                          ),
                          DropdownMenuItem(
                            value: SessionProfileType.vnc,
                            child: Text('VNC'),
                          ),
                        ],
                        onChanged: _changeType,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: _group,
                        decoration: const InputDecoration(labelText: '分组'),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('未分组'),
                          ),
                          ...widget.groups.map(
                            (group) => DropdownMenuItem(
                              value: group,
                              child: Text(group),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _group = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: '连接名称'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入名称' : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _host,
                        decoration: const InputDecoration(labelText: '主机地址'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入主机地址'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '端口'),
                        validator: (value) {
                          final port = int.tryParse(value ?? '');
                          return port == null || port < 1 || port > 65535
                              ? '端口无效'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _username,
                  decoration: InputDecoration(
                    labelText: _type == SessionProfileType.vnc
                        ? '用户名（可选）'
                        : '用户名',
                  ),
                ),
                if (_type == SessionProfileType.tunnel) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _targetHost,
                          decoration: const InputDecoration(labelText: '目标主机'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _targetPort,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '目标端口'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '密码不会写入普通配置文件；SSH 凭据连接时由 Keychain/Vault 管理。',
                    style: TextStyle(color: Color(0xff8e98a8), fontSize: 12),
                  ),
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
}

String connectionTypeLabel(SessionProfileType type) {
  return switch (type) {
    SessionProfileType.ssh => 'SSH',
    SessionProfileType.rdp => 'RDP',
    SessionProfileType.telnet => 'Telnet',
    SessionProfileType.tunnel => '隧道',
    SessionProfileType.vnc => 'VNC',
    SessionProfileType.localShell => 'Shell',
  };
}

int defaultPortForProfile(SessionProfileType type) {
  return switch (type) {
    SessionProfileType.ssh || SessionProfileType.tunnel => 22,
    SessionProfileType.rdp => 3389,
    SessionProfileType.telnet => 23,
    SessionProfileType.vnc => 5900,
    SessionProfileType.localShell => 0,
  };
}

IconData connectionTypeIcon(SessionProfileType type) {
  return switch (type) {
    SessionProfileType.ssh => Icons.terminal_rounded,
    SessionProfileType.rdp => Icons.desktop_windows_outlined,
    SessionProfileType.telnet => Icons.settings_ethernet_rounded,
    SessionProfileType.tunnel => Icons.route_outlined,
    SessionProfileType.vnc => Icons.monitor_outlined,
    SessionProfileType.localShell => Icons.code_rounded,
  };
}

class _ProtocolButton extends StatelessWidget {
  const _ProtocolButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff233c2d) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xff8be5a9) : const Color(0xff9aa7b5),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.label,
    required this.count,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff20332a) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: const Color(0xff72c991)),
            const SizedBox(width: 9),
            Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
            Text('$count', style: const TextStyle(color: Color(0xff657181))),
          ],
        ),
      ),
    );
  }
}

class _ConnectionHeader extends StatelessWidget {
  const _ConnectionHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Color(0xff151b23),
        border: Border.symmetric(
          horizontal: BorderSide(color: Color(0xff27313b)),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(width: 44),
          Expanded(flex: 3, child: Text('名称')),
          Expanded(flex: 2, child: Text('协议')),
          Expanded(flex: 3, child: Text('地址')),
          Expanded(flex: 2, child: Text('分组')),
          SizedBox(width: 190, child: Text('操作')),
        ],
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    required this.profile,
    required this.onOpen,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final SessionProfile profile;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onDoubleTap: onOpen,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xff202933))),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Icon(
                connectionTypeIcon(profile.type),
                color: const Color(0xff72c991),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                profile.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(flex: 2, child: Text(connectionTypeLabel(profile.type))),
            Expanded(
              flex: 3,
              child: Text(
                '${profile.host ?? '-'}:${profile.port ?? '-'}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xff9aa7b5)),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                profile.folder ?? '未分组',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 190,
              child: Row(
                children: [
                  FilledButton(onPressed: onOpen, child: const Text('连接')),
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: '编辑',
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'copy') onDuplicate();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'copy', child: Text('复制')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyConnections extends StatelessWidget {
  const _EmptyConnections({required this.onCreate});

  final ValueChanged<SessionProfileType> onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hub_outlined, size: 52, color: Color(0xff4e5d6b)),
          const SizedBox(height: 14),
          const Text(
            '还没有符合条件的连接',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            '创建 SSH、RDP、Telnet、隧道或 VNC 配置',
            style: TextStyle(color: Color(0xff7f8b99)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => onCreate(SessionProfileType.ssh),
            icon: const Icon(Icons.add_rounded),
            label: const Text('新建 SSH'),
          ),
        ],
      ),
    );
  }
}
