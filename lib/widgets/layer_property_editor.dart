/// 图层属性编辑面板（M6 e1 编辑器）——按选中图层类型渲染属性编辑控件。
///
/// 直接修改传入的可变图层对象，通过 [onChanged] 通知外部 setState 重绘画布。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor/layout_model.dart';
import '../formula/formula_engine.dart';
import '../models/global_var.dart';

/// 预设色板（ARGB），覆盖常用深浅色。
const List<int> _presetColors = [
  0xFF3D5AFE,
  0xFF00C853,
  0xFFFFAB00,
  0xFFFF3D00,
  0xFFAA00FF,
  0xFF00B8D4,
  0xFF101018,
  0xFFFFFFFF,
];

/// 图层属性编辑面板。
class LayerPropertyEditor extends StatelessWidget {
  const LayerPropertyEditor({
    super.key,
    required this.layer,
    required this.onChanged,
    this.globals = const [],
  });

  final LayoutLayer? layer;
  final VoidCallback onChanged;

  /// 当前已定义的全局变量（追加到系统变量 chips 之后，用于快捷插入）。
  final List<GlobalVar> globals;

  @override
  Widget build(BuildContext context) {
    final selected = layer;
    if (selected == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('先在画布或图层列表中选中一个图层')),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        ..._commonFields(context, selected),
        if (selected is RectLayer) ..._rectFields(context, selected),
        if (selected is TextLayer) ..._textFields(context, selected),
      ],
    );
  }

  // ---- 通用字段 ----

  List<Widget> _commonFields(BuildContext context, LayoutLayer layer) {
    return [
      _sectionTitle(context, '位置与尺寸 (dp)'),
      _NumRow([
        _NumField(label: 'X', value: layer.x, onSaved: (v) => layer.x = v),
        _NumField(label: 'Y', value: layer.y, onSaved: (v) => layer.y = v),
        _NumField(label: '宽', value: layer.w, onSaved: (v) => layer.w = v),
        _NumField(label: '高', value: layer.h, onSaved: (v) => layer.h = v),
      ]),
      const SizedBox(height: 8),
      Row(
        children: [
          const Text('不透明度'),
          Expanded(
            child: Slider(
              value: layer.opacity,
              min: 0.05,
              max: 1,
              divisions: 19,
              label: '${(layer.opacity * 100).round()}%',
              onChanged: (v) {
                layer.opacity = v;
                onChanged();
              },
            ),
          ),
        ],
      ),
    ];
  }

  // ---- 矩形字段 ----

  List<Widget> _rectFields(BuildContext context, RectLayer layer) {
    return [
      _sectionTitle(context, '填充'),
      _colorField(context, '填充色', layer.fillColor, (c) {
        layer.fillColor = c;
        onChanged();
      }),
      Row(
        children: [
          const Text('圆角'),
          Expanded(
            child: Slider(
              value: layer.cornerRadius.clamp(0, 40),
              min: 0,
              max: 40,
              divisions: 40,
              label: layer.cornerRadius.toStringAsFixed(0),
              onChanged: (v) {
                layer.cornerRadius = v;
                onChanged();
              },
            ),
          ),
        ],
      ),
    ];
  }

  // ---- 文本字段 ----

  List<Widget> _textFields(BuildContext context, TextLayer layer) {
    return [
      _sectionTitle(context, '文本模板'),
      _templateField(context, layer),
      const SizedBox(height: 8),
      _variableChips(context, layer),
      _sectionTitle(context, '样式'),
      Row(
        children: [
          const Text('字号'),
          Expanded(
            child: Slider(
              value: layer.fontSize.clamp(6, 64),
              min: 6,
              max: 64,
              divisions: 58,
              label: layer.fontSize.toStringAsFixed(0),
              onChanged: (v) {
                layer.fontSize = v;
                onChanged();
              },
            ),
          ),
        ],
      ),
      _colorField(context, '文字色', layer.color, (c) {
        layer.color = c;
        onChanged();
      }),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('加粗'),
        value: layer.bold,
        onChanged: (v) {
          layer.bold = v;
          onChanged();
        },
      ),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'left', icon: Icon(Icons.format_align_left)),
          ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center)),
          ButtonSegment(value: 'right', icon: Icon(Icons.format_align_right)),
        ],
        selected: {layer.align},
        onSelectionChanged: (s) {
          layer.align = s.first;
          onChanged();
        },
      ),
    ];
  }

  /// 模板输入框 + 常用格式快捷按钮。
  Widget _templateField(BuildContext context, TextLayer layer) {
    return TextFormField(
      key: ValueKey('template-${layer.id}'),
      initialValue: layer.template,
      minLines: 1,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: '模板（\$表达式\$ 插值，\$\$ 转义）',
        border: OutlineInputBorder(),
      ),
      onChanged: (v) {
        layer.template = v;
        onChanged();
      },
    );
  }

  /// 变量快捷插入 chips：系统变量 + 全局变量（分组展示）。
  Widget _variableChips(BuildContext context, TextLayer layer) {
    final systemChips = FormulaEngine.knownVariables.entries
        .map(
          (e) => ActionChip(
            label: Text(e.key),
            tooltip: e.value,
            onPressed: () {
              layer.template = '${layer.template}\$${e.key}\$';
              onChanged();
            },
          ),
        )
        .toList();
    if (globals.isEmpty) {
      return Wrap(spacing: 6, runSpacing: 6, children: systemChips);
    }
    final gvChips = globals
        .map(
          (g) => ActionChip(
            label: Text(g.key),
            tooltip: '全局变量 · ${g.type.label}',
            onPressed: () {
              layer.template = '${layer.template}\$${g.key}\$';
              onChanged();
            },
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: systemChips),
        const SizedBox(height: 6),
        Text('全局变量', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: gvChips),
      ],
    );
  }

  // ---- 公共小部件 ----

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );

  Widget _colorField(
    BuildContext context,
    String label,
    int value,
    ValueChanged<int> onChangedColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _presetColors)
              InkWell(
                onTap: () => onChangedColor(c),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: value == c
                        ? Border.all(color: Colors.blue, width: 3)
                        : Border.all(color: Colors.white24),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _HexColorField(initialHex: value, onSaved: onChangedColor),
      ],
    );
  }
}

