import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../../core_bridge/rust_core.dart';
import '../settings/terminal_settings.dart';
import 'terminal_search.dart';

// ── 256 色调色板 ──

/// 256 色索引转 Color
Color _indexedToColor(int index) {
  if (index < 16) {
    // 标准 + 高亮色
    const colors = [
      0xff000000,
      0xffcc0000,
      0xff4e9a06,
      0xffc4a000,
      0xff3465a4,
      0xff75507b,
      0xff06989a,
      0xffd3d7cf,
      0xff555753,
      0xffef2929,
      0xff8ae234,
      0xfffce94f,
      0xff729fcf,
      0xffad7fa8,
      0xff34e2e2,
      0xffeeeeec,
    ];
    return Color(colors[index]);
  }
  if (index < 232) {
    // 6x6x6 RGB 色块
    final i = index - 16;
    final r = (i ~/ 36) * 51;
    final g = ((i % 36) ~/ 6) * 51;
    final b = (i % 6) * 51;
    return Color.fromARGB(255, r, g, b);
  }
  // 灰度渐变
  final gray = 8 + (index - 232) * 10;
  return Color.fromARGB(255, gray, gray, gray);
}

/// 终端颜色映射（支持 RGB / Indexed / 标准色）
Color _resolveColor(
  TerminalColor color, {
  RgbColor? rgb,
  IndexedColor? indexed,
  bool isBackground = false,
}) {
  switch (color) {
    case TerminalColor.rgb:
      if (rgb != null) return Color.fromARGB(255, rgb.r, rgb.g, rgb.b);
      return isBackground ? const Color(0xff05070a) : const Color(0xffd7e0ee);
    case TerminalColor.indexed:
      if (indexed != null) return _indexedToColor(indexed.index);
      return isBackground ? const Color(0xff05070a) : const Color(0xffd7e0ee);
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
  }
}

/// 选区位置
class SelectionPosition {
  final int row;
  final int col;
  const SelectionPosition(this.row, this.col);
}

/// 终端视图组件
class TerminalView extends StatefulWidget {
  final TerminalSnapshot? snapshot;
  final void Function(String text)? onSelectionChanged;
  final void Function(
    TerminalMouseEventType eventType,
    TerminalMouseButton button,
    int col,
    int row,
    bool shift,
    bool meta,
    bool ctrl,
  )?
  onMouseEvent;
  final TerminalSettings settings;
  final SearchResult? searchResult;

