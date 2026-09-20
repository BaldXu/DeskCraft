import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/monitor_config.dart';

/// 系统监控配置的持久化与 widget 桥同步。
///
/// - App 侧：SharedPreferences 存 JSON（[_appConfigKey]）+ 最后刷新时间戳；
/// - widget 侧：home_widget 的 saveWidgetData 写入同一份 JSON
///   （原生 provider 读到的 SharedPreferences 即 home_widget 托管文件）。
class MonitorConfigStore {
  MonitorConfigStore._();

  /// 原生侧读取的 JSON key（home_widget 托管 SharedPreferences）。
  static const String widgetDataJsonKey = 'monitor_config_json';

  static const String _appConfigKey = 'monitor_config_v1';
  static const String _lastSyncKey = 'monitor_last_sync_ms';

  /// App 侧缓存：最近一次保存的 lastSyncAt（供首页展示）。
  static DateTime? lastSyncAt;

  static Future<MonitorConfig> load() async {
    final sp = await SharedPreferences.getInstance();
    lastSyncAt = sp.getInt(_lastSyncKey) == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(sp.getInt(_lastSyncKey)!);
    return MonitorConfig.fromJsonString(sp.getString(_appConfigKey));
  }

  /// 保存配置并推送到桌面 widget（数据桥：saveWidgetData → updateWidget）。
  /// 返回 updateWidget 的结果（true = 已通知 provider 重绘）。
  static Future<bool> saveAndPush(MonitorConfig config) async {
    final json = jsonEncode(config.toJson());
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_appConfigKey, json);
    await HomeWidget.saveWidgetData<String>(widgetDataJsonKey, json);
    final ok = await HomeWidget.updateWidget(
      androidName: 'MonitorWidgetProvider',
    );
    lastSyncAt = DateTime.now();
    await sp.setInt(_lastSyncKey, lastSyncAt!.millisecondsSinceEpoch);
    return ok == true;
  }
}
