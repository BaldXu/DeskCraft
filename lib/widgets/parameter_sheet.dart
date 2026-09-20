import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 通用「设置参数」底部弹窗。
///
/// 视觉与动效：
/// - 从屏幕底部非线性平移进入（easeOutCubic），退出用 easeInCubic 回落；
/// - 弹窗以外背景的模糊程度与平移进度联动：进入时逐渐变模糊，退出时逐渐清晰；
/// - 默认占屏高 80%，四角 G2 连续曲率大圆角（[ContinuousRectangleBorder]）；
/// - 点击弹窗外区域或系统返回关闭。
///
/// 定位：全项目「设置参数」类弹窗统一使用本组件（如刷新周期、图层属性）；
/// 提示 / 确认等轻量对话框不使用本组件，另走 [showDialog]。
Future<T?> showParameterSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double heightFactor = 0.8,
  bool isDismissible = true,
}) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<T>(_ParameterSheetRoute<T>(builder, heightFactor, isDismissible));
}

final class _ParameterSheetRoute<T> extends PopupRoute<T> {
  _ParameterSheetRoute(this._builder, this._heightFactor, this._isDismissible);

  final WidgetBuilder _builder;
  final double _heightFactor;
  final bool _isDismissible;

  static const double _maxBlurSigma = 18;
  static const double _maxScrimAlpha = 0.45;

  @override
  Color? get barrierColor => Colors.transparent; // scrim 自绘，与模糊联动

  @override
  bool get barrierDismissible => _isDismissible;

  @override
  String? get barrierLabel => '设置弹窗';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 380);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        // 浮岛式：四周留 12dp，让四角大圆角都可见
        padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            height: screenHeight * _heightFactor - bottomInset,
            decoration: ShapeDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              shape: ContinuousRectangleBorder(
                borderRadius: BorderRadius.circular(36),
              ),
            ),
            child: _builder(context),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 一条曲线同时驱动三个量：平移、背景模糊、scrim 亮度，
    // 保证「背景模糊程度 = 弹窗平移程度」严格联动。
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, page) {
        final t = curved.value;
        return Stack(
          children: [
            // 背景层：模糊 + 压暗（clip 防止模糊晕染出屏幕边缘）
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: _maxBlurSigma * t,
                      sigmaY: _maxBlurSigma * t,
                    ),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: _maxScrimAlpha * t),
                    ),
                  ),
                ),
              ),
            ),
            // 弹窗本体：按自身高度从底部平移进出场
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionalTranslation(
                translation: Offset(0, 1 - t),
                child: page,
              ),
            ),
          ],
        );
      },
    );
  }
}
