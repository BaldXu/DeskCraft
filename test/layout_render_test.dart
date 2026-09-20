// 布局渲染测试（M6 m2）：位图导出基础可用性 + painter 不崩。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:desk_craft/editor/layout_bitmap.dart';
import 'package:desk_craft/editor/layout_model.dart';
import 'package:desk_craft/editor/layout_painter.dart';
import 'package:desk_craft/formula/formula_context.dart';
import 'package:flutter_test/flutter_test.dart';

FormulaContext _ctx() => FormulaContext(
  now: DateTime(2026, 9, 20, 14, 5, 9),
  variables: const {
    'batTemp': 33.5,
    'cpuUsage': 12,
    'memUsage': 40,
    'cpuFreqMax': 2.84,
    'cpuFreqMin': 1.2,
  },
);

WidgetLayout _layout() => WidgetLayout(
  id: 'custom-1',
  name: '渲染测试',
  layers: [
    RectLayer(
      id: 'r1',
      x: 8,
      y: 8,
      w: 60,
      h: 30,
      fillColor: 0xFF3D5AFE,
      cornerRadius: 6,
      opacity: 0.8,
    ),
    TextLayer(
      id: 't1',
      x: 10,
      y: 10,
      w: 120,
      h: 24,
      template: r'$tf("HH:mm:ss")$ 温度 $batTemp$°C',
      fontSize: 14,
      bold: true,
      align: 'center',
    ),
  ],
);

void main() {
  test('paintLayout 空布局与完整布局均可绘制', () {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    paintLayout(canvas, WidgetLayout(id: 'x', name: 'x'), scale: 2);
    paintLayout(
      canvas,
      _layout(),
      scale: 2,
      context: _ctx(),
      background: const ui.Color(0xFF111111),
    );
    recorder.endRecording();
  });

  test('exportLayoutPng 输出 PNG 字节', () async {
    final bytes = await exportLayoutPng(
      _layout(),
      context: _ctx(),
      pixelRatio: 2,
      background: const ui.Color(0xFF101010),
    );
    expect(bytes, isNotNull);
    expect(bytes!.lengthInBytes, greaterThan(100));
    // PNG 魔数
    final magic = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
    expect(bytes.sublist(0, 4), magic);
  });

  test('exportLayoutPng 透明背景同样可用', () async {
    final bytes = await exportLayoutPng(
      _layout(),
      context: _ctx(),
      pixelRatio: 1,
    );
    expect(bytes, isNotNull);
  });

  test('textAlignOf 映射', () {
    expect(textAlignOf('center'), ui.TextAlign.center);
    expect(textAlignOf('right'), ui.TextAlign.right);
    expect(textAlignOf('left'), ui.TextAlign.left);
    expect(textAlignOf('unknown'), ui.TextAlign.left);
  });
}
