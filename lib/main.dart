import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'models/clock_config.dart';
import 'pages/clock_config_page.dart';
import 'root_bridge.dart';
import 'services/clock_config_store.dart';
import 'theme/app_theme.dart';
import 'widgets/clock_preview.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeskCraftApp());
}

/// M3 数字时钟组件在原生侧注册的 Provider 类名。
const _kClockProviderName = 'ClockWidgetProvider';

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

/// 组件工坊首页 —— 组件卡片列表：数字时钟（可配置）+ 规划中占位 + Root 数据源。
class WorkshopHomePage extends StatefulWidget {
  const WorkshopHomePage({super.key});

  @override
  State<WorkshopHomePage> createState() => _WorkshopHomePageState();
}

class _WorkshopHomePageState extends State<WorkshopHomePage> {
  ClockConfig _config = const ClockConfig();
  bool _pinnedOnHome = false;
  DateTime? _lastSyncAt;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final config = await ClockConfigStore.load();
    final pinned = await _isClockPinned();
    if (!mounted) return;
    setState(() {
      _config = config;
      _pinnedOnHome = pinned;
      _lastSyncAt = ClockConfigStore.lastSyncAt;
    });
  }

  Future<bool> _isClockPinned() async {
    try {
      final widgets = await HomeWidget.getInstalledWidgets();
      return widgets.any(
        (w) => w.androidClassName?.contains(_kClockProviderName) ?? false,
      );
    } catch (_) {
      return false; // 桌面不支持查询时降级显示"未检测"
    }
  }

  /// 一键添加到桌面（Android 8+ 系统弹窗确认）。
  Future<void> _requestPin() async {
    try {
      await HomeWidget.requestPinWidget(androidName: _kClockProviderName);
      await Future<void>.delayed(const Duration(seconds: 3));
      final pinned = await _isClockPinned();
      if (!mounted) return;
      setState(() => _pinnedOnHome = pinned);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前桌面不支持一键添加，请长按桌面 → 添加组件手动添加')),
      );
    }
  }

  Future<void> _openClockConfig() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ClockConfigPage(initial: _config),
      ),
    );
    await _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DeskCraft · 组件工坊')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ClockWidgetCard(
            config: _config,
            pinned: _pinnedOnHome,
            lastSyncAt: _lastSyncAt,
            onTap: _openClockConfig,
            onPin: _requestPin,
          ),
          const SizedBox(height: 16),
          const _PlannedWidgetCard(
            icon: Icons.thermostat,
            title: '环境监视器',
            subtitle: 'CPU 频率 · 温度 · 内存（Root 数据源已就绪，M4 上桌）',
          ),
          const SizedBox(height: 16),
          const _RootProbeCard(),
          const SizedBox(height: 16),
          Text(
            'M1：数字时钟上桌（TextClock 零功耗走秒）\n'
            'M2：libsu root 数据源验证（白名单只读命令）\n'
            'M3：组件卡片页 + 配置页 + 主题系统',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// 数字时钟组件卡片：实时预览 + 状态徽章，点击进入配置页。
class _ClockWidgetCard extends StatelessWidget {
  const _ClockWidgetCard({
    required this.config,
    required this.pinned,
    required this.lastSyncAt,
    required this.onTap,
    required this.onPin,
  });

  final ClockConfig config;
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
                  Icon(Icons.schedule, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    '数字时钟',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  _PinnedBadge(pinned: pinned),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'TextClock 驱动 · 零功耗走秒 · 点击卡片配置样式',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ClockPreview(config: config),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(syncLabel, style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
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

/// 规划中的组件占位卡。
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
            Icon(icon, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
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

/// Root 数据源验证卡片（M2）——进入页面自动探测一次。
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
                const Text(
                  'Root 数据源（M2）',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
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

class _PinnedBadge extends StatelessWidget {
  const _PinnedBadge({required this.pinned});

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
