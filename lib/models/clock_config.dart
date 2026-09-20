import 'dart:convert';

import 'package:flutter/material.dart';

/// 数字时钟组件配置（M3）。
///
/// 序列化为 JSON 后经由 home_widget 的 saveWidgetData 写入
/// SharedPreferences key [widgetDataJsonKey]（见 clock_config_store.dart），
/// 原生 ClockWidgetProvider 读取同一份 JSON 渲染 RemoteViews。
class ClockConfig {
  const ClockConfig({
    this.textColor = 0xFFFFFFFF,
    this.bgStyle = ClockBgStyle.solid,
    this.bgColor = 0xE61C1C22,
    this.bgGradientIndex = 0,
    this.bgImagePath = '',
    this.cornerRadiusDp = 22,
    this.timeSizeSp = 38,
    this.timeAlign = ClockTimeAlign.left,
    this.use24h = true,
    this.showSeconds = false,
    this.showDate = true,
    this.showWeekday = true,
    this.extraText = 'DeskCraft - M1',
  });

  factory ClockConfig.fromJson(Map<String, dynamic> json) => ClockConfig(
    textColor: (json['textColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
    bgStyle: ClockBgStyle.values.firstWhere(
      (s) => s.name == json['bgStyle'],
      orElse: () => ClockBgStyle.solid,
    ),
    bgColor: (json['bgColor'] as num?)?.toInt() ?? 0xE61C1C22,
    bgGradientIndex: (json['bgGradientIndex'] as num?)?.toInt() ?? 0,
    bgImagePath: json['bgImagePath'] as String? ?? '',
    cornerRadiusDp: (json['cornerRadiusDp'] as num?)?.toInt() ?? 22,
    timeSizeSp: (json['timeSizeSp'] as num?)?.toInt() ?? 38,
    timeAlign: ClockTimeAlign.values.firstWhere(
      (a) => a.name == json['timeAlign'],
      orElse: () => ClockTimeAlign.left,
    ),
    use24h: json['use24h'] as bool? ?? true,
    showSeconds: json['showSeconds'] as bool? ?? false,
    showDate: json['showDate'] as bool? ?? true,
    showWeekday: json['showWeekday'] as bool? ?? true,
    extraText: json['extraText'] as String? ?? 'DeskCraft - M1',
  );

  /// 从 widget 桥同步过来的原始 JSON 解析（失败返回默认配置）。
  factory ClockConfig.fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return const ClockConfig();
    try {
      return ClockConfig.fromJson(
        (jsonDecode(raw) as Map<dynamic, dynamic>).cast<String, dynamic>(),
      );
    } catch (_) {
      return const ClockConfig();
    }
  }

  final int textColor;
  final ClockBgStyle bgStyle;
  final int bgColor;

  /// [kGradients] 的下标。
  final int bgGradientIndex;

  /// 背景图片的本地绝对路径（bgStyle == image 时生效）。
  final String bgImagePath;
  final int cornerRadiusDp;
  final int timeSizeSp;

  /// 时间内容块的水平对齐方式（时间 + 日期 + 附加文案整体）。
  final ClockTimeAlign timeAlign;
  final bool use24h;
  final bool showSeconds;
  final bool showDate;
  final bool showWeekday;
  final String extraText;

  Map<String, dynamic> toJson() => {
    'textColor': textColor,
    'bgStyle': bgStyle.name,
    'bgColor': bgColor,
    'bgGradientIndex': bgGradientIndex,
    'bgImagePath': bgImagePath,
    'cornerRadiusDp': cornerRadiusDp,
    'timeSizeSp': timeSizeSp,
    'timeAlign': timeAlign.name,
    'use24h': use24h,
    'showSeconds': showSeconds,
    'showDate': showDate,
    'showWeekday': showWeekday,
    'extraText': extraText,
  };

  ClockConfig copyWith({
    int? textColor,
    ClockBgStyle? bgStyle,
    int? bgColor,
    int? bgGradientIndex,
    String? bgImagePath,
    int? cornerRadiusDp,
    int? timeSizeSp,
    ClockTimeAlign? timeAlign,
    bool? use24h,
    bool? showSeconds,
    bool? showDate,
    bool? showWeekday,
    String? extraText,
  }) => ClockConfig(
    textColor: textColor ?? this.textColor,
    bgStyle: bgStyle ?? this.bgStyle,
    bgColor: bgColor ?? this.bgColor,
    bgGradientIndex: bgGradientIndex ?? this.bgGradientIndex,
    bgImagePath: bgImagePath ?? this.bgImagePath,
    cornerRadiusDp: cornerRadiusDp ?? this.cornerRadiusDp,
    timeSizeSp: timeSizeSp ?? this.timeSizeSp,
    timeAlign: timeAlign ?? this.timeAlign,
    use24h: use24h ?? this.use24h,
    showSeconds: showSeconds ?? this.showSeconds,
    showDate: showDate ?? this.showDate,
    showWeekday: showWeekday ?? this.showWeekday,
    extraText: extraText ?? this.extraText,
  );

  /// 当前背景在预览中的装饰（纯色或渐变）。
  /// 预览背景装饰：G2 连续曲率圆角（ContinuousRectangleBorder，曲率在
  /// 直线衔接处为 0），与原生 smoothCornerPath 同一算法，观感一致。
  Decoration get previewDecoration => ShapeDecoration(
    shape: ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(cornerRadiusDp.toDouble()),
    ),
    color: bgStyle == ClockBgStyle.solid ? Color(bgColor) : null,
    gradient: bgStyle == ClockBgStyle.gradient
        ? kGradients[bgGradientIndex.clamp(0, kGradients.length - 1)].$1
        : null,
  );
}

/// 背景样式：纯色 / 预置渐变 / 本地图片（cover 裁剪不拉伸）。
enum ClockBgStyle { solid, gradient, image }

/// 时间内容块水平对齐：居左 / 居中。
enum ClockTimeAlign { left, center }

/// 预置渐变档位：(Flutter 渐变, 原生资源索引)。
/// 原生侧对应 res/drawable/bg_widget_gradient_`<index>`.xml。
const List<(LinearGradient, int)> kGradients = [
  (LinearGradient(colors: [Color(0xFF1A1B2E), Color(0xFF4A3B78)]), 0),
  (LinearGradient(colors: [Color(0xFF0F2027), Color(0xFF2C5364)]), 1),
  (LinearGradient(colors: [Color(0xFF2F0743), Color(0xFF41295A)]), 2),
  (LinearGradient(colors: [Color(0xFF232526), Color(0xFF414345)]), 3),
];

/// 预置纯色背景板。
const List<int> kSolidPalette = [
  0xE61C1C22, // 石墨黑（默认）
  0xE6000000, // 纯黑
  0xE6122436, // 深海军蓝
  0xE61B3A2C, // 墨绿
  0xE63A1F2B, // 酒红
  0xE6332E1F, // 咖啡棕
  0xCCFFFFFF, // 半透白
  0xB3202020, // 半透灰
];

/// 预置文字颜色板。
const List<int> kTextPalette = [
  0xFFFFFFFF, // 白（默认）
  0xFFF5D76E, // 暖黄
  0xFF8BE9C6, // 薄荷绿
  0xFF9DB8FF, // 天蓝
  0xFFFF9DAD, // 樱粉
  0xFFC6A6FF, // 淡紫
  0xFFFFB86C, // 橙
  0xFF9AA0A6, // 灰
];
