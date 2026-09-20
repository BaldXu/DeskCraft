import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'root_bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeskCraftApp());
}

/// M1 数字时钟组件在原生侧注册的 Provider 类名。
const _kClockProviderName = 'ClockWidgetProvider';

/// 数字时钟副标题在 SharedPreferences 的 key（原生侧同款）。
const _kClockExtraTextKey = 'clock_extra_text';

class DeskCraftApp extends StatelessWidget {
  const DeskCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeskCraft',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C8CF8),
      ),
      home: const WorkshopHomePage(),
    );
  }
}

/// 组件工坊首页 —— M1 骨架：数字时钟卡片 + 数据桥验证。
class WorkshopHomePage extends StatefulWidget {
  const WorkshopHomePage({super.key});

  @override
  State<WorkshopHomePage> createState() => _WorkshopHomePageState();
}

class _WorkshopHomePageState extends State<WorkshopHomePage> {
  final _extraController = TextEditingController();

  bool _pinnedOnHome = false;
  DateTime? _lastSyncAt;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _extraController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final saved = await HomeWidget.getWidgetData<String>(_kClockExtraTextKey);
    final pinned = await _isClockPinned();
    if (!mounted) return;
    if (saved != null) _extraController.text = saved;
    setState(() => _pinnedOnHome = pinned);
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

  /// 数据桥验证：saveWidgetData → updateWidget → 桌面组件文本变化。
  Future<void> _syncToHome() async {
    setState(() {
      _lastError = null;
    });
    try {
      await HomeWidget.saveWidgetData<String>(
        _kClockExtraTextKey,
        _extraController.text.trim(),
      );
      final ok = await HomeWidget.updateWidget(
        androidName: _kClockProviderName,
      );
      if (!mounted) return;
      if (ok == true) {
        setState(() => _lastSyncAt = DateTime.now());
        _showSnackBar('已推送到桌面组件');
      } else {
        _showSnackBar('推送失败：updateWidget 返回 false');
      }
    } catch (e) {
      setState(() => _lastError = e.toString());
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
      _showSnackBar('当前桌面不支持一键添加，请长按桌面 → 添加组件手动添加');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('DeskCraft · 组件工坊')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
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
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      _PinnedBadge(pinned: _pinnedOnHome),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'TextClock 驱动 · 零功耗走秒 · M1 全链路验证组件',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Divider(height: 24),
                  TextField(
                    controller: _extraController,
                    decoration: const InputDecoration(
                      labelText: '组件副标题（数据桥验证）',
                      hintText: '输入内容后点"保存并更新到桌面"',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _syncToHome,
                        icon: const Icon(Icons.sync, size: 18),
                        label: const Text('保存并更新到桌面'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _requestPin,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('添加到桌面'),
                      ),
                    ],
                  ),
                  if (_lastSyncAt != null)
                    Text(
                      '最后刷新：${_lastSyncAt!.toIso8601String().substring(11, 19)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (_lastError != null)
                    Text(
                      '最近错误：$_lastError',
                      style: TextStyle(color: scheme.error, fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _RootProbeCard(),
          const SizedBox(height: 16),
          Text(
            'M1：Flutter 工程 + home_widget 接通 + 数字时钟上桌\n'
            'M2：libsu root 数据源验证（白名单只读命令）\n'
            '时钟链路：桌面添加 → 更新 → 点击（点组件跳回本 App）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'libsu · 白名单只读命令 · 读 sysfs 温度 / CPU 频率',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
