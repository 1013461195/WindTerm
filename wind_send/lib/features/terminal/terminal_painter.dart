import 'package:flutter/material.dart';
import '../../core_bridge/rust_core.dart';

/// 终端颜色映射
Color _mapTerminalColor(TerminalColor color, {bool isBackground = false}) {
  switch (color) {
    case TerminalColor.defaultColor:
      return isBackground ? const Color(0xff05070a) : const Color(0xffd7e0ee);
    case TerminalColor.black:
      return const Color(0xff000000);
    case TerminalColor.red:
      return const Color(0xffcc0000);
    case TerminalColor.green:
      return const Color(0xff4e9a06);
    case TerminalColor.yellow:
      return const Color(0xffc4a000);
    case TerminalColor.blue:
      return const Color(0xff3465a4);
    case TerminalColor.magenta:
      return const Color(0xff75507b);
    case TerminalColor.cyan:
      return const Color(0xff06989a);
    case TerminalColor.white:
      return const Color(0xffd3d7cf);
    case TerminalColor.brightBlack:
      return const Color(0xff555753);
    case TerminalColor.brightRed:
      return const Color(0xffef2929);
    case TerminalColor.brightGreen:
      return const Color(0xff8ae234);
    case TerminalColor.brightYellow:
      return const Color(0xfffce94f);
    case TerminalColor.brightBlue:
      return const Color(0xff729fcf);
    case TerminalColor.brightMagenta:
      return const Color(0xffad7fa8);
    case TerminalColor.brightCyan:
      return const Color(0xff34e2e2);
    case TerminalColor.brightWhite:
      return const Color(0xffeeeeec);
    default:
      return isBackground ? const Color(0xff05070a) : const Color(0xffd7e0ee);
  }
}

/// 终端视图组件
class TerminalView extends StatelessWidget {
  final TerminalSnapshot? snapshot;

  const TerminalView({super.key, this.snapshot});

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
          painter: TerminalPainter(snapshot),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// 终端绘制器
class TerminalPainter extends CustomPainter {
  final TerminalSnapshot? snapshot;

  TerminalPainter(this.snapshot);

  static const double _cellWidth = 8.0;
  static const double _cellHeight = 16.0;
  static const double _leftPadding = 4.0;
  static const double _topPadding = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制背景
    final Paint background = Paint()..color = const Color(0xff05070a);
    canvas.drawRect(Offset.zero & size, background);

    if (snapshot == null) {
      _drawNoSession(canvas, size);
      return;
    }

    final snap = snapshot!;
    final int visibleRows = ((size.height - _topPadding * 2) / _cellHeight).floor();
    final int visibleCols = ((size.width - _leftPadding * 2) / _cellWidth).floor();
    final int startRow = 0;

    // 绘制每个单元格
    for (int row = startRow; row < snap.rows && row < startRow + visibleRows; row++) {
      if (row >= snap.lines.length) break;
      final line = snap.lines[row];

      for (int col = 0; col < snap.cols && col < visibleCols; col++) {
        if (col >= line.cells.length) break;
        final cell = line.cells[col];

        final double x = _leftPadding + col * _cellWidth;
        final double y = _topPadding + (row - startRow) * _cellHeight;

        // 绘制背景色
        final bgColor = _mapTerminalColor(cell.attr.bg, isBackground: true);
        if (bgColor != const Color(0xff05070a)) {
          final bgPaint = Paint()..color = bgColor;
          canvas.drawRect(
            Rect.fromLTWH(x, y, _cellWidth, _cellHeight),
            bgPaint,
          );
        }

        // 绘制字符
        if (cell.ch != ' ') {
          final fgColor = _mapTerminalColor(cell.attr.fg);
          final textStyle = TextStyle(
            color: fgColor,
            fontFamily: 'Menlo',
            fontFamilyFallback: const ['Consolas', 'Courier New', 'monospace'],
            fontSize: 13,
            height: 1.0,
            letterSpacing: 0,
            fontWeight: cell.attr.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: cell.attr.italic ? FontStyle.italic : FontStyle.normal,
            decoration: cell.attr.underline ? TextDecoration.underline : TextDecoration.none,
          );

          final textPainter = TextPainter(
            text: TextSpan(text: cell.ch, style: textStyle),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(x, y));
        }
      }
    }

    // 绘制光标
    if (snap.cursorVisible &&
        snap.cursorRow >= startRow &&
        snap.cursorRow < startRow + visibleRows &&
        snap.cursorCol < visibleCols) {
      final double cursorX = _leftPadding + snap.cursorCol * _cellWidth;
      final double cursorY = _topPadding + (snap.cursorRow - startRow) * _cellHeight;

      final cursorPaint = Paint()
        ..color = const Color(0xffd7e0ee).withAlpha(180)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawRect(
        Rect.fromLTWH(cursorX, cursorY, _cellWidth, _cellHeight),
        cursorPaint,
      );
    }
  }

  void _drawNoSession(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '未连接\n点击 "新建连接" 开始',
        style: TextStyle(
          color: Color(0xff4a5568),
          fontSize: 16,
          height: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout(maxWidth: size.width);
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(TerminalPainter oldDelegate) {
    return oldDelegate.snapshot != snapshot;
  }
}
