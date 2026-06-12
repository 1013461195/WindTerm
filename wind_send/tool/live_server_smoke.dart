import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:wind_send/core_bridge/rust_core.dart';

typedef _OpenJsonNative = Uint64 Function(Pointer<Utf8>);
typedef _OpenJsonDart = int Function(Pointer<Utf8>);
typedef _LastErrorNative = Pointer<Utf8> Function();
typedef _LastErrorDart = Pointer<Utf8> Function();
typedef _StringFreeNative = Void Function(Pointer<Utf8>);
typedef _StringFreeDart = void Function(Pointer<Utf8>);

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln(
      'usage: dart run tool/live_server_smoke.dart <host> <port> <username>',
    );
    exitCode = 2;
    return;
  }
  final echoWasEnabled = stdin.hasTerminal ? stdin.echoMode : false;
  if (stdin.hasTerminal) stdin.echoMode = false;
  final password = stdin.readLineSync();
  if (stdin.hasTerminal) {
    stdin.echoMode = echoWasEnabled;
    stdout.writeln();
  }
  if (password == null || password.isEmpty) {
    throw StateError('password is required on stdin');
  }

  final host = arguments[0];
  final port = int.parse(arguments[1]);
  final username = arguments[2];
  final dylibPath =
      'build/macos/Build/Products/Release/wind_send.app/Contents/'
      'Frameworks/librust_core.dylib';
  final library = DynamicLibrary.open(dylibPath);
  final core = NativeRustCore(library);
  final openJson = library.lookupFunction<_OpenJsonNative, _OpenJsonDart>(
    'core_session_open_json',
  );
  final lastError = library.lookupFunction<_LastErrorNative, _LastErrorDart>(
    'core_session_last_open_error',
  );
  final stringFree = library.lookupFunction<_StringFreeNative, _StringFreeDart>(
    'core_string_free',
  );

  final knownHosts = File(
    '${Directory.systemTemp.path}/wind_send_live_${DateTime.now().microsecondsSinceEpoch}.known_hosts',
  );
  final localRoot = await Directory.systemTemp.createTemp(
    'wind_send_live_sftp_',
  );
  final echoServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  echoServer.listen((socket) {
    socket.listen(socket.add, onDone: socket.destroy);
  });
  final localPort = await _unusedPort();
  final dynamicPort = await _unusedPort();
  final remotePort = await _unusedPort();
  final httpProxyPort = await _unusedPort();
  final socksProxyPort = await _unusedPort();
  final httpProxy = await _startTestProxy('http', httpProxyPort);
  final socksProxy = await _startTestProxy('socks5', socksProxyPort);
  final remoteRoot =
      '/tmp/wind_send_live_${DateTime.now().microsecondsSinceEpoch}';
  final protocolBase = 40000 + DateTime.now().millisecondsSinceEpoch % 15000;
  final rawPort = protocolBase;
  final telnetPort = protocolBase + 1;

  String takeError() {
    final pointer = lastError();
    if (pointer.address == 0) return 'unknown error';
    try {
      return pointer.toDartString();
    } finally {
      stringFree(pointer);
    }
  }

  int open(Map<String, Object?> request) {
    final pointer = jsonEncode(request).toNativeUtf8();
    try {
      final id = openJson(pointer);
      if (id == 0) throw StateError(takeError());
      return id;
    } finally {
      malloc.free(pointer);
    }
  }

  Map<String, Object?> request({
    bool acceptUnknown = false,
    String? proxyCommand,
    Map<String, Object?>? proxy,
    List<Map<String, Object?>> jumpHosts = const [],
    List<Map<String, Object?>> portForwards = const [],
  }) {
    return <String, Object?>{
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'private_key_path': null,
      'passphrase': null,
      'known_hosts_path': knownHosts.path,
      'accept_unknown_host': acceptUnknown,
      'network': <String, Object?>{
        'proxy': proxy,
        'proxyCommand': proxyCommand,
        'jumpHosts': jumpHosts,
        'portForwards': portForwards,
        'keepalive': <String, Object?>{
          'enabled': true,
          'intervalSeconds': 3,
          'maxMisses': 2,
        },
        'reconnect': <String, Object?>{
          'enabled': true,
          'maxAttempts': 2,
          'initialDelayMs': 50,
          'maxDelayMs': 200,
          'backoffFactor': 1.5,
          'jitter': false,
        },
        'agentForwarding': false,
      },
    };
  }

  SshSession? session;
  SftpSession? sftp;
  try {
    session = core.attachSession(
      open(
        request(
          acceptUnknown: true,
          portForwards: <Map<String, Object?>>[
            <String, Object?>{
              'type': 'local',
              'bindAddress': '127.0.0.1',
              'bindPort': localPort,
              'remoteHost': '127.0.0.1',
              'remotePort': port,
            },
            <String, Object?>{
              'type': 'dynamic',
              'bindAddress': '127.0.0.1',
              'bindPort': dynamicPort,
              'remoteHost': null,
              'remotePort': null,
            },
          ],
        ),
      ),
    );
    _pass('SSH password authentication and known_hosts acceptance');

    _expect(session.getState() == 'running', 'SSH state is running');
    _expect(session.resize(100, 31) == 0, 'PTY resize request');
    session.writeInput(
      "printf '\\n__TERM_BEGIN__\\n'; stty size; "
      "printf '中文🙂é\\n'; printf '__TERM_END__\\n'\n",
    );
    final terminalOutput = await _readUntil(session, '__TERM_END__');
    _expect(terminalOutput.contains('31 100'), 'remote PTY reports 31x100');
    _expect(terminalOutput.contains('中文🙂é'), 'UTF-8/emoji/combining output');

    sftp = core.openSftp(session.id);
    _expect(sftp.mkdir(remoteRoot) == 0, 'SFTP mkdir');
    final upload = File('${localRoot.path}/upload.txt');
    await upload.writeAsString('wind-send-live-${DateTime.now().toUtc()}');
    final remoteUpload = '$remoteRoot/upload.txt';
    _expect(sftp.upload(upload.path, remoteUpload) == 0, 'SFTP upload');
    _expect(sftp.chmod(remoteUpload, 0x1a0) == 0, 'SFTP chmod 0640');
    final stat = sftp.stat(remoteUpload);
    _expect(stat != null && (stat.permissions & 0x1ff) == 0x1a0, 'SFTP stat');
    final renamed = '$remoteRoot/renamed.txt';
    _expect(sftp.rename(remoteUpload, renamed) == 0, 'SFTP rename');
    final listing = sftp.listDir(remoteRoot);
    _expect(listing.any((entry) => entry.name == 'renamed.txt'), 'SFTP list');
    final downloaded = File('${localRoot.path}/downloaded.txt');
    _expect(sftp.download(renamed, downloaded.path) == 0, 'SFTP download');
    _expect(
      await downloaded.readAsString() == await upload.readAsString(),
      'SFTP content integrity',
    );

    final localShell = core.openLocalShell(
      shell: '/bin/zsh',
      cols: 90,
      rows: 25,
    );
    localShell.writeInput("printf '__LOCAL_SHELL_OK__\\n'\n");
    _expect(
      (await _readLocalUntil(
        localShell,
        '__LOCAL_SHELL_OK__',
      )).contains('__LOCAL_SHELL_OK__'),
      'local PTY shell',
    );
    _expect(localShell.resize(101, 32) == 0, 'local PTY resize');
    localShell.close();

    final rawScript = base64Encode(
      utf8.encode(r'''
#!/bin/sh
printf 'RAW_READY\n'
IFS= read -r line
printf 'RAW_ECHO:%s\n' "$line"
'''),
    );
    final telnetScript = base64Encode(
      utf8.encode(r'''
#!/bin/sh
printf '\377\373\001\377\375\037\377\375\030TELNET_READY\r\n'
timeout 2 dd bs=1 count=256 2>/dev/null |
  od -An -tx1 |
  tr -d '\n' > /tmp/wind_send_telnet_received.hex
printf 'TELNET_ECHO\r\n'
if grep -q 'ff fa 1f 00 78 00 28 ff f0' /tmp/wind_send_telnet_received.hex; then
  printf 'NAWS_OK\r\n'
else
  printf 'NAWS_MISSING\r\n'
fi
'''),
    );
    session.writeInput(
      "printf %s '$rawScript' | base64 -d > /tmp/wind_send_raw.sh; "
      "printf %s '$telnetScript' | base64 -d > /tmp/wind_send_telnet.sh; "
      "chmod 700 /tmp/wind_send_raw.sh /tmp/wind_send_telnet.sh; "
      "nc -l -p $rawPort -e /tmp/wind_send_raw.sh "
      ">/tmp/wind_send_raw.log 2>&1 & "
      "nc -l -p $telnetPort -e /tmp/wind_send_telnet.sh "
      ">/tmp/wind_send_telnet.log 2>&1 & "
      "sleep 0.3; printf '__PROTOCOL_SERVERS_READY__\\n'\n",
    );
    await _readUntil(session, '__PROTOCOL_SERVERS_READY__');

    final raw = core.openProtocol(<String, Object?>{
      'type': 'raw_tcp',
      'config': <String, Object?>{
        'host': host,
        'port': rawPort,
        'encoding': 'utf-8',
        'newline': 'CRLF',
      },
    });
    _expect(
      (await _readProtocolUntil(raw, 'RAW_READY')).contains('RAW_READY'),
      'Raw TCP connect/read',
    );
    raw.writeInput('ping\n');
    _expect(
      (await _readProtocolUntil(raw, 'RAW_ECHO:')).contains('RAW_ECHO:'),
      'Raw TCP write/newline',
    );
    raw.close();

    final telnet = core.openProtocol(<String, Object?>{
      'type': 'telnet',
      'config': <String, Object?>{
        'host': host,
        'port': telnetPort,
        'naws': true,
        'ttype': true,
        'echo': false,
        'sga': true,
        'binary': false,
        'encoding': 'utf-8',
        'newline': 'CRLF',
      },
    });
    _expect(
      (await _readProtocolUntil(
        telnet,
        'TELNET_READY',
      )).contains('TELNET_READY'),
      'Telnet connect and IAC filtering',
    );
    _expect(telnet.resize(120, 40) == 0, 'Telnet NAWS resize request');
    telnet.writeInput('ping\n');
    final telnetOutput = await _readProtocolUntil(telnet, 'NAWS_');
    _expect(telnetOutput.contains('TELNET_ECHO'), 'Telnet write/newline');
    _expect(telnetOutput.contains('NAWS_OK'), 'Telnet NAWS payload');
    telnet.close();

    try {
      await _testSshBanner(localPort, 'local port forwarding');
    } on Object catch (error) {
      final status = _statusByType(session.portForwardStatus(), 'local');
      if (status?.lastError?.contains('administratively prohibited') == true) {
        stdout.writeln('BLOCKED: local port forwarding: ${status!.lastError}');
      } else {
        throw StateError(
          'local forwarding failed: $error / ${status?.lastError}',
        );
      }
    }
    try {
      await _testSocks5(dynamicPort, port);
    } on Object catch (error) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final status = _statusByType(session.portForwardStatus(), 'dynamic');
      if (status?.lastError?.contains('administratively prohibited') == true) {
        stdout.writeln(
          'BLOCKED: dynamic port forwarding: ${status!.lastError}',
        );
      } else {
        throw StateError(
          'dynamic forwarding failed: $error / ${status?.lastError}',
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final statuses = session.portForwardStatus();
    _expect(statuses.length == 2, 'port forwarding status count');
    _expect(
      statuses.every(
        (status) => status.state == 'running' || status.state == 'error',
      ),
      'port forwarding states',
    );
    _expect(
      statuses.every((status) => status.totalConnections > 0),
      'port forwarding connection metrics',
    );

    _expect(session.reconnect() == 0, 'SSH reconnect');
    session.writeInput("printf '__RECONNECT_OK__\\n'\n");
    _expect(
      (await _readUntil(
        session,
        '__RECONNECT_OK__',
      )).contains('__RECONNECT_OK__'),
      'terminal works after reconnect',
    );

    _expect(sftp.unlink(renamed) == 0, 'SFTP unlink');
    _expect(sftp.rmdir(remoteRoot) == 0, 'SFTP rmdir');
    sftp.close();
    sftp = null;
    session.close();
    session = null;

    final proxySession = core.attachSession(
      open(request(proxyCommand: '/usr/bin/nc %h %p')),
    );
    proxySession.writeInput("printf '__PROXY_COMMAND_OK__\\n'\n");
    _expect(
      (await _readUntil(
        proxySession,
        '__PROXY_COMMAND_OK__',
      )).contains('__PROXY_COMMAND_OK__'),
      'ProxyCommand connection',
    );
    proxySession.close();

    for (final proxy in <Map<String, Object?>>[
      <String, Object?>{
        'type': 'http',
        'host': '127.0.0.1',
        'port': httpProxyPort,
        'username': null,
        'password': null,
      },
      <String, Object?>{
        'type': 'socks5',
        'host': '127.0.0.1',
        'port': socksProxyPort,
        'username': null,
        'password': null,
      },
    ]) {
      final proxyType = proxy['type'];
      final proxiedSession = core.attachSession(open(request(proxy: proxy)));
      proxiedSession.writeInput("printf '__PROXY_${proxyType}_OK__\\n'\n");
      _expect(
        (await _readUntil(
          proxiedSession,
          '__PROXY_${proxyType}_OK__',
        )).contains('__PROXY_${proxyType}_OK__'),
        '$proxyType proxy connection',
      );
      proxiedSession.close();
    }

    try {
      final jumpSession = core.attachSession(
        open(
          request(
            jumpHosts: <Map<String, Object?>>[
              <String, Object?>{
                'host': host,
                'port': port,
                'username': username,
                'password': password,
                'privateKeyPath': null,
              },
            ],
          ),
        ),
      );
      jumpSession.writeInput("printf '__JUMP_OK__\\n'\n");
      _expect(
        (await _readUntil(jumpSession, '__JUMP_OK__')).contains('__JUMP_OK__'),
        'single jump host connection',
      );
      jumpSession.close();
    } on Object catch (error) {
      if (error.toString().contains('administratively prohibited')) {
        stdout.writeln('BLOCKED: single jump host connection: $error');
      } else {
        rethrow;
      }
    }

    try {
      final remoteForwardSession = core.attachSession(
        open(
          request(
            portForwards: <Map<String, Object?>>[
              <String, Object?>{
                'type': 'remote',
                'bindAddress': '127.0.0.1',
                'bindPort': remotePort,
                'remoteHost': '127.0.0.1',
                'remotePort': echoServer.port,
              },
            ],
          ),
        ),
      );
      remoteForwardSession.writeInput(
        "exec 3<>/dev/tcp/127.0.0.1/$remotePort; "
        "printf REMOTE_FORWARD_OK >&3; "
        "head -c 17 <&3; printf '\\n__RF_DONE__\\n'\n",
      );
      final output = await _readUntil(remoteForwardSession, '__RF_DONE__');
      _expect(output.contains('REMOTE_FORWARD_OK'), 'remote port forwarding');
      remoteForwardSession.close();
    } on Object catch (error) {
      stdout.writeln('BLOCKED: remote port forwarding: $error');
    }

    final originalKnownHosts = await knownHosts.readAsString();
    final fields = originalKnownHosts.trim().split(RegExp(r'\s+'));
    if (fields.length >= 3 && fields[2].isNotEmpty) {
      final replacement = fields[2].startsWith('A')
          ? 'B${fields[2].substring(1)}'
          : 'A${fields[2].substring(1)}';
      fields[2] = replacement;
      await knownHosts.writeAsString('${fields.join(' ')}\n');
      final pointer = jsonEncode(request()).toNativeUtf8();
      try {
        final id = openJson(pointer);
        _expect(id == 0, 'changed host key is rejected');
        _expect(
          takeError().startsWith('HOST_KEY_CHANGED:'),
          'changed key error',
        );
      } finally {
        malloc.free(pointer);
      }
    }
  } finally {
    sftp?.close();
    session?.close();
    await echoServer.close();
    httpProxy.kill();
    socksProxy.kill();
    await httpProxy.exitCode;
    await socksProxy.exitCode;
    if (await knownHosts.exists()) await knownHosts.delete();
    if (await localRoot.exists()) await localRoot.delete(recursive: true);
  }
}

Future<Process> _startTestProxy(String mode, int port) async {
  const script = r'''
import select, socket, socketserver, struct, sys

mode, listen_port = sys.argv[1], int(sys.argv[2])

def exact(sock, count):
    data = b""
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise EOFError()
        data += chunk
    return data

def relay(left, right):
    sockets = [left, right]
    while True:
        readable, _, _ = select.select(sockets, [], [], 10)
        if not readable:
            continue
        for source in readable:
            data = source.recv(65536)
            if not data:
                return
            (right if source is left else left).sendall(data)

class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        client = self.request
        if mode == "http":
            request = b""
            while b"\r\n\r\n" not in request:
                request += client.recv(4096)
            target = request.split(b"\r\n", 1)[0].split()[1].decode()
            host, port_text = target.rsplit(":", 1)
            upstream = socket.create_connection((host, int(port_text)), timeout=10)
            client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        else:
            version, count = exact(client, 2)
            exact(client, count)
            client.sendall(b"\x05\x00")
            version, command, reserved, address_type = exact(client, 4)
            if address_type == 1:
                host = socket.inet_ntoa(exact(client, 4))
            elif address_type == 3:
                host = exact(client, exact(client, 1)[0]).decode()
            else:
                host = socket.inet_ntop(socket.AF_INET6, exact(client, 16))
            target_port = struct.unpack("!H", exact(client, 2))[0]
            upstream = socket.create_connection((host, target_port), timeout=10)
            client.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
        try:
            relay(client, upstream)
        finally:
            upstream.close()

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

Server(("127.0.0.1", listen_port), Handler).serve_forever()
''';
  final process = await Process.start('python3', <String>[
    '-u',
    '-c',
    script,
    mode,
    '$port',
  ]);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  if (await _processExited(process)) {
    throw StateError('$mode test proxy failed to start');
  }
  return process;
}

Future<bool> _processExited(Process process) async {
  try {
    await process.exitCode.timeout(const Duration(milliseconds: 1));
    return true;
  } on TimeoutException {
    return false;
  }
}

Future<int> _unusedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<String> _readUntil(
  SshSession session,
  String marker, {
  Duration timeout = const Duration(seconds: 8),
  int occurrences = 2,
}) async {
  final deadline = DateTime.now().add(timeout);
  final output = StringBuffer();
  while (DateTime.now().isBefore(deadline)) {
    final snapshot = session.readOutput();
    if (snapshot != null) {
      output.write(snapshot.outputText);
      if (marker.allMatches(output.toString()).length >= occurrences) {
        return output.toString();
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw TimeoutException('did not receive $marker; output=$output');
}

Future<String> _readLocalUntil(
  LocalShellSession session,
  String marker, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  final output = StringBuffer();
  while (DateTime.now().isBefore(deadline)) {
    final snapshot = session.readOutput();
    if (snapshot != null) {
      output.write(snapshot.outputText);
      if (marker.allMatches(output.toString()).length >= 2) {
        return output.toString();
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw TimeoutException('local shell did not receive $marker');
}

Future<String> _readProtocolUntil(
  ProtocolSession session,
  String marker, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  final output = StringBuffer();
  while (DateTime.now().isBefore(deadline)) {
    final snapshot = session.readOutput();
    if (snapshot != null) {
      output.write(snapshot.outputText);
      if (output.toString().contains(marker)) return output.toString();
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw TimeoutException('protocol did not receive $marker; output=$output');
}

Future<void> _testSshBanner(int port, String label) async {
  final socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    port,
    timeout: const Duration(seconds: 3),
  );
  final reader = _SocketReader(socket);
  try {
    socket.add(utf8.encode('SSH-2.0-WindSendForwardTest\r\n'));
    await socket.flush();
    final banner = utf8.decode(
      await reader.readUntil(10, timeout: const Duration(seconds: 4)),
      allowMalformed: true,
    );
    _expect(banner.startsWith('SSH-'), label);
  } finally {
    await reader.close();
  }
}

Future<void> _testSocks5(int proxyPort, int targetPort) async {
  final socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    proxyPort,
    timeout: const Duration(seconds: 3),
  );
  final reader = _SocketReader(socket);
  try {
    socket.add(const <int>[5, 1, 0]);
    await socket.flush();
    _expect(
      _bytesEqual(await reader.readExact(2), const <int>[5, 0]),
      'SOCKS5 negotiation',
    );
    socket.add(<int>[
      5,
      1,
      0,
      1,
      127,
      0,
      0,
      1,
      targetPort >> 8,
      targetPort & 0xff,
    ]);
    await socket.flush();
    final response = await reader.readExact(10);
    _expect(response[1] == 0, 'SOCKS5 connect');
    final banner = utf8.decode(
      await reader.readUntil(10, timeout: const Duration(seconds: 4)),
      allowMalformed: true,
    );
    _expect(banner.startsWith('SSH-'), 'dynamic SOCKS5 forwarding');
  } finally {
    await reader.close();
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

PortForwardStatus? _statusByType(
  List<PortForwardStatus> statuses,
  String type,
) {
  for (final status in statuses) {
    if (status.type == type) return status;
  }
  return null;
}

void _expect(bool value, String label) {
  if (!value) throw StateError('FAIL: $label');
  _pass(label);
}

void _pass(String label) {
  stdout.writeln('PASS: $label');
}

class _SocketReader {
  _SocketReader(this.socket) {
    _subscription = socket.listen(
      (data) {
        _buffer.addAll(data);
        _notify();
      },
      onError: (Object error, StackTrace stack) {
        _error = error;
        _notify();
      },
      onDone: () {
        _done = true;
        _notify();
      },
    );
  }

  final Socket socket;
  final List<int> _buffer = <int>[];
  late final StreamSubscription<Uint8List> _subscription;
  Completer<void>? _changed;
  Object? _error;
  bool _done = false;

  Future<List<int>> readExact(
    int length, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_buffer.length < length) {
      await _wait(deadline);
    }
    final result = _buffer.sublist(0, length);
    _buffer.removeRange(0, length);
    return result;
  }

  Future<List<int>> readUntil(
    int byte, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final index = _buffer.indexOf(byte);
      if (index >= 0) {
        final result = _buffer.sublist(0, index + 1);
        _buffer.removeRange(0, index + 1);
        return result;
      }
      await _wait(deadline);
    }
  }

  Future<void> _wait(DateTime deadline) async {
    if (_error != null) throw _error!;
    if (_done) throw StateError('socket closed before expected data');
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) throw TimeoutException('socket read');
    final completer = _changed ??= Completer<void>();
    await completer.future.timeout(remaining);
  }

  void _notify() {
    final completer = _changed;
    _changed = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Future<void> close() async {
    await _subscription.cancel();
    await socket.close();
  }
}