/// 十六进制颜色输入（#RRGGBB / #AARRGGBB）。
class _HexColorField extends StatefulWidget {
  const _HexColorField({required this.initialHex, required this.onSaved});

  final int initialHex;
  final ValueChanged<int> onSaved;

  @override
  State<_HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<_HexColorField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialHex.toRadixString(16).padLeft(8, '0'),
    );
  }

  @override
  void didUpdateWidget(_HexColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialHex != widget.initialHex) {
      _controller.text = widget.initialHex.toRadixString(16).padLeft(8, '0');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: '自定义 (#AARRGGBB)',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
        ],
        onSubmitted: (v) {
          final hex = v.replaceAll('#', '');
          final parsed = int.tryParse(hex, radix: 16);
          if (parsed != null) {
            widget.onSaved(hex.length == 6 ? (0xFF000000 | parsed) : parsed);
          }
        },
      ),
    );
  }
}

/// 双列数字输入行。
class _NumRow extends StatelessWidget {
  const _NumRow(this.fields);

  final List<Widget> fields;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [for (final f in fields) SizedBox(width: 130, child: f)],
    );
  }
}

class _NumField extends StatefulWidget {
  const _NumField({
    required this.label,
    required this.value,
    required this.onSaved,
  });

  final String label;
  final double value;
  final ValueChanged<double> onSaved;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(_NumField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = _format(widget.value);
    }
  }

  static String _format(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
      onChanged: (v) {
        final parsed = double.tryParse(v);
        if (parsed != null) widget.onSaved(parsed);
      },
    );
  }
}
