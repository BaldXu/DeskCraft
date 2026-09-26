/// 日历组件后台刷新回调。
///
/// 链路：原生 AlarmManager / DATE_CHANGED / 日历数据变更 → CalendarWidgetProvider
/// （查询系统日历事件写入 widget 桥 SP）→ `HomeWidgetBackgroundIntent`（headless
/// FlutterEngine）→ [calendarBackgroundCallback]（本文件，顶层函数，可被回调句柄引用）。
///
/// 回调内完成：读取配置 JSON + 事件 JSON + 渲染尺寸 → 重渲染位图 →
/// saveFile 覆盖位图 → updateWidget 通知原生 provider 重绘。
///
/// 注意：headless 引擎中没有 implicitView，渲染必须走 renderCalendarPng
/// （纯 PictureRecorder），不能用 renderFlutterWidget。
library;

import 'package:home_widget/home_widget.dart';

import '../calendar/calendar_data.dart';
import '../calendar/calendar_painter.dart';
import '../models/calendar_config.dart';
import 'calendar_config_store.dart';

/// 后台回调入口：重渲染日历位图并推送上桌。
///
/// 必须是顶层函数（PluginUtilities 只支持顶层/静态回调句柄）。
@pragma('vm:entry-point')
Future<void> calendarBackgroundCallback(Uri? uri) async {
  final configJson = await HomeWidget.getWidgetData<String>(
    CalendarConfigStore.widgetConfigKey,
  );
  if (configJson == null || configJson.isEmpty) return;
  final config = CalendarConfig.fromJsonString(configJson);

  final events = parseEventsJson(
    await HomeWidget.getWidgetData<String>(CalendarConfigStore.widgetEventsKey),
  );

  final now = DateTime.now();
  final grid = attachEvents(buildMonthGrid(now, config), events);

  // 渲染尺寸：原生写入的 "WxH"；缺失回落基准 4×4 × dpr
  var widthPx = (CalendarConfigStore.refWidthDp * 3).round();
  var heightPx = (CalendarConfigStore.refHeightDp * 3).round();
  final sizeRaw = await HomeWidget.getWidgetData<String>(
    CalendarConfigStore.widgetSizeKey,
  );
  if (sizeRaw != null) {
    final parts = sizeRaw.split('x');
    if (parts.length == 2) {
      final w = int.tryParse(parts[0]);
      final h = int.tryParse(parts[1]);
      if (w != null && h != null && w > 0 && h > 0) {
        widthPx = w;
        heightPx = h;
      }
    }
  }

  final backgroundImage = config.bgStyle == CalendarBgStyle.image &&
          config.bgImagePath.isNotEmpty
      ? await loadBackgroundImage(config.bgImagePath)
      : null;
  final bytes = await renderCalendarPng(
    config: config,
    grid: grid,
    widthPx: widthPx,
    heightPx: heightPx,
    backgroundImage: backgroundImage,
  );
  backgroundImage?.dispose();
  if (bytes == null) return;

  await HomeWidget.saveFile(
    CalendarConfigStore.widgetBitmapKey,
    bytes,
    extension: 'png',
  );
  await HomeWidget.updateWidget(androidName: 'CalendarWidgetProvider');
}

/// 注册回调（App 前台启动时调用一次，保存回调句柄）。
Future<bool?> registerCalendarBackgroundCallback() {
  return HomeWidget.registerInteractivityCallback(calendarBackgroundCallback);
}
