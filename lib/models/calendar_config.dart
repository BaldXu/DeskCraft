import 'dart:convert';

import 'package:flutter/material.dart';

/// 预置渐变颜色对（与数字时钟 kGradients 一一对应，bgGradientIndex 索引）。
const List<List<int>> kCalendarGradients = [
  [0xFF1A1B2E, 0xFF4A3B78],
  [0xFF0F2027, 0xFF2C5364],
  [0xFF2F0743, 0xFF41295A],
  [0xFF232526, 0xFF414345],
];

/// 预置纯色背景板（与数字时钟 kSolidPalette 一致）。
const List<int> kCalendarSolidPalette = [
  0xE61C1C22, // 石墨黑（默认）
  0xE6000000, // 纯黑
  0xE6122436, // 深海军蓝
  0xE61B3A2C, // 墨绿
  0xE63A1F2B, // 酒红
  0xE6332E1F, // 咖啡棕
  0xCCFFFFFF, // 半透白
  0xB3202020, // 半透灰
];

/// 预置文字颜色板（与数字时钟 kTextPalette 一致）。
const List<int> kCalendarTextPalette = [
  0xFFFFFFFF, // 白（默认）
  0xFFF5D76E, // 暖黄
  0xFF8BE9C6, // 薄荷绿
  0xFF9DB8FF, // 天蓝
  0xFFFF9DAD, // 樱粉
  0xFFC6A6FF, // 淡紫
  0xFFFFB86C, // 橙
  0xFF9AA0A6, // 灰
];

/// 预置高亮/周末强调色板。
const List<int> kCalendarAccentPalette = [
  0xFF4CAF50, // 草绿（今天高亮默认）
  0xFFE53935, // 红
  0xFFF4511E, // 橙
  0xFFFB8C00, // 琥珀
  0xFF43A047, // 深绿
  0xFF1E88E5, // 蓝
  0xFF8E24AA, // 紫
  0xFFFF8A80, // 樱粉（周末默认）
];

/// 日历组件配置。
///
/// 序列化为 JSON 后经由 home_widget 的 saveWidgetData 写入
/// SharedPreferences（key 见 calendar_config_store.dart），
/// 后台回调读取同一份 JSON 渲染位图（见 calendar_callback.dart）。
/// JSON key 与 Dart 侧读取逐字段对齐，改动需同步两处。
///
/// 内容数据来源（V1）：
/// - 农历 / 节气：lunar 包本地计算（免权限保底）；
/// - 节日 / 纪念日：系统日历 CalendarContract.Instances（READ_CALENDAR），
///   用户订阅的节假日源 + 自建重复事件，零维护。
/// 副文字优先级：系统日历事件 > 节气 > 农历。
class CalendarConfig {
  const CalendarConfig({
    this.textColor = 0xFFFFFFFF,
    this.bgStyle = CalendarBgStyle.solid,
    this.bgColor = 0xE61C1C22,
    this.bgGradientIndex = 0,
    this.bgImagePath = '',
    this.cornerRadiusDp = 22,
    this.showHeader = true,
    this.showWeekdayHeader = true,
    this.firstDayOfWeek = CalendarFirstDay.monday,
    this.showLunar = true,
    this.showSolarTerm = true,
    this.showCalendarEvents = true,
    this.showAdjacentDays = true,
    this.highlightToday = true,
    this.highlightColor = 0xFF4CAF50,
    this.highlightShape = CalendarHighlightShape.circle,
    this.highlightStyle = CalendarHighlightStyle.filled,
    this.showWeekend = true,
    this.weekendColor = 0xFFFF8A80,
    this.dayFontSize = 14,
    this.subFontSize = 9,
  });

