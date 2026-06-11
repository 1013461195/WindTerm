import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core_bridge/rust_core.dart';

class UpdatePackage {
  const UpdatePackage({
    required this.url,
    required this.sha256,
    required this.fileName,
  });

  final String url;
  final String sha256;
  final String fileName;

  factory UpdatePackage.fromJson(Map<String, dynamic> json) {
    return UpdatePackage(
      url: json['url'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      fileName: json['fileName'] as String? ?? 'wind-send-update',
    );
  }
}

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.package,
  });

  final String version;
  final String notes;
  final UpdatePackage package;
}

class UpdateService {
  UpdateService(
    this._core, {
    required this.dataDirectory,
    this.manifestUrl = const String.fromEnvironment('UPDATE_MANIFEST_URL'),
    this.publicKey = const String.fromEnvironment('UPDATE_PUBLIC_KEY'),
    this.currentVersion = const String.fromEnvironment(
      'APP_VERSION',
      defaultValue: '1.0.0',
    ),
  });

  final RustCore _core;
  final String dataDirectory;
  final String manifestUrl;
  final String publicKey;
  final String currentVersion;

  bool get configured => manifestUrl.isNotEmpty && publicKey.isNotEmpty;

  Future<UpdateInfo?> check() async {
    if (!configured) {
      throw StateError('未配置 UPDATE_MANIFEST_URL 或 UPDATE_PUBLIC_KEY');
    }
    final manifestUri = Uri.parse(manifestUrl);
    if (!_isAllowedDownloadUri(manifestUri)) {
      throw StateError('更新清单必须使用 HTTPS');
    }
    final envelopeBytes = await _downloadBytes(
      manifestUri,
      maxBytes: 1024 * 1024,
    );
    final envelope =
        jsonDecode(utf8.decode(envelopeBytes)) as Map<String, dynamic>;
    final payload = base64Decode(envelope['payload'] as String? ?? '');
    final signature = envelope['signature'] as String? ?? '';
    if (!_core.verifyUpdateSignature(payload, signature, publicKey)) {
      throw StateError('更新清单签名无效');
    }
    final manifest = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    final version = manifest['version'] as String? ?? '';
    if (!RegExp(
      r'^[0-9]+(?:\.[0-9]+){0,2}(?:[-+][0-9A-Za-z.-]+)?$',
    ).hasMatch(version)) {
      throw StateError('更新版本号格式无效');
    }
    if (!_isNewer(version, currentVersion)) return null;
    final packages = manifest['packages'] as Map<String, dynamic>? ?? {};
    final packageJson = packages[_platformName];
    if (packageJson is! Map<String, dynamic>) {
      throw StateError('更新清单不包含 $_platformName 安装包');
    }
    final package = UpdatePackage.fromJson(packageJson);
    final packageUri = Uri.tryParse(package.url);
    if (packageUri == null ||
        !_isAllowedDownloadUri(packageUri) ||
        package.sha256.length != 64 ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(package.sha256) ||
        package.fileName.isEmpty ||
        package.fileName != _safeFileName(package.fileName)) {
      throw StateError('更新包信息不完整');
    }
    return UpdateInfo(
      version: version,
      notes: manifest['notes'] as String? ?? '',
      package: package,
    );
  }

  Future<File> download(UpdateInfo update) async {
    final directory = Directory('$dataDirectory/updates/${update.version}');
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${update.package.fileName}',
    );
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(update.package.url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '下载更新失败: HTTP ${response.statusCode}',
          uri: Uri.parse(update.package.url),
        );
      }
      final sink = file.openWrite();
      try {
        await response.pipe(sink);
      } on Object {
        await sink.close();
        if (await file.exists()) await file.delete();
        rethrow;
      }
    } on Object {
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
    if (!_core.verifyUpdateFileSha256(file.path, update.package.sha256)) {
      await file.delete();
      throw StateError('更新包 SHA-256 校验失败');
    }
    return file;
  }

  Future<void> openInstaller(File file) async {
    if (Platform.isMacOS) {
      await Process.start('open', [file.path], mode: ProcessStartMode.detached);
    } else if (Platform.isWindows) {
      await Process.start('cmd', [
        '/c',
        'start',
        '',
        file.path,
      ], mode: ProcessStartMode.detached);
    } else {
      await Process.start('xdg-open', [
        file.path,
      ], mode: ProcessStartMode.detached);
    }
  }

  Future<Uint8List> _downloadBytes(Uri uri, {required int maxBytes}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('获取更新清单失败: HTTP ${response.statusCode}', uri: uri);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw StateError('更新清单超过大小限制');
        }
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  bool _isNewer(String candidate, String current) {
    final candidateParts = _versionParts(candidate);
    final currentParts = _versionParts(current);
    for (var index = 0; index < 3; index++) {
      if (candidateParts[index] != currentParts[index]) {
        return candidateParts[index] > currentParts[index];
      }
    }
    return false;
  }

  List<int> _versionParts(String value) {
    final core = value.split(RegExp(r'[-+]')).first;
    final parts = core
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    return List<int>.generate(
      3,
      (index) => index < parts.length ? parts[index] : 0,
    );
  }

  String _safeFileName(String value) {
    return value.split(RegExp(r'[/\\]')).last;
  }

  bool _isAllowedDownloadUri(Uri uri) {
    if (uri.scheme == 'https' && uri.host.isNotEmpty) return true;
    return uri.scheme == 'http' &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '::1');
  }

  String get _platformName {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'linux';
  }
}
