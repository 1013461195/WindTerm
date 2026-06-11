import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core_bridge/rust_core.dart';

/// SFTP 文件管理面板
class SftpPanel extends StatefulWidget {
  final SftpSession? sftpSession;
  final String initialPath;

  const SftpPanel({super.key, this.sftpSession, this.initialPath = '.'});

  @override
  State<SftpPanel> createState() => _SftpPanelState();
}

class _SftpPanelState extends State<SftpPanel> {
  String _currentPath = '.';
  late String _localPath;
  List<SftpFileInfo> _files = [];
  List<FileSystemEntity> _localFiles = [];
  bool _showLocalFiles = false;
  bool _loading = false;
  String? _error;
  final Map<int, SftpTransferTask> _transfers = {};
  Timer? _transferTimer;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _localPath =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    _loadLocalDirectory();
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

  @override
  void dispose() {
    _transferTimer?.cancel();
    super.dispose();
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

  void _loadLocalDirectory() {
    try {
      final entries = Directory(_localPath).listSync(followLinks: false)
        ..sort((left, right) {
          final leftDirectory = left is Directory;
          final rightDirectory = right is Directory;
          if (leftDirectory != rightDirectory) return leftDirectory ? -1 : 1;
          return left.path.toLowerCase().compareTo(right.path.toLowerCase());
        });
      setState(() => _localFiles = entries);
    } on Object catch (error) {
      _showError('读取本地目录失败: $error');
    }
  }

  void _navigateLocal(String path) {
    _localPath = path;
    _loadLocalDirectory();
  }

  void _navigateLocalUp() {
    final parent = Directory(_localPath).parent.path;
    if (parent != _localPath) _navigateLocal(parent);
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
              leading: const Icon(
                Icons.download_rounded,
                color: Color(0xff8ae234),
              ),
              title: const Text(
                '下载',
                style: TextStyle(color: Color(0xffd7e0ee)),
              ),
              onTap: () {
                Navigator.pop(context);
                _downloadFile(file);
              },
            ),
          if (file.isDir)
            ListTile(
              leading: const Icon(
                Icons.download_rounded,
                color: Color(0xff8ae234),
              ),
              title: const Text(
                '递归下载目录',
                style: TextStyle(color: Color(0xffd7e0ee)),
              ),
              onTap: () {
                Navigator.pop(context);
                _downloadDirectory(file);
              },
            ),
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: Color(0xff8fb6ff)),
            title: const Text(
              '重命名',
              style: TextStyle(color: Color(0xffd7e0ee)),
            ),
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
            leading: const Icon(
              Icons.info_outline_rounded,
              color: Color(0xff8fb6ff),
            ),
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
                _runOperation(
                  () => widget.sftpSession?.rename(file.path, newPath) ?? -1,
                  '重命名',
                );
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
            onPressed: () async {
              Navigator.pop(context);
              await _deleteRemoteEntry(file);
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
        title: Text(
          file.name,
          style: const TextStyle(color: Color(0xffd7e0ee)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(
              '类型',
              file.isDir
                  ? '目录'
                  : file.isFile
                  ? '文件'
                  : '其他',
            ),
            _infoRow('大小', file.sizeString),
            _infoRow('权限', file.permissionsString),
            _infoRow('路径', file.path),
            if (file.modifiedString.isNotEmpty)
              _infoRow('修改时间', file.modifiedString),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showChmodDialog(file);
            },
            child: const Text('修改权限'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showChmodDialog(SftpFileInfo file) {
    final controller = TextEditingController(
      text: (file.permissions & 0x1ff).toRadixString(8).padLeft(3, '0'),
    );
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff191d25),
        title: const Text('修改权限', style: TextStyle(color: Color(0xffd7e0ee))),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 4,
          style: const TextStyle(
            color: Color(0xffd7e0ee),
            fontFamily: 'monospace',
          ),
          decoration: const InputDecoration(
            labelText: '八进制权限',
            hintText: '例如 755 或 0644',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (!RegExp(r'^[0-7]{3,4}$').hasMatch(value)) {
                _showError('权限必须是 3 或 4 位八进制数字');
                return;
              }
              final mode = int.parse(value, radix: 8) & 0x1ff;
              Navigator.pop(context);
              _runOperation(
                () => widget.sftpSession?.chmod(file.path, mode) ?? -1,
                '修改权限',
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
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
      final result = await FilePicker.pickFiles();
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final localPath = file.path;
        if (localPath != null) {
          final remotePath = '$_currentPath/${file.name}';
          _startTransfer(
            widget.sftpSession!.startUpload(localPath, remotePath),
          );
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

  Future<void> _uploadDirectory() async {
    final session = widget.sftpSession;
    if (session == null) return;
    try {
      final selected = await FilePicker.getDirectoryPath();
      if (selected == null) return;
      final root = Directory(selected);
      final rootName = root.path
          .split(Platform.pathSeparator)
          .where((part) => part.isNotEmpty)
          .last;
      final remoteRoot = _joinRemote(_currentPath, rootName);
      if (session.mkdir(remoteRoot) != 0 && session.stat(remoteRoot) == null) {
        throw StateError('无法创建远程目录 $remoteRoot');
      }
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        final relative = entity.path
            .substring(root.path.length)
            .replaceAll(Platform.pathSeparator, '/');
        final remotePath = '$remoteRoot$relative';
        if (entity is Directory) {
          if (session.mkdir(remotePath) != 0 &&
              session.stat(remotePath) == null) {
            throw StateError('无法创建远程目录 $remotePath');
          }
        } else if (entity is File) {
          _startTransfer(session.startUpload(entity.path, remotePath));
        }
      }
    } on Object catch (error) {
      _showError('目录上传失败: $error');
    }
  }

  void _uploadLocalEntity(FileSystemEntity entity) {
    if (entity is File) {
      final name = entity.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      _startTransfer(
        widget.sftpSession!.startUpload(
          entity.path,
          _joinRemote(_currentPath, name),
        ),
      );
    } else if (entity is Directory) {
      unawaited(_uploadDirectoryPath(entity));
    }
  }

  Future<void> _uploadDirectoryPath(Directory root) async {
    final session = widget.sftpSession;
    if (session == null) return;
    try {
      final rootName = root.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      final remoteRoot = _joinRemote(_currentPath, rootName);
      if (session.mkdir(remoteRoot) != 0 && session.stat(remoteRoot) == null) {
        throw StateError('无法创建远程目录 $remoteRoot');
      }
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        final relative = entity.path
            .substring(root.path.length)
            .replaceAll(Platform.pathSeparator, '/');
        final remotePath = '$remoteRoot$relative';
        if (entity is Directory) {
          if (session.mkdir(remotePath) != 0 &&
              session.stat(remotePath) == null) {
            throw StateError('无法创建远程目录 $remotePath');
          }
        } else if (entity is File) {
          _startTransfer(session.startUpload(entity.path, remotePath));
        }
      }
    } on Object catch (error) {
      _showError('目录上传失败: $error');
    }
  }

  void _showLocalActions(FileSystemEntity entity) {
    final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xff191d25),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_rounded),
              title: Text('上传 $name'),
              onTap: () {
                Navigator.of(context).pop();
                _uploadLocalEntity(entity);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('重命名'),
              onTap: () {
                Navigator.of(context).pop();
                _showLocalRenameDialog(entity);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_rounded,
                color: Colors.redAccent,
              ),
              title: const Text('删除'),
              onTap: () {
                Navigator.of(context).pop();
                _deleteLocalEntity(entity);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLocalRenameDialog(FileSystemEntity entity) {
    final oldName = entity.uri.pathSegments
        .where((part) => part.isNotEmpty)
        .last;
    final controller = TextEditingController(text: oldName);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名本地项目'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                entity.renameSync('$_localPath${Platform.pathSeparator}$name');
                Navigator.of(context).pop();
                _loadLocalDirectory();
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _deleteLocalEntity(FileSystemEntity entity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本地项目'),
        content: Text('确定删除 ${entity.path} 吗？目录将递归删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await entity.delete(recursive: true);
      _loadLocalDirectory();
    } on Object catch (error) {
      _showError('删除本地项目失败: $error');
    }
  }

  void _createLocalDirectory() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建本地目录'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Directory(
                  '$_localPath${Platform.pathSeparator}$name',
                ).createSync();
                Navigator.of(context).pop();
                _loadLocalDirectory();
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _showCreateFileDialog({required bool local}) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff191d25),
        title: Text(
          local ? '新建本地文件' : '新建远程文件',
          style: const TextStyle(color: Color(0xffd7e0ee)),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xffd7e0ee)),
          decoration: const InputDecoration(hintText: '输入文件名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty || name == '.' || name == '..') return;
              Navigator.pop(context);
              if (local) {
                unawaited(_createLocalFile(name));
              } else {
                unawaited(_createRemoteFile(name));
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _createLocalFile(String name) async {
    try {
      final file = File('$_localPath${Platform.pathSeparator}$name');
      if (await file.exists()) throw StateError('文件已存在');
      await file.create();
      _loadLocalDirectory();
    } on Object catch (error) {
      _showError('创建本地文件失败: $error');
    }
  }

  Future<void> _createRemoteFile(String name) async {
    final session = widget.sftpSession;
    if (session == null) return;
    Directory? temporaryDirectory;
    try {
      final remotePath = _joinRemote(_currentPath, name);
      if (session.stat(remotePath) != null) throw StateError('文件已存在');
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'wind_send_empty_',
      );
      final emptyFile = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}empty',
      );
      await emptyFile.create();
      if (session.upload(emptyFile.path, remotePath) != 0) {
        throw StateError('服务器拒绝创建文件');
      }
      _loadDirectory();
    } on Object catch (error) {
      _showError('创建远程文件失败: $error');
    } finally {
      await temporaryDirectory?.delete(recursive: true);
    }
  }

  void _downloadFile(SftpFileInfo file) async {
    if (widget.sftpSession == null || file.isDir) return;

    try {
      final result = await FilePicker.saveFile(fileName: file.name);
      if (result != null) {
        _startTransfer(widget.sftpSession!.startDownload(file.path, result));
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

  Future<void> _downloadDirectory(SftpFileInfo directory) async {
    final session = widget.sftpSession;
    if (session == null) return;
    try {
      final selected = await FilePicker.getDirectoryPath(dialogTitle: '选择下载位置');
      if (selected == null) return;
      final localRoot = Directory(
        '$selected${Platform.pathSeparator}${directory.name}',
      );
      await localRoot.create(recursive: true);
      await _downloadRemoteTree(session, directory.path, localRoot.path);
    } on Object catch (error) {
      _showError('目录下载失败: $error');
    }
  }

  Future<void> _downloadRemoteTree(
    SftpSession session,
    String remotePath,
    String localPath,
  ) async {
    for (final entry in session.listDir(remotePath)) {
      final childLocal = '$localPath${Platform.pathSeparator}${entry.name}';
      if (entry.isDir) {
        await Directory(childLocal).create(recursive: true);
        await _downloadRemoteTree(session, entry.path, childLocal);
      } else if (entry.isFile) {
        _startTransfer(session.startDownload(entry.path, childLocal));
      }
    }
  }

  Future<void> _deleteRemoteEntry(SftpFileInfo entry) async {
    final session = widget.sftpSession;
    if (session == null) return;
    try {
      if (entry.isDir) {
        await _deleteRemoteTree(session, entry.path);
      } else if (session.unlink(entry.path) != 0) {
        throw StateError('无法删除 ${entry.path}');
      }
      _loadDirectory();
    } on Object catch (error) {
      _showError('删除失败: $error');
    }
  }

  Future<void> _deleteRemoteTree(SftpSession session, String remotePath) async {
    for (final entry in session.listDir(remotePath)) {
      if (entry.isDir) {
        await _deleteRemoteTree(session, entry.path);
      } else if (session.unlink(entry.path) != 0) {
        throw StateError('无法删除 ${entry.path}');
      }
    }
    if (session.rmdir(remotePath) != 0) {
      throw StateError('无法删除目录 $remotePath');
    }
  }

  String _joinRemote(String parent, String name) {
    if (parent == '.' || parent.isEmpty) return name;
    if (parent == '/') return '/$name';
    return '${parent.replaceFirst(RegExp(r'/+$'), '')}/$name';
  }

  Future<void> _runOperation(int Function() operation, String label) async {
    try {
      if (operation() != 0) throw StateError('$label失败');
      _loadDirectory();
    } on Object catch (error) {
      _showError('$label失败: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _startTransfer(int transferId) {
    if (transferId == 0) {
      throw StateError('创建 SFTP 传输任务失败');
    }
    _trackTransfer(transferId);
  }

  void _pollTransfers() {
    final session = widget.sftpSession;
    if (session == null) return;
    final ids = <int>{..._transfers.keys};
    var completed = false;
    for (final id in ids) {
      final task = session.transferStatus(id);
      if (task != null) {
        if (_transfers[id]?.state != SftpTransferState.completed &&
            task.state == SftpTransferState.completed) {
          completed = true;
        }
        _transfers[id] = task;
      }
    }
    if (mounted) setState(() {});
    if (completed) _loadDirectory();
    if (_transfers.values.every(
      (task) =>
          task.state != SftpTransferState.running &&
          task.state != SftpTransferState.queued,
    )) {
      _transferTimer?.cancel();
      _transferTimer = null;
    }
  }

  void _trackTransfer(int transferId) {
    final task = widget.sftpSession?.transferStatus(transferId);
    if (task != null) {
      _transfers[transferId] = task;
    }
    _transferTimer ??= Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _pollTransfers(),
    );
  }

  void _retryTransfer(SftpTransferTask task) {
    final id = task.isUpload
        ? widget.sftpSession?.startUpload(task.localPath, task.remotePath)
        : widget.sftpSession?.startDownload(task.remotePath, task.localPath);
    if (id != null && id != 0) _trackTransfer(id);
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
                _runOperation(
                  () => widget.sftpSession?.mkdir(path) ?? -1,
                  '创建目录',
                );
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
          _buildPanelSelector(),
          _buildToolbar(),
          _buildPathBar(),
          Expanded(
            child: _showLocalFiles ? _buildLocalFileList() : _buildFileList(),
          ),
          if (_transfers.isNotEmpty) _buildTransferQueue(),
        ],
      ),
    );
  }

  Widget _buildPanelSelector() {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: true, label: Text('本地')),
        ButtonSegment(value: false, label: Text('远程')),
      ],
      selected: {_showLocalFiles},
      onSelectionChanged: (values) {
        setState(() => _showLocalFiles = values.first);
      },
    );
  }