  factory CalendarConfig.fromJson(Map<String, dynamic> json) {
    return CalendarConfig(
      textColor: (json['textColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
      bgStyle: CalendarBgStyle.values.firstWhere(
        (s) => s.name == json['bgStyle'],
        orElse: () => CalendarBgStyle.solid,
      ),
      bgColor: (json['bgColor'] as num?)?.toInt() ?? 0xE61C1C22,
      bgGradientIndex: (json['bgGradientIndex'] as num?)?.toInt() ?? 0,
      bgImagePath: json['bgImagePath'] as String? ?? '',
      cornerRadiusDp: (json['cornerRadiusDp'] as num?)?.toInt() ?? 22,
      showHeader: json['showHeader'] as bool? ?? true,
      showWeekdayHeader: json['showWeekdayHeader'] as bool? ?? true,
      firstDayOfWeek: CalendarFirstDay.values.firstWhere(
        (v) => v.name == json['firstDayOfWeek'],
        orElse: () => CalendarFirstDay.monday,
      ),
      showLunar: json['showLunar'] as bool? ?? true,
      showSolarTerm: json['showSolarTerm'] as bool? ?? true,
      showCalendarEvents: json['showCalendarEvents'] as bool? ?? true,
      showAdjacentDays: json['showAdjacentDays'] as bool? ?? true,
      highlightToday: json['highlightToday'] as bool? ?? true,
      highlightColor: (json['highlightColor'] as num?)?.toInt() ?? 0xFF4CAF50,
      highlightShape: CalendarHighlightShape.values.firstWhere(
        (v) => v.name == json['highlightShape'],
        orElse: () => CalendarHighlightShape.circle,
      ),
      highlightStyle: CalendarHighlightStyle.values.firstWhere(
        (v) => v.name == json['highlightStyle'],
        orElse: () => CalendarHighlightStyle.filled,
      ),
      showWeekend: json['showWeekend'] as bool? ?? true,
      weekendColor: (json['weekendColor'] as num?)?.toInt() ?? 0xFFFF8A80,
      dayFontSize: (json['dayFontSize'] as num?)?.toInt() ?? 14,
      subFontSize: (json['subFontSize'] as num?)?.toInt() ?? 9,
    );
  }

  /// 从 widget 桥同步过来的原始 JSON 解析（失败返回默认配置）。
  factory CalendarConfig.fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return const CalendarConfig();
    try {
      return CalendarConfig.fromJson(
        (jsonDecode(raw) as Map<dynamic, dynamic>).cast<String, dynamic>(),
      );
    } catch (_) {
      return const CalendarConfig();
    }
  }

  final int textColor;
  final CalendarBgStyle bgStyle;
  final int bgColor;

  /// [kGradients] 的下标（与数字时钟/监控复用同一套渐变）。
  final int bgGradientIndex;

  /// 背景图片的本地绝对路径（bgStyle == image 时生效）。
  final String bgImagePath;
  final int cornerRadiusDp;

  /// 是否显示头部「yyyy年M月」。
  final bool showHeader;

  /// 是否显示星期行（一~日 / 日~六）。
  final bool showWeekdayHeader;

  /// 周首：周一开头 or 周日开头。
  final CalendarFirstDay firstDayOfWeek;

  /// 每格副文字：农历（初一/十五…）。
  final bool showLunar;

  /// 每格副文字：节气（立春/秋分…）。
  final bool showSolarTerm;

  /// 每格副文字：系统日历事件（节日/纪念日，需 READ_CALENDAR）。
  final bool showCalendarEvents;

  /// 是否显示前后月补位日（关闭则留空）。
  final bool showAdjacentDays;

  /// 今天高亮。
  final bool highlightToday;

  /// 今天高亮颜色。
  final int highlightColor;

  /// 今天高亮形状。
  final CalendarHighlightShape highlightShape;

  /// 今天高亮样式。
  final CalendarHighlightStyle highlightStyle;

  /// 周末染色。
  final bool showWeekend;

  /// 周末日号颜色（周六日）。
  final int weekendColor;

  /// 日号字号（dp）。
  final int dayFontSize;

  /// 副文字字号（dp，农历/节气/事件）。
  final int subFontSize;

  Map<String, dynamic> toJson() => {
    'textColor': textColor,
    'bgStyle': bgStyle.name,
    'bgColor': bgColor,
    'bgGradientIndex': bgGradientIndex,
    'bgImagePath': bgImagePath,
    'cornerRadiusDp': cornerRadiusDp,
    'showHeader': showHeader,
    'showWeekdayHeader': showWeekdayHeader,
    'firstDayOfWeek': firstDayOfWeek.name,
    'showLunar': showLunar,
    'showSolarTerm': showSolarTerm,
    'showCalendarEvents': showCalendarEvents,
    'showAdjacentDays': showAdjacentDays,
    'highlightToday': highlightToday,
    'highlightColor': highlightColor,
    'highlightShape': highlightShape.name,
    'highlightStyle': highlightStyle.name,
    'showWeekend': showWeekend,
    'weekendColor': weekendColor,
    'dayFontSize': dayFontSize,
    'subFontSize': subFontSize,
  };

  CalendarConfig copyWith({
    int? textColor,
    CalendarBgStyle? bgStyle,
    int? bgColor,
    int? bgGradientIndex,
    String? bgImagePath,
    int? cornerRadiusDp,
    bool? showHeader,
    bool? showWeekdayHeader,
    CalendarFirstDay? firstDayOfWeek,
    bool? showLunar,
    bool? showSolarTerm,
    bool? showCalendarEvents,
    bool? showAdjacentDays,
    bool? highlightToday,
    int? highlightColor,
    CalendarHighlightShape? highlightShape,
    CalendarHighlightStyle? highlightStyle,
    bool? showWeekend,
    int? weekendColor,
    int? dayFontSize,
    int? subFontSize,
  }) => CalendarConfig(
    textColor: textColor ?? this.textColor,
    bgStyle: bgStyle ?? this.bgStyle,
    bgColor: bgColor ?? this.bgColor,
    bgGradientIndex: bgGradientIndex ?? this.bgGradientIndex,
    bgImagePath: bgImagePath ?? this.bgImagePath,
    cornerRadiusDp: cornerRadiusDp ?? this.cornerRadiusDp,
    showHeader: showHeader ?? this.showHeader,
    showWeekdayHeader: showWeekdayHeader ?? this.showWeekdayHeader,
    firstDayOfWeek: firstDayOfWeek ?? this.firstDayOfWeek,
    showLunar: showLunar ?? this.showLunar,
    showSolarTerm: showSolarTerm ?? this.showSolarTerm,
    showCalendarEvents: showCalendarEvents ?? this.showCalendarEvents,
    showAdjacentDays: showAdjacentDays ?? this.showAdjacentDays,
    highlightToday: highlightToday ?? this.highlightToday,
    highlightColor: highlightColor ?? this.highlightColor,
    highlightShape: highlightShape ?? this.highlightShape,
    highlightStyle: highlightStyle ?? this.highlightStyle,
    showWeekend: showWeekend ?? this.showWeekend,
    weekendColor: weekendColor ?? this.weekendColor,
    dayFontSize: dayFontSize ?? this.dayFontSize,
    subFontSize: subFontSize ?? this.subFontSize,
  );

  /// 当前背景在预览中的装饰（纯色或渐变）。
  Decoration get previewDecoration => ShapeDecoration(
    shape: ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(cornerRadiusDp.toDouble()),
    ),
    color: bgStyle == CalendarBgStyle.solid ? Color(bgColor) : null,
    gradient: bgStyle == CalendarBgStyle.gradient
        ? LinearGradient(
            colors: [
              for (final c in kCalendarGradients[
                  bgGradientIndex.clamp(0, kCalendarGradients.length - 1)])
                Color(c),
            ],
          )
        : null,
  );
}

/// 背景样式：纯色 / 预置渐变 / 本地图片（cover 裁剪不拉伸）。
enum CalendarBgStyle { solid, gradient, image }

/// 周首：周一 / 周日。
enum CalendarFirstDay { monday, sunday }

/// 今天高亮形状：圆形 / 圆角方形。
enum CalendarHighlightShape { circle, roundedRect }

/// 今天高亮样式：实心 / 描边。
enum CalendarHighlightStyle { filled, outline }
