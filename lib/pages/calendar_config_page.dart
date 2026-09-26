import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/calendar_config.dart';
import '../services/calendar_bridge.dart';
import '../services/calendar_config_store.dart';
import '../widgets/calendar_preview.dart';

/// 日历样式配置页 —— 背景 / 文字 / 内容开关 / 今天高亮 + 实时预览 + 日历权限。
class CalendarConfigPage extends StatefulWidget {
  const CalendarConfigPage({super.key, required this.initial});

  final CalendarConfig initial;

  @override
  State<CalendarConfigPage> createState() => _CalendarConfigPageState();
}

class _CalendarConfigPageState extends State<CalendarConfigPage> {
  late CalendarConfig _config = widget.initial;
  bool _saving = false;
  bool? _calendarPermission;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final ok = await CalendarBridge.checkPermission();
    if (!mounted) return;
    setState(() => _calendarPermission = ok);
  }

  void _update(CalendarConfig Function(CalendarConfig) transform) {
    setState(() => _config = transform(_config));
  }

  /// 从相册选图并持久化到应用文档目录，作为日历背景（cover 裁剪不拉伸）。
  Future<void> _pickBackgroundImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 2048,
      );
      if (picked == null) return;
      final path = await _persistBackground(picked);
      if (!mounted) return;
      _update(
        (c) => c.copyWith(bgImagePath: path, bgStyle: CalendarBgStyle.image),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('选择图片失败，请重试')));
    }
  }

  Future<String> _persistBackground(XFile picked) async {
    final docs = await getApplicationDocumentsDirectory();
    final bgDir = Directory('${docs.path}/calendar_bg');
    if (!bgDir.existsSync()) bgDir.createSync(recursive: true);
    final ext = picked.name.contains('.')
        ? picked.name.substring(picked.name.lastIndexOf('.')).toLowerCase()
        : '.jpg';
    final target =
        '${bgDir.path}/bg_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(picked.path).copy(target);
    final old = _config.bgImagePath;
    if (old.startsWith(bgDir.path)) {
      try {
        File(old).deleteSync();
      } catch (_) {}
    }
    return target;
  }

  void _removeBackground() {
    final old = _config.bgImagePath;
    if (old.isNotEmpty) {
      try {
        final file = File(old);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    _update((c) => c.copyWith(bgImagePath: '', bgStyle: CalendarBgStyle.solid));
  }

  /// 授予日历权限（系统弹窗）；被拒后引导跳设置页。
  Future<void> _grantCalendar() async {
    var ok = await CalendarBridge.requestPermission();
    if (!ok) {
      // 请求失败（通常是被拒且勾选了不再询问）→ 跳设置页
      await CalendarBridge.openCalendarSettings();
      ok = await CalendarBridge.checkPermission();
    }
    if (!mounted) return;
    setState(() => _calendarPermission = ok);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(ok ? '已授予日历权限' : '仍未授予，桌面组件将只显示农历与节气')),
      );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await CalendarConfigStore.saveAndPush(_config);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(ok ? '已保存并更新到桌面组件' : '推送失败：桌面组件未响应（请确认组件已添加到桌面）'),
        ),
      );
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('日历 · 样式配置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('实时预览', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  CalendarPreview(config: _config),
                  const SizedBox(height: 8),
                  Text(
                    '与桌面组件同款渲染，保存后推送到桌面',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle('背景样式'),
          SegmentedButton<CalendarBgStyle>(
            segments: const [
              ButtonSegment(value: CalendarBgStyle.solid, label: Text('纯色')),
              ButtonSegment(value: CalendarBgStyle.gradient, label: Text('渐变')),
              ButtonSegment(value: CalendarBgStyle.image, label: Text('图片')),
            ],
            selected: {_config.bgStyle},
            onSelectionChanged: (s) {
              final next = s.first;
              if (next == CalendarBgStyle.image && _config.bgImagePath.isEmpty) {
                _pickBackgroundImage();
              } else {
                _update((c) => c.copyWith(bgStyle: next));
              }
            },
          ),
          const SizedBox(height: 12),
          switch (_config.bgStyle) {
            CalendarBgStyle.solid => _ColorPalette(
              palette: kCalendarSolidPalette,
              selected: _config.bgColor,
              onSelected: (v) => _update((c) => c.copyWith(bgColor: v)),
            ),
            CalendarBgStyle.gradient => _GradientPalette(
              selected: _config.bgGradientIndex,
              onSelected: (v) => _update((c) => c.copyWith(bgGradientIndex: v)),
            ),
            CalendarBgStyle.image => _ImagePickerRow(
              imagePath: _config.bgImagePath,
              onPick: _pickBackgroundImage,
              onRemove: _removeBackground,
            ),
          },
          const SizedBox(height: 20),
          _SectionTitle('文字颜色'),
          _ColorPalette(
            palette: kCalendarTextPalette,
            selected: _config.textColor,
            onSelected: (v) => _update((c) => c.copyWith(textColor: v)),
          ),
          const SizedBox(height: 20),
          _SectionTitle('圆角'),
          _LabeledSlider(
            label: '${_config.cornerRadiusDp}dp',
            value: _config.cornerRadiusDp.toDouble(),
            min: 0,
            max: 120,
            onChanged: (v) =>
                _update((c) => c.copyWith(cornerRadiusDp: v.round())),
          ),
          const SizedBox(height: 12),
          _SectionTitle('显示内容'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('年月头部'),
            value: _config.showHeader,
            onChanged: (v) => _update((c) => c.copyWith(showHeader: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('星期行'),
            value: _config.showWeekdayHeader,
            onChanged: (v) => _update((c) => c.copyWith(showWeekdayHeader: v)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('一周从哪天开始'),
            trailing: SegmentedButton<CalendarFirstDay>(
              segments: const [
                ButtonSegment(value: CalendarFirstDay.monday, label: Text('周一')),
                ButtonSegment(value: CalendarFirstDay.sunday, label: Text('周日')),
              ],
              selected: {_config.firstDayOfWeek},
              onSelectionChanged: (s) =>
                  _update((c) => c.copyWith(firstDayOfWeek: s.first)),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('农历'),
            subtitle: const Text('每格显示初一/十五等'),
            value: _config.showLunar,
            onChanged: (v) => _update((c) => c.copyWith(showLunar: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('节气'),
            subtitle: const Text('立春/秋分等 24 节气'),
            value: _config.showSolarTerm,
            onChanged: (v) => _update((c) => c.copyWith(showSolarTerm: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('系统日历事件'),
            subtitle: const Text('节日/纪念日，需「日历」读取权限'),
            value: _config.showCalendarEvents,
            onChanged: (v) => _update((c) => c.copyWith(showCalendarEvents: v)),
          ),
          if (_config.showCalendarEvents) ..._permissionSection(scheme),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('前后月补位日'),
            subtitle: const Text('关闭后非本月日期留空'),
            value: _config.showAdjacentDays,
            onChanged: (v) => _update((c) => c.copyWith(showAdjacentDays: v)),
          ),
          const SizedBox(height: 12),
          _SectionTitle('今天高亮'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('高亮今天'),
            value: _config.highlightToday,
            onChanged: (v) => _update((c) => c.copyWith(highlightToday: v)),
          ),
          if (_config.highlightToday) ...[
            _ColorPalette(
              palette: kCalendarAccentPalette,
              selected: _config.highlightColor,
              onSelected: (v) => _update((c) => c.copyWith(highlightColor: v)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<CalendarHighlightShape>(
                    segments: const [
                      ButtonSegment(
                        value: CalendarHighlightShape.circle,
                        label: Text('圆形'),
                      ),
                      ButtonSegment(
                        value: CalendarHighlightShape.roundedRect,
                        label: Text('圆角方'),
                      ),
                    ],
                    selected: {_config.highlightShape},
                    onSelectionChanged: (s) => _update(
                      (c) => c.copyWith(highlightShape: s.first),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<CalendarHighlightStyle>(
                    segments: const [
                      ButtonSegment(
                        value: CalendarHighlightStyle.filled,
                        label: Text('实心'),
                      ),
                      ButtonSegment(
                        value: CalendarHighlightStyle.outline,
                        label: Text('描边'),
                      ),
                    ],
                    selected: {_config.highlightStyle},
                    onSelectionChanged: (s) => _update(
                      (c) => c.copyWith(highlightStyle: s.first),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _SectionTitle('周末'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('周末染色'),
            value: _config.showWeekend,
            onChanged: (v) => _update((c) => c.copyWith(showWeekend: v)),
          ),
          if (_config.showWeekend)
            _ColorPalette(
              palette: kCalendarAccentPalette,
              selected: _config.weekendColor,
              onSelected: (v) => _update((c) => c.copyWith(weekendColor: v)),
            ),
          const SizedBox(height: 12),
          _SectionTitle('字号'),
          _LabeledSlider(
            label: '${_config.dayFontSize}',
            value: _config.dayFontSize.toDouble(),
            min: 10,
            max: 20,
            onChanged: (v) =>
                _update((c) => c.copyWith(dayFontSize: v.round())),
          ),
          _LabeledSlider(
            label: '${_config.subFontSize}',
            value: _config.subFontSize.toDouble(),
            min: 7,
            max: 13,
            onChanged: (v) =>
                _update((c) => c.copyWith(subFontSize: v.round())),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined, size: 18),
            label: Text(_saving ? '正在推送…' : '保存并更新到桌面'),
          ),
          const SizedBox(height: 8),
          Text(
            '保存会同时写入本机配置与桌面组件数据，桌面端立即刷新',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 日历读取权限状态区（开启系统日历事件时展示）。
  List<Widget> _permissionSection(ColorScheme scheme) {
    final state = _calendarPermission;
    return [
      Card(
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                state == true ? Icons.check_circle : Icons.shield_outlined,
                size: 20,
                color: state == true
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state == true
                      ? '已授权：将显示系统日历中的节日/纪念日事件'
                      : '未授权：桌面组件将只显示农历与节气',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: state == true ? null : _grantCalendar,
                child: Text(state == true ? '已授权' : '去授权'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            label,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _ColorPalette extends StatelessWidget {
  const _ColorPalette({
    required this.palette,
    required this.selected,
    required this.onSelected,
  });

  final List<int> palette;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final value in palette)
          _Swatch(
            selected: value == selected,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(value),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
            onTap: () => onSelected(value),
          ),
      ],
    );
  }
}

class _ImagePickerRow extends StatelessWidget {
  const _ImagePickerRow({
    required this.imagePath,
    required this.onPick,
    required this.onRemove,
  });

  final String imagePath;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = imagePath.isNotEmpty;
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          ),
          child: hasImage
              ? Image.file(File(imagePath), fit: BoxFit.cover)
              : Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '按 cover 居中裁剪，不拉伸变形',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onPick,
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: Text(hasImage ? '更换图片' : '选择图片'),
                  ),
                  if (hasImage) ...[
                    const SizedBox(width: 8),
                    TextButton(onPressed: onRemove, child: const Text('移除')),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GradientPalette extends StatelessWidget {
  const _GradientPalette({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < kCalendarGradients.length; i++)
          _Swatch(
            size: 56,
            selected: i == selected,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    for (final c in kCalendarGradients[i]) Color(c),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            onTap: () => onSelected(i),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.selected,
    required this.child,
    required this.onTap,
    this.size = 40,
  });

  final bool selected;
  final Widget child;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(child: child),
            if (selected)
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surface.withValues(alpha: 0.55),
                ),
                child: Icon(
                  Icons.check,
                  size: size * 0.45,
                  color: scheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
