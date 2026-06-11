import 'package:flutter/material.dart';
import 'session_profile.dart';

/// 命令面板
class CommandPalette extends StatefulWidget {
  final List<SessionProfile> profiles;
  final void Function(SessionProfile profile) onSessionSelected;
  final void Function(String command) onCommand;

  const CommandPalette({
    super.key,
    required this.profiles,
    required this.onSessionSelected,
    required this.onCommand,
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<_CommandItem> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _buildItems();
    _controller.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _buildItems() {
    final items = <_CommandItem>[];

    // 会话
    for (final profile in widget.profiles) {
      items.add(_CommandItem(
        icon: profile.type == SessionProfileType.ssh
            ? Icons.cloud_rounded
            : Icons.terminal_rounded,
        label: profile.name,
        description: profile.host ?? profile.shell ?? '',
        type: _CommandItemType.session,
        profile: profile,
      ));
    }

    // 命令
    items.add(_CommandItem(
      icon: Icons.add_rounded,
      label: '新建 SSH 连接',
      description: '创建新的 SSH 会话',
      type: _CommandItemType.command,
      command: 'new_ssh',
    ));
    items.add(_CommandItem(
      icon: Icons.terminal_rounded,
      label: '新建本地 Shell',
      description: '创建新的本地终端',
      type: _CommandItemType.command,
      command: 'new_shell',
    ));
    items.add(_CommandItem(
      icon: Icons.settings_rounded,
      label: '打开设置',
      description: '配置终端选项',
      type: _CommandItemType.command,
      command: 'settings',
    ));

    setState(() {
      _filteredItems = items;
    });
  }

  void _onQueryChanged() {
    final query = _controller.text.toLowerCase();
    if (query.isEmpty) {
      _buildItems();
      return;
    }

    final allItems = <_CommandItem>[];
    for (final profile in widget.profiles) {
      allItems.add(_CommandItem(
        icon: profile.type == SessionProfileType.ssh
            ? Icons.cloud_rounded
            : Icons.terminal_rounded,
        label: profile.name,
        description: profile.host ?? profile.shell ?? '',
        type: _CommandItemType.session,
        profile: profile,
      ));
    }

    allItems.add(_CommandItem(
      icon: Icons.add_rounded,
      label: '新建 SSH 连接',
      description: '创建新的 SSH 会话',
      type: _CommandItemType.command,
      command: 'new_ssh',
    ));
    allItems.add(_CommandItem(
      icon: Icons.terminal_rounded,
      label: '新建本地 Shell',
      description: '创建新的本地终端',
      type: _CommandItemType.command,
      command: 'new_shell',
    ));
    allItems.add(_CommandItem(
      icon: Icons.settings_rounded,
      label: '打开设置',
      description: '配置终端选项',
      type: _CommandItemType.command,
      command: 'settings',
    ));

    setState(() {
      _filteredItems = allItems.where((item) {
        return item.label.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _onItemSelected(_CommandItem item) {
    if (item.type == _CommandItemType.session && item.profile != null) {
      widget.onSessionSelected(item.profile!);
    } else if (item.type == _CommandItemType.command && item.command != null) {
      widget.onCommand(item.command!);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xff191d25),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 400),
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(child: _buildResultsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xff2a303b))),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18, color: Color(0xff8e98a8)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(color: Color(0xffd7e0ee), fontSize: 14),
              decoration: const InputDecoration(
                hintText: '搜索会话或命令...',
                hintStyle: TextStyle(color: Color(0xff4a5568)),
                border: InputBorder.none,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xff2a303b),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'ESC',
              style: TextStyle(
                color: Color(0xff4a5568),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    if (_filteredItems.isEmpty) {
      return const Center(
        child: Text(
          '没有匹配的结果',
          style: TextStyle(color: Color(0xff4a5568)),
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        return _buildResultItem(item);
      },
    );
  }

  Widget _buildResultItem(_CommandItem item) {
    return InkWell(
      onTap: () => _onItemSelected(item),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(item.icon, size: 18, color: const Color(0xff8fb6ff)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      color: Color(0xffd7e0ee),
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.description.isNotEmpty)
                    Text(
                      item.description,
                      style: const TextStyle(
                        color: Color(0xff4a5568),
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (item.type == _CommandItemType.session)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xff2a303b),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Enter',
                  style: TextStyle(
                    color: Color(0xff4a5568),
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _CommandItemType {
  session,
  command,
}

class _CommandItem {
  final IconData icon;
  final String label;
  final String description;
  final _CommandItemType type;
  final SessionProfile? profile;
  final String? command;

  const _CommandItem({
    required this.icon,
    required this.label,
    required this.description,
    required this.type,
    this.profile,
    this.command,
  });
}
