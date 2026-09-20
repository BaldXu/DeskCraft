import 'package:flutter/material.dart';

import '../models/monitor_config.dart';
import '../root_bridge.dart';
import '../services/monitor_config_store.dart';
import '../services/widget_pin_service.dart';
import '../widgets/app_page_route.dart';
import '../widgets/monitor_preview.dart';
import '../widgets/widget_entry_cards.dart';
import 'monitor_config_page.dart';

/// 系统监控在原生侧注册的 Provider 类名。
const _kMonitorProviderName = 'MonitorWidgetProvider';

/// 系统监控类目页 —— 展示该类目下已完成的组件成品与数据源状态，
/// 点击成品卡进入配置页（第三层）。
class MonitorCollectionPage extends StatefulWidget {
  const MonitorCollectionPage({super.key});

  @override
  State<MonitorCollectionPage> createState() => _MonitorCollectionPageState();
}

class _MonitorCollectionPageState extends State<MonitorCollectionPage> {
  MonitorConfig _config = const MonitorConfig();
  bool _pinnedOnHome = false;
  DateTime? _lastSyncAt;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final config = await MonitorConfigStore.load();
    final pinned = await WidgetPinService.isPinned(_kMonitorProviderName);
    if (!mounted) return;
    setState(() {
      _config = config;
      _pinnedOnHome = pinned;
      _lastSyncAt = MonitorConfigStore.lastSyncAt;
    });
  }

  Future<void> _openConfig() async {
    await Navigator.of(context).push<bool>(
      AppPageRoute<bool>(builder: (_) => MonitorConfigPage(initial: _config)),
    );
    await _reload();
  }

  /// 一键添加到桌面（Android 8+ 系统弹窗确认）。
  Future<void> _requestPin() async {
    try {
      await WidgetPinService.requestPin(_kMonitorProviderName);
      // 弹窗确认后桌面注册有延迟，稍等再刷新状态
      await Future<void>.delayed(const Duration(seconds: 3));
      final pinned = await WidgetPinService.isPinned(_kMonitorProviderName);
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
      appBar: AppBar(title: const Text('系统监控')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('已完成组件', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          WidgetEntryCard(
            icon: Icons.thermostat,
            title: '系统监控',
            subtitle: '电池温度 · CPU · 内存 · 点击卡片配置样式',
            preview: MonitorPreview(config: _config),
            pinned: _pinnedOnHome,
            lastSyncAt: _lastSyncAt,
            onTap: _openConfig,
            onPin: _requestPin,
          ),
          const SizedBox(height: 16),
          Text('数据源', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          const _RootProbeCard(),
        ],
      ),
    );
  }
}

/// Root 数据源验证卡（M2）——监控组件的数据底座，进入页面自动探测一次。
class _RootProbeCard extends StatefulWidget {
  const _RootProbeCard();

  @override
  State<_RootProbeCard> createState() => _RootProbeCardState();
}

class _RootProbeCardState extends State<_RootProbeCard> {
  RootProbe? _probe;
  bool _probing = false;
  bool _isCollapsed = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_probing) return;
    setState(() => _probing = true);
    final result = await RootBridge.probe();
    if (!mounted) return;
    setState(() {
      _probe = result;
      _probing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final probe = _probe;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.memory, color: scheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Root 数据源（M2）',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    // 标题受限换行，避免右侧徽章/按钮被挤出溢出
                    softWrap: true,
                  ),
                ),
                if (probe != null) _RootBadge(probe: probe),
                IconButton(
                  onPressed: _probing ? null : _refresh,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
                IconButton(
                  onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
                  icon: Icon(
                    _isCollapsed ? Icons.expand_more : Icons.expand_less,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'libsu · 白名单只读命令 · 读 sysfs 温度 / CPU 频率',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _isCollapsed
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 24),
                  if (_probing && probe == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('探测中…（首次会触发 Magisk 授权弹窗，请选择允许）'),
                    )
                  else if (probe == null)
                    const Text('尚未探测')
                  else
                    _RootProbeBody(probe: probe),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RootProbeBody extends StatelessWidget {
  const _RootProbeBody({required this.probe});

  final RootProbe probe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bodySmall = Theme.of(context).textTheme.bodySmall;

    if (!probe.rooted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          probe.error ?? '未获取 root 授权',
          style: TextStyle(color: scheme.error, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CPU 实时频率（${probe.cpuFreqsKHz.length} 核）', style: bodySmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < probe.cpuFreqsKHz.length; i++)
              _MiniChip(label: 'C$i ${_fmtMhz(probe.cpuFreqsKHz[i])}'),
          ],
        ),
        const SizedBox(height: 14),
        Text('热区温度（${probe.thermalZones.length} 个）', style: bodySmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final z in probe.thermalZones)
              _MiniChip(label: '${z.type} ${z.celsius.toStringAsFixed(1)}℃'),
          ],
        ),
        const SizedBox(height: 14),
        if (probe.memInfoKb.containsKey('MemTotal'))
          Text(
            '内存：可用 ${((probe.memInfoKb['MemAvailable'] ?? 0) / 1048576).toStringAsFixed(2)} GB / '
            '共 ${((probe.memInfoKb['MemTotal'] ?? 0) / 1048576).toStringAsFixed(2)} GB',
            style: bodySmall,
          ),
        if (probe.tookMs != null)
          Text('探测耗时 ${probe.tookMs}ms', style: bodySmall),
      ],
    );
  }

  String _fmtMhz(int kHz) =>
      kHz >= 1000 ? '${(kHz / 1000).round()}MHz' : '${kHz}kHz';
}

class _RootBadge extends StatelessWidget {
  const _RootBadge({required this.probe});

  final RootProbe probe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = probe.rooted
        ? ('已授权', scheme.primary)
        : ('无 root', scheme.error);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}
