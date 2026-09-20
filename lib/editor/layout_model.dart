/// 自定义组件图层布局模型（M6 ②图层画布最小闭环）。
///
/// V1 支持两类图层：矩形（[RectLayer]）与文本（[TextLayer]）。
/// 坐标单位统一为 dp（与原生 widget 的 dp 基准一致，默认画布 250×110 对应 4×2 格）。
///
/// 文本图层内容为公式模板（`$表达式$`，见 formula/formula_engine.dart），
/// 渲染时由公式引擎求值替换。
///
/// JSON 序列化遵循项目兼容约定：缺字段宽松回落默认值，未知 type 图层跳过不抛错。
library;

import 'dart:convert';

import '../formula/formula_engine.dart';

/// 图层类型。
enum LayerType { rect, text }

/// 布局 JSON 版本，结构变更时递增。
const int layoutSchemaVersion = 1;

/// 默认画布尺寸（dp），对应 4×2 格 widget，与原生 REF_WIDTH/HEIGHT 基准一致。
const double defaultCanvasWidth = 250;
const double defaultCanvasHeight = 110;

/// 图层公共字段。
sealed class LayoutLayer {
  LayoutLayer({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.opacity = 1,
  });

  /// 图层唯一 id（生成后不再变化，编辑器以 id 定位图层）。
  String id;

  /// 相对画布左上角的位置（dp）。
  double x;
  double y;

  /// 图层尺寸（dp）。
  double w;
  double h;

  /// 不透明度 0~1，1 为完全不透明。
  double opacity;

  LayerType get type;

  Map<String, Object?> toJson() {
    return {
      'type': type.name,
      'id': id,
      'x': _num(x),
      'y': _num(y),
      'w': _num(w),
      'h': _num(h),
      'opacity': _num(opacity),
    };
  }

  /// 公共字段从 JSON 回填（缺字段保留当前值）。
  void fillCommonFromJson(Map<String, Object?> json) {
    id = _readString(json, 'id', id);
    x = _readDouble(json, 'x', x);
    y = _readDouble(json, 'y', y);
    w = _readDouble(json, 'w', w);
    h = _readDouble(json, 'h', h);
    opacity = _readDouble(json, 'opacity', opacity).clamp(0, 1).toDouble();
  }
}

/// 矩形图层：纯色填充 + 圆角。
class RectLayer extends LayoutLayer {
  RectLayer({
    required super.id,
    required super.x,
    required super.y,
    required super.w,
    required super.h,
    super.opacity,
    this.fillColor = 0xFF3D5AFE,
    this.cornerRadius = 0,
  });

  /// 填充色，ARGB 整数（0xAARRGGBB）。
  int fillColor;

  /// 圆角半径（dp），0 为直角。
  double cornerRadius;

  @override
  LayerType get type => LayerType.rect;

  @override
  Map<String, Object?> toJson() {
    return {
      ...super.toJson(),
      'fillColor': fillColor,
      'cornerRadius': _num(cornerRadius),
    };
  }
}

/// 文本图层：公式模板 + 样式。
class TextLayer extends LayoutLayer {
  TextLayer({
    required super.id,
    required super.x,
    required super.y,
    required super.w,
    required super.h,
    super.opacity,
    this.template = r'$tf("HH:mm")$',
    this.fontSize = 14,
    this.color = 0xFFFFFFFF,
    this.bold = false,
    this.align = 'left',
  });

  /// 文本模板，`$表达式$` 片段在渲染时由公式引擎求值。
  String template;

  /// 字号（dp）。
  double fontSize;

  /// 文本颜色，ARGB 整数。
  int color;

  bool bold;

  /// 水平对齐：left / center / right。
  String align;

  @override
  LayerType get type => LayerType.text;

  @override
  Map<String, Object?> toJson() {
    return {
      ...super.toJson(),
      'template': template,
      'fontSize': _num(fontSize),
      'color': color,
      'bold': bold,
      'align': align,
    };
  }

  @override
  void fillCommonFromJson(Map<String, Object?> json) {
    super.fillCommonFromJson(json);
    template = _readString(json, 'template', template);
    fontSize = _readDouble(json, 'fontSize', fontSize);
    color = _readInt(json, 'color', color);
    bold = _readBool(json, 'bold', bold);
    align = _readString(json, 'align', align);
  }
}

/// 整卡布局：画布尺寸 + 有序图层列表（列表顺序即 z 序，后者在上）。
class WidgetLayout {
  WidgetLayout({
    required this.id,
    required this.name,
    this.canvasWidth = defaultCanvasWidth,
    this.canvasHeight = defaultCanvasHeight,
    List<LayoutLayer>? layers,
    int? updatedAt,
  }) : layers = layers ?? [],
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 组件实例 id（custom-<时间戳>），同时是存储 key 与 widget id 的一部分。
  String id;
  String name;

