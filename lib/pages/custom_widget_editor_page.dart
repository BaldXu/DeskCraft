/// 自定义组件编辑器（M6 e1）——画布拖摆 + 图层列表 + 属性面板。
///
/// 布局：上部画布预览（点选 / 拖动图层，缩放条），
/// 下部「图层 / 属性」双 Tab。保存走 [CustomWidgetStore]，
/// 上桌 = 保存 + 渲染位图推送（前台即可预览效果，后台回调负责定时刷新）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../editor/layout_model.dart';
import '../editor/layout_preview.dart';
import '../formula/formula_context.dart';
import '../services/custom_widget_store.dart';
import '../widgets/layer_property_editor.dart';

/// 自定义组件编辑器页面。
///
/// [initial] 为空时以 [CustomWidgetStore.defaultLayout] 起稿。
class CustomWidgetEditorPage extends StatefulWidget {
  const CustomWidgetEditorPage({super.key, this.initial});

  final WidgetLayout? initial;

  @override
  State<CustomWidgetEditorPage> createState() => _CustomWidgetEditorPageState();
}

class _CustomWidgetEditorPageState extends State<CustomWidgetEditorPage> {
  late WidgetLayout _layout;
  String? _selectedLayerId;
  double _zoom = 1.3;
  Timer? _tick;
  bool _busy = false;

  FormulaContext? _previewContext;

