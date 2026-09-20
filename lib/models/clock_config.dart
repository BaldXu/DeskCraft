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
    this.cornerRadiusDp = 22,
    this.timeSizeSp = 38,
    this.use24h = true,
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
    cornerRadiusDp: (json['cornerRadiusDp'] as num?)?.toInt() ?? 22,
    timeSizeSp: (json['timeSizeSp'] as num?)?.toInt() ?? 38,
    use24h: json['use24h'] as bool? ?? true,
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
  final int cornerRadiusDp;
  final int timeSizeSp;
  final bool use24h;
  final bool showDate;
  final bool showWeekday;
  final String extraText;

  Map<String, dynamic> toJson() => {
    'textColor': textColor,
    'bgStyle': bgStyle.name,
    'bgColor': bgColor,
    'bgGradientIndex': bgGradientIndex,
    'cornerRadiusDp': cornerRadiusDp,
    'timeSizeSp': timeSizeSp,
    'use24h': use24h,
    'showDate': showDate,
    'showWeekday': showWeekday,
    'extraText': extraText,
  };

  ClockConfig copyWith({
    int? textColor,
    ClockBgStyle? bgStyle,
    int? bgColor,
    int? bgGradientIndex,
    int? cornerRadiusDp,
    int? timeSizeSp,
    bool? use24h,
    bool? showDate,
    bool? showWeekday,
    String? extraText,
  }) => ClockConfig(
    textColor: textColor ?? this.textColor,
    bgStyle: bgStyle ?? this.bgStyle,
    bgColor: bgColor ?? this.bgColor,
    bgGradientIndex: bgGradientIndex ?? this.bgGradientIndex,
    cornerRadiusDp: cornerRadiusDp ?? this.cornerRadiusDp,
    timeSizeSp: timeSizeSp ?? this.timeSizeSp,
    use24h: use24h ?? this.use24h,
    showDate: showDate ?? this.showDate,
    showWeekday: showWeekday ?? this.showWeekday,
    extraText: extraText ?? this.extraText,
  );

  /// 当前背景在预览中的装饰（纯色或渐变）。
  Decoration get previewDecoration => BoxDecoration(
    borderRadius: BorderRadius.circular(cornerRadiusDp.toDouble()),
    color: bgStyle == ClockBgStyle.solid ? Color(bgColor) : null,
    gradient: bgStyle == ClockBgStyle.gradient
        ? kGradients[bgGradientIndex.clamp(0, kGradients.length - 1)].$1
        : null,
  );
}

/// 背景样式：纯色 / 预置渐变。
enum ClockBgStyle { solid, gradient }

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
