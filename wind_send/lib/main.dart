import 'dart:async';

import 'package:flutter/material.dart';

import 'core_bridge/rust_core.dart';

void main() {
  runApp(const WindSendApp());
}

class WindSendApp extends StatelessWidget {
  const WindSendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WindSend',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2f6fed),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff111318),
        useMaterial3: true,
      ),
      home: const ShellWorkspace(),
    );
  }
}

class ShellWorkspace extends StatefulWidget {
  const ShellWorkspace({super.key});

  @override
  State<ShellWorkspace> createState() => _ShellWorkspaceState();
}

class _ShellWorkspaceState extends State<ShellWorkspace> {
  final RustCore _core = RustCore.load();
  final List<String> _lines = <String>[];
  Timer? _timer;
  int? _sessionId;

  @override
  void initState() {
    super.initState();
    _startMockSession();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startMockSession() {
    final int sessionId = _core.openMockSession(cols: 120, rows: 36);
    _sessionId = sessionId;
    _lines
      ..clear()
      ..add('WindSend phase 0')
      ..add('Core: ${_core.version}')
      ..add('Session #$sessionId opened')
      ..add('');

    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final int? id = _sessionId;
      if (id == null) {
        return;
      }

      final CoreEvent? event = _core.pollEvent(id);
      if (event == null) {
        return;
      }

      setState(() {
        _lines.add(event.line);
        if (_lines.length > 200) {
          _lines.removeRange(0, _lines.length - 200);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: <Widget>[
          const _SessionRail(),
          Expanded(
            child: Column(
              children: <Widget>[
                const _TopBar(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: TerminalSurface(lines: _lines),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRail extends StatelessWidget {
  const _SessionRail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: Color(0xff191d25),
        border: Border(right: BorderSide(color: Color(0xff2a303b))),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Text(
                'WindSend',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            _NavItem(
              icon: Icons.terminal_rounded,
              label: 'Phase 0 mock core',
              selected: true,
            ),
            const Divider(color: Color(0xff2a303b), height: 28),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'Milestone',
                style: TextStyle(color: Color(0xff8e98a8), fontSize: 12),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Text(
                'Flutter UI -> Rust FFI -> mock terminal events',
                style: TextStyle(color: Color(0xffc4cad4), height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? const Color(0xff263247) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: const Color(0xff8fb6ff)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          const Icon(Icons.memory_rounded, size: 18, color: Color(0xff8fb6ff)),
          const SizedBox(width: 10),
          const Text(
            'Rust core bridge',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xff3a4657)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'M0',
              style: TextStyle(color: Color(0xffaeb8c8), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class TerminalSurface extends StatelessWidget {
  const TerminalSurface({super.key, required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff05070a),
        border: Border.all(color: const Color(0xff2a303b)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          painter: TerminalPainter(lines),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class TerminalPainter extends CustomPainter {
  TerminalPainter(this.lines);

  final List<String> lines;

  static const double _lineHeight = 20;
  static const double _leftPadding = 14;
  static const double _topPadding = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint background = Paint()..color = const Color(0xff05070a);
    canvas.drawRect(Offset.zero & size, background);

    final int visibleRows = ((size.height - _topPadding * 2) / _lineHeight)
        .floor()
        .clamp(0, lines.length);
    final int firstLine = (lines.length - visibleRows).clamp(0, lines.length);
    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );

    for (int i = firstLine; i < lines.length; i++) {
      final double y = _topPadding + (i - firstLine) * _lineHeight;
      textPainter.text = TextSpan(
        text: lines[i],
        style: const TextStyle(
          color: Color(0xffd7e0ee),
          fontFamily: 'Menlo',
          fontFamilyFallback: <String>['Consolas', 'monospace'],
          fontSize: 13,
          height: 1.25,
          letterSpacing: 0,
        ),
      );
      textPainter.layout(maxWidth: size.width - _leftPadding * 2);
      textPainter.paint(canvas, Offset(_leftPadding, y));
    }
  }

  @override
  bool shouldRepaint(TerminalPainter oldDelegate) {
    return true;
  }
}
