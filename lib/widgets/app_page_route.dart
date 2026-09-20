import 'package:flutter/material.dart';

/// 全局页面路由：退出动画比进入动画长 35%。
///
/// 进入保持 300ms；退出 405ms（300 × 1.35）——返回时页面离开更从容，
/// 与预测性返回手势的回落衔接也更自然。全项目页面跳转统一使用本路由。
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });

  static const int _enterMs = 300;

  @override
  Duration get transitionDuration => const Duration(milliseconds: _enterMs);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 405); // 300 × 1.35
}
