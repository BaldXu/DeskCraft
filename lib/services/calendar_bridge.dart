import 'dart:convert';

import 'package:flutter/services.dart';

import '../calendar/calendar_data.dart';

/// 系统日历桥（MethodChannel desk_craft/calendar，原生侧在 MainActivity 注册）。
///
/// 职责：
/// - READ_CALENDAR 权限检测 / 请求 / 跳系统设置页；
/// - 按月查询 CalendarContract.Instances 事件（节日/纪念日数据源，零维护）；
/// - 查询日历 widget 当前尺寸（推送时按实际尺寸渲染，防拉伸模糊）。
class CalendarBridge {
  CalendarBridge._();

  static const MethodChannel _channel = MethodChannel('desk_craft/calendar');

  /// 是否已授予 READ_CALENDAR。
  static Future<bool> checkPermission() async {
    try {
      return await _channel.invokeMethod<bool>('checkPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 请求 READ_CALENDAR（系统弹窗），返回最终是否已授予。
  static Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 跳转系统日历权限设置页。
  static Future<void> openCalendarSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      // 忽略跳转失败
    } on MissingPluginException {
      // 忽略
    }
  }

  /// 查询某月的系统日历事件，返回 {yyyy-MM-dd: [标题, ...]}。
  /// 无权限 / 查询失败返回空表。
  static Future<Map<String, List<String>>> queryMonthEvents(
    int year,
    int month,
  ) async {
    try {
      final raw = await _channel.invokeMethod<String>('queryMonth', {
        'year': year,
        'month': month,
      });
      return parseEventsJson(raw);
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  /// 查询日历 widget 当前尺寸（px）。未上桌时返回 null（调用方回落基准尺寸）。
  static Future<(int, int)?> widgetSizePx() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('widgetSizePx');
      if (raw == null || raw.length < 2) return null;
      final w = (raw[0] as num?)?.toInt();
      final h = (raw[1] as num?)?.toInt();
      if (w == null || h == null || w <= 0 || h <= 0) return null;
      return (w, h);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 把 MethodChannel 返回的 JSON 串解析为事件表（供预览/推送共用）。
  static Map<String, List<String>> eventsFromRaw(String? raw) =>
      parseEventsJson(raw);

  /// 事件表编码为 JSON 串（原生侧缓存/推送用）。
  static String encodeEvents(Map<String, List<String>> events) =>
      jsonEncode(events);
}
