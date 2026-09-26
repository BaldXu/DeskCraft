/// 日历月网格数据（V1）。
///
/// 数据来源：
/// - 农历 / 节气：lunar 包本地计算（免权限，永远可用）；
/// - 节日 / 纪念日：系统日历事件标题（原生 CalendarWidgetProvider
///   按月查询 CalendarContract.Instances 写入 JSON，本文件解析）。
library;

import 'dart:convert';

import 'package:lunar/lunar.dart';

import '../models/calendar_config.dart';

/// 一天的完整显示数据（一格）。
class CalendarDayInfo {
  const CalendarDayInfo({
    required this.date,
    required this.isCurrentMonth,
    required this.isToday,
    required this.isWeekend,
    required this.lunarText,
    required this.solarTerm,
    required this.events,
  });

  /// 该格对应日期（含前后月补位日）。
  final DateTime date;

  /// 是否属于当前显示月份。
  final bool isCurrentMonth;

  /// 是否今天。
  final bool isToday;

  /// 是否周末（周六/周日，与周首配置无关）。
  final bool isWeekend;

  /// 农历日（初一/十五/三十…）。
  final String lunarText;

  /// 节气名（非节气日为空串）。
  final String solarTerm;

  /// 系统日历事件标题（去重，按开始时间排序）。
  final List<String> events;

  /// 本地时区日期 key（与原生 Instances 聚合 JSON 的 key 对齐）。
  String get dateKey => _dateKey(date);

  /// 副文字：事件 > 节气 > 农历（优先级固定）。
  String get subText {
    if (events.isNotEmpty) return events.first;
    if (solarTerm.isNotEmpty) return solarTerm;
    return lunarText;
  }

  /// 副文字是否来自系统日历事件（配置页提示用）。
  bool get hasEvent => events.isNotEmpty;
}

/// 一个月的网格数据：固定 6 行 × 7 列 = 42 格。
///
/// [cells] 长度恒为 42；[showAdjacentDays] 关闭时前后月补位格为 null。
class CalendarMonthData {
  const CalendarMonthData({
    required this.year,
    required this.month,
    required this.cells,
  });

  final int year;
  final int month;

  /// 42 格（行优先），补位格可能为 null。
  final List<CalendarDayInfo?> cells;
}

/// 构建某天的所在月网格（6 行 42 格）。
///
/// [today] 为当前日期（决定 isToday 与高亮）；[config] 决定周首与补位日显隐。
CalendarMonthData buildMonthGrid(DateTime today, CalendarConfig config) {
  final firstOfMonth = DateTime(today.year, today.month, 1);
  // 本月 1 号相对周首的偏移（0 = 第一格）
  final offset = config.firstDayOfWeek == CalendarFirstDay.monday
      ? firstOfMonth.weekday - 1
      : firstOfMonth.weekday % 7;
  final gridStart = firstOfMonth.subtract(Duration(days: offset));

  final cells = <CalendarDayInfo?>[];
  for (var i = 0; i < 42; i++) {
    final date = gridStart.add(Duration(days: i));
    final isCurrentMonth = date.month == today.month && date.year == today.year;
    if (!isCurrentMonth && !config.showAdjacentDays) {
      cells.add(null);
      continue;
    }
    cells.add(_buildDayInfo(date, today, isCurrentMonth));
  }
  return CalendarMonthData(year: today.year, month: today.month, cells: cells);
}

CalendarDayInfo _buildDayInfo(
  DateTime date,
  DateTime today,
  bool isCurrentMonth,
) {
  final lunar = Solar.fromDate(date).getLunar();
  return CalendarDayInfo(
    date: date,
    isCurrentMonth: isCurrentMonth,
    isToday: date.year == today.year &&
        date.month == today.month &&
        date.day == today.day,
    isWeekend: date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday,
    lunarText: lunar.getDayInChinese(),
    solarTerm: lunar.getJieQi(),
    events: const [],
  );
}

/// 本地时区日期 key：yyyy-MM-dd（与原生聚合 JSON 的 key 对齐）。
String _dateKey(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}

/// 解析原生写入的系统日历事件 JSON（{"yyyy-MM-dd": ["标题", ...]}）。
///
/// 解析失败 / 空串返回空表。
Map<String, List<String>> parseEventsJson(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const {};
    final out = <String, List<String>>{};
    decoded.forEach((key, value) {
      if (value is List) {
        out[key] = value
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList();
      }
    });
    return out;
  } catch (_) {
    return const {};
  }
}

/// 把事件表注入月网格：按 dateKey 匹配每格 events。
CalendarMonthData attachEvents(
  CalendarMonthData grid,
  Map<String, List<String>> events,
) {
  if (events.isEmpty) return grid;
  return CalendarMonthData(
    year: grid.year,
    month: grid.month,
    cells: [
      for (final cell in grid.cells)
        if (cell == null)
          null
        else
          CalendarDayInfo(
            date: cell.date,
            isCurrentMonth: cell.isCurrentMonth,
            isToday: cell.isToday,
            isWeekend: cell.isWeekend,
            lunarText: cell.lunarText,
            solarTerm: cell.solarTerm,
            events: events[cell.dateKey] ?? const [],
          ),
    ],
  );
}
