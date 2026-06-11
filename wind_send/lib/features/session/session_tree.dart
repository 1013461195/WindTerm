import 'package:flutter/material.dart';
import 'session_profile.dart';

/// 会话树组件
class SessionTree extends StatefulWidget {
  final List<SessionProfile> profiles;
  final void Function(SessionProfile profile) onSessionTap;
  final void Function(SessionProfile profile) onSessionEdit;
  final void Function(SessionProfile profile) onSessionDelete;
  final String? selectedFolder;
  final String? selectedTag;

  const SessionTree({
    super.key,
    required this.profiles,
    required this.onSessionTap,
    required this.onSessionEdit,
    required this.onSessionDelete,
    this.selectedFolder,
    this.selectedTag,
  });

  @override
  State<SessionTree> createState() => _SessionTreeState();
}

class _SessionTreeState extends State<SessionTree> {
  final Set<String> _expandedFolders = {};

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByFolder();

    return ListView(
      children: grouped.entries.map((entry) {
        final folder = entry.key;
        final profiles = entry.value;

        if (folder == null) {
          // 无文件夹的会话
          return Column(
            children: profiles.map((p) => _buildSessionItem(p)).toList(),
          );
        }

        return _buildFolderItem(folder, profiles);
      }).toList(),
    );
  }

  Map<String?, List<SessionProfile>> _groupByFolder() {
    if (widget.selectedTag != null) {
      final filtered = widget.profiles
          .where((p) => p.tags.contains(widget.selectedTag))
          .toList();
      return {null: filtered};
    }

    final map = <String?, List<SessionProfile>>{};
    for (final profile in widget.profiles) {
      if (widget.selectedFolder != null &&
          profile.folder != widget.selectedFolder) {
        continue;
      }
      final folder = profile.folder;
      map.putIfAbsent(folder, () => []).add(profile);
    }
    return map;
  }

  Widget _buildFolderItem(String folder, List<SessionProfile> profiles) {
    final isExpanded = _expandedFolders.contains(folder);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedFolders.remove(folder);
              } else {
                _expandedFolders.add(folder);
              }
            });
          },
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 16,
                  color: const Color(0xff8e98a8),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.folder_rounded,
                  size: 16,
                  color: const Color(0xffc4a000),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder,
                    style: const TextStyle(
                      color: Color(0xffd7e0ee),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${profiles.length}',
                  style: const TextStyle(
                    color: Color(0xff4a5568),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              children: profiles.map((p) => _buildSessionItem(p)).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildSessionItem(SessionProfile profile) {
    final icon = profile.type == SessionProfileType.ssh
        ? Icons.cloud_rounded
        : Icons.terminal_rounded;

    final iconColor = profile.type == SessionProfileType.ssh
        ? const Color(0xff8fb6ff)
        : const Color(0xff8ae234);

    return InkWell(
      onTap: () => widget.onSessionTap(profile),
      onLongPress: () => _showContextMenu(profile),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(
                      color: Color(0xffd7e0ee),
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (profile.host != null)
                    Text(
                      '${profile.username}@${profile.host}',
                      style: const TextStyle(
                        color: Color(0xff4a5568),
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (profile.autoLogin)
              const Icon(
                Icons.login_rounded,
                size: 12,
                color: Color(0xff8ae234),
              ),
            if (profile.logging)
              const Icon(
                Icons.fiber_manual_record_rounded,
                size: 12,
                color: Colors.redAccent,
              ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(SessionProfile profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff191d25),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Color(0xff8fb6ff)),
              title: const Text('编辑', style: TextStyle(color: Color(0xffd7e0ee))),
              onTap: () {
                Navigator.pop(context);
                widget.onSessionEdit(profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: Color(0xff8fb6ff)),
              title: const Text('复制', style: TextStyle(color: Color(0xffd7e0ee))),
              onTap: () {
                Navigator.pop(context);
                // TODO: 复制会话配置
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: const Text('删除', style: TextStyle(color: Color(0xffd7e0ee))),
              onTap: () {
                Navigator.pop(context);
                widget.onSessionDelete(profile);
              },
            ),
          ],
        ),
      ),
    );
  }
}
