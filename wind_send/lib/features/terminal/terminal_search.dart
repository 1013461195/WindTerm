import 'package:flutter/material.dart';
import '../../core_bridge/rust_core.dart';

/// 搜索结果
class SearchResult {
  final int row;
  final int col;
  final int length;

  const SearchResult({
    required this.row,
    required this.col,
    required this.length,
  });
}

/// 终端搜索组件
class TerminalSearchBar extends StatefulWidget {
  final TerminalSnapshot? snapshot;
  final void Function(SearchResult? result) onSearchResult;
  final VoidCallback onClose;

  const TerminalSearchBar({
    super.key,
    this.snapshot,
    required this.onSearchResult,
    required this.onClose,
  });

  @override
  State<TerminalSearchBar> createState() => _TerminalSearchBarState();
}

class _TerminalSearchBarState extends State<TerminalSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<SearchResult> _results = [];
  int _currentResultIndex = -1;
  bool _caseSensitive = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _search() {
    final query = _controller.text;
    if (query.isEmpty || widget.snapshot == null) {
      setState(() {
        _results = [];
        _currentResultIndex = -1;
      });
      widget.onSearchResult(null);
      return;
    }

    final snapshot = widget.snapshot!;
    final allLines = [...snapshot.scrollback, ...snapshot.lines];
    final results = <SearchResult>[];

    for (int row = 0; row < allLines.length; row++) {
      final line = allLines[row];
      final lineText = _lineToText(line);

      int startIndex = 0;
      while (true) {
        final index = _caseSensitive
            ? lineText.indexOf(query, startIndex)
            : lineText.toLowerCase().indexOf(query.toLowerCase(), startIndex);

        if (index == -1) break;

        results.add(SearchResult(row: row, col: index, length: query.length));

        startIndex = index + 1;
      }
    }

    setState(() {
      _results = results;
      _currentResultIndex = results.isNotEmpty ? 0 : -1;
    });

    if (_currentResultIndex >= 0) {
      widget.onSearchResult(_results[_currentResultIndex]);
    } else {
      widget.onSearchResult(null);
    }
  }

  String _lineToText(TerminalLine line) {
    final buffer = StringBuffer();
    for (final cell in line.cells) {
      if (cell.wide != 2) {
        buffer.write(cell.ch == ' ' ? ' ' : cell.ch);
      }
    }
    return buffer.toString();
  }

  void _nextResult() {
    if (_results.isEmpty) return;
    setState(() {
      _currentResultIndex = (_currentResultIndex + 1) % _results.length;
    });
    widget.onSearchResult(_results[_currentResultIndex]);
  }

  void _previousResult() {
    if (_results.isEmpty) return;
    setState(() {
      _currentResultIndex =
          (_currentResultIndex - 1 + _results.length) % _results.length;
    });
    widget.onSearchResult(_results[_currentResultIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xff191d25),
        border: Border(bottom: BorderSide(color: Color(0xff2a303b))),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18, color: Color(0xff8e98a8)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(color: Color(0xffd7e0ee), fontSize: 14),
              decoration: const InputDecoration(
                hintText: '搜索...',
                hintStyle: TextStyle(color: Color(0xff4a5568)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) => _search(),
              onSubmitted: (_) => _nextResult(),
            ),
          ),
          if (_results.isNotEmpty) ...[
            Text(
              '${_currentResultIndex + 1}/${_results.length}',
              style: const TextStyle(color: Color(0xff8e98a8), fontSize: 12),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
              color: const Color(0xff8e98a8),
              onPressed: _previousResult,
              tooltip: '上一个',
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              color: const Color(0xff8e98a8),
              onPressed: _nextResult,
              tooltip: '下一个',
            ),
          ],
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              setState(() {
                _caseSensitive = !_caseSensitive;
              });
              _search();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: _caseSensitive
                    ? const Color(0xff2f6fed)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xff2a303b)),
              ),
              child: Text(
                'Aa',
                style: TextStyle(
                  color: _caseSensitive
                      ? Colors.white
                      : const Color(0xff8e98a8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: const Color(0xff8e98a8),
            onPressed: widget.onClose,
            tooltip: '关闭搜索',
          ),
        ],
      ),
    );
  }
}
