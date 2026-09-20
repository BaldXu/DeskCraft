import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/clock_config.dart';

/// 桌面数字时钟的实时预览（首页卡片与配置页共用）。
///
/// 排版数值与原生 ClockWidgetProvider 严格对齐：
/// 2:1 宽高比（默认 4×2 格）、内边距 16/10、日期 13sp、附加 11sp；
/// 原生侧按 widget 实际尺寸相对 4×2 基准等比缩放，默认尺寸下观感一致。
class ClockPreview extends StatefulWidget {
  const ClockPreview({super.key, required this.config});

  final ClockConfig config;

  @override
  State<ClockPreview> createState() => _ClockPreviewState();
}

class _ClockPreviewState extends State<ClockPreview> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scheduleTicker();
  }

  @override
  void didUpdateWidget(covariant ClockPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.showSeconds != widget.config.showSeconds) {
      _scheduleTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 显示秒时按秒刷新；否则对齐下一个整分后按分钟刷新（与桌面 TextClock 一致）。
  void _scheduleTicker() {
    _ticker?.cancel();
    if (widget.config.showSeconds) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
      return;
    }
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _ticker = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    });
  }

  /// 与原生 TextClock 格式对齐：24h 为 HH:mm[:ss]，12h 为 上午 h:mm[:ss]。
  String get _timeText {
    final t = _now;
    final seconds = widget.config.showSeconds ? ':${_two(t.second)}' : '';
    if (widget.config.use24h) {
      final hh = t.hour.toString().padLeft(2, '0');
      return '$hh:${_two(t.minute)}$seconds';
    }
    final suffix = t.hour < 12 ? '上午' : '下午';
    var h = t.hour % 12;
    if (h == 0) h = 12;
    return '$suffix $h:${_two(t.minute)}$seconds';
  }

  /// 与原生 TextClock 对齐：日期用 M月d日，星期用 EEEE（星期X）。
  String get _dateText {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final parts = <String>[
      if (widget.config.showDate) '${_now.month}月${_now.day}日',
      if (widget.config.showWeekday) weekdays[_now.weekday - 1],
    ];
    return parts.join(' ');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 背景装饰：统一走 G2 连续曲率圆角；图片按 cover 裁剪不拉伸，
  /// 图片缺失时与原生一致回落到配置纯色。
  Decoration _backgroundDecoration(ClockConfig c) {
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(c.cornerRadiusDp.toDouble()),
    );
    if (c.bgStyle == ClockBgStyle.image) {
      final file = File(c.bgImagePath);
      if (c.bgImagePath.isNotEmpty && file.existsSync()) {
        return ShapeDecoration(
          shape: shape,
          image: DecorationImage(image: FileImage(file), fit: BoxFit.cover),
        );
      }
      return ShapeDecoration(shape: shape, color: Color(c.bgColor));
    }
    return c.previewDecoration;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    final color = Color(c.textColor);
    final dateText = _dateText;
    final extra = c.extraText.trim();
    final centered = c.timeAlign == ClockTimeAlign.center;

    return AspectRatio(
      aspectRatio: 2,
      child: Container(
        decoration: _backgroundDecoration(c),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        alignment: centered ? Alignment.center : Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: centered
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              _timeText,
              style: TextStyle(
                color: color,
                fontSize: c.timeSizeSp.toDouble(),
                height: 1.15,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (dateText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                dateText,
                style: TextStyle(
                  color: color.withValues(alpha: 0.78),
                  fontSize: 13,
                ),
              ),
            ],
            if (extra.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                extra,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color.withValues(alpha: 0.58),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
