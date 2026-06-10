import 'package:flutter/services.dart';

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
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final alt =
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // ── Ctrl + 字母/符号 ──
    if (ctrl && !alt) {
      final data = _handleCtrlKey(event);
      if (data != null) {
        onInput(data);
        return true;
      }
    }

    // ── Alt + 字符 → 发送 ESC + 字符 ──
    if (alt && character != null && character.isNotEmpty) {
      final codeUnit = character.codeUnitAt(0);
      if (codeUnit >= 0x20 && codeUnit < 0x7f) {
        onInput(Uint8List.fromList([0x1b, codeUnit]));
        return true;
      }
    }

    // ── 功能键和特殊键 ──
    final specialData = _handleSpecialKey(key, shift);
    if (specialData != null) {
      onInput(specialData);
      return true;
    }

    // ── 普通字符输入 ──
    if (character != null && character.isNotEmpty) {
      final bytes = <int>[];
      for (final rune in character.runes) {
        if (rune < 0x80) {
          bytes.add(rune);
        } else if (rune < 0x800) {
          bytes.add(0xc0 | (rune >> 6));
          bytes.add(0x80 | (rune & 0x3f));
        } else if (rune < 0x10000) {
          bytes.add(0xe0 | (rune >> 12));
          bytes.add(0x80 | ((rune >> 6) & 0x3f));
          bytes.add(0x80 | (rune & 0x3f));
        } else {
          bytes.add(0xf0 | (rune >> 18));
          bytes.add(0x80 | ((rune >> 12) & 0x3f));
          bytes.add(0x80 | ((rune >> 6) & 0x3f));
          bytes.add(0x80 | (rune & 0x3f));
        }
      }
      onInput(Uint8List.fromList(bytes));
      return true;
    }

    return false;
  }

  /// 处理 Ctrl+字母/symbol 组合键
  Uint8List? _handleCtrlKey(KeyEvent event) {
    final physical = event.physicalKey;

    // Ctrl+字母 (A-Z) → ASCII 1-26
    if (physical == PhysicalKeyboardKey.keyA) return Uint8List.fromList([0x01]);
    if (physical == PhysicalKeyboardKey.keyB) return Uint8List.fromList([0x02]);
    if (physical == PhysicalKeyboardKey.keyC) return Uint8List.fromList([0x03]);
    if (physical == PhysicalKeyboardKey.keyD) return Uint8List.fromList([0x04]);
    if (physical == PhysicalKeyboardKey.keyE) return Uint8List.fromList([0x05]);
    if (physical == PhysicalKeyboardKey.keyF) return Uint8List.fromList([0x06]);
    if (physical == PhysicalKeyboardKey.keyG) return Uint8List.fromList([0x07]);
    if (physical == PhysicalKeyboardKey.keyH) return Uint8List.fromList([0x08]);
    if (physical == PhysicalKeyboardKey.keyI) return Uint8List.fromList([0x09]);
    if (physical == PhysicalKeyboardKey.keyJ) return Uint8List.fromList([0x0a]);
    if (physical == PhysicalKeyboardKey.keyK) return Uint8List.fromList([0x0b]);
    if (physical == PhysicalKeyboardKey.keyL) return Uint8List.fromList([0x0c]);
    if (physical == PhysicalKeyboardKey.keyM) return Uint8List.fromList([0x0d]);
    if (physical == PhysicalKeyboardKey.keyN) return Uint8List.fromList([0x0e]);
    if (physical == PhysicalKeyboardKey.keyO) return Uint8List.fromList([0x0f]);
    if (physical == PhysicalKeyboardKey.keyP) return Uint8List.fromList([0x10]);
    if (physical == PhysicalKeyboardKey.keyQ) return Uint8List.fromList([0x11]);
    if (physical == PhysicalKeyboardKey.keyR) return Uint8List.fromList([0x12]);
    if (physical == PhysicalKeyboardKey.keyS) return Uint8List.fromList([0x13]);
    if (physical == PhysicalKeyboardKey.keyT) return Uint8List.fromList([0x14]);
    if (physical == PhysicalKeyboardKey.keyU) return Uint8List.fromList([0x15]);
    if (physical == PhysicalKeyboardKey.keyV) return Uint8List.fromList([0x16]);
    if (physical == PhysicalKeyboardKey.keyW) return Uint8List.fromList([0x17]);
    if (physical == PhysicalKeyboardKey.keyX) return Uint8List.fromList([0x18]);
    if (physical == PhysicalKeyboardKey.keyY) return Uint8List.fromList([0x19]);
    if (physical == PhysicalKeyboardKey.keyZ) return Uint8List.fromList([0x1a]);

    // Ctrl+[ → ESC (0x1b)
    if (physical == PhysicalKeyboardKey.bracketLeft) {
      return Uint8List.fromList([0x1b]);
    }
    // Ctrl+\ → FS (0x1c)
    if (physical == PhysicalKeyboardKey.backslash) {
      return Uint8List.fromList([0x1c]);
    }
    // Ctrl+] → GS (0x1d)
    if (physical == PhysicalKeyboardKey.bracketRight) {
      return Uint8List.fromList([0x1d]);
    }

    return null;
  }

  /// 处理功能键和特殊键
  Uint8List? _handleSpecialKey(LogicalKeyboardKey key, bool shift) {
    // 回车
    if (key == LogicalKeyboardKey.enter) {
      return Uint8List.fromList([0x0d]);
    }
    // 退格
    if (key == LogicalKeyboardKey.backspace) {
      return Uint8List.fromList([0x7f]);
    }
    // Tab（Shift+Tab → 反向 Tab）
    if (key == LogicalKeyboardKey.tab) {
      if (shift) {
        return Uint8List.fromList([0x1b, 0x5b, 0x5a]); // ESC [ Z
      }
      return Uint8List.fromList([0x09]);
    }
    // ESC
    if (key == LogicalKeyboardKey.escape) {
      return Uint8List.fromList([0x1b]);
    }

    // 方向键（普通模式）
    if (key == LogicalKeyboardKey.arrowUp) {
      return Uint8List.fromList([0x1b, 0x5b, 0x41]);
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return Uint8List.fromList([0x1b, 0x5b, 0x42]);
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return Uint8List.fromList([0x1b, 0x5b, 0x43]);
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return Uint8List.fromList([0x1b, 0x5b, 0x44]);
    }

    // Home / End
    if (key == LogicalKeyboardKey.home) {
      return Uint8List.fromList([0x1b, 0x5b, 0x48]);
    }
    if (key == LogicalKeyboardKey.end) {
      return Uint8List.fromList([0x1b, 0x5b, 0x46]);
    }

    // Insert
    if (key == LogicalKeyboardKey.insert) {
      return Uint8List.fromList([0x1b, 0x5b, 0x32, 0x7e]);
    }
    // Delete
    if (key == LogicalKeyboardKey.delete) {
      return Uint8List.fromList([0x1b, 0x5b, 0x33, 0x7e]);
    }

    // Page Up / Down
    if (key == LogicalKeyboardKey.pageUp) {
      return Uint8List.fromList([0x1b, 0x5b, 0x35, 0x7e]);
    }
    if (key == LogicalKeyboardKey.pageDown) {
      return Uint8List.fromList([0x1b, 0x5b, 0x36, 0x7e]);
    }

    // F1-F4（VT100 模式）
    if (key == LogicalKeyboardKey.f1) {
      return Uint8List.fromList([0x1b, 0x4f, 0x50]);
    }
    if (key == LogicalKeyboardKey.f2) {
      return Uint8List.fromList([0x1b, 0x4f, 0x51]);
    }
    if (key == LogicalKeyboardKey.f3) {
      return Uint8List.fromList([0x1b, 0x4f, 0x52]);
    }
    if (key == LogicalKeyboardKey.f4) {
      return Uint8List.fromList([0x1b, 0x4f, 0x53]);
    }

    // F5-F12
    if (key == LogicalKeyboardKey.f5) {
      return Uint8List.fromList([0x1b, 0x5b, 0x31, 0x35, 0x7e]);
    }
    if (key == LogicalKeyboardKey.f6) {
      return Uint8List.fromList([0x1b, 0x5b, 0x31, 0x37, 0x7e]);
    }
    if (key == LogicalKeyboardKey.f7) {
      return Uint8List.fromList([0x1b, 0x5b, 0x31, 0x38, 0x7e]);
    }
    if (key == LogicalKeyboardKey.f8) {
      return Uint8List.fromList([0x1b, 0x5b, 0x31, 0x39, 0x7e]);
    }
    if (key == LogicalKeyboardKey.f9) {
      return Uint8List.fromList([0x1b, 0x5b, 0x32, 0x30, 0x7e]);
    }
    if (key == LogicalKeyboardKey.f10) {
      return Uint8List.fromList([0x1b, 0x5b, 0x32, 0x31, 0x7e]);
    }
    if (key == LogicalKeyboardKey.f11) {
      return Uint8List.fromList([0x1b, 0x5b, 0x32, 0x33, 0x7e]);
    }
    if (key == LogicalKeyboardKey.f12) {
      return Uint8List.fromList([0x1b, 0x5b, 0x32, 0x34, 0x7e]);
    }

    return null;
  }
}