  @override
  void initState() {
    super.initState();
    _layout = widget.initial ?? CustomWidgetStore.defaultLayout();
    _selectedLayerId = _layout.layers.isEmpty ? null : _layout.layers.last.id;
    _refreshPreviewContext();
    // 预览每秒重绘（时间类模板实时走秒）
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshPreviewContext();
      if (mounted) setState(() {});
    });
  }

  Future<void> _refreshPreviewContext() async {
    final ctx = await CustomWidgetStore.renderContext();
    if (mounted) setState(() => _previewContext = ctx);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  LayoutLayer? get _selected {
    final id = _selectedLayerId;
    if (id == null) return null;
    for (final layer in _layout.layers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  // ---- 画布交互 ----

  LayoutLayer? _hitLayer(Offset localPoint) {
    // dp 坐标（画布显示原点 = 画布左上角）
    final x = localPoint.dx / _zoom;
    final y = localPoint.dy / _zoom;
    // 顶层优先
    for (final layer in _layout.layers.reversed) {
      if (x >= layer.x &&
          x <= layer.x + layer.w &&
          y >= layer.y &&
          y <= layer.y + layer.h) {
        return layer;
      }
    }
    return null;
  }

  void _onTapCanvas(Offset localPoint) {
    final hit = _hitLayer(localPoint);
    setState(() {
      _selectedLayerId = hit?.id;
    });
  }

  void _onDragCanvas(DragUpdateDetails details) {
    final layer = _selected;
    if (layer == null) return;
    setState(() {
      layer.x = (layer.x + details.delta.dx / _zoom).clamp(
        -layer.w * 0.5,
        _layout.canvasWidth - layer.w * 0.5,
      );
      layer.y = (layer.y + details.delta.dy / _zoom).clamp(
        -layer.h * 0.5,
        _layout.canvasHeight - layer.h * 0.5,
      );
    });
  }

  // ---- 图层列表操作 ----

  void _addLayer(LayerType type) {
    final id = 'l${DateTime.now().millisecondsSinceEpoch % 100000}';
    final selected = _selected;
    final cx = _layout.canvasWidth / 2;
    final cy = _layout.canvasHeight / 2;
    setState(() {
      if (type == LayerType.rect) {
        _layout.layers.add(
          RectLayer(id: id, x: cx - 40, y: cy - 20, w: 80, h: 40),
        );
      } else {
        _layout.layers.add(
          TextLayer(id: id, x: cx - 60, y: cy - 14, w: 120, h: 28),
        );
      }
      _selectedLayerId = id;
    });
    // 未选中任何图层时以画布中心为默认位置；已选中时略偏移避免完全重叠
    if (selected != null) {
      final layer = _layout.layers.last;
      layer.x = selected.x + 12;
      layer.y = selected.y + 12;
    }
  }

  void _removeLayer(String id) {
    setState(() {
      _layout.layers.removeWhere((l) => l.id == id);
      if (_selectedLayerId == id) _selectedLayerId = null;
    });
  }

  void _moveLayer(String id, int delta) {
    final index = _layout.layers.indexWhere((l) => l.id == id);
    if (index < 0) return;
    final target = index + delta;
    if (target < 0 || target >= _layout.layers.length) return;
    setState(() {
      final layer = _layout.layers.removeAt(index);
      _layout.layers.insert(target, layer);
    });
  }

  // ---- 保存 / 上桌 ----

  Future<void> _save({bool push = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await CustomWidgetStore.saveLayout(_layout);
      var ok = true;
      var message = '布局已保存';
      if (push) {
        ok = await CustomWidgetStore.pushToDesktop(_layout);
        message = ok ? '已保存并推送到桌面' : '推送失败，请检查组件是否已添加';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _layout.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('组件名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      setState(() => _layout.name = name.trim());
    }
  }

  // ---- 构建 ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _rename,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(_layout.name, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.edit,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: '保存',
            icon: const Icon(Icons.save_outlined),
            onPressed: _busy ? null : () => _save(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _save(push: true),
              icon: const Icon(Icons.push_pin_outlined, size: 18),
              label: const Text('上桌'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCanvasArea(context),
          const Divider(height: 1),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: const [
                      Tab(text: '图层'),
                      Tab(text: '属性'),
                    ],
                    dividerColor: Colors.transparent,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildLayerList(),
                        LayerPropertyEditor(
                          layer: _selected,
                          onChanged: () => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加图层',
        onPressed: _showAddLayerSheet,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildCanvasArea(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Center(
            child: GestureDetector(
              onTapDown: (d) => _onTapCanvas(d.localPosition),
              onPanUpdate: _onDragCanvas,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: LayoutPreviewCanvas(
                    layout: _layout,
                    scale: _zoom,
                    context: _previewContext,
                    background: const Color(0xFF16161E),
                    selectedLayerId: _selectedLayerId,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.zoom_out, size: 18),
              Expanded(
                child: Slider(
                  value: _zoom,
                  min: 0.6,
                  max: 3,
                  onChanged: (v) => setState(() => _zoom = v),
                ),
              ),
              const Icon(Icons.zoom_in, size: 18),
              const SizedBox(width: 12),
              Text(
                '${_layout.canvasWidth.round()}×${_layout.canvasHeight.round()} dp',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLayerList() {
    final layers = _layout.layers;
    if (layers.isEmpty) {
      return const Center(child: Text('还没有图层，点右下角 + 添加'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: layers.length,
      itemBuilder: (context, index) {
        final layer = layers[index];
        final selected = layer.id == _selectedLayerId;
        return ListTile(
          selected: selected,
          selectedTileColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.12),
          leading: Icon(
            switch (layer) {
              RectLayer() => Icons.crop_square,
              TextLayer() => Icons.text_fields,
            },
            color: switch (layer) {
              RectLayer(:final fillColor) => Color(fillColor),
              TextLayer(:final color) => Color(color),
            },
          ),
          title: Text(_layerTitle(layer), overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'z${index + 1} · ${layer.x.round()},${layer.y.round()} · ${layer.w.round()}×${layer.h.round()}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '上移一层',
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: index == layers.length - 1
                    ? null
                    : () => _moveLayer(layer.id, 1),
              ),
              IconButton(
                tooltip: '下移一层',
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: index == 0 ? null : () => _moveLayer(layer.id, -1),
              ),
              IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _removeLayer(layer.id),
              ),
            ],
          ),
          onTap: () => setState(() => _selectedLayerId = layer.id),
        );
      },
    );
  }

  String _layerTitle(LayoutLayer layer) {
    switch (layer) {
      case RectLayer():
        return '矩形 ${layer.cornerRadius > 0 ? '(圆角 ${layer.cornerRadius.round()})' : ''}';
      case TextLayer():
        return '文本 ${layer.template.replaceAll('\n', ' ')}';
    }
  }

  Future<void> _showAddLayerSheet() async {
    final type = await showModalBottomSheet<LayerType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.crop_square),
              title: const Text('矩形'),
              subtitle: const Text('纯色填充 + 圆角'),
              onTap: () => Navigator.of(context).pop(LayerType.rect),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('文本'),
              subtitle: const Text('支持 \$公式\$ 模板'),
              onTap: () => Navigator.of(context).pop(LayerType.text),
            ),
          ],
        ),
      ),
    );
    if (type != null) _addLayer(type);
  }
}
