import 'package:flutter/material.dart';
import 'terminal_settings.dart';

/// 终端设置页面
class SettingsPage extends StatefulWidget {
  final TerminalSettings settings;
  final void Function(TerminalSettings settings) onSettingsChanged;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TerminalSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _updateSettings(TerminalSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    widget.onSettingsChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('终端设置'),
        backgroundColor: const Color(0xff191d25),
      ),
      backgroundColor: const Color(0xff111318),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            title: '主题',
            children: [
              _buildThemeSelector(),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '字体',
            children: [
              _buildFontSizeSlider(),
              const SizedBox(height: 16),
              _buildFontFamilySelector(),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '颜色',
            children: [
              _buildColorSelector('背景色', _settings.backgroundColor, (color) {
                _updateSettings(_settings.copyWith(backgroundColor: color));
              }),
              const SizedBox(height: 8),
              _buildColorSelector('前景色', _settings.foregroundColor, (color) {
                _updateSettings(_settings.copyWith(foregroundColor: color));
              }),
              const SizedBox(height: 8),
              _buildColorSelector('光标色', _settings.cursorColor, (color) {
                _updateSettings(_settings.copyWith(cursorColor: color));
              }),
              const SizedBox(height: 8),
              _buildColorSelector('选区色', _settings.selectionColor, (color) {
                _updateSettings(_settings.copyWith(selectionColor: color));
              }),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '高级',
            children: [
              _buildCellSizeSliders(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff191d25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff2a303b)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xffd7e0ee),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildThemeSelector() {
    return Column(
      children: TerminalThemes.all.map((theme) {
        final isSelected = theme.name == _settings.themeName;
        return ListTile(
          title: Text(
            theme.displayName,
            style: TextStyle(
              color: isSelected ? const Color(0xff2f6fed) : const Color(0xffd7e0ee),
            ),
          ),
          leading: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: theme.background,
              border: Border.all(color: const Color(0xff2a303b)),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          trailing: isSelected
              ? const Icon(Icons.check_rounded, color: Color(0xff2f6fed))
              : null,
          onTap: () {
            _updateSettings(_settings.copyWith(
              themeName: theme.name,
              backgroundColor: theme.background,
              foregroundColor: theme.foreground,
              cursorColor: theme.cursor,
              selectionColor: theme.selection,
            ));
          },
        );
      }).toList(),
    );
  }

  Widget _buildFontSizeSlider() {
    return Row(
      children: [
        const Text(
          '字号',
          style: TextStyle(color: Color(0xff8e98a8)),
        ),
        Expanded(
          child: Slider(
            value: _settings.fontSize,
            min: 10,
            max: 24,
            divisions: 14,
            label: _settings.fontSize.round().toString(),
            activeColor: const Color(0xff2f6fed),
            onChanged: (value) {
              _updateSettings(_settings.copyWith(fontSize: value));
            },
          ),
        ),
        Text(
          '${_settings.fontSize.round()}',
          style: const TextStyle(color: Color(0xffd7e0ee)),
        ),
      ],
    );
  }

  Widget _buildFontFamilySelector() {
    final fonts = ['Menlo', 'Consolas', 'Courier New', 'Monaco', 'DejaVu Sans Mono'];
    return Row(
      children: [
        const Text(
          '字体',
          style: TextStyle(color: Color(0xff8e98a8)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DropdownButton<String>(
            value: _settings.fontFamily,
            isExpanded: true,
            dropdownColor: const Color(0xff191d25),
            style: const TextStyle(color: Color(0xffd7e0ee)),
            items: fonts.map((font) {
              return DropdownMenuItem(
                value: font,
                child: Text(font),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                _updateSettings(_settings.copyWith(fontFamily: value));
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColorSelector(
    String label,
    Color color,
    void Function(Color color) onChanged,
  ) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xff8e98a8)),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () {
            // 简单的颜色选择器（实际应用中可以使用更复杂的颜色选择器）
            _showColorPicker(color, onChanged);
          },
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: const Color(0xff2a303b)),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }

  void _showColorPicker(Color currentColor, void Function(Color color) onChanged) {
    // 简化的颜色选择器，实际应用中可以使用更完整的实现
    final colors = [
      const Color(0xff05070a),
      const Color(0xff191d25),
      const Color(0xff2a303b),
      const Color(0xffd7e0ee),
      const Color(0xff2f6fed),
      const Color(0xffcc0000),
      const Color(0xff4e9a06),
      const Color(0xffc4a000),
      const Color(0xff3465a4),
      const Color(0xff75507b),
      const Color(0xff06989a),
      const Color(0xffd3d7cf),
    ];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xff191d25),
          title: const Text('选择颜色', style: TextStyle(color: Color(0xffd7e0ee))),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors.map((color) {
              return GestureDetector(
                onTap: () {
                  onChanged(color);
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(
                      color: color == currentColor
                          ? const Color(0xff2f6fed)
                          : const Color(0xff2a303b),
                      width: color == currentColor ? 3 : 1,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildCellSizeSliders() {
    return Column(
      children: [
        Row(
          children: [
            const Text(
              '单元格宽度',
              style: TextStyle(color: Color(0xff8e98a8)),
            ),
            Expanded(
              child: Slider(
                value: _settings.cellWidth,
                min: 6,
                max: 12,
                divisions: 12,
                label: _settings.cellWidth.toStringAsFixed(1),
                activeColor: const Color(0xff2f6fed),
                onChanged: (value) {
                  _updateSettings(_settings.copyWith(cellWidth: value));
                },
              ),
            ),
            Text(
              _settings.cellWidth.toStringAsFixed(1),
              style: const TextStyle(color: Color(0xffd7e0ee)),
            ),
          ],
        ),
        Row(
          children: [
            const Text(
              '单元格高度',
              style: TextStyle(color: Color(0xff8e98a8)),
            ),
            Expanded(
              child: Slider(
                value: _settings.cellHeight,
                min: 12,
                max: 24,
                divisions: 12,
                label: _settings.cellHeight.toStringAsFixed(1),
                activeColor: const Color(0xff2f6fed),
                onChanged: (value) {
                  _updateSettings(_settings.copyWith(cellHeight: value));
                },
              ),
            ),
            Text(
              _settings.cellHeight.toStringAsFixed(1),
              style: const TextStyle(color: Color(0xffd7e0ee)),
            ),
          ],
        ),
      ],
    );
  }
}
