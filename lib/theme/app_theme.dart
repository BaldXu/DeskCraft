import 'package:flutter/material.dart';

/// DeskCraft App 主题系统（M3）。
///
/// 深色优先（组件工坊在手机上长期使用，深色更省电也更贴合桌面 widget 风格），
/// 主色为紫罗兰色系，与 M1 数字时钟默认背景呼应。
abstract final class AppTheme {
  /// 主色：紫罗兰。
  static const Color seed = Color(0xFF7C8CF8);

  /// 全局深色主题。
  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: seed,
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(centerTitle: false),
      // 页面转场：Android 用预测性返回转场（手势拖拽 → 松手有完整的
      // 进入/退出补间，不会瞬间消失），iOS 用 Cupertino 左右滑转场。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: base.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: base.colorScheme.outlineVariant.withValues(alpha: 0.4),
        space: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
