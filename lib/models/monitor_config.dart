import 'dart:convert';

import 'package:flutter/material.dart';

import 'clock_config.dart';
import 'info_bit.dart';

/// 系统监控组件配置（M4）。
///
/// 序列化为 JSON 后经由 home_widget 的 saveWidgetData 写入
/// SharedPreferences key monitor_config_json（见 monitor_config_store.dart），
/// 原生 MonitorWidgetProvider 读取同一份 JSON 渲染 RemoteViews。
/// JSON key 与原生 MonitorNativeConfig.from 逐字段对齐，勿改名。
///
/// 信息位（M4.1 解耦）：电池温度 / CPU / 内存是带刷新频率的 [InfoBit]；
/// 整卡有效刷新周期按最快信息位计算，同时写回旧版扁平 key
/// refreshIntervalSeconds（原生继续读），渐进迁移。
class MonitorConfig {
  static const _defaultBatteryTempBit = InfoBit(
    key: 'batteryTemp',
    label: '电池温度',
    enabled: true,
    refreshSeconds: 60,
  );
  static const _defaultCpuBit = InfoBit(
    key: 'cpu',
    label: 'CPU 占用',
    enabled: true,
    refreshSeconds: 15,
  );
  static const _defaultMemBit = InfoBit(
    key: 'mem',
    label: '内存占用',
    enabled: true,
    refreshSeconds: 30,
  );

  const MonitorConfig({
    this.textColor = 0xFFFFFFFF,
    this.bgStyle = MonitorBgStyle.solid,
    this.bgColor = 0xE61C1C22,
    this.bgGradientIndex = 0,
    this.bgImagePath = '',
    this.cornerRadiusDp = 22,
    this.align = MonitorAlign.left,
    this.highTempThresholdC = 45.0,
    this.batteryTempBit = _defaultBatteryTempBit,
    this.cpuBit = _defaultCpuBit,
    this.memBit = _defaultMemBit,
  });

  factory MonitorConfig.fromJson(Map<String, dynamic> json) {
    final bits = (json['bits'] as Map<dynamic, dynamic>?)
        ?.cast<String, dynamic>();
    Map<String, dynamic>? bitJson(String key) =>
        (bits?[key] as Map<dynamic, dynamic>?)?.cast<String, dynamic>();
    // 缺 bits 时：enabled 回落旧扁平布尔 key，频率回落旧整卡间隔
    final legacyInterval =
        (json['refreshIntervalSeconds'] as num?)?.toInt() ?? 60;
    return MonitorConfig(
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
      highTempThresholdC:
          (json['highTempThresholdC'] as num?)?.toDouble() ?? 45.0,
      batteryTempBit: InfoBit.fromJson(
        'batteryTemp',
        '电池温度',
        bitJson('batteryTemp'),
        _defaultBatteryTempBit.copyWith(
          enabled: json['showBatteryTemp'] as bool? ?? true,
          refreshSeconds: legacyInterval,
        ),
      ),
      cpuBit: InfoBit.fromJson(
        'cpu',
        'CPU 占用',
        bitJson('cpu'),
        _defaultCpuBit.copyWith(
          enabled: json['showCpu'] as bool? ?? true,
          refreshSeconds: legacyInterval,
        ),
      ),
      memBit: InfoBit.fromJson(
        'mem',
        '内存占用',
        bitJson('mem'),
        _defaultMemBit.copyWith(
          enabled: json['showMem'] as bool? ?? true,
          refreshSeconds: legacyInterval,
        ),
      ),
    );
  }

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

  /// 高温警示阈值（°C），电池温度 ≥ 该值时温度行变红。
  final double highTempThresholdC;

  /// 电池温度信息位（enabled 对应旧版 showBatteryTemp）。
  final InfoBit batteryTempBit;

  /// CPU 占用信息位（enabled 对应旧版 showCpu）。
  final InfoBit cpuBit;

  /// 内存占用信息位（enabled 对应旧版 showMem）。
  final InfoBit memBit;

  bool get showBatteryTemp => batteryTempBit.enabled;
  bool get showCpu => cpuBit.enabled;
  bool get showMem => memBit.enabled;

  /// 本卡全部信息位。
  List<InfoBit> get infoBits => [batteryTempBit, cpuBit, memBit];

  /// 整卡有效刷新周期（秒）：以启用信息位中最快者为准，
  /// 同时作为旧版扁平 key refreshIntervalSeconds 写出（原生按此调度）。
  int get effectiveRefreshSeconds => effectiveCardRefreshSeconds(infoBits);

  Map<String, dynamic> toJson() => {
    'textColor': textColor,
    'bgStyle': bgStyle.name,
    'bgColor': bgColor,
    'bgGradientIndex': bgGradientIndex,
    'bgImagePath': bgImagePath,
    'cornerRadiusDp': cornerRadiusDp,
    'align': align.name,
    // 旧版扁平 key（原生 MonitorWidgetProvider 继续读），由信息位派生
    'refreshIntervalSeconds': effectiveRefreshSeconds,
    'showBatteryTemp': showBatteryTemp,
    'showCpu': showCpu,
    'showMem': showMem,
    // 新版信息位结构
    'bits': {for (final bit in infoBits) bit.key: bit.toJson()},
    'highTempThresholdC': highTempThresholdC,
  };

  MonitorConfig copyWith({
    int? textColor,
    MonitorBgStyle? bgStyle,
    int? bgColor,
    int? bgGradientIndex,
    String? bgImagePath,
    int? cornerRadiusDp,
    MonitorAlign? align,
    double? highTempThresholdC,
    InfoBit? batteryTempBit,
    InfoBit? cpuBit,
    InfoBit? memBit,
  }) => MonitorConfig(
    textColor: textColor ?? this.textColor,
    bgStyle: bgStyle ?? this.bgStyle,
    bgColor: bgColor ?? this.bgColor,
    bgGradientIndex: bgGradientIndex ?? this.bgGradientIndex,
    bgImagePath: bgImagePath ?? this.bgImagePath,
    cornerRadiusDp: cornerRadiusDp ?? this.cornerRadiusDp,
    align: align ?? this.align,
    highTempThresholdC: highTempThresholdC ?? this.highTempThresholdC,
    batteryTempBit: batteryTempBit ?? this.batteryTempBit,
    cpuBit: cpuBit ?? this.cpuBit,
    memBit: memBit ?? this.memBit,
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
