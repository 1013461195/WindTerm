import 'package:flutter/material.dart';

import 'protocol_config.dart';

class ProtocolSessionEditor extends StatefulWidget {
  const ProtocolSessionEditor({
    super.key,
    required this.serialPorts,
    required this.onTelnet,
    required this.onRawTcp,
    required this.onSerial,
  });

  final List<String> serialPorts;
  final ValueChanged<TelnetConfig> onTelnet;
  final ValueChanged<RawTcpConfig> onRawTcp;
  final ValueChanged<SerialConfig> onSerial;

  @override
  State<ProtocolSessionEditor> createState() => _ProtocolSessionEditorState();
}

class _ProtocolSessionEditorState extends State<ProtocolSessionEditor> {
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '23');
  final _serialPort = TextEditingController();
  final _baudRate = TextEditingController(text: '9600');
  ProtocolType _type = ProtocolType.telnet;
  SerialDataBits _dataBits = SerialDataBits.eight;
  SerialParity _parity = SerialParity.none;
  SerialStopBits _stopBits = SerialStopBits.one;
  SerialFlowControl _flowControl = SerialFlowControl.none;
  String _encoding = 'utf-8';
  String _newline = 'CRLF';

  @override
  void initState() {
    super.initState();
    if (widget.serialPorts.isNotEmpty) {
      _serialPort.text = widget.serialPorts.first;
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _serialPort.dispose();
    _baudRate.dispose();
    super.dispose();
  }

  void _changeType(ProtocolType? value) {
    if (value == null) return;
    setState(() {
      _type = value;
      if (value == ProtocolType.telnet) {
        _port.text = '23';
      } else if (value == ProtocolType.rawTcp && _port.text == '23') {
        _port.clear();
      }
    });
  }

  void _connect() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    switch (_type) {
      case ProtocolType.telnet:
        widget.onTelnet(
          TelnetConfig(
            host: _host.text.trim(),
            port: int.parse(_port.text),
            encoding: _encoding,
            newline: _newline,
          ),
        );
      case ProtocolType.rawTcp:
        widget.onRawTcp(
          RawTcpConfig(
            host: _host.text.trim(),
            port: int.parse(_port.text),
            encoding: _encoding,
            newline: _newline,
          ),
        );
      case ProtocolType.serial:
        widget.onSerial(
          SerialConfig(
            port: _serialPort.text.trim(),
            baudRate: int.parse(_baudRate.text),
            dataBits: _dataBits,
            parity: _parity,
            stopBits: _stopBits,
            flowControl: _flowControl,
            encoding: _encoding,
            newline: _newline,
          ),
        );
      case ProtocolType.ssh:
      case ProtocolType.localShell:
        throw StateError('Unsupported protocol editor type: $_type');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建协议连接'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ProtocolType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: '协议'),
                  items: const [
                    DropdownMenuItem(
                      value: ProtocolType.telnet,
                      child: Text('Telnet'),
                    ),
                    DropdownMenuItem(
                      value: ProtocolType.rawTcp,
                      child: Text('Raw TCP'),
                    ),
                    DropdownMenuItem(
                      value: ProtocolType.serial,
                      child: Text('Serial'),
                    ),
                  ],
                  onChanged: _changeType,
                ),
                const SizedBox(height: 16),
                if (_type == ProtocolType.serial)
                  ..._buildSerialFields()
                else
                  ..._buildNetworkFields(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _encoding,
                        decoration: const InputDecoration(labelText: '编码'),
                        items: const [
                          DropdownMenuItem(
                            value: 'utf-8',
                            child: Text('UTF-8'),
                          ),
                          DropdownMenuItem(value: 'gbk', child: Text('GBK')),
                          DropdownMenuItem(
                            value: 'windows-1252',
                            child: Text('Windows-1252'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _encoding = value ?? _encoding),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _newline,
                        decoration: const InputDecoration(labelText: '换行'),
                        items: const [
                          DropdownMenuItem(value: 'CRLF', child: Text('CRLF')),
                          DropdownMenuItem(value: 'LF', child: Text('LF')),
                          DropdownMenuItem(value: 'CR', child: Text('CR')),
                        ],
                        onChanged: (value) =>
                            setState(() => _newline = value ?? _newline),
                      ),
                    ),
                  ],
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
        FilledButton(onPressed: _connect, child: const Text('连接')),
      ],
    );
  }

  List<Widget> _buildNetworkFields() {
    return [
      TextFormField(
        controller: _host,
        decoration: const InputDecoration(labelText: '主机'),
        validator: (value) =>
            value == null || value.trim().isEmpty ? '请输入主机地址' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _port,
        decoration: const InputDecoration(labelText: '端口'),
        keyboardType: TextInputType.number,
        validator: (value) {
          final port = int.tryParse(value ?? '');
          return port == null || port < 1 || port > 65535 ? '请输入有效端口' : null;
        },
      ),
    ];
  }

  List<Widget> _buildSerialFields() {
    return [
      if (widget.serialPorts.isNotEmpty)
        DropdownButtonFormField<String>(
          initialValue: _serialPort.text,
          decoration: const InputDecoration(labelText: '串口'),
          items: widget.serialPorts
              .map((port) => DropdownMenuItem(value: port, child: Text(port)))
              .toList(),
          onChanged: (value) => _serialPort.text = value ?? '',
        )
      else
        TextFormField(
          controller: _serialPort,
          decoration: const InputDecoration(
            labelText: '串口',
            hintText: '/dev/tty.usbserial 或 COM3',
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? '请输入串口名称' : null,
        ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _baudRate,
        decoration: const InputDecoration(labelText: '波特率'),
        keyboardType: TextInputType.number,
        validator: (value) {
          final baudRate = int.tryParse(value ?? '');
          return baudRate == null || baudRate <= 0 ? '请输入有效波特率' : null;
        },
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<SerialDataBits>(
              initialValue: _dataBits,
              decoration: const InputDecoration(labelText: '数据位'),
              items: SerialDataBits.values
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _dataBits = value ?? _dataBits),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<SerialParity>(
              initialValue: _parity,
              decoration: const InputDecoration(labelText: '校验'),
              items: SerialParity.values
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _parity = value ?? _parity),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<SerialStopBits>(
              initialValue: _stopBits,
              decoration: const InputDecoration(labelText: '停止位'),
              items: SerialStopBits.values
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _stopBits = value ?? _stopBits),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<SerialFlowControl>(
              initialValue: _flowControl,
              decoration: const InputDecoration(labelText: '流控'),
              items: SerialFlowControl.values
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _flowControl = value ?? _flowControl),
            ),
          ),
        ],
      ),
    ];
  }
}
