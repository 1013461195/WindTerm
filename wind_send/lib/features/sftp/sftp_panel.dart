import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core_bridge/rust_core.dart';

/// SFTP 文件管理面板
class SftpPanel extends StatefulWidget {
  final SftpSession? sftpSession;
  final String initialPath;

  const SftpPanel({
    super.key,
    this.sftpSession,
    this.initialPath = '.',
  });

  @override
  State<SftpPanel> createState() => _SftpPanelState();
}

class _SftpPanelState extends State<SftpPanel> {
  String _currentPath = '.';
  List<SftpFileInfo> _files = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    if (widget.sftpSession != null) {
      _loadDirectory();
    }
  }

  @override
  void didUpdateWidget(SftpPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sftpSession != oldWidget.sftpSession) {
      if (widget.sftpSession != null) {
        _loadDirectory();
      } else {
        setState(() {
          _files = [];
        });
      }
    }
  }

  void _loadDirectory() {
    if (widget.sftpSession == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final files = widget.sftpSession!.listDir(_currentPath);
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _navigateTo(String path) {
    setState(() {
      _currentPath = path;
    });
    _loadDirectory();
  }

  void _navigateUp() {
    final parts = _currentPath.split('/');
    if (parts.length > 1) {
      parts.removeLast();
      _navigateTo(parts.join('/'));
    }
  }

  void _onFileTap(SftpFileInfo file) {
    if (file.isDir) {
      _navigateTo(file.path);
    }
  }

  void _onFileLongPress(SftpFileInfo file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff191d25),
      builder: (context) => _buildFileActions(file),
    );
  }

  Widget _buildFileActions(SftpFileInfo file) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!file.isDir)
            ListTile(
              leading: const Icon(Icons.download_rounded, color: Color(0xff8ae234)),
              title: const Text('下载', style: TextStyle(color: Color(0xffd7e0ee))),
              onTap: () {
                Navigator.pop(context);
                _downloadFile(file);
              },
            ),
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: Color(0xff8fb6ff)),
            title: const Text('重命名', style: TextStyle(color: Color(0xffd7e0ee))),
            onTap: () {
              Navigator.pop(context);
              _showRenameDialog(file);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
            title: const Text('删除', style: TextStyle(color: Color(0xffd7e0ee))),
            onTap: () {
              Navigator.pop(context);
              _showDeleteConfirm(file);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded, color: Color(0xff8fb6ff)),
            title: const Text('属性', style: TextStyle(color: Color(0xffd7e0ee))),
            onTap: () {
              Navigator.pop(context);
              _showFileInfo(file);
            },
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(SftpFileInfo file) {
    final controller = TextEditingController(text: file.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff191d25),
        title: const Text('重命名', style: TextStyle(color: Color(0xffd7e0ee))),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Color(0xffd7e0ee)),
          decoration: const InputDecoration(
            hintText: '输入新名称',
            hintStyle: TextStyle(color: Color(0xff4a5568)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              final newName = controller.text;
              if (newName.isNotEmpty && newName != file.name) {
                final newPath = '$_currentPath/$newName';
                widget.sftpSession?.rename(file.path, newPath);
                _loadDirectory();
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(SftpFileInfo file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff191d25),
        title: const Text('确认删除', style: TextStyle(color: Color(0xffd7e0ee))),
        content: Text(
          '确定要删除 ${file.name} 吗？',
          style: const TextStyle(color: Color(0xffd7e0ee)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              if (file.isDir) {
                widget.sftpSession?.rmdir(file.path);
              } else {
                widget.sftpSession?.unlink(file.path);
              }
              _loadDirectory();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showFileInfo(SftpFileInfo file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff191d25),
        title: Text(file.name, style: const TextStyle(color: Color(0xffd7e0ee))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('类型', file.isDir ? '目录' : file.isFile ? '文件' : '其他'),
            _infoRow('大小', file.sizeString),
            _infoRow('权限', file.permissionsString),
            _infoRow('路径', file.path),
            if (file.modifiedString.isNotEmpty)
              _infoRow('修改时间', file.modifiedString),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xff8e98a8)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xffd7e0ee)),
            ),
          ),
        ],
      ),
    );
  }

  void _uploadFile() async {
    if (widget.sftpSession == null) return;

    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final localPath = file.path;
        if (localPath != null) {
          final remotePath = '$_currentPath/${file.name}';
          final ret = widget.sftpSession!.upload(localPath, remotePath);
          if (ret == 0) {
            _loadDirectory();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('上传成功: ${file.name}')),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('上传失败: ${file.name}'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传失败: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _downloadFile(SftpFileInfo file) async {
    if (widget.sftpSession == null || file.isDir) return;

    try {
      final result = await FilePicker.platform.saveFile(
        fileName: file.name,
      );
      if (result != null) {
        final ret = widget.sftpSession!.download(file.path, result);
        if (ret == 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('下载成功: ${file.name}')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('下载失败: ${file.name}'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showCreateDirectoryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff191d25),
        title: const Text('新建目录', style: TextStyle(color: Color(0xffd7e0ee))),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Color(0xffd7e0ee)),
          decoration: const InputDecoration(
            hintText: '输入目录名称',
            hintStyle: TextStyle(color: Color(0xff4a5568)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              final name = controller.text;
              if (name.isNotEmpty) {
                final path = '$_currentPath/$name';
                widget.sftpSession?.mkdir(path);
                _loadDirectory();
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xff111318),
        border: Border(left: BorderSide(color: Color(0xff2a303b))),
      ),
      child: Column(
        children: [
          _buildToolbar(),
          _buildPathBar(),
          Expanded(
            child: _buildFileList(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xff191d25),
        border: Border(bottom: BorderSide(color: Color(0xff2a303b))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            color: const Color(0xff8e98a8),
            onPressed: _navigateUp,
            tooltip: '上级目录',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: const Color(0xff8e98a8),
            onPressed: _loadDirectory,
            tooltip: '刷新',
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.upload_rounded, size: 18),
            color: const Color(0xff8e98a8),
            onPressed: _uploadFile,
            tooltip: '上传文件',
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_rounded, size: 18),
            color: const Color(0xff8e98a8),
            onPressed: _showCreateDirectoryDialog,
            tooltip: '新建目录',
          ),
        ],
      ),
    );
  }

  Widget _buildPathBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        color: Color(0xff191d25),
        border: Border(bottom: BorderSide(color: Color(0xff2a303b))),
      ),
      child: Text(
        _currentPath,
        style: const TextStyle(
          color: Color(0xff8e98a8),
          fontSize: 12,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildFileList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xff2f6fed)),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xff8e98a8)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDirectory,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_files.isEmpty) {
      return const Center(
        child: Text(
          '空目录',
          style: TextStyle(color: Color(0xff4a5568)),
        ),
      );
    }

    return ListView.builder(
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        return _buildFileItem(file);
      },
    );
  }

  Widget _buildFileItem(SftpFileInfo file) {
    final icon = file.isDir
        ? Icons.folder_rounded
        : file.isSymlink
            ? Icons.link_rounded
            : Icons.insert_drive_file_rounded;

    final iconColor = file.isDir
        ? const Color(0xffc4a000)
        : file.isSymlink
            ? const Color(0xff2aa198)
            : const Color(0xff8e98a8);

    return InkWell(
      onTap: () => _onFileTap(file),
      onLongPress: () => _onFileLongPress(file),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                file.name,
                style: const TextStyle(
                  color: Color(0xffd7e0ee),
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!file.isDir) ...[
              Text(
                file.sizeString,
                style: const TextStyle(
                  color: Color(0xff8e98a8),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              file.permissionsString,
              style: const TextStyle(
                color: Color(0xff4a5568),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
