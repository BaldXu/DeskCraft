/// 布局画布绘制核心（M6 m2）——纯 dart:ui 实现，预览与位图导出共享。
///
/// 坐标单位为 dp，通过 [scale] 换算为像素。不依赖 widget 树与
/// implicitView，因此在前台编辑器与后台 headless 引擎中均可使用。
library;

import 'dart:ui' as ui;

import '../formula/formula_context.dart';
import '../formula/formula_engine.dart';
import 'layout_model.dart';

/// 把整卡布局绘制到画布（画布原点为布局左上角）。
///
/// [scale]：dp → 像素缩放系数（通常取设备 pixelRatio）。
/// [background]：画布底色，null 为透明。
/// [context]：公式求值上下文；null 时文本模板原样绘制（如流程示意）。
/// [selectedLayerId]：编辑器选中高亮（预览专用，导出不传）。
void paintLayout(
  ui.Canvas canvas,
  WidgetLayout layout, {
  required double scale,
  FormulaContext? context,
  ui.Color? background,
  String? selectedLayerId,
}) {
  final size = ui.Size(layout.canvasWidth * scale, layout.canvasHeight * scale);
  if (background != null) {
    canvas.drawRect(ui.Offset.zero & size, ui.Paint()..color = background);
  }

  for (final layer in layout.layers) {
    canvas.save();
    final paint = ui.Paint()
      ..color = ui.Color(0x00000000).withValues(alpha: layer.opacity);
    if (layer.opacity < 1) {
      // 半透明图层统一走 saveLayer，避免逐元素调 alpha
      canvas.saveLayer(ui.Offset.zero & size, paint);
    }
    switch (layer) {
      case RectLayer():
        _paintRect(canvas, layer, scale);
      case TextLayer():
        _paintText(canvas, layer, scale, context);
    }
    if (layer.opacity < 1) {
      canvas.restore(); // saveLayer
    }
    canvas.restore();

    if (selectedLayerId != null && layer.id == selectedLayerId) {
      _paintSelection(canvas, layer, scale);
    }
  }
}

void _paintRect(ui.Canvas canvas, RectLayer layer, double scale) {
  final rect = ui.Rect.fromLTWH(
    layer.x * scale,
    layer.y * scale,
    layer.w * scale,
    layer.h * scale,
  );
  final rrect = ui.RRect.fromRectAndRadius(
    rect,
    ui.Radius.circular(layer.cornerRadius * scale),
  );
  canvas.drawRRect(rrect, ui.Paint()..color = ui.Color(layer.fillColor));
}

void _paintText(
  ui.Canvas canvas,
  TextLayer layer,
  double scale,
  FormulaContext? context,
) {
  // 文本模板先经公式引擎求值；无上下文时原样绘制
  final rendered = context == null
      ? layer.template
      : FormulaEngine.render(layer.template, context).text;
  final paragraphStyle = ui.ParagraphStyle(
    textAlign: switch (layer.align) {
      'center' => ui.TextAlign.center,
      'right' => ui.TextAlign.right,
      _ => ui.TextAlign.left,
    },
    fontSize: layer.fontSize * scale,
    fontWeight: layer.bold ? ui.FontWeight.bold : ui.FontWeight.normal,
  );
  final builder = ui.ParagraphBuilder(paragraphStyle)
    ..pushStyle(
      ui.TextStyle(
        color: ui.Color(layer.color),
        fontFamilyFallback: const ['sans-serif'],
      ),
    )
    ..addText(rendered);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: layer.w * scale));
  canvas.drawParagraph(paragraph, ui.Offset(layer.x * scale, layer.y * scale));
}

/// 预览态选中框（蓝色描边 + 角点），仅编辑器使用。
void _paintSelection(ui.Canvas canvas, LayoutLayer layer, double scale) {
  final rect = ui.Rect.fromLTWH(
    layer.x * scale - 2,
    layer.y * scale - 2,
    layer.w * scale + 4,
    layer.h * scale + 4,
  );
  canvas.drawRect(
    rect,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const ui.Color(0xFF2196F3),
  );
}

/// 水平对齐样式 → ui.TextAlign（导出侧公共工具）。
ui.TextAlign textAlignOf(String align) => switch (align) {
  'center' => ui.TextAlign.center,
  'right' => ui.TextAlign.right,
  _ => ui.TextAlign.left,
};