  const TerminalView({
    super.key,
    this.snapshot,
    this.onSelectionChanged,
    this.onMouseEvent,
    this.settings = const TerminalSettings(),
    this.searchResult,
  });

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  int _scrollOffset = 0;
  final ScrollController _scrollController = ScrollController();
  SelectionPosition? _selectionStart;
  SelectionPosition? _selectionEnd;
  bool _isSelecting = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && widget.snapshot != null) {
      final snap = widget.snapshot!;
      final totalLines = snap.scrollback.length + snap.lines.length;
      final visibleRows = snap.rows;
      final maxScroll = (totalLines - visibleRows).clamp(0, totalLines);

      setState(() {
        _scrollOffset = (_scrollOffset - (event.scrollDelta.dy / 16).round())
            .clamp(0, maxScroll);
      });
    }
  }

  SelectionPosition? _hitTest(Offset position) {
    if (widget.snapshot == null) return null;
    const cellWidth = 8.0;
    const cellHeight = 16.0;
    const leftPadding = 4.0;
    const topPadding = 4.0;

    final col = ((position.dx - leftPadding) / cellWidth).floor();
    final row = ((position.dy - topPadding) / cellHeight).floor();

    if (col < 0 || row < 0) return null;
    if (col >= widget.snapshot!.cols) return null;

    final allLines = [
      ...widget.snapshot!.scrollback,
      ...widget.snapshot!.lines,
    ];
    final totalLines = allLines.length;
    final visibleRows = widget.snapshot!.rows;
    final startRow = (totalLines - visibleRows - _scrollOffset).clamp(
      0,
      totalLines,
    );
    final actualRow = startRow + row;

    if (actualRow >= totalLines) return null;

    return SelectionPosition(actualRow, col);
  }

  void _onPointerDown(PointerDownEvent event) {
    _selectionStart = _hitTest(event.localPosition);
    _selectionEnd = _selectionStart;
    _isSelecting = true;

    // 发送鼠标按下事件
    _sendMouseEvent(event.localPosition, TerminalMouseEventType.press, event);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isSelecting) {
      setState(() {
        _selectionEnd = _hitTest(event.localPosition);
      });
    }

    // 发送鼠标移动事件
    _sendMouseEvent(event.localPosition, TerminalMouseEventType.motion, event);
  }

  void _onPointerUp(PointerUpEvent event) {
    _isSelecting = false;
    _notifySelection();

    // 发送鼠标释放事件
    _sendMouseEvent(event.localPosition, TerminalMouseEventType.release, event);
  }

  void _sendMouseEvent(
    Offset position,
    TerminalMouseEventType eventType,
    PointerEvent event,
  ) {
    if (widget.onMouseEvent == null || widget.snapshot == null) return;

    const cellWidth = 8.0;
    const cellHeight = 16.0;
    const leftPadding = 4.0;
    const topPadding = 4.0;

    final col = ((position.dx - leftPadding) / cellWidth).floor();
    final row = ((position.dy - topPadding) / cellHeight).floor();

    if (col < 0 ||
        row < 0 ||
        col >= widget.snapshot!.cols ||
        row >= widget.snapshot!.rows) {
      return;
    }

    // 确定鼠标按键
    TerminalMouseButton button;
    if (event is PointerDownEvent || event is PointerUpEvent) {
      final pointerEvent = event as PointerDownEvent;
      switch (pointerEvent.buttons) {
        case kPrimaryMouseButton:
          button = TerminalMouseButton.left;
          break;
        case kMiddleMouseButton:
          button = TerminalMouseButton.middle;
          break;
        case kSecondaryMouseButton:
          button = TerminalMouseButton.right;
          break;
        default:
          button = TerminalMouseButton.none;
      }
    } else {
      button = TerminalMouseButton.none;
    }

    final shift = HardwareKeyboard.instance.isShiftPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final ctrl = HardwareKeyboard.instance.isControlPressed;

    widget.onMouseEvent!(eventType, button, col, row, shift, meta, ctrl);
  }

  void _notifySelection() {
    if (_selectionStart == null ||
        _selectionEnd == null ||
        widget.snapshot == null) {
      return;
    }

    final allLines = [
      ...widget.snapshot!.scrollback,
      ...widget.snapshot!.lines,
    ];
    final start = _selectionStart!;
    final end = _selectionEnd!;

    // 确保 start 在 end 之前
    final bool startIsBefore =
        start.row < end.row || (start.row == end.row && start.col <= end.col);
    final actualStart = startIsBefore ? start : end;
    final actualEnd = startIsBefore ? end : start;

    final buffer = StringBuffer();
    for (
      int row = actualStart.row;
      row <= actualEnd.row && row < allLines.length;
      row++
    ) {
      final line = allLines[row];
      final startCol = row == actualStart.row ? actualStart.col : 0;
      final endCol = row == actualEnd.row
          ? actualEnd.col
          : line.cells.length - 1;

      for (
        int col = startCol;
        col <= endCol && col < line.cells.length;
        col++
      ) {
        final cell = line.cells[col];
        if (cell.wide != 2) {
          buffer.write(cell.ch == ' ' ? ' ' : cell.ch);
        }
      }

      if (row < actualEnd.row) {
        buffer.write('\n');
      }
    }

    final text = buffer.toString();
    if (text.isNotEmpty) {
      widget.onSelectionChanged?.call(text);
    }
  }

  /// 获取当前选中的文本
  String? getSelectedText() {
    if (_selectionStart == null ||
        _selectionEnd == null ||
        widget.snapshot == null) {
      return null;
    }

    final allLines = [
      ...widget.snapshot!.scrollback,
      ...widget.snapshot!.lines,
    ];
    final start = _selectionStart!;
    final end = _selectionEnd!;

    final bool startIsBefore =
        start.row < end.row || (start.row == end.row && start.col <= end.col);
    final actualStart = startIsBefore ? start : end;
    final actualEnd = startIsBefore ? end : start;

    final buffer = StringBuffer();
    for (
      int row = actualStart.row;
      row <= actualEnd.row && row < allLines.length;
      row++
    ) {
      final line = allLines[row];
      final startCol = row == actualStart.row ? actualStart.col : 0;
      final endCol = row == actualEnd.row
          ? actualEnd.col
          : line.cells.length - 1;

      for (
        int col = startCol;
        col <= endCol && col < line.cells.length;
        col++
      ) {
        final cell = line.cells[col];
        if (cell.wide != 2) {
          buffer.write(cell.ch == ' ' ? ' ' : cell.ch);
        }
      }

      if (row < actualEnd.row) {
        buffer.write('\n');
      }
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        onTapDown: (details) => _onPointerDown(
          PointerDownEvent(
            position: details.localPosition,
            kind: PointerDeviceKind.mouse,
          ),
        ),
        onPanStart: (details) => _onPointerDown(
          PointerDownEvent(
            position: details.localPosition,
            kind: PointerDeviceKind.mouse,
          ),
        ),
        onPanUpdate: (details) => _onPointerMove(
          PointerMoveEvent(
            position: details.localPosition,
            kind: PointerDeviceKind.mouse,
          ),
        ),
        onPanEnd: (details) => _onPointerUp(
          PointerUpEvent(position: Offset.zero, kind: PointerDeviceKind.mouse),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xff05070a),
            border: Border.all(color: const Color(0xff2a303b)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CustomPaint(
              painter: TerminalPainter(
                widget.snapshot,
                _scrollOffset,
                _selectionStart,
                _selectionEnd,
                widget.settings,
                widget.searchResult,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

/// 终端绘制器
class TerminalPainter extends CustomPainter {
  final TerminalSnapshot? snapshot;
  final int scrollOffset;
  final SelectionPosition? selectionStart;
  final SelectionPosition? selectionEnd;
  final TerminalSettings settings;
  final SearchResult? searchResult;

  TerminalPainter(
    this.snapshot, [
    this.scrollOffset = 0,
    this.selectionStart,
    this.selectionEnd,
    this.settings = const TerminalSettings(),
    this.searchResult,
  ]);

  double get _cellWidth => settings.cellWidth;
  double get _cellHeight => settings.cellHeight;
  double get _leftPadding => settings.leftPadding;
  double get _topPadding => settings.topPadding;
  String get _fontFamily => settings.fontFamily;
  List<String> get _fontFallback => settings.fontFamilyFallback;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint background = Paint()..color = settings.backgroundColor;
    canvas.drawRect(Offset.zero & size, background);

    if (snapshot == null) {
      _drawNoSession(canvas, size);
      return;
    }

    final snap = snapshot!;
    final int visibleRows = ((size.height - _topPadding * 2) / _cellHeight)
        .floor();
    final int visibleCols = ((size.width - _leftPadding * 2) / _cellWidth)
        .floor();

    // 合并 scrollback 和当前行
    final allLines = <TerminalLine>[...snap.scrollback, ...snap.lines];

    // 计算起始行（考虑滚动偏移）
    final int totalLines = allLines.length;
    final int startRow = (totalLines - visibleRows - scrollOffset).clamp(
      0,
      totalLines,
    );

    // 批量绘制背景色和字符
    _drawCells(
      canvas,
      size,
      allLines,
      startRow,
      visibleRows,
      visibleCols,
      snap,
    );

    // 绘制选区高亮
    if (selectionStart != null && selectionEnd != null) {
      _drawSelection(canvas, allLines, startRow, visibleRows, visibleCols);
    }

    // 绘制搜索结果高亮
    if (searchResult != null) {
      _drawSearchResult(canvas, allLines, startRow, visibleRows, visibleCols);
    }

    // 绘制光标（仅在未滚动时）
    if (scrollOffset == 0 && snap.cursorVisible) {
      _drawCursor(canvas, snap, visibleRows, visibleCols, startRow);
    }

    // 绘制滚动指示器
    if (scrollOffset > 0) {
      _drawScrollIndicator(canvas, size, snap.scrollback.length);
    }
  }

  /// 批量绘制单元格（背景色 + 字符）
  void _drawCells(
    Canvas canvas,
    Size size,
    List<TerminalLine> allLines,
    int startRow,
    int visibleRows,
    int visibleCols,
    TerminalSnapshot snap,
  ) {
    for (
      int row = 0;
      row < visibleRows && (startRow + row) < allLines.length;
      row++
    ) {
      final line = allLines[startRow + row];
      final double y = _topPadding + row * _cellHeight;

      // 跟踪连续相同属性的字符，合并为一个 TextSpan 绘制
      _drawLine(canvas, line, y, visibleCols);
    }
  }

  /// 绘制单行（合并连续相同属性的字符为 TextSpan）
  void _drawLine(Canvas canvas, TerminalLine line, double y, int visibleCols) {
    int runStart = 0;
    CellAttr? runAttr;
    final buffer = StringBuffer();

    for (int col = 0; col < line.cells.length && col < visibleCols; col++) {
      final cell = line.cells[col];

      // 跳过宽字符占位符（wide == 2）
      if (cell.wide == 2) continue;

      final attr = cell.attr;

      runAttr ??= attr;

      // 属性变化或到达末尾时，绘制当前 run
      if (!_attrsEqual(attr, runAttr) ||
          col == visibleCols - 1 ||
          col == line.cells.length - 1) {
        if (buffer.isNotEmpty) {
          _drawTextRun(canvas, buffer.toString(), runStart, y, runAttr);
          buffer.clear();
        }
        runStart = col;
        runAttr = attr;
      }

      // 处理 inverse
      final ch = cell.ch == ' ' ? '' : cell.ch;
      buffer.write(ch);
    }

    // 绘制最后一段
    if (buffer.isNotEmpty && runAttr != null) {
      _drawTextRun(canvas, buffer.toString(), runStart, y, runAttr);
    }
  }

  /// 比较两个 CellAttr 是否相同
  bool _attrsEqual(CellAttr a, CellAttr b) {
    return a.fg == b.fg &&
        a.bg == b.bg &&
        a.bold == b.bold &&
        a.italic == b.italic &&
        a.underline == b.underline &&
        a.inverse == b.inverse &&
        a.fgRgb == b.fgRgb &&
        a.bgRgb == b.bgRgb &&
        a.fgIndexed == b.fgIndexed &&
        a.bgIndexed == b.bgIndexed;
  }

  /// 绘制一段文字 run
  void _drawTextRun(
    Canvas canvas,
    String text,
    int col,
    double y,
    CellAttr attr,
  ) {
    final double x = _leftPadding + col * _cellWidth;

    // 处理 inverse
    TerminalColor effectiveFg = attr.fg;
    TerminalColor effectiveBg = attr.bg;
    RgbColor? fgRgb = attr.fgRgb;
    RgbColor? bgRgb = attr.bgRgb;
    IndexedColor? fgIndexed = attr.fgIndexed;
    IndexedColor? bgIndexed = attr.bgIndexed;

    if (attr.inverse) {
      effectiveFg = attr.bg;
      effectiveBg = attr.fg;
      fgRgb = attr.bgRgb;
      bgRgb = attr.fgRgb;
      fgIndexed = attr.bgIndexed;
      bgIndexed = attr.fgIndexed;
    }

    // 绘制背景色
    final bgColor = _resolveColor(
      effectiveBg,
      rgb: bgRgb,
      indexed: bgIndexed,
      isBackground: true,
    );
    if (bgColor != const Color(0xff05070a)) {
      final bgPaint = Paint()..color = bgColor;
      canvas.drawRect(
        Rect.fromLTWH(x, y, text.length * _cellWidth, _cellHeight),
        bgPaint,
      );
    }

    // 绘制字符
    if (text.trimRight().isNotEmpty) {
      final fgColor = _resolveColor(
        effectiveFg,
        rgb: fgRgb,
        indexed: fgIndexed,
      );
      final textStyle = TextStyle(
        color: fgColor,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
        fontSize: settings.fontSize,
        height: settings.lineHeight,
        letterSpacing: 0,
        fontWeight: attr.bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: attr.italic ? FontStyle.italic : FontStyle.normal,
        decoration: attr.underline
            ? TextDecoration.underline
            : TextDecoration.none,
      );

      final textPainter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x, y));
    }
  }

  /// 绘制光标
  void _drawCursor(
    Canvas canvas,
    TerminalSnapshot snap,
    int visibleRows,
    int visibleCols,
    int startRow,
  ) {
    if (snap.cursorRow < startRow || snap.cursorRow >= startRow + visibleRows) {
      return;
    }
    if (snap.cursorCol >= visibleCols) {
      return;
    }

    final double cursorX = _leftPadding + snap.cursorCol * _cellWidth;
    final double cursorY =
        _topPadding + (snap.cursorRow - startRow) * _cellHeight;

    // 使用块状光标或框光标
    final cursorPaint = Paint()
      ..color = settings.cursorColor.withAlpha(180)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRect(
      Rect.fromLTWH(cursorX, cursorY, _cellWidth, _cellHeight),
      cursorPaint,
    );
  }

  /// 绘制滚动指示器
  void _drawScrollIndicator(Canvas canvas, Size size, int scrollbackLines) {
    final indicatorPaint = Paint()
      ..color = const Color(0xff4a5568).withAlpha(120)
      ..style = PaintingStyle.fill;

    final barHeight = 40.0;
    final barY = size.height - barHeight - 8;
    final barX = size.width - 8;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barX, barY, 4, barHeight),
        const Radius.circular(2),
      ),
      indicatorPaint,
    );

    // 文字提示
    final textPainter = TextPainter(
      text: TextSpan(
        text: '↑ $scrollbackLines lines',
        style: const TextStyle(color: Color(0xff4a5568), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(barX - textPainter.width - 8, barY));
  }

  /// 绘制搜索结果高亮
  void _drawSearchResult(
    Canvas canvas,
    List<TerminalLine> allLines,
    int startRow,
    int visibleRows,
    int visibleCols,
  ) {
    if (searchResult == null) return;

    final result = searchResult!;
    final visibleRow = result.row - startRow;

    // 检查是否在可见范围内
    if (visibleRow < 0 || visibleRow >= visibleRows) return;
    if (result.col >= visibleCols) return;

    final searchPaint = Paint()
      ..color = const Color(0xfff4bf75).withAlpha(100)
      ..style = PaintingStyle.fill;

    final x = _leftPadding + result.col * _cellWidth;
    final y = _topPadding + visibleRow * _cellHeight;
    final width = result.length * _cellWidth;

    canvas.drawRect(Rect.fromLTWH(x, y, width, _cellHeight), searchPaint);
  }

  /// 绘制选区高亮
  void _drawSelection(
    Canvas canvas,
    List<TerminalLine> allLines,
    int startRow,
    int visibleRows,
    int visibleCols,
  ) {
    if (selectionStart == null || selectionEnd == null) return;

    final start = selectionStart!;
    final end = selectionEnd!;

    // 确保 start 在 end 之前
    final bool startIsBefore =
        start.row < end.row || (start.row == end.row && start.col <= end.col);
    final actualStart = startIsBefore ? start : end;
    final actualEnd = startIsBefore ? end : start;

    final selectionPaint = Paint()
      ..color = settings.selectionColor.withAlpha(80)
      ..style = PaintingStyle.fill;

    for (int row = actualStart.row; row <= actualEnd.row; row++) {
      // 检查行是否在可见范围内
      final visibleRow = row - startRow;
      if (visibleRow < 0 || visibleRow >= visibleRows) continue;

      final startCol = row == actualStart.row ? actualStart.col : 0;
      final endCol = row == actualEnd.row
          ? actualEnd.col
          : (allLines[row].cells.length - 1).clamp(0, visibleCols - 1);

      if (startCol >= visibleCols) continue;

      final x1 = _leftPadding + startCol * _cellWidth;
      final x2 = _leftPadding + (endCol + 1) * _cellWidth;
      final y = _topPadding + visibleRow * _cellHeight;

      canvas.drawRect(
        Rect.fromLTWH(x1, y, x2 - x1, _cellHeight),
        selectionPaint,
      );
    }
  }

  void _drawNoSession(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '未连接\n点击 "新建连接" 开始',
        style: TextStyle(color: Color(0xff4a5568), fontSize: 16, height: 1.5),
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
    return oldDelegate.snapshot != snapshot ||
        oldDelegate.scrollOffset != scrollOffset ||
        oldDelegate.selectionStart != selectionStart ||
        oldDelegate.selectionEnd != selectionEnd ||
        oldDelegate.settings != settings ||
        oldDelegate.searchResult != searchResult;
  }
}
