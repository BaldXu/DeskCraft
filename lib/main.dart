import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

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
      final ok = await HomeWidget.updateWidget(androidName: _kClockProviderName);
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
                      const Text('数字时钟', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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
          Text(
            'M1 里程碑：Flutter 工程 + home_widget 接通 + 数字时钟上桌\n'
            '验证链路：桌面添加 → 更新 → 点击（点组件跳回本 App）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
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
