// 日历月网格数据测试（V1）：42 格布局、周首偏移、今天/周末识别、
// 农历/节气副文字、事件解析与注入。
import 'package:desk_craft/calendar/calendar_data.dart';
import 'package:desk_craft/models/calendar_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildMonthGrid', () {
    test('固定 42 格，周一首开偏移正确', () {
      // 2026-09-01 是周二（DateTime.weekday == 2）
      final today = DateTime(2026, 9, 15);
      final grid = buildMonthGrid(today, const CalendarConfig());

      expect(grid.cells.length, 42);
      expect(grid.year, 2026);
      expect(grid.month, 9);

      // 周一开头：9/1 在第二列（索引 1）
      final first = grid.cells.first!;
      expect(first.date, DateTime(2026, 8, 31));
      expect(first.isCurrentMonth, isFalse); // 补位日

      final sep1 = grid.cells[1]!;
      expect(sep1.date, DateTime(2026, 9, 1));
      expect(sep1.isCurrentMonth, isTrue);
    });

    test('周首切换为周日时偏移 +1', () {
      final today = DateTime(2026, 9, 15);
      final grid = buildMonthGrid(
        today,
        const CalendarConfig(firstDayOfWeek: CalendarFirstDay.sunday),
      );
      // 周日开头：9/1（周二）在第三列（索引 2）
      expect(grid.cells[2]!.date, DateTime(2026, 9, 1));
      expect(grid.cells.first!.date, DateTime(2026, 8, 30));
    });

    test('今天识别与周末识别', () {
      // 2026-09-26 是周六
      final today = DateTime(2026, 9, 26);
      final grid = buildMonthGrid(today, const CalendarConfig());

      final todayCell = grid.cells.firstWhere((c) => c != null && c.isToday);
      expect(todayCell!.date, today);

      final weekendCells = grid.cells
          .where((c) => c != null && c.isCurrentMonth && c.isWeekend)
          .toList();
      // 9 月有 8 个周末日（周六日各 4 天）
      expect(weekendCells.length, 8);
      for (final c in weekendCells) {
        expect(c!.date.weekday, anyOf(DateTime.saturday, DateTime.sunday));
      }
    });

    test('关闭补位日后非本月格为 null', () {
      final today = DateTime(2026, 9, 15);
      final grid = buildMonthGrid(
        today,
        const CalendarConfig(showAdjacentDays: false),
      );
      expect(grid.cells.first, isNull);
      expect(grid.cells[1]!.date, DateTime(2026, 9, 1));
      expect(grid.cells[30]!.date, DateTime(2026, 9, 30));
      expect(grid.cells[31], isNull);
      expect(grid.cells.last, isNull);
    });

    test('农历与节气副文字（2026-09-23 秋分，农历八月十三）', () {
      final today = DateTime(2026, 9, 23);
      final grid = buildMonthGrid(today, const CalendarConfig());
      final cell = grid.cells.firstWhere(
        (c) => c != null && c.date.day == 23 && c.isCurrentMonth,
      )!;
      // 2026-09-23 = 农历八月十三 + 秋分
      expect(cell.lunarText, '十三');
      expect(cell.solarTerm, '秋分');
      // 副文字优先级：事件 > 节气 > 农历
      expect(cell.subText, '秋分');
    });

    test('农历普通日副文字回落农历（无事件无节气）', () {
      final today = DateTime(2026, 9, 10);
      final grid = buildMonthGrid(today, const CalendarConfig());
      final cell = grid.cells.firstWhere(
        (c) => c != null && c.date.day == 10 && c.isCurrentMonth,
      )!;
      // 2026-09-10 = 农历七月廿九（无节气）
      expect(cell.solarTerm, isEmpty);
      expect(cell.lunarText, '廿九');
      expect(cell.subText, '廿九');
    });
  });

  group('parseEventsJson', () {
    test('正常解析按天聚合', () {
      final events = parseEventsJson(
        '{"2026-10-01":["国庆节"],"2026-10-02":["国庆节","出行"]}',
      );
      expect(events['2026-10-01'], ['国庆节']);
      expect(events['2026-10-02'], ['国庆节', '出行']);
    });

    test('空串/非法 JSON/非对象返回空表', () {
      expect(parseEventsJson(null), isEmpty);
      expect(parseEventsJson(''), isEmpty);
      expect(parseEventsJson('not json'), isEmpty);
      expect(parseEventsJson('[1,2]'), isEmpty);
    });

    test('过滤空标题与数字条目', () {
      final events = parseEventsJson('{"2026-10-01":["", "有效", 42]}');
      expect(events['2026-10-01'], ['有效']);
    });
  });

  group('attachEvents', () {
    test('按日期注入事件并影响副文字优先级', () {
      final today = DateTime(2026, 10, 1);
      final grid = buildMonthGrid(today, const CalendarConfig());
      final withEvents = attachEvents(grid, {
        '2026-10-01': ['国庆节'],
      });
      final cell = withEvents.cells.firstWhere(
        (c) => c != null && c.date.day == 1 && c.isCurrentMonth,
      )!;
      expect(cell.hasEvent, isTrue);
      expect(cell.events, ['国庆节']);
      expect(cell.subText, '国庆节');
    });

    test('空事件表不改变原网格', () {
      final today = DateTime(2026, 10, 1);
      final grid = buildMonthGrid(today, const CalendarConfig());
      final withEvents = attachEvents(grid, const {});
      expect(withEvents.cells.length, grid.cells.length);
      final cell = withEvents.cells.firstWhere(
        (c) => c != null && c.isToday,
      )!;
      expect(cell.events, isEmpty);
    });
  });
}