  /// 画布尺寸（dp）。
  double canvasWidth;
  double canvasHeight;

  /// 图层列表，顺序即绘制顺序（后绘制者在上方）。
  List<LayoutLayer> layers;

  /// 最近保存时间（epoch 毫秒）。
  int updatedAt;

  /// 有效刷新周期（秒）：各文本图层模板刷新周期的最小值；
  /// 无文本或全静态时为 3600。
  int get refreshSeconds {
    var min = 3600;
    for (final layer in layers) {
      if (layer is! TextLayer) continue;
      final s = FormulaEngine.analyzeRefreshSeconds(layer.template);
      if (s < min) min = s;
    }
    return min;
  }

  WidgetLayout copyWith({
    String? id,
    String? name,
    double? canvasWidth,
    double? canvasHeight,
    List<LayoutLayer>? layers,
    int? updatedAt,
  }) {
    return WidgetLayout(
      id: id ?? this.id,
      name: name ?? this.name,
      canvasWidth: canvasWidth ?? this.canvasWidth,
      canvasHeight: canvasHeight ?? this.canvasHeight,
      layers: layers ?? this.layers,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': layoutSchemaVersion,
      'id': id,
      'name': name,
      'canvas': {'width': _num(canvasWidth), 'height': _num(canvasHeight)},
      'layers': layers.map((l) => l.toJson()).toList(),
      'updatedAt': updatedAt,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  /// 从 JSON 反序列化：缺字段宽松回落，未知 type 图层跳过。
  factory WidgetLayout.fromJson(Map<String, Object?> json) {
    final canvas = _asMap(json['canvas']);
    final rawLayers = _asList(json['layers']);
    final layers = <LayoutLayer>[];
    for (final item in rawLayers) {
      final layer = _layerFromJson(_asMap(item));
      if (layer != null) layers.add(layer);
    }
    return WidgetLayout(
      id: _readString(json, 'id', 'custom-0'),
      name: _readString(json, 'name', '未命名组件'),
      canvasWidth: _readDouble(canvas, 'width', defaultCanvasWidth),
      canvasHeight: _readDouble(canvas, 'height', defaultCanvasHeight),
      layers: layers,
      updatedAt: _readInt(json, 'updatedAt', 0),
    );
  }

  factory WidgetLayout.fromJsonString(String source) =>
      WidgetLayout.fromJson(_asMap(jsonDecode(source)));

  /// 单个图层 JSON → 图层对象；type 未知返回 null（调用方跳过）。
  static LayoutLayer? _layerFromJson(Map<String, Object?> json) {
    final type = json['type'];
    switch (type) {
      case 'rect':
        final layer = RectLayer(
          id: _readString(json, 'id', ''),
          x: _readDouble(json, 'x', 0),
          y: _readDouble(json, 'y', 0),
          w: _readDouble(json, 'w', 40),
          h: _readDouble(json, 'h', 40),
          fillColor: _readInt(json, 'fillColor', 0xFF3D5AFE),
          cornerRadius: _readDouble(json, 'cornerRadius', 0),
        );
        layer.fillCommonFromJson(json);
        return layer;
      case 'text':
        final layer = TextLayer(
          id: _readString(json, 'id', ''),
          x: _readDouble(json, 'x', 0),
          y: _readDouble(json, 'y', 0),
          w: _readDouble(json, 'w', 120),
          h: _readDouble(json, 'h', 30),
        );
        layer.fillCommonFromJson(json);
        return layer;
      default:
        return null;
    }
  }
}

// ---------------------------------------------------------------------------
// JSON 读取工具（宽松回落）
// ---------------------------------------------------------------------------

Map<String, Object?> _asMap(Object? v) =>
    v is Map<String, Object?> ? v : <String, Object?>{};

List<Object?> _asList(Object? v) => v is List<Object?> ? v : const [];

String _readString(Map<String, Object?> json, String key, String fallback) {
  final v = json[key];
  return v is String ? v : fallback;
}

double _readDouble(Map<String, Object?> json, String key, double fallback) {
  final v = json[key];
  if (v is num) return v.toDouble();
  if (v is String) {
    final parsed = double.tryParse(v);
    if (parsed != null) return parsed;
  }
  return fallback;
}

int _readInt(Map<String, Object?> json, String key, int fallback) {
  final v = json[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final parsed = int.tryParse(v);
    if (parsed != null) return parsed;
  }
  return fallback;
}

bool _readBool(Map<String, Object?> json, String key, bool fallback) {
  final v = json[key];
  if (v is bool) return v;
  if (v is num) return v != 0;
  return fallback;
}

/// 数字序列化时去掉多余的 .0（250.0 → 250），便于人工检查 JSON。
Object _num(double v) => v % 1 == 0 ? v.toInt() : v;
