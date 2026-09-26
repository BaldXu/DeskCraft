import 'dart:convert';
import 'dart:ui' as ui;

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../calendar/calendar_data.dart';
import '../calendar/calendar_painter.dart';
import '../models/calendar_config.dart';
import 'calendar_bridge.dart';

/// 日历组件配置持久化与上桌推送。
///
/// - App 侧：SharedPreferences 存配置 JSON（[appConfigKey]）+ 最后同步时间戳；
/// - widget 桥：home_widget 托管 SharedPreferences，key 见下方常量；
/// - 上桌：前台按 widget 实际尺寸（未上桌回落到基准 4×4）渲染 PNG
///   （saveFile 落盘）→ 写配置 / 尺寸 / dpr → updateWidget 通知原生 provider。
class CalendarConfigStore {
  CalendarConfigStore._();

  /// 原生侧读取的 JSON key（home_widget 托管 SharedPreferences）。
  static const String widgetConfigKey = 'calendar_config_json';

  /// 位图 PNG 路径 key（saveFile 写入，原生 ImageView 显示）。
  static const String widgetBitmapKey = 'calendar_bitmap';

  /// 渲染尺寸（px）key，格式 "WxH"（原生 onAppWidgetOptionsChanged 会更新）。
  static const String widgetSizeKey = 'calendar_widget_size';

  /// 渲染像素比 key（后台 headless 引擎拿不到 dpr，上桌时存下）。
  static const String widgetDprKey = 'calendar_widget_dpr';

  /// 系统日历事件 JSON key（原生查询后写入，后台回调读取渲染）。
  static const String widgetEventsKey = 'calendar_events_json';

  static const String _appConfigKey = 'calendar_config_v1';
  static const String _lastSyncKey = 'calendar_last_sync_ms';

  /// 基准尺寸：4×4 格（dp），未上桌 / 拿不到尺寸时的渲染兜底。
  static const double refWidthDp = 250;
  static const double refHeightDp = 220;

  /// App 侧缓存：最近一次保存的 lastSyncAt（供首页展示）。
  static DateTime? lastSyncAt;

  static Future<CalendarConfig> load() async {
    final sp = await SharedPreferences.getInstance();
    lastSyncAt = sp.getInt(_lastSyncKey) == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(sp.getInt(_lastSyncKey)!);
    return CalendarConfig.fromJsonString(sp.getString(_appConfigKey));
  }

  /// 保存配置并推送到桌面 widget。
  ///
  /// 渲染链路：查询系统日历事件（有权限时）→ 按 widget 实际尺寸渲染 PNG →
  /// saveFile 落盘 → 写配置/尺寸/dpr → updateWidget。
  /// 返回 updateWidget 的结果（true = 已通知 provider 重绘）。
  static Future<bool> saveAndPush(CalendarConfig config) async {
    final now = DateTime.now();
    final grid = buildMonthGrid(now, config);

    // 事件（权限已授予才查；未授予显示农历/节气）
    var events = const <String, List<String>>{};
    if (config.showCalendarEvents && await CalendarBridge.checkPermission()) {
      events = await CalendarBridge.queryMonthEvents(now.year, now.month);
    }
    final gridWithEvents = attachEvents(grid, events);

    // 渲染尺寸：优先 widget 实际尺寸，回落基准 4×4
    final size = await CalendarBridge.widgetSizePx();
    final widthPx = size?.$1 ?? (refWidthDp * 3).round();
    final heightPx = size?.$2 ?? (refHeightDp * 3).round();

    final backgroundImage = config.bgStyle == CalendarBgStyle.image &&
            config.bgImagePath.isNotEmpty
        ? await loadBackgroundImage(config.bgImagePath)
        : null;
    final bytes = await renderCalendarPng(
      config: config,
      grid: gridWithEvents,
      widthPx: widthPx,
      heightPx: heightPx,
      backgroundImage: backgroundImage,
    );
    backgroundImage?.dispose();
    if (bytes == null) return false;

    final json = jsonEncode(config.toJson());
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_appConfigKey, json);

    await HomeWidget.saveFile(widgetBitmapKey, bytes, extension: 'png');
    await HomeWidget.saveWidgetData<String>(widgetConfigKey, json);
    await HomeWidget.saveWidgetData<String>(
      widgetSizeKey,
      '${widthPx}x$heightPx',
    );
    await HomeWidget.saveWidgetData<double>(
      widgetDprKey,
      ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 3.0,
    );
    await HomeWidget.saveWidgetData<String>(
      widgetEventsKey,
      jsonEncode(events),
    );

    final ok = await HomeWidget.updateWidget(androidName: 'CalendarWidgetProvider');
    lastSyncAt = DateTime.now();
    await sp.setInt(_lastSyncKey, lastSyncAt!.millisecondsSinceEpoch);
    return ok == true;
  }
}
