import 'dart:io';
import 'dart:ui' as ui;
import 'package:desk_craft/calendar/calendar_data.dart';
import 'package:desk_craft/calendar/calendar_painter.dart';
import 'package:desk_craft/models/calendar_config.dart';

Future<void> main() async {
  final now = DateTime(2026, 9, 26);
  final config = const CalendarConfig();
  var grid = buildMonthGrid(now, config);
  grid = attachEvents(grid, {
    '2026-09-26': ['世界地球日'],
    '2026-10-01': ['国庆节'],
  });
  final bytes = await renderCalendarPng(
    config: config,
    grid: grid,
    widthPx: 750,
    heightPx: 660,
  );
  File('calendar_render.png').writeAsBytesSync(bytes!);
  print('saved ${bytes.length} bytes');
}
