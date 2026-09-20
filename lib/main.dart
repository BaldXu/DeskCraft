import 'package:flutter/material.dart';

import 'pages/clock_collection_page.dart';
import 'pages/custom_widget_collection_page.dart';
import 'pages/monitor_collection_page.dart';
import 'services/custom_widget_callback.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerCustomWidgetBackgroundCallback();
  runApp(const DeskCraftApp());
}

class DeskCraftApp extends StatelessWidget {
  const DeskCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeskCraft',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const WorkshopHomePage(),
    );
  }
}

/// 组件工坊首页 —— 三层导航的第一层：
/// 仅展示组件类目入口，点击进入组件库页（第二层），再由成品卡进入配置页（第三层）。
class WorkshopHomePage extends StatelessWidget {
  const WorkshopHomePage({super.key});

  void _openCategory(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('DeskCraft · 组件工坊')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('打造属于你的桌面组件', style: textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('选择一个类目，进入组件库挑选并定制成品', style: textTheme.bodySmall),
          const SizedBox(height: 20),
          Text('组件类目', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          _CategoryCard(
            icon: Icons.schedule,
            title: '数字时钟',
            subtitle: 'TextClock 驱动 · 零功耗走时 · 样式自由定制',
            count: 1,
            onTap: () => _openCategory(context, const ClockCollectionPage()),
          ),
          const SizedBox(height: 12),
          _CategoryCard(
            icon: Icons.thermostat,
            title: '系统监控',
            subtitle: '电池温度 · CPU · 内存 · Root 数据源驱动',
            count: 1,
            onTap: () => _openCategory(context, const MonitorCollectionPage()),
          ),
          const SizedBox(height: 24),
          Text('规划中', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          const _PlannedWidgetCard(
            icon: Icons.calendar_month,
            title: '日历组件',
            subtitle: '月视图 · 上桌即用 · 样式可定制',
          ),
          const SizedBox(height: 12),
          _CategoryCard(
            icon: Icons.design_services,
            title: '自定义组件',
            subtitle: '图层画布拖摆 · 公式驱动 · 编辑器自由定制',
            count: null,
            onTap: () =>
                _openCategory(context, const CustomWidgetCollectionPage()),
          ),
          const SizedBox(height: 24),
          Text(
            'M1：数字时钟上桌（TextClock 零功耗走秒）\n'
            'M2：libsu root 数据源验证（白名单只读命令）\n'
            'M3：组件卡片页 + 配置页 + 主题系统\n'
            'M4：系统监控组件上桌（定时采样 · 快照秒开）',
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// 类目入口卡：图标 + 标题 + 副标题 + 已完成组件数（null 时显示「自由定制」），
/// 点击进入组件库页。
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                count == null ? '自由定制' : '$count 个组件',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 规划中的组件占位卡：与类目入口卡同构但弱化视觉，预留未来扩展位。
class _PlannedWidgetCard extends StatelessWidget {
  const _PlannedWidgetCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '规划中',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
