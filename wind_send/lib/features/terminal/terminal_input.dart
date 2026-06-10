import 'package:flutter/services.dart';
import 'dart:typed_data';

/// 终端输入处理器
class TerminalInputHandler {
  final void Function(Uint8List data) onInput;

  TerminalInputHandler({required this.onInput});

  /// 处理键盘事件
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }

    final key = event.logicalKey;
    final character = event.character;

    // 处理控制键
    if (event.physicalKey == PhysicalKeyboardKey.keyC &&
        HardwareKeyboard.instance.isControlPressed) {
      onInput(Uint8List.fromList([0x03])); // Ctrl+C
      return true;
    }

    if (event.physicalKey == PhysicalKeyboardKey.keyD &&
        HardwareKeyboard.instance.isControlPressed) {
      onInput(Uint8List.fromList([0x04])); // Ctrl+D
      return true;
    }

    if (event.physicalKey == PhysicalKeyboardKey.keyZ &&
        HardwareKeyboard.instance.isControlPressed) {
      onInput(Uint8List.fromList([0x1a])); // Ctrl+Z
      return true;
    }

    if (event.physicalKey == PhysicalKeyboardKey.keyL &&
        HardwareKeyboard.instance.isControlPressed) {
      onInput(Uint8List.fromList([0x0c])); // Ctrl+L
      return true;
    }

    // 处理特殊键
    if (key == LogicalKeyboardKey.enter) {
      onInput(Uint8List.fromList([0x0d])); // CR
      return true;
    }

    if (key == LogicalKeyboardKey.backspace) {
      onInput(Uint8List.fromList([0x7f])); // DEL
      return true;
    }

    if (key == LogicalKeyboardKey.tab) {
      onInput(Uint8List.fromList([0x09])); // TAB
      return true;
    }

    if (key == LogicalKeyboardKey.escape) {
      onInput(Uint8List.fromList([0x1b])); // ESC
      return true;
    }

    // 方向键
    if (key == LogicalKeyboardKey.arrowUp) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x41])); // ESC [ A
      return true;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x42])); // ESC [ B
      return true;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x43])); // ESC [ C
      return true;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x44])); // ESC [ D
      return true;
    }

    // Home/End
    if (key == LogicalKeyboardKey.home) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x48])); // ESC [ H
      return true;
    }

    if (key == LogicalKeyboardKey.end) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x46])); // ESC [ F
      return true;
    }

    // Page Up/Down
    if (key == LogicalKeyboardKey.pageUp) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x35, 0x7e])); // ESC [ 5 ~
      return true;
    }

    if (key == LogicalKeyboardKey.pageDown) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x36, 0x7e])); // ESC [ 6 ~
      return true;
    }

    // Delete
    if (key == LogicalKeyboardKey.delete) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x33, 0x7e])); // ESC [ 3 ~
      return true;
    }

    // F1-F12
    if (key == LogicalKeyboardKey.f1) {
      onInput(Uint8List.fromList([0x1b, 0x4f, 0x50])); // ESC O P
      return true;
    }

    if (key == LogicalKeyboardKey.f2) {
      onInput(Uint8List.fromList([0x1b, 0x4f, 0x51])); // ESC O Q
      return true;
    }

    if (key == LogicalKeyboardKey.f3) {
      onInput(Uint8List.fromList([0x1b, 0x4f, 0x52])); // ESC O R
      return true;
    }

    if (key == LogicalKeyboardKey.f4) {
      onInput(Uint8List.fromList([0x1b, 0x4f, 0x53])); // ESC O S
      return true;
    }

    if (key == LogicalKeyboardKey.f5) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x31, 0x35, 0x7e])); // ESC [ 1 5 ~
      return true;
    }

    if (key == LogicalKeyboardKey.f6) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x31, 0x37, 0x7e])); // ESC [ 1 7 ~
      return true;
    }

    if (key == LogicalKeyboardKey.f7) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x31, 0x38, 0x7e])); // ESC [ 1 8 ~
      return true;
    }

    if (key == LogicalKeyboardKey.f8) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x31, 0x39, 0x7e])); // ESC [ 1 9 ~
      return true;
    }

    if (key == LogicalKeyboardKey.f9) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x32, 0x30, 0x7e])); // ESC [ 2 0 ~
      return true;
    }

    if (key == LogicalKeyboardKey.f10) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x32, 0x31, 0x7e])); // ESC [ 2 1 ~
      return true;
    }

    if (key == LogicalKeyboardKey.f11) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x32, 0x33, 0x7e])); // ESC [ 2 3 ~
      return true;
    }

    if (key == LogicalKeyboardKey.f12) {
      onInput(Uint8List.fromList([0x1b, 0x5b, 0x32, 0x34, 0x7e])); // ESC [ 2 4 ~
      return true;
    }

    // 处理普通字符输入
    if (character != null && character.isNotEmpty) {
      final bytes = character.codeUnits;
      onInput(Uint8List.fromList(bytes));
      return true;
    }

    return false;
  }
}
