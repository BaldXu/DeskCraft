import 'dart:io';

import 'package:flutter/material.dart';

import '../models/monitor_config.dart';

/// 桌面系统监控的实时预览（首页卡片与配置页共用）。
///
/// 排版数值与原生 monitor_widget.xml / MonitorWidgetProvider 严格对齐：
/// 2:1 宽高比（默认 4×2 格）、内边距 16/10、温度主行 17sp（w500）、
/// CPU / 内存行 13sp（secondary = 文字色 78% 不透明度）；
/// 采样数据为固定模拟值，温度行颜色随高温阈值联动（≥阈值变红）。
class MonitorPreview extends StatelessWidget {
  const MonitorPreview({super.key, required this.config});

  final MonitorConfig config;

  // 预览模拟采样数据（字段与原生 MonitorDataSource 快照一一对应）。
  static const double _mockBatteryTempC = 42.5;
  static const int _mockCpuUsagePercent = 35;
  static const double _mockCpuFreqMaxGhz = 2.84;
  static const double _mockCpuFreqMinGhz = 1.02;
  static const int _mockMemUsagePercent = 62;

  /// 与原生 WARN_COLOR 一致的高温警示色。
  static const Color _warnColor = Color(0xFFFF5252);

  /// 背景装饰：统一走 G2 连续曲率圆角；图片按 cover 裁剪不拉伸，
  /// 图片缺失时与原生一致回落到配置纯色。
  Decoration _backgroundDecoration(MonitorConfig c) {
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(c.cornerRadiusDp.toDouble()),
    );
    if (c.bgStyle == MonitorBgStyle.image) {
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
    final c = config;
    final color = Color(c.textColor);
    final centered = c.align == MonitorAlign.center;
    final tempHot = _mockBatteryTempC >= c.highTempThresholdC;
    final cpuText =
        'CPU $_mockCpuUsagePercent% · $_mockCpuFreqMaxGhz/${_mockCpuFreqMinGhz}GHz';

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
            if (c.showBatteryTemp)
              Text(
                '电池 ${_mockBatteryTempC.toStringAsFixed(1)}°C',
                style: TextStyle(
                  color: tempHot ? _warnColor : color,
                  fontSize: 17,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            if (c.showCpu) ...[
              const SizedBox(height: 2),
              Text(
                cpuText,
                style: TextStyle(
                  color: color.withValues(alpha: 0.78),
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            if (c.showMem) ...[
              const SizedBox(height: 2),
              Text(
                '内存 $_mockMemUsagePercent%',
                style: TextStyle(
                  color: color.withValues(alpha: 0.78),
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
