/// 自定义组件后台刷新回调（M6 m4）。
///
/// 链路：原生 AlarmManager → CustomWidgetProvider.onReceive
/// → `HomeWidgetBackgroundWorker.enqueueWork`（headless FlutterEngine）
/// → [callbackDispatcher]（home_widget 内置）
/// → [customWidgetBackgroundCallback]（本文件，顶层函数，可被回调句柄引用）。
///
/// 回调内完成：读取布局 JSON + dpr + 最新采样变量 → 重渲染位图 →
/// saveFile 覆盖位图 → updateWidget 通知原生 provider 重绘。
///
/// 注意：headless 引擎中没有 implicitView，因此渲染必须走
/// exportLayoutPng（纯 PictureRecorder），不能用 renderFlutterWidget。
library;

import 'package:home_widget/home_widget.dart';

import '../editor/layout_bitmap.dart';
import '../editor/layout_model.dart';
import 'custom_widget_store.dart';

/// 后台回调入口：重渲染激活布局并推送上桌。
///
/// 必须是顶层函数（PluginUtilities 只支持顶层/静态回调句柄）。
@pragma('vm:entry-point')
Future<void> customWidgetBackgroundCallback(Uri? uri) async {
  final layoutJson = await HomeWidget.getWidgetData<String>(
    CustomWidgetStore.widgetLayoutKey,
  );
  if (layoutJson == null || layoutJson.isEmpty) return;

  WidgetLayout layout;
  try {
    layout = WidgetLayout.fromJsonString(layoutJson);
  } catch (_) {
    return;
  }

  final dpr =
      await HomeWidget.getWidgetData<double>(CustomWidgetStore.widgetDprKey) ??
      3.0;
  // 读取最近采样变量 + 全局变量，构造渲染上下文
  final context = await CustomWidgetStore.renderContext();

  final bytes = await exportLayoutPng(
    layout,
    context: context,
    pixelRatio: dpr,
  );
  if (bytes == null) return;

  // saveFile 内部会把新路径写入 widgetBitmapKey
  await HomeWidget.saveFile(
    CustomWidgetStore.widgetBitmapKey,
    bytes,
    extension: 'png',
  );
  await HomeWidget.updateWidget(androidName: 'CustomWidgetProvider');
}

/// 注册回调（App 前台启动时调用一次，保存回调句柄）。
Future<bool?> registerCustomWidgetBackgroundCallback() {
  return HomeWidget.registerInteractivityCallback(
    customWidgetBackgroundCallback,
  );
}
