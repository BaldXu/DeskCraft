import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/clock_config.dart';
import '../models/monitor_config.dart';
import '../services/monitor_config_store.dart';
import '../widgets/monitor_preview.dart';

/// 系统监控样式配置页 —— 背景 / 圆角 / 文字 / 刷新间隔 / 高温警示 / 显示项 + 实时预览。
class MonitorConfigPage extends StatefulWidget {
  const MonitorConfigPage({super.key, required this.initial});

  final MonitorConfig initial;

  @override
  State<MonitorConfigPage> createState() => _MonitorConfigPageState();
}

class _MonitorConfigPageState extends State<MonitorConfigPage> {
  late MonitorConfig _config = widget.initial;
  bool _saving = false;

  void _update(MonitorConfig Function(MonitorConfig) transform) {
    setState(() => _config = transform(_config));
  }

  /// 从相册选图并持久化到应用文档目录，作为监控背景（cover 裁剪不拉伸）。
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
        (c) => c.copyWith(bgImagePath: path, bgStyle: MonitorBgStyle.image),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('选择图片失败，请重试')));
    }
  }

  /// 把选中的图片复制到应用文档目录（相册临时路径可能被系统清理），返回持久路径。
  Future<String> _persistBackground(XFile picked) async {
    final docs = await getApplicationDocumentsDirectory();
    final bgDir = Directory('${docs.path}/monitor_bg');
    if (!bgDir.existsSync()) bgDir.createSync(recursive: true);
    final ext = picked.name.contains('.')
        ? picked.name.substring(picked.name.lastIndexOf('.')).toLowerCase()
        : '.jpg';
    final target =
        '${bgDir.path}/bg_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(picked.path).copy(target);
    // 清理被替换的旧背景图
    final old = _config.bgImagePath;
    if (old.startsWith(bgDir.path)) {
      try {
        File(old).deleteSync();
      } catch (_) {}
    }
    return target;
  }

  /// 移除自定义背景：删除图片文件并回落到纯色样式。
  void _removeBackground() {
    final old = _config.bgImagePath;
    if (old.isNotEmpty) {
      try {
        final file = File(old);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    _update((c) => c.copyWith(bgImagePath: '', bgStyle: MonitorBgStyle.solid));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await MonitorConfigStore.saveAndPush(_config);
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
      appBar: AppBar(title: const Text('系统监控 · 样式配置')),
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
                  MonitorPreview(config: _config),
                  const SizedBox(height: 8),
                  Text(
                    '与桌面组件同款排版（采样数据为模拟值），保存后推送到桌面',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle('背景样式'),
          SegmentedButton<MonitorBgStyle>(
            segments: const [
              ButtonSegment(value: MonitorBgStyle.solid, label: Text('纯色')),
              ButtonSegment(value: MonitorBgStyle.gradient, label: Text('渐变')),
              ButtonSegment(value: MonitorBgStyle.image, label: Text('图片')),
            ],
            selected: {_config.bgStyle},
            onSelectionChanged: (s) {
              final next = s.first;
              // 选"图片"但还没有图时直接拉起相册；已有图则直接切换
              if (next == MonitorBgStyle.image && _config.bgImagePath.isEmpty) {
                _pickBackgroundImage();
              } else {
                _update((c) => c.copyWith(bgStyle: next));
              }
            },
          ),
          const SizedBox(height: 12),
          switch (_config.bgStyle) {
            MonitorBgStyle.solid => _ColorPalette(
              palette: kSolidPalette,
              selected: _config.bgColor,
              onSelected: (v) => _update((c) => c.copyWith(bgColor: v)),
            ),
            MonitorBgStyle.gradient => _GradientPalette(
              selected: _config.bgGradientIndex,
              onSelected: (v) => _update((c) => c.copyWith(bgGradientIndex: v)),
            ),
            MonitorBgStyle.image => _ImagePickerRow(
              imagePath: _config.bgImagePath,
              onPick: _pickBackgroundImage,
              onRemove: _removeBackground,
            ),
          },
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
          const SizedBox(height: 20),
          _SectionTitle('文字颜色'),
          _ColorPalette(
            palette: kTextPalette,
            selected: _config.textColor,
            onSelected: (v) => _update((c) => c.copyWith(textColor: v)),
          ),
          const SizedBox(height: 12),
          _SectionTitle('对齐方式'),
          SegmentedButton<MonitorAlign>(
            segments: const [
              ButtonSegment(value: MonitorAlign.left, label: Text('居左')),
              ButtonSegment(value: MonitorAlign.center, label: Text('居中')),
            ],
            selected: {_config.align},
            onSelectionChanged: (s) =>
                _update((c) => c.copyWith(align: s.first)),
          ),
          const SizedBox(height: 12),
          _SectionTitle('刷新间隔'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 30, label: Text('30秒')),
              ButtonSegment(value: 60, label: Text('1分钟')),
              ButtonSegment(value: 300, label: Text('5分钟')),
            ],
            selected: {_config.refreshIntervalSeconds},
            onSelectionChanged: (s) =>
                _update((c) => c.copyWith(refreshIntervalSeconds: s.first)),
          ),
          const SizedBox(height: 6),
          Text(
            '桌面组件按此间隔定时采样刷新（间隔越长越省电）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _SectionTitle('高温警示阈值'),
          _LabeledSlider(
            label: '≥${_config.highTempThresholdC.toStringAsFixed(1)}°C 变红',
            value: _config.highTempThresholdC,
            min: 40,
            max: 55,
            divisions: 30, // 步进 0.5°C
            labelWidth: 96,
            onChanged: (v) => _update((c) => c.copyWith(highTempThresholdC: v)),
          ),
          const SizedBox(height: 6),
          Text(
            '预览模拟温度 42.5°C，把阈值调到 42.5°C 以下即可预览变红效果',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _SectionTitle('显示项'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('电池温度'),
            value: _config.showBatteryTemp,
            onChanged: (v) => _update((c) => c.copyWith(showBatteryTemp: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('CPU 占用与频率'),
            value: _config.showCpu,
            onChanged: (v) => _update((c) => c.copyWith(showCpu: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('内存占用'),
            value: _config.showMem,
            onChanged: (v) => _update((c) => c.copyWith(showMem: v)),
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
    this.divisions,
    this.labelWidth = 52,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// 刻度档数；缺省按 1 为步长（与数字时钟配置页一致），传 30 可实现 0.5 步进。
  final int? divisions;

  /// 右侧标签列宽度（高温阈值标签较长，需加宽）。
  final double labelWidth;

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
            divisions: divisions ?? (max - min).round(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: labelWidth,
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

/// 纯色色板（背景 / 文字共用）。
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

/// 图片背景选择行：缩略图 + 选图 / 移除按钮。
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

/// 渐变档位色板（与数字时钟共用同一套 kGradients，原生 bg_widget_gradient_<i>.xml 一一对应）。
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
        for (var i = 0; i < kGradients.length; i++)
          _Swatch(
            size: 56,
            selected: i == selected,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: kGradients[i].$1,
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
