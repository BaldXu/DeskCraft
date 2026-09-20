import 'package:flutter/material.dart';

import '../editor/layout_model.dart';
import '../editor/layout_preview.dart';
import '../services/custom_widget_store.dart';
import '../widgets/app_page_route.dart';
import 'custom_widget_editor_page.dart';

/// 自定义组件类目页 —— 布局库管理（新建 / 编辑 / 删除）。
///
/// 与时钟 / 监控类目不同，这里管理的是用户自建的布局草稿：
/// 点击布局卡进入编辑器（画布拖摆），编辑器内负责保存与上桌。
class CustomWidgetCollectionPage extends StatefulWidget {
  const CustomWidgetCollectionPage({super.key});

  @override
  State<CustomWidgetCollectionPage> createState() =>
      _CustomWidgetCollectionPageState();
}

class _CustomWidgetCollectionPageState
    extends State<CustomWidgetCollectionPage> {
  List<WidgetLayout> _layouts = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final layouts = await CustomWidgetStore.loadAll();
    if (!mounted) return;
    setState(() => _layouts = layouts);
  }

  Future<void> _openEditor([WidgetLayout? initial]) async {
    await Navigator.of(context).push<void>(
      AppPageRoute<void>(
        builder: (_) => CustomWidgetEditorPage(initial: initial),
      ),
    );
    await _reload();
  }

  Future<void> _confirmDelete(WidgetLayout layout) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除布局'),
        content: Text('确定删除「${layout.name}」吗？已上桌的组件不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await CustomWidgetStore.deleteLayout(layout.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('自定义组件')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新建布局'),
      ),
      body: _layouts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.dashboard_customize,
                    size: 56,
                    color: textTheme.bodySmall?.color?.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text('还没有自定义布局', style: textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Text('点右下角「新建布局」开始拖摆你的专属组件', style: textTheme.bodySmall),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: _layouts.length,
              itemBuilder: (context, index) {
                final layout = _layouts[index];
                return _LayoutCard(
                  layout: layout,
                  onTap: () => _openEditor(layout),
                  onDelete: () => _confirmDelete(layout),
                );
              },
            ),
    );
  }
}

/// 布局卡：左侧缩略预览，右侧名称与图层概览。
class _LayoutCard extends StatelessWidget {
  const _LayoutCard({
    required this.layout,
    required this.onTap,
    required this.onDelete,
  });

  final WidgetLayout layout;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textCount = layout.layers.whereType<TextLayer>().length;
    final updated = DateTime.fromMillisecondsSinceEpoch(layout.updatedAt);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 缩略预览：等比缩放到约 120dp 宽，文本原样渲染（不做公式求值）。
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LayoutPreviewCanvas(
                    layout: layout,
                    scale: 120 / layout.canvasWidth,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      layout.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${layout.layers.length} 个图层 · $textCount 处公式',
                      style: textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '刷新周期 ${_refreshLabel(layout)} · 更新于 '
                      '${updated.month}/${updated.day} '
                      '${updated.hour.toString().padLeft(2, '0')}:'
                      '${updated.minute.toString().padLeft(2, '0')}',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20),
                        SizedBox(width: 8),
                        Text('删除'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _refreshLabel(WidgetLayout layout) {
    final seconds = layout.refreshSeconds;
    if (seconds <= 0) return '静态';
    if (seconds < 60) return '$seconds 秒';
    if (seconds % 60 == 0) return '${seconds ~/ 60} 分钟';
    return '$seconds 秒';
  }
}
