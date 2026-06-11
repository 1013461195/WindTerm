import 'package:flutter/material.dart';

/// 终端配置
class TerminalSettings {
  /// 字体大小
  final double fontSize;

  /// 字体行高
  final double lineHeight;

  /// 字体族
  final String fontFamily;

  /// 字体 fallback 列表
  final List<String> fontFamilyFallback;

  /// 单元格宽度（像素）
  final double cellWidth;

  /// 单元格高度（像素）
  final double cellHeight;

  /// 左边距
  final double leftPadding;

  /// 上边距
  final double topPadding;

  /// 背景颜色
  final Color backgroundColor;

  /// 默认前景色
  final Color foregroundColor;

  /// 光标颜色
  final Color cursorColor;

  /// 选区颜色
  final Color selectionColor;

  /// 主题名称
  final String themeName;
  final double windowOpacity;

  const TerminalSettings({
    this.fontSize = 13,
    this.lineHeight = 1.0,
    this.fontFamily = 'Menlo',
    this.fontFamilyFallback = const ['Consolas', 'Courier New', 'monospace'],
    this.cellWidth = 8.0,
    this.cellHeight = 16.0,
    this.leftPadding = 4.0,
    this.topPadding = 4.0,
    this.backgroundColor = const Color(0xff05070a),
    this.foregroundColor = const Color(0xffd7e0ee),
    this.cursorColor = const Color(0xffd7e0ee),
    this.selectionColor = const Color(0xff2f6fed),
    this.themeName = 'default',
    this.windowOpacity = 1.0,
  });

  TerminalSettings copyWith({
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    double? cellWidth,
    double? cellHeight,
    double? leftPadding,
    double? topPadding,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? cursorColor,
    Color? selectionColor,
    String? themeName,
    double? windowOpacity,
  }) {
    return TerminalSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
      cellWidth: cellWidth ?? this.cellWidth,
      cellHeight: cellHeight ?? this.cellHeight,
      leftPadding: leftPadding ?? this.leftPadding,
      topPadding: topPadding ?? this.topPadding,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      foregroundColor: foregroundColor ?? this.foregroundColor,
      cursorColor: cursorColor ?? this.cursorColor,
      selectionColor: selectionColor ?? this.selectionColor,
      themeName: themeName ?? this.themeName,
      windowOpacity: windowOpacity ?? this.windowOpacity,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'fontFamily': fontFamily,
    'fontFamilyFallback': fontFamilyFallback,
    'cellWidth': cellWidth,
    'cellHeight': cellHeight,
    'leftPadding': leftPadding,
    'topPadding': topPadding,
    'backgroundColor': backgroundColor.toARGB32(),
    'foregroundColor': foregroundColor.toARGB32(),
    'cursorColor': cursorColor.toARGB32(),
    'selectionColor': selectionColor.toARGB32(),
    'themeName': themeName,
    'windowOpacity': windowOpacity,
  };

