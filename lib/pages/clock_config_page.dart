import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/clock_config.dart';
import '../services/clock_config_store.dart';
import '../widgets/clock_preview.dart';

/// 数字时钟样式配置页 —— 背景 / 圆角 / 字号 / 内容开关 + 实时预览。
class ClockConfigPage extends StatefulWidget {
  const ClockConfigPage({super.key, required this.initial});

  final ClockConfig initial;

  @override
  State<ClockConfigPage> createState() => _ClockConfigPageState();
}

class _ClockConfigPageState extends State<ClockConfigPage> {
  late ClockConfig _config = widget.initial;
  late final TextEditingController _extraController = TextEditingController(
    text: widget.initial.extraText,
  );
  bool _saving = false;

  @override
  void dispose() {
    _extraController.dispose();
    super.dispose();
  }

  void _update(ClockConfig Function(ClockConfig) transform) {
    setState(() => _config = transform(_config));
  }

  /// 从相册选图并持久化到应用文档目录，作为时钟背景（cover 裁剪不拉伸）。
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
        (c) => c.copyWith(bgImagePath: path, bgStyle: ClockBgStyle.image),
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
    final bgDir = Directory('${docs.path}/clock_bg');
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
    _update((c) => c.copyWith(bgImagePath: '', bgStyle: ClockBgStyle.solid));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await ClockConfigStore.saveAndPush(_config);
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
      appBar: AppBar(title: const Text('数字时钟 · 样式配置')),
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
                  ClockPreview(config: _config),
                  const SizedBox(height: 8),
                  Text(
                    '与桌面组件同款排版，保存后推送到桌面',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle('背景样式'),
          SegmentedButton<ClockBgStyle>(
            segments: const [
              ButtonSegment(value: ClockBgStyle.solid, label: Text('纯色')),
              ButtonSegment(value: ClockBgStyle.gradient, label: Text('渐变')),
              ButtonSegment(value: ClockBgStyle.image, label: Text('图片')),
            ],
            selected: {_config.bgStyle},
            onSelectionChanged: (s) {
              final next = s.first;
              // 选"图片"但还没有图时直接拉起相册；已有图则直接切换
              if (next == ClockBgStyle.image && _config.bgImagePath.isEmpty) {
                _pickBackgroundImage();
              } else {
                _update((c) => c.copyWith(bgStyle: next));
              }
            },
          ),
          const SizedBox(height: 12),
          switch (_config.bgStyle) {
            ClockBgStyle.solid => _ColorPalette(
              palette: kSolidPalette,
              selected: _config.bgColor,
              onSelected: (v) => _update((c) => c.copyWith(bgColor: v)),
            ),
            ClockBgStyle.gradient => _GradientPalette(
              selected: _config.bgGradientIndex,
              onSelected: (v) => _update((c) => c.copyWith(bgGradientIndex: v)),
            ),
            ClockBgStyle.image => _ImagePickerRow(
              imagePath: _config.bgImagePath,
              onPick: _pickBackgroundImage,
              onRemove: _removeBackground,
            ),
          },
          const SizedBox(height: 20),
          _SectionTitle('文字颜色'),
          _ColorPalette(
            palette: kTextPalette,
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
          const SizedBox(height: 4),
          _SectionTitle('时间字号'),
          _LabeledSlider(
            label: '${_config.timeSizeSp}sp',
            value: _config.timeSizeSp.toDouble(),
            min: 24,
            max: 90,
            onChanged: (v) => _update((c) => c.copyWith(timeSizeSp: v.round())),
          ),
          const SizedBox(height: 12),
          _SectionTitle('对齐方式'),
          SegmentedButton<ClockTimeAlign>(
            segments: const [
              ButtonSegment(value: ClockTimeAlign.left, label: Text('居左')),
              ButtonSegment(value: ClockTimeAlign.center, label: Text('居中')),
            ],
            selected: {_config.timeAlign},
            onSelectionChanged: (s) =>
                _update((c) => c.copyWith(timeAlign: s.first)),
          ),
          const SizedBox(height: 12),
          _SectionTitle('内容开关'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('24 小时制'),
            value: _config.use24h,
            onChanged: (v) => _update((c) => c.copyWith(use24h: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('显示秒'),
            subtitle: const Text('关闭后桌面组件按分钟刷新，更省电'),
            value: _config.showSeconds,
            onChanged: (v) => _update((c) => c.copyWith(showSeconds: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('显示日期'),
            value: _config.showDate,
            onChanged: (v) => _update((c) => c.copyWith(showDate: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('显示星期'),
            value: _config.showWeekday,
            onChanged: (v) => _update((c) => c.copyWith(showWeekday: v)),
          ),
          const SizedBox(height: 12),
          _SectionTitle('附加文案'),
          TextField(
            controller: _extraController,
            maxLength: 30,
            decoration: const InputDecoration(
              hintText: '显示在日期下方，留空则隐藏',
              border: OutlineInputBorder(),
              isDense: true,
              counterText: '',
            ),
            onChanged: (v) => _update((c) => c.copyWith(extraText: v)),
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
          width: 52,
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

/// 渐变档位色板（与原生 bg_widget_gradient_<i>.xml 一一对应）。
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
