/// 布局 → PNG 位图导出（M6 m2）。
///
/// 纯 dart:ui（PictureRecorder），不依赖 widget 树与 implicitView，
/// 因此前台编辑器与后台 headless 回调引擎中均可调用。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import '../formula/formula_context.dart';
import 'layout_model.dart';
import 'layout_painter.dart';

/// 把整卡布局渲染为 PNG 字节。
///
/// [pixelRatio]：dp → 像素缩放系数，输出尺寸 = 画布 dp × pixelRatio。
/// [background]：底色，null 为透明背景（widget 常用）。
Future<Uint8List?> exportLayoutPng(
  WidgetLayout layout, {
  required FormulaContext context,
  required double pixelRatio,
  ui.Color? background,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paintLayout(
    canvas,
    layout,
    scale: pixelRatio,
    context: context,
    background: background,
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      (layout.canvasWidth * pixelRatio).round(),
      (layout.canvasHeight * pixelRatio).round(),
    );
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
