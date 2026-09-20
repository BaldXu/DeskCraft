import 'package:home_widget/home_widget.dart';

/// 桌面组件「已上桌」检测与一键添加（Android 8+ requestPinWidget 系统弹窗）。
///
/// 统一收口，供各组件类目页共用；查询失败一律降级为"未添加"，
/// 由调用方决定是否提示用户手动添加。
abstract final class WidgetPinService {
  /// 桌面上是否已存在该 Provider 的组件实例。
  static Future<bool> isPinned(String providerName) async {
    try {
      final widgets = await HomeWidget.getInstalledWidgets();
      return widgets.any(
        (w) => w.androidClassName?.contains(providerName) ?? false,
      );
    } catch (_) {
      return false; // 桌面不支持查询时降级为未添加
    }
  }

  /// 一键添加到桌面（系统弹窗确认）。
  static Future<void> requestPin(String providerName) {
    return HomeWidget.requestPinWidget(androidName: providerName);
  }
}