  Widget _buildTransferQueue() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: const BoxDecoration(
        color: Color(0xff191d25),
        border: Border(top: BorderSide(color: Color(0xff2a303b))),
      ),
      child: ListView(
        shrinkWrap: true,
        children: _transfers.values.map((task) {
          final running =
              task.state == SftpTransferState.running ||
              task.state == SftpTransferState.queued;
          return ListTile(
            dense: true,
            title: Text(
              task.isUpload ? '上传 ${task.localPath}' : '下载 ${task.remotePath}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: task.totalBytes == 0 ? null : task.progress,
                ),
                Text(
                  '${_formatBytes(task.transferredBytes)} / '
                  '${_formatBytes(task.totalBytes)}  '
                  '${_formatBytes(task.speed.round())}/s'
                  '${task.error == null ? '' : '  ${task.error}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            trailing: running
                ? IconButton(
                    onPressed: () =>
                        widget.sftpSession?.cancelTransfer(task.id),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '取消',
                  )
                : task.state == SftpTransferState.failed ||
                      task.state == SftpTransferState.canceled
                ? IconButton(
                    onPressed: () => _retryTransfer(task),
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: '重试',
                  )
                : const Icon(Icons.check_rounded, color: Colors.green),
          );
        }).toList(),
      ),
    );
  }

  String _formatBytes(num bytes) {
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
            onPressed: _showLocalFiles ? _navigateLocalUp : _navigateUp,
            tooltip: '上级目录',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: const Color(0xff8e98a8),
            onPressed: _showLocalFiles ? _loadLocalDirectory : _loadDirectory,
            tooltip: '刷新',
          ),
          const Spacer(),
          if (!_showLocalFiles) ...[
            IconButton(
              icon: const Icon(Icons.upload_rounded, size: 18),
              color: const Color(0xff8e98a8),
              onPressed: _uploadFile,
              tooltip: '上传文件',
            ),
            IconButton(
              icon: const Icon(Icons.drive_folder_upload_rounded, size: 18),
              color: const Color(0xff8e98a8),
              onPressed: _uploadDirectory,
              tooltip: '递归上传目录',
            ),
          ],
          IconButton(
            icon: const Icon(Icons.note_add_rounded, size: 18),
            color: const Color(0xff8e98a8),
            onPressed: () => _showCreateFileDialog(local: _showLocalFiles),
            tooltip: '新建文件',
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_rounded, size: 18),
            color: const Color(0xff8e98a8),
            onPressed: _showLocalFiles
                ? _createLocalDirectory
                : _showCreateDirectoryDialog,
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
        _showLocalFiles ? _localPath : _currentPath,
        style: const TextStyle(color: Color(0xff8e98a8), fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildLocalFileList() {
    if (_localFiles.isEmpty) {
      return const Center(child: Text('空目录'));
    }
    return ListView.builder(
      itemCount: _localFiles.length,
      itemBuilder: (context, index) {
        final entity = _localFiles[index];
        final directory = entity is Directory;
        final name = entity.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last;
        int? size;
        if (entity is File) {
          try {
            size = entity.lengthSync();
          } on Object {
            size = null;
          }
        }
        return ListTile(
          dense: true,
          leading: Icon(
            directory ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
            color: directory
                ? const Color(0xffc4a000)
                : const Color(0xff8e98a8),
          ),
          title: Text(name, overflow: TextOverflow.ellipsis),
          subtitle: size == null ? null : Text(_formatBytes(size)),
          onTap: directory
              ? () => _navigateLocal(entity.path)
              : () => _uploadLocalEntity(entity),
          onLongPress: () => _showLocalActions(entity),
          trailing: IconButton(
            icon: const Icon(Icons.upload_rounded, size: 18),
            tooltip: '上传到当前远程目录',
            onPressed: () => _uploadLocalEntity(entity),
          ),
        );
      },
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
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xff8e98a8)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadDirectory, child: const Text('重试')),
          ],
        ),
      );
    }

    if (_files.isEmpty) {
      return const Center(
        child: Text('空目录', style: TextStyle(color: Color(0xff4a5568))),
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
                style: const TextStyle(color: Color(0xffd7e0ee), fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!file.isDir) ...[
              Text(
                file.sizeString,
                style: const TextStyle(color: Color(0xff8e98a8), fontSize: 11),
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
