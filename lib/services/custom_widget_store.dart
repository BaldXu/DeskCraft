/// 自定义组件布局存储与上桌推送服务（M6 m3）。
///
/// - App 侧布局库：SharedPreferences（key [_layoutsKey]，JSON 数组）；
/// - widget 桥：home_widget 托管 SharedPreferences，key 见下方常量；
/// - 上桌：前台渲染 PNG（saveFile 落盘 `{appSupport}/home_widget/`）
///   → saveWidgetData 写布局 / dpr / 刷新周期 → updateWidget 通知原生 provider。
///
/// V1 约定：同一时刻只有一个「激活布局」上桌（与 monitor/clock 模式一致），
/// 多布局草稿保存在 App 侧布局库中。
library;

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../editor/layout_bitmap.dart';
import '../editor/layout_model.dart';
import '../formula/formula_context.dart';
import 'global_var_store.dart';

/// 原生采样快照 → 公式变量名的映射（key 与 MonitorDataSource 输出对齐）。
const Map<String, String> _nativeVarMapping = {
  'batteryTempC': 'batTemp',
  'cpuUsagePercent': 'cpuUsage',
  'memUsagePercent': 'memUsage',
  'cpuFreqMaxGhz': 'cpuFreqMax',
  'cpuFreqMinGhz': 'cpuFreqMin',
};

class CustomWidgetStore {
  CustomWidgetStore._();

  /// widget 桥：位图 PNG 路径（saveFile 写入，原生 ImageView 显示）。
  static const String widgetBitmapKey = 'custom_widget_bitmap';

  /// widget 桥：激活布局 JSON（后台回调重渲染用）。
  static const String widgetLayoutKey = 'custom_widget_layout';

  /// widget 桥：渲染像素比（后台 headless 引擎拿不到 dpr，上桌时存下）。
  static const String widgetDprKey = 'custom_widget_dpr';

  /// widget 桥：刷新周期（秒），原生 AlarmManager 调度用。
  static const String widgetRefreshKey = 'custom_widget_refresh_seconds';

  /// widget 桥：最近系统采样快照 JSON（原生侧写入，Dart 渲染时读取）。
  static const String widgetVarsKey = 'custom_widget_vars_json';

  /// App 侧布局库 key。
  static const String _layoutsKey = 'custom_widget_layouts_v1';

  // ---- 布局库 ----

  static Future<List<WidgetLayout>> loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_layoutsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<Object?>;
      return list
          .whereType<Map<String, Object?>>()
          .map(WidgetLayout.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 新增或按 id 更新布局（自动刷新 updatedAt），返回保存后的布局。
  static Future<WidgetLayout> saveLayout(WidgetLayout layout) async {
    final updated = layout.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final all = await loadAll();
    final index = all.indexWhere((l) => l.id == updated.id);
    if (index >= 0) {
      all[index] = updated;
    } else {
      all.add(updated);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _layoutsKey,
      jsonEncode(all.map((l) => l.toJson()).toList()),
    );
    return updated;
  }

  static Future<void> deleteLayout(String id) async {
    final all = await loadAll().then(
      (list) => list.where((l) => l.id != id).toList(),
    );
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _layoutsKey,
      jsonEncode(all.map((l) => l.toJson()).toList()),
    );
  }

  // ---- 渲染上下文 ----

  /// 读取最近一次原生采样快照并映射为公式变量。
  static Future<Map<String, Object?>> loadWidgetVars() async {
    final raw = await HomeWidget.getWidgetData<String>(widgetVarsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return {};
      final vars = <String, Object?>{};
      json.forEach((key, value) {
        if (value == null) return;
        vars[_nativeVarMapping[key] ?? key] = value;
      });
      return vars;
    } catch (_) {
      return {};
    }
  }

  /// 构造渲染上下文：当前时间 + 最近采样变量 + 已解析的全局变量。
  static Future<FormulaContext> renderContext() async {
    final vars = await loadWidgetVars();
    final globals = await GlobalVarStore.loadResolvedGlobals(variables: vars);
    return FormulaContext(
      now: DateTime.now(),
      variables: vars,
      globals: globals,
    );
  }

  // ---- 上桌推送 ----

  /// 渲染布局为位图并推送到桌面 widget。
  ///
  /// [pixelRatio] 缺省取当前视图 dpr（后台调用请显式传入）。
  /// 返回 updateWidget 结果（true = 已通知原生 provider）。
  static Future<bool> pushToDesktop(
    WidgetLayout layout, {
    double? pixelRatio,
    ui.Color? background,
  }) async {
    final dpr =
        pixelRatio ??
        ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
        3.0;
    final context = await renderContext();
    final bytes = await exportLayoutPng(
      layout,
      context: context,
      pixelRatio: dpr,
      background: background,
    );
    if (bytes == null) return false;

    // 位图落盘（saveFile 内部把路径写入 widgetBitmapKey）
    await HomeWidget.saveFile(widgetBitmapKey, bytes, extension: 'png');

    await HomeWidget.saveWidgetData<String>(
      widgetLayoutKey,
      layout.toJsonString(),
    );
    await HomeWidget.saveWidgetData<double>(widgetDprKey, dpr);
    await HomeWidget.saveWidgetData<int>(
      widgetRefreshKey,
      await GlobalVarStore.effectiveRefreshSecondsFor(layout),
    );

    final ok = await HomeWidget.updateWidget(
      androidName: 'CustomWidgetProvider',
    );
    return ok == true;
  }

  /// 用当前（最新）全局变量与采样重新渲染「激活布局」并推送桌面。
  ///
  /// 全局变量编辑后调用：让桌面组件立即反映最新值，不必等下一次 Alarm 刷新。
  /// 没有激活布局时返回 false。
  static Future<bool> refreshDesktop() async {
    final layoutJson = await HomeWidget.getWidgetData<String>(widgetLayoutKey);
    if (layoutJson == null || layoutJson.isEmpty) return false;
    WidgetLayout layout;
    try {
      layout = WidgetLayout.fromJsonString(layoutJson);
    } catch (_) {
      return false;
    }
    final dpr =
        await HomeWidget.getWidgetData<double>(widgetDprKey) ??
        ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
        3.0;
    return pushToDesktop(layout, pixelRatio: dpr);
  }

  // ---- 默认布局 ----

  /// 新建布局的默认内容：深色底 + 大时钟 + 副标题。
  static WidgetLayout defaultLayout() {
    return WidgetLayout(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: '我的组件',
      layers: [
        RectLayer(
          id: 'bg',
          x: 0,
          y: 0,
          w: defaultCanvasWidth,
          h: defaultCanvasHeight,
          fillColor: 0xF0101018,
          cornerRadius: 16,
        ),
        TextLayer(
          id: 'clock',
          x: 16,
          y: 18,
          w: 150,
          h: 40,
          template: r'$tf("HH:mm:ss")$',
          fontSize: 26,
          bold: true,
          color: 0xFFFFFFFF,
        ),
        TextLayer(
          id: 'info',
          x: 16,
          y: 62,
          w: 218,
          h: 20,
          template: r'$batTemp$°C · CPU $cpuUsage$%',
          fontSize: 13,
          color: 0xCCFFFFFF,
        ),
      ],
    );
  }
}
