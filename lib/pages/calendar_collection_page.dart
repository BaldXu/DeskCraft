import 'package:flutter/material.dart';

import '../models/calendar_config.dart';
import '../services/calendar_config_store.dart';
import '../services/widget_pin_service.dart';
import '../widgets/app_page_route.dart';
import '../widgets/calendar_preview.dart';
import '../widgets/widget_entry_cards.dart';
import 'calendar_config_page.dart';

/// 日历在原生侧注册的 Provider 类名。
const _kCalendarProviderName = 'CalendarWidgetProvider';

/// 日历类目页 —— 展示日历组件成品卡，点击进入配置页。
class CalendarCollectionPage extends StatefulWidget {
  const CalendarCollectionPage({super.key});

  @override
  State<CalendarCollectionPage> createState() => _CalendarCollectionPageState();
}

class _CalendarCollectionPageState extends State<CalendarCollectionPage> {
  CalendarConfig _config = const CalendarConfig();
  bool _pinnedOnHome = false;
  DateTime? _lastSyncAt;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final config = await CalendarConfigStore.load();
    final pinned = await WidgetPinService.isPinned(_kCalendarProviderName);
    if (!mounted) return;
    setState(() {
      _config = config;
      _pinnedOnHome = pinned;
      _lastSyncAt = CalendarConfigStore.lastSyncAt;
    });
  }

  Future<void> _openConfig() async {
    await Navigator.of(context).push<bool>(
      AppPageRoute<bool>(builder: (_) => CalendarConfigPage(initial: _config)),
    );
    await _reload();
  }

  /// 一键添加到桌面（Android 8+ 系统弹窗确认）。
  Future<void> _requestPin() async {
    try {
      await WidgetPinService.requestPin(_kCalendarProviderName);
      await Future<void>.delayed(const Duration(seconds: 3));
      final pinned = await WidgetPinService.isPinned(_kCalendarProviderName);
      if (!mounted) return;
      setState(() => _pinnedOnHome = pinned);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前桌面不支持一键添加，请长按桌面 → 添加组件手动添加')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('日历')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('已完成组件', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          WidgetEntryCard(
            icon: Icons.calendar_month,
            title: '日历',
            subtitle: '月视图 · 农历节气 · 系统日历节日/纪念日 · 翻日即时更新',
            preview: CalendarPreview(config: _config),
            pinned: _pinnedOnHome,
            lastSyncAt: _lastSyncAt,
            onTap: _openConfig,
            onPin: _requestPin,
          ),
          const SizedBox(height: 12),
          Text(
            '提示：授予「日历」读取权限后，桌面组件会显示系统日历中的节日与纪念日事件（如小米日历订阅的「中国节日」）。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
