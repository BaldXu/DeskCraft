// 图层布局模型测试（M6 m1）：JSON 往返、宽松回落、刷新周期聚合、copyWith。
import 'package:desk_craft/editor/layout_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toJson/fromJson 往返保持字段一致', () {
    final layout = WidgetLayout(
      id: 'custom-1001',
      name: '测试卡',
      layers: [
        RectLayer(
          id: 'r1',
          x: 10,
          y: 20.5,
          w: 60,
          h: 30,
          fillColor: 0xFF112233,
          cornerRadius: 8,
          opacity: 0.5,
        ),
        TextLayer(
          id: 't1',
          x: 0,
          y: 0,
          w: 100,
          h: 24,
          template: r'$tf("HH:mm:ss")$',
          fontSize: 16,
          color: 0xFFFF0000,
          bold: true,
          align: 'center',
        ),
      ],
    );

    final restored = WidgetLayout.fromJsonString(layout.toJsonString());

    expect(restored.id, 'custom-1001');
    expect(restored.name, '测试卡');
    expect(restored.canvasWidth, defaultCanvasWidth);
    expect(restored.canvasHeight, defaultCanvasHeight);
    expect(restored.layers.length, 2);

    final rect = restored.layers[0] as RectLayer;
    expect(rect.x, 10);
    expect(rect.y, 20.5);
    expect(rect.w, 60);
    expect(rect.h, 30);
    expect(rect.fillColor, 0xFF112233);
    expect(rect.cornerRadius, 8);
    expect(rect.opacity, 0.5);

    final text = restored.layers[1] as TextLayer;
    expect(text.template, r'$tf("HH:mm:ss")$');
    expect(text.fontSize, 16);
    expect(text.color, 0xFFFF0000);
    expect(text.bold, isTrue);
    expect(text.align, 'center');
    expect(restored.updatedAt, layout.updatedAt);
  });

  test('缺字段宽松回落默认值', () {
    final layout = WidgetLayout.fromJson(const {});
    expect(layout.id, 'custom-0');
    expect(layout.name, '未命名组件');
    expect(layout.canvasWidth, defaultCanvasWidth);
    expect(layout.canvasHeight, defaultCanvasHeight);
    expect(layout.layers, isEmpty);
  });

  test('未知 type 图层被跳过且不抛错', () {
    final layout = WidgetLayout.fromJson(const {
      'layers': [
        {'type': 'rect', 'id': 'r1'},
        {'type': 'progress', 'id': 'p1', 'x': 1, 'y': 2},
        {'type': 'text', 'id': 't1'},
      ],
    });
    expect(layout.layers.length, 2);
    expect(layout.layers[0].type, LayerType.rect);
    expect(layout.layers[1].type, LayerType.text);
    // 缺字段回落
    final rect = layout.layers[0] as RectLayer;
    expect(rect.fillColor, 0xFF3D5AFE);
    final text = layout.layers[1] as TextLayer;
    expect(text.align, 'left');
  });

  test('refreshSeconds 取各文本图层最小值', () {
    WidgetLayout build(List<LayoutLayer> layers) =>
        WidgetLayout(id: 'x', name: 'x', layers: layers);

    // 含秒变量 → 1
    expect(
      build([
        TextLayer(id: 't', x: 0, y: 0, w: 10, h: 10, template: r'$second$'),
      ]).refreshSeconds,
      1,
    );
    // 分钟级时间格式 → 60
    expect(
      build([
        TextLayer(
          id: 't',
          x: 0,
          y: 0,
          w: 10,
          h: 10,
          template: r'$tf("HH:mm")$',
        ),
      ]).refreshSeconds,
      60,
    );
    // 快照变量 → 30
    expect(
      build([
        TextLayer(id: 't', x: 0, y: 0, w: 10, h: 10, template: r'$batTemp$'),
      ]).refreshSeconds,
      30,
    );
    // 纯矩形 → 3600
    expect(
      build([RectLayer(id: 'r', x: 0, y: 0, w: 10, h: 10)]).refreshSeconds,
      3600,
    );
    // 混合取最小：文本 60 + 秒文本 1 → 1
    expect(
      build([
        TextLayer(
          id: 'a',
          x: 0,
          y: 0,
          w: 10,
          h: 10,
          template: r'$tf("HH:mm")$',
        ),
        RectLayer(id: 'r', x: 0, y: 0, w: 10, h: 10),
        TextLayer(
          id: 'b',
          x: 0,
          y: 0,
          w: 10,
          h: 10,
          template: r'$hour$:$second$',
        ),
      ]).refreshSeconds,
      1,
    );
  });

  test('copyWith 替换指定字段', () {
    final layout = WidgetLayout(
      id: 'a',
      name: '旧名',
      layers: [RectLayer(id: 'r', x: 0, y: 0, w: 10, h: 10)],
    );
    final copied = layout.copyWith(name: '新名', updatedAt: 123);
    expect(copied.id, 'a');
    expect(copied.name, '新名');
    expect(copied.updatedAt, 123);
    expect(copied.layers, same(layout.layers));
  });
}
