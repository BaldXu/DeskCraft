// 日历配置模型测试（V1）：JSON 往返、宽松回落、copyWith。
import 'dart:convert';

import 'package:desk_craft/models/calendar_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalendarConfig', () {
    test('默认配置字段符合约定', () {
      const c = CalendarConfig();
      expect(c.textColor, 0xFFFFFFFF);
      expect(c.bgStyle, CalendarBgStyle.solid);
      expect(c.cornerRadiusDp, 22);
      expect(c.firstDayOfWeek, CalendarFirstDay.monday);
      expect(c.showLunar, isTrue);
      expect(c.showSolarTerm, isTrue);
      expect(c.showCalendarEvents, isTrue);
      expect(c.highlightToday, isTrue);
      expect(c.highlightColor, 0xFF4CAF50);
      expect(c.highlightShape, CalendarHighlightShape.circle);
      expect(c.highlightStyle, CalendarHighlightStyle.filled);
      expect(c.showWeekend, isTrue);
      expect(c.weekendColor, 0xFFFF8A80);
    });

    test('toJson/fromJson 往返保持字段一致', () {
      const c = CalendarConfig(
        textColor: 0xFFF5D76E,
        bgStyle: CalendarBgStyle.gradient,
        bgColor: 0xFF123456,
        bgGradientIndex: 2,
        cornerRadiusDp: 36,
        showHeader: false,
        showWeekdayHeader: false,
        firstDayOfWeek: CalendarFirstDay.sunday,
        showLunar: false,
        showSolarTerm: false,
        showCalendarEvents: false,
        showAdjacentDays: false,
        highlightToday: false,
        highlightColor: 0xFFE53935,
        highlightShape: CalendarHighlightShape.roundedRect,
        highlightStyle: CalendarHighlightStyle.outline,
        showWeekend: false,
        weekendColor: 0xFF1E88E5,
        dayFontSize: 18,
        subFontSize: 11,
      );
      final restored = CalendarConfig.fromJsonString(
        jsonEncode(c.toJson()),
      );
      expect(restored.toJson(), c.toJson());
    });

    test('空串/非法 JSON 回落默认', () {
      expect(CalendarConfig.fromJsonString(null).toJson(),
          const CalendarConfig().toJson());
      expect(CalendarConfig.fromJsonString('').toJson(),
          const CalendarConfig().toJson());
      expect(CalendarConfig.fromJsonString('oops').toJson(),
          const CalendarConfig().toJson());
    });

    test('未知枚举值宽松回落默认', () {
      final restored = CalendarConfig.fromJsonString(
        '{"firstDayOfWeek":"friday","highlightShape":"star","bgStyle":"weird"}',
      );
      expect(restored.firstDayOfWeek, CalendarFirstDay.monday);
      expect(restored.highlightShape, CalendarHighlightShape.circle);
      expect(restored.bgStyle, CalendarBgStyle.solid);
    });

    test('copyWith 只改指定字段', () {
      const c = CalendarConfig();
      final updated = c.copyWith(showHeader: false, dayFontSize: 20);
      expect(updated.showHeader, isFalse);
      expect(updated.dayFontSize, 20);
      expect(updated.showLunar, isTrue); // 未改的保持默认
      expect(updated.highlightColor, 0xFF4CAF50);
    });
  });
}
