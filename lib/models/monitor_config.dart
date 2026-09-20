import 'dart:convert';

import 'package:flutter/material.dart';

import 'clock_config.dart';

/// 系统监控组件配置（M4）。
///
/// 序列化为 JSON 后经由 home_widget 的 saveWidgetData 写入
/// SharedPreferences key monitor_config_json（见 monitor_config_store.dart），
/// 原生 MonitorWidgetProvider 读取同一份 JSON 渲染 RemoteViews。
/// JSON key 与原生 MonitorNativeConfig.from 逐字段对齐，勿改名。
class MonitorConfig {
  const MonitorConfig({
    this.textColor = 0xFFFFFFFF,
    this.bgStyle = MonitorBgStyle.solid,
    this.bgColor = 0xE61C1C22,
    this.bgGradientIndex = 0,
    this.bgImagePath = '',
    this.cornerRadiusDp = 22,
    this.align = MonitorAlign.left,
    this.refreshIntervalSeconds = 60,
    this.highTempThresholdC = 45.0,
    this.showBatteryTemp = true,
    this.showCpu = true,
    this.showMem = true,
  });

  factory MonitorConfig.fromJson(Map<String, dynamic> json) => MonitorConfig(
    textColor: (json['textColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
    bgStyle: MonitorBgStyle.values.firstWhere(
      (s) => s.name == json['bgStyle'],
      orElse: () => MonitorBgStyle.solid,
    ),
    bgColor: (json['bgColor'] as num?)?.toInt() ?? 0xE61C1C22,
    bgGradientIndex: (json['bgGradientIndex'] as num?)?.toInt() ?? 0,
    bgImagePath: json['bgImagePath'] as String? ?? '',
    cornerRadiusDp: (json['cornerRadiusDp'] as num?)?.toInt() ?? 22,
    align: MonitorAlign.values.firstWhere(
      (a) => a.name == json['align'],
      orElse: () => MonitorAlign.left,
    ),
    refreshIntervalSeconds:
        (json['refreshIntervalSeconds'] as num?)?.toInt() ?? 60,
    highTempThresholdC: (json['highTempThresholdC'] as num?)?.toDouble() ?? 45.0,
    showBatteryTemp: json['showBatteryTemp'] as bool? ?? true,
    showCpu: json['showCpu'] as bool? ?? true,
    showMem: json['showMem'] as bool? ?? true,
  );

  /// 从 widget 桥同步过来的原始 JSON 解析（失败返回默认配置）。
  factory MonitorConfig.fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return const MonitorConfig();
    try {
      return MonitorConfig.fromJson(
        (jsonDecode(raw) as Map<dynamic, dynamic>).cast<String, dynamic>(),
      );
    } catch (_) {
      return const MonitorConfig();
    }
  }

  final int textColor;
  final MonitorBgStyle bgStyle;
  final int bgColor;

  /// [kGradients] 的下标（渐变档位与数字时钟复用同一套）。
  final int bgGradientIndex;

  /// 背景图片的本地绝对路径（bgStyle == image 时生效）。
  final String bgImagePath;
  final int cornerRadiusDp;

  /// 内容块的水平对齐方式（电池温度 + CPU + 内存整体）。
  final MonitorAlign align;

  /// 桌面端定时采样间隔（秒），原生 AlarmManager 按此调度。
  final int refreshIntervalSeconds;

  /// 高温警示阈值（°C），电池温度 ≥ 该值时温度行变红。
  final double highTempThresholdC;
  final bool showBatteryTemp;
  final bool showCpu;
  final bool showMem;

  Map<String, dynamic> toJson() => {
    'textColor': textColor,
    'bgStyle': bgStyle.name,
    'bgColor': bgColor,
    'bgGradientIndex': bgGradientIndex,
    'bgImagePath': bgImagePath,
    'cornerRadiusDp': cornerRadiusDp,
    'align': align.name,
    'refreshIntervalSeconds': refreshIntervalSeconds,
    'highTempThresholdC': highTempThresholdC,
    'showBatteryTemp': showBatteryTemp,
    'showCpu': showCpu,
    'showMem': showMem,
  };

  MonitorConfig copyWith({
    int? textColor,
    MonitorBgStyle? bgStyle,
    int? bgColor,
    int? bgGradientIndex,
    String? bgImagePath,
    int? cornerRadiusDp,
    MonitorAlign? align,
    int? refreshIntervalSeconds,
    double? highTempThresholdC,
    bool? showBatteryTemp,
    bool? showCpu,
    bool? showMem,
  }) => MonitorConfig(
    textColor: textColor ?? this.textColor,
    bgStyle: bgStyle ?? this.bgStyle,
    bgColor: bgColor ?? this.bgColor,
    bgGradientIndex: bgGradientIndex ?? this.bgGradientIndex,
    bgImagePath: bgImagePath ?? this.bgImagePath,
    cornerRadiusDp: cornerRadiusDp ?? this.cornerRadiusDp,
    align: align ?? this.align,
    refreshIntervalSeconds: refreshIntervalSeconds ?? this.refreshIntervalSeconds,
    highTempThresholdC: highTempThresholdC ?? this.highTempThresholdC,
    showBatteryTemp: showBatteryTemp ?? this.showBatteryTemp,
    showCpu: showCpu ?? this.showCpu,
    showMem: showMem ?? this.showMem,
  );

  /// 当前背景在预览中的装饰（纯色或渐变）。
  /// 预览背景装饰：G2 连续曲率圆角（ContinuousRectangleBorder，曲率在
  /// 直线衔接处为 0），与原生 smoothCornerPath 同一算法，观感一致。
  Decoration get previewDecoration => ShapeDecoration(
    shape: ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(cornerRadiusDp.toDouble()),
    ),
    color: bgStyle == MonitorBgStyle.solid ? Color(bgColor) : null,
    gradient: bgStyle == MonitorBgStyle.gradient
        ? kGradients[bgGradientIndex.clamp(0, kGradients.length - 1)].$1
        : null,
  );
}

/// 背景样式：纯色 / 预置渐变 / 本地图片（cover 裁剪不拉伸）。
enum MonitorBgStyle { solid, gradient, image }

/// 内容块水平对齐：居左 / 居中。
enum MonitorAlign { left, center }
