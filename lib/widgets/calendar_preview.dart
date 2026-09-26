import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../calendar/calendar_data.dart';
import '../calendar/calendar_painter.dart';
import '../models/calendar_config.dart';
import '../services/calendar_bridge.dart';

/// 日历组件实时预览（首页卡片与配置页共用）。
///
/// 与桌面渲染使用同一 [CalendarPainter]（CustomPaint 预览 / PictureRecorder 出图），
/// 严格所见即所得。预览还会按权限实时查询系统日历事件并注入网格。
/// 尺寸按 4×4 基准（250:220）等比展示，与桌面默认尺寸观感一致。
class CalendarPreview extends StatefulWidget {
  const CalendarPreview({super.key, required this.config});

  final CalendarConfig config;

  @override
  State<CalendarPreview> createState() => _CalendarPreviewState();
}

class _CalendarPreviewState extends State<CalendarPreview> {
  DateTime _now = DateTime.now();
  Map<String, List<String>> _events = const {};
  ui.Image? _bgImage;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reload();
    _scheduleMidnight();
  }

  @override
  void didUpdateWidget(covariant CalendarPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) _reload();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bgImage?.dispose();
    super.dispose();
  }

  /// 对齐下一个整月（含午夜翻日 + 事件/背景刷新）。
  void _scheduleMidnight() {
    _timer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1, 1);
    _timer = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _reload();
      _scheduleMidnight();
    });
  }

  Future<void> _reload() async {
    final cfg = widget.config;
    // 事件：仅在开启 + 有权限时查询
    if (cfg.showCalendarEvents) {
      final ok = await CalendarBridge.checkPermission();
      if (ok) {
        final events = await CalendarBridge.queryMonthEvents(
          _now.year,
          _now.month,
        );
        if (!mounted) return;
        _events = events;
      }
    }
    // 背景图片：style 为 image 且路径有效时解码
    if (cfg.bgStyle == CalendarBgStyle.image && cfg.bgImagePath.isNotEmpty) {
      final img = await loadBackgroundImage(cfg.bgImagePath);
      if (!mounted) return;
      _bgImage?.dispose();
      _bgImage = img;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final grid = attachEvents(buildMonthGrid(_now, widget.config), _events);
    return AspectRatio(
      aspectRatio: 250 / 220,
      child: CustomPaint(
        painter: _CalendarPainterDelegate(
          CalendarPainter(
            config: widget.config,
            grid: grid,
            backgroundImage: _bgImage,
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _CalendarPainterDelegate extends CustomPainter {
  const _CalendarPainterDelegate(this.painter);

  final CalendarPainter painter;

  @override
  void paint(Canvas canvas, Size size) => painter.paint(canvas, size);

  @override
  bool shouldRepaint(covariant _CalendarPainterDelegate oldDelegate) => true;
}