  factory TerminalSettings.fromJson(Map<String, dynamic> json) {
    Color color(String key, Color fallback) =>
        json[key] is int ? Color(json[key] as int) : fallback;
    return TerminalSettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 13,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1,
      fontFamily: json['fontFamily'] as String? ?? 'Menlo',
      fontFamilyFallback: List<String>.from(
        json['fontFamilyFallback'] ??
            const ['Consolas', 'Courier New', 'monospace'],
      ),
      cellWidth: (json['cellWidth'] as num?)?.toDouble() ?? 8,
      cellHeight: (json['cellHeight'] as num?)?.toDouble() ?? 16,
      leftPadding: (json['leftPadding'] as num?)?.toDouble() ?? 4,
      topPadding: (json['topPadding'] as num?)?.toDouble() ?? 4,
      backgroundColor: color('backgroundColor', const Color(0xff05070a)),
      foregroundColor: color('foregroundColor', const Color(0xffd7e0ee)),
      cursorColor: color('cursorColor', const Color(0xffd7e0ee)),
      selectionColor: color('selectionColor', const Color(0xff2f6fed)),
      themeName: json['themeName'] as String? ?? 'default',
      windowOpacity: (json['windowOpacity'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// 终端主题
class TerminalTheme {
  final String name;
  final String displayName;
  final Color background;
  final Color foreground;
  final Color cursor;
  final Color selection;
  final Color black;
  final Color red;
  final Color green;
  final Color yellow;
  final Color blue;
  final Color magenta;
  final Color cyan;
  final Color white;
  final Color brightBlack;
  final Color brightRed;
  final Color brightGreen;
  final Color brightYellow;
  final Color brightBlue;
  final Color brightMagenta;
  final Color brightCyan;
  final Color brightWhite;

  const TerminalTheme({
    required this.name,
    required this.displayName,
    required this.background,
    required this.foreground,
    required this.cursor,
    required this.selection,
    required this.black,
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
    required this.magenta,
    required this.cyan,
    required this.white,
    required this.brightBlack,
    required this.brightRed,
    required this.brightGreen,
    required this.brightYellow,
    required this.brightBlue,
    required this.brightMagenta,
    required this.brightCyan,
    required this.brightWhite,
  });
}

/// 预定义主题
class TerminalThemes {
  static const defaultTheme = TerminalTheme(
    name: 'default',
    displayName: '默认',
    background: Color(0xff05070a),
    foreground: Color(0xffd7e0ee),
    cursor: Color(0xffd7e0ee),
    selection: Color(0xff2f6fed),
    black: Color(0xff000000),
    red: Color(0xffcc0000),
    green: Color(0xff4e9a06),
    yellow: Color(0xffc4a000),
    blue: Color(0xff3465a4),
    magenta: Color(0xff75507b),
    cyan: Color(0xff06989a),
    white: Color(0xffd3d7cf),
    brightBlack: Color(0xff555753),
    brightRed: Color(0xffef2929),
    brightGreen: Color(0xff8ae234),
    brightYellow: Color(0xfffce94f),
    brightBlue: Color(0xff729fcf),
    brightMagenta: Color(0xffad7fa8),
    brightCyan: Color(0xff34e2e2),
    brightWhite: Color(0xffeeeeec),
  );

  static const solarizedDark = TerminalTheme(
    name: 'solarized-dark',
    displayName: 'Solarized Dark',
    background: Color(0xff002b36),
    foreground: Color(0xff839496),
    cursor: Color(0xff839496),
    selection: Color(0xff073642),
    black: Color(0xff073642),
    red: Color(0xffdc322f),
    green: Color(0xff859900),
    yellow: Color(0xffb58900),
    blue: Color(0xff268bd2),
    magenta: Color(0xffd33682),
    cyan: Color(0xff2aa198),
    white: Color(0xffeee8d5),
    brightBlack: Color(0xff586e75),
    brightRed: Color(0xffcb4b16),
    brightGreen: Color(0xff586e75),
    brightYellow: Color(0xff657b83),
    brightBlue: Color(0xff839496),
    brightMagenta: Color(0xff6c71c4),
    brightCyan: Color(0xff93a1a1),
    brightWhite: Color(0xfffdf6e3),
  );

  static const monokai = TerminalTheme(
    name: 'monokai',
    displayName: 'Monokai',
    background: Color(0xff272822),
    foreground: Color(0xfff8f8f2),
    cursor: Color(0xfff8f8f0),
    selection: Color(0xff49483e),
    black: Color(0xff272822),
    red: Color(0xfff92672),
    green: Color(0xffa6e22e),
    yellow: Color(0xfff4bf75),
    blue: Color(0xff66d9ef),
    magenta: Color(0xffae81ff),
    cyan: Color(0xffa1efe4),
    white: Color(0xfff8f8f2),
    brightBlack: Color(0xff75715e),
    brightRed: Color(0xfff92672),
    brightGreen: Color(0xffa6e22e),
    brightYellow: Color(0xfff4bf75),
    brightBlue: Color(0xff66d9ef),
    brightMagenta: Color(0xffae81ff),
    brightCyan: Color(0xffa1efe4),
    brightWhite: Color(0xfff9f8f5),
  );

  static const dracula = TerminalTheme(
    name: 'dracula',
    displayName: 'Dracula',
    background: Color(0xff282a36),
    foreground: Color(0xfff8f8f2),
    cursor: Color(0xfff8f8f0),
    selection: Color(0xff44475a),
    black: Color(0xff21222c),
    red: Color(0xffff5555),
    green: Color(0xff50fa7b),
    yellow: Color(0xfff1fa8c),
    blue: Color(0xffbd93f9),
    magenta: Color(0xffff79c6),
    cyan: Color(0xff8be9fd),
    white: Color(0xfff8f8f2),
    brightBlack: Color(0xff6272a4),
    brightRed: Color(0xffff6e6e),
    brightGreen: Color(0xff69ff94),
    brightYellow: Color(0xffffffa5),
    brightBlue: Color(0xffd6acff),
    brightMagenta: Color(0xffff92df),
    brightCyan: Color(0xffa4ffff),
    brightWhite: Color(0xffffffff),
  );

  static List<TerminalTheme> get all => [
    defaultTheme,
    solarizedDark,
    monokai,
    dracula,
  ];

  static TerminalTheme getThemeByName(String name) {
    return all.firstWhere(
      (theme) => theme.name == name,
      orElse: () => defaultTheme,
    );
  }
}
