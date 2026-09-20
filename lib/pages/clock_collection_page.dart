import 'package:flutter/material.dart';

import '../models/clock_config.dart';
import '../services/clock_config_store.dart';
import '../services/widget_pin_service.dart';
import '../widgets/clock_preview.dart';
import '../widgets/widget_entry_cards.dart';
import 'clock_config_page.dart';

/// 数字时钟在原生侧注册的 Provider 类名。
const _kClockProviderName = 'ClockWidgetProvider';

/// 数字时钟类目页 —— 展示该类目下已完成的组件成品，
/// 点击成品卡进入配置页（第三层），未来同类组件在此追加。
class ClockCollectionPage extends StatefulWidget {
  const ClockCollectionPage({super.key});

  @override
  State<ClockCollectionPage> createState() => _ClockCollectionPageState();
}

class _ClockCollectionPageState extends State<ClockCollectionPage> {
  ClockConfig _config = const ClockConfig();
  bool _pinnedOnHome = false;
  DateTime? _lastSyncAt;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final config = await ClockConfigStore.load();
    final pinned = await WidgetPinService.isPinned(_kClockProviderName);
    if (!mounted) return;
    setState(() {
      _config = config;
      _pinnedOnHome = pinned;
      _lastSyncAt = ClockConfigStore.lastSyncAt;
    });
  }

  Future<void> _openConfig() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ClockConfigPage(initial: _config),
      ),
    );
    await _reload();
  }

  /// 一键添加到桌面（Android 8+ 系统弹窗确认）。
  Future<void> _requestPin() async {
    try {
      await WidgetPinService.requestPin(_kClockProviderName);
      // 弹窗确认后桌面注册有延迟，稍等再刷新状态
      await Future<void>.delayed(const Duration(seconds: 3));
      final pinned = await WidgetPinService.isPinned(_kClockProviderName);
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
      appBar: AppBar(title: const Text('数字时钟')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('已完成组件', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          WidgetEntryCard(
            icon: Icons.schedule,
            title: '数字时钟',
            subtitle: 'TextClock 驱动 · 零功耗走时 · 点击卡片配置样式',
            preview: ClockPreview(config: _config),
            pinned: _pinnedOnHome,
            lastSyncAt: _lastSyncAt,
            onTap: _openConfig,
            onPin: _requestPin,
          ),
        ],
      ),
    );
  }
}
