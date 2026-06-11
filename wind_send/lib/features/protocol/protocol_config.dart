/// 协议类型
enum ProtocolType {
  ssh,
  telnet,
  serial,
  rawTcp,
  localShell,
}

/// Telnet 配置
class TelnetConfig {
  final String host;
  final int port;
  final bool naws; // Negotiate About Window Size
  final bool ttype; // Terminal Type
  final bool echo;
  final bool sga; // Suppress Go Ahead
  final bool binary;
  final String encoding;

  const TelnetConfig({
    required this.host,
    this.port = 23,
    this.naws = true,
    this.ttype = true,
    this.echo = false,
    this.sga = true,
    this.binary = false,
    this.encoding = 'utf-8',
  });

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'naws': naws,
      'ttype': ttype,
      'echo': echo,
      'sga': sga,
      'binary': binary,
      'encoding': encoding,
    };
  }

  factory TelnetConfig.fromJson(Map<String, dynamic> json) {
    return TelnetConfig(
      host: json['host'] ?? '',
      port: json['port'] ?? 23,
      naws: json['naws'] ?? true,
      ttype: json['ttype'] ?? true,
      echo: json['echo'] ?? false,
      sga: json['sga'] ?? true,
      binary: json['binary'] ?? false,
      encoding: json['encoding'] ?? 'utf-8',
    );
  }
}

/// 串口数据位
enum SerialDataBits {
  five,
  six,
  seven,
  eight,
}

/// 串口校验位
enum SerialParity {
  none,
  odd,
  even,
  mark,
  space,
}

/// 串口停止位
enum SerialStopBits {
  one,
  onePointFive,
  two,
}

/// 串口流控
enum SerialFlowControl {
  none,
  hardware,
  software,
}

/// Serial 配置
class SerialConfig {
  final String port;
  final int baudRate;
  final SerialDataBits dataBits;
  final SerialParity parity;
  final SerialStopBits stopBits;
  final SerialFlowControl flowControl;
  final bool dtr;
  final bool rts;

  const SerialConfig({
    required this.port,
    this.baudRate = 9600,
    this.dataBits = SerialDataBits.eight,
    this.parity = SerialParity.none,
    this.stopBits = SerialStopBits.one,
    this.flowControl = SerialFlowControl.none,
    this.dtr = true,
    this.rts = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'port': port,
      'baudRate': baudRate,
      'dataBits': dataBits.name,
      'parity': parity.name,
      'stopBits': stopBits.name,
      'flowControl': flowControl.name,
      'dtr': dtr,
      'rts': rts,
    };
  }

  factory SerialConfig.fromJson(Map<String, dynamic> json) {
    return SerialConfig(
      port: json['port'] ?? '',
      baudRate: json['baudRate'] ?? 9600,
      dataBits: SerialDataBits.values.firstWhere(
        (e) => e.name == json['dataBits'],
        orElse: () => SerialDataBits.eight,
      ),
      parity: SerialParity.values.firstWhere(
        (e) => e.name == json['parity'],
        orElse: () => SerialParity.none,
      ),
      stopBits: SerialStopBits.values.firstWhere(
        (e) => e.name == json['stopBits'],
        orElse: () => SerialStopBits.one,
      ),
      flowControl: SerialFlowControl.values.firstWhere(
        (e) => e.name == json['flowControl'],
        orElse: () => SerialFlowControl.none,
      ),
      dtr: json['dtr'] ?? true,
      rts: json['rts'] ?? true,
    );
  }

  String get description {
    return '$port $baudRate ${_dataBitsString()}${_parityString()}${_stopBitsString()}';
  }

  String _dataBitsString() {
    switch (dataBits) {
      case SerialDataBits.five: return '5';
      case SerialDataBits.six: return '6';
      case SerialDataBits.seven: return '7';
      case SerialDataBits.eight: return '8';
    }
  }

  String _parityString() {
    switch (parity) {
      case SerialParity.none: return 'N';
      case SerialParity.odd: return 'O';
      case SerialParity.even: return 'E';
      case SerialParity.mark: return 'M';
      case SerialParity.space: return 'S';
    }
  }

  String _stopBitsString() {
    switch (stopBits) {
      case SerialStopBits.one: return '1';
      case SerialStopBits.onePointFive: return '1.5';
      case SerialStopBits.two: return '2';
    }
  }
}

/// Raw TCP 配置
class RawTcpConfig {
  final String host;
  final int port;
  final String encoding;
  final String newline; // CR, LF, CRLF

  const RawTcpConfig({
    required this.host,
    required this.port,
    this.encoding = 'utf-8',
    this.newline = 'CRLF',
  });

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'encoding': encoding,
      'newline': newline,
    };
  }

  factory RawTcpConfig.fromJson(Map<String, dynamic> json) {
    return RawTcpConfig(
      host: json['host'] ?? '',
      port: json['port'] ?? 0,
      encoding: json['encoding'] ?? 'utf-8',
      newline: json['newline'] ?? 'CRLF',
    );
  }
}
