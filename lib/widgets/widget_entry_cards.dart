import 'package:flutter/material.dart';

/// 组件成品卡（类目页通用）：实时预览 + 状态徽章 + 添加到桌面操作。
///
/// 点击卡片进入配置页；[onPin] 触发系统一键添加弹窗，
/// 添加结果由调用方刷新 [pinned] 后回传。
class WidgetEntryCard extends StatelessWidget {
  const WidgetEntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.pinned,
    required this.lastSyncAt,
    required this.onTap,
    required this.onPin,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// 组件实时预览（与桌面渲染同一套配置模型驱动）。
  final Widget preview;
  final bool pinned;
  final DateTime? lastSyncAt;
  final VoidCallback onTap;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final syncLabel = lastSyncAt == null
        ? '尚未同步'
        : '最后同步 ${lastSyncAt!.toIso8601String().substring(11, 19)}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      // 标题过长时换行，避免右侧徽章/箭头被挤出溢出
                      softWrap: true,
                    ),
                  ),
                  PinnedBadge(pinned: pinned),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              preview,
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      syncLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                      softWrap: true,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onPin,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加到桌面'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「已上桌 / 未检测」状态徽章。
class PinnedBadge extends StatelessWidget {
  const PinnedBadge({super.key, required this.pinned});

  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: pinned
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        pinned ? '已上桌' : '未检测',
        style: TextStyle(
          fontSize: 11,
          color: pinned ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
