/// 布局预览画布 widget（M6 e1 编辑器用）——把 [paintLayout] 包装为 CustomPaint。
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../formula/formula_context.dart';
import 'layout_model.dart';
import 'layout_painter.dart';

/// 按整卡布局绘制预览；[scale] 为显示缩放（dp → 逻辑像素）。
class LayoutPreviewCanvas extends StatelessWidget {
  const LayoutPreviewCanvas({
    super.key,
    required this.layout,
    required this.scale,
    this.context,
    this.background,
    this.selectedLayerId,
  });

  final WidgetLayout layout;
  final double scale;

  /// 公式求值上下文；null 时文本模板原样显示。
  final FormulaContext? context;

  /// 画布底色；null 为透明。
  final ui.Color? background;

  /// 选中的图层 id（高亮描边）。
  final String? selectedLayerId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: layout.canvasWidth * scale,
      height: layout.canvasHeight * scale,
      child: CustomPaint(
        painter: _LayoutPreviewPainter(
          layout: layout,
          scale: scale,
          formulaContext: this.context,
          background: background,
          selectedLayerId: selectedLayerId,
        ),
      ),
    );
  }
}

class _LayoutPreviewPainter extends CustomPainter {
  _LayoutPreviewPainter({
    required this.layout,
    required this.scale,
    required this.formulaContext,
    required this.background,
    required this.selectedLayerId,
  });

  final WidgetLayout layout;
  final double scale;
  final FormulaContext? formulaContext;
  final ui.Color? background;
  final String? selectedLayerId;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    paintLayout(
      canvas,
      layout,
      scale: scale,
      context: formulaContext,
      background: background,
      selectedLayerId: selectedLayerId,
    );
  }

  @override
  bool shouldRepaint(_LayoutPreviewPainter oldDelegate) {
    return layout != oldDelegate.layout ||
        scale != oldDelegate.scale ||
        background != oldDelegate.background ||
        selectedLayerId != oldDelegate.selectedLayerId ||
        formulaContext?.now != oldDelegate.formulaContext?.now;
  }
}
