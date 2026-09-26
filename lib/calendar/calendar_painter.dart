/// 日历位图绘制核心——纯 dart:ui 实现，预览（CustomPaint）与位图导出共享。
///
/// 布局单位为 dp，通过 [scale]（= 目标像素宽 / 参考宽度 [refWidthDp]）换算为
/// 像素。不依赖 widget 树与 implicitView，因此前台预览与后台 headless 引擎
/// 均可使用（headless 中文本必须走 ParagraphBuilder，不能用 TextPainter）。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/calendar_config.dart';
import 'calendar_data.dart';

/// 日历绘制器：把 [grid] 月网格按 [config] 样式画满 [size]。
///
/// [backgroundImage]：背景图片（已解码），bgStyle == image 时生效，
/// cover 居中裁剪；未提供时回落到配置纯色。
class CalendarPainter {
  CalendarPainter({
    required this.config,
    required this.grid,
    this.backgroundImage,
  });

  final CalendarConfig config;
  final CalendarMonthData grid;

  /// 背景图片（已解码的 ui.Image），null 表示无/未加载。
  final ui.Image? backgroundImage;

  /// 参考宽度（dp）：网格排版数值基准，实际尺寸经 scale 等比缩放。
  static const double refWidthDp = 250;

  void paint(ui.Canvas canvas, ui.Size size) {
    final scale = size.width / refWidthDp;
    final rrect = ui.RRect.fromRectAndRadius(
      ui.Offset.zero & size,
      ui.Radius.circular(config.cornerRadiusDp * scale),
    );

    canvas.save();
    canvas.clipRRect(rrect);
    _paintBackground(canvas, size, scale);
    final regions = _LayoutRegions.compute(size, scale, config);
    if (config.showHeader) _paintHeader(canvas, regions);
    if (config.showWeekdayHeader) _paintWeekdayRow(canvas, regions);
    _paintGrid(canvas, regions);
    canvas.restore();
  }

  // ---- 背景（纯色 / 渐变 / 图片 cover） ----

  void _paintBackground(ui.Canvas canvas, ui.Size size, double scale) {
    final rect = ui.Offset.zero & size;
    final paint = ui.Paint();
    switch (config.bgStyle) {
      case CalendarBgStyle.solid:
        canvas.drawRect(rect, paint..color = ui.Color(config.bgColor));
      case CalendarBgStyle.gradient:
        final colors = kCalendarGradients[
            config.bgGradientIndex.clamp(0, kCalendarGradients.length - 1)];
        canvas.drawRect(
          rect,
          paint
            ..shader = ui.Gradient.linear(
              ui.Offset.zero,
              ui.Offset(size.width, 0),
              [for (final c in colors) ui.Color(c)],
            ),
        );
      case CalendarBgStyle.image:
        final img = backgroundImage;
        if (img != null) {
          // cover 居中裁剪：等比放大到铺满，裁剪多余部分
          final s = ui.Size(img.width.toDouble(), img.height.toDouble());
          final cover = (size.width / s.width) > (size.height / s.height)
              ? size.height / s.height
              : size.width / s.width;
          final drawW = s.width * cover;
          final drawH = s.height * cover;
          final src = ui.Rect.fromLTWH(
            (drawW - size.width) / 2 / cover,
            (drawH - size.height) / 2 / cover,
            size.width / cover,
            size.height / cover,
          );
          canvas.drawImageRect(img, src, rect, paint);
        } else {
          canvas.drawRect(rect, paint..color = ui.Color(config.bgColor));
        }
    }
  }

  // ---- 头部 / 星期行 / 网格 ----

  void _paintHeader(ui.Canvas canvas, _LayoutRegions r) {
    _drawText(
      canvas,
      '${grid.year}年${grid.month}月',
      r.headerRect,
      _s(config.dayFontSize * 1.05, r.scale),
      _withAlpha(config.textColor, 1),
      weight: ui.FontWeight.w500,
    );
  }

  void _paintWeekdayRow(ui.Canvas canvas, _LayoutRegions r) {
    final names = config.firstDayOfWeek == CalendarFirstDay.monday
        ? const ['一', '二', '三', '四', '五', '六', '日']
        : const ['日', '一', '二', '三', '四', '五', '六'];
    final weekendCols = config.firstDayOfWeek == CalendarFirstDay.monday
        ? const [5, 6]
        : const [0, 6];
    for (var col = 0; col < 7; col++) {
      final isWeekend = weekendCols.contains(col);
      final color = isWeekend && config.showWeekend
          ? ui.Color(config.weekendColor).withValues(alpha: 0.9)
          : _withAlpha(config.textColor, 0.72);
      _drawText(
        canvas,
        names[col],
        r.weekdayRectOf(col),
        _s(config.dayFontSize * 0.72, r.scale),
        color,
      );
    }
  }

  void _paintGrid(ui.Canvas canvas, _LayoutRegions r) {
    for (var i = 0; i < grid.cells.length; i++) {
      final cell = grid.cells[i];
      if (cell == null) continue;
      final cellRect = r.cellRectOf(i);
      _paintCell(canvas, cell, cellRect, r.scale);
    }
  }

  void _paintCell(
    ui.Canvas canvas,
    CalendarDayInfo cell,
    ui.Rect rect,
    double scale,
  ) {
    final isToday = config.highlightToday && cell.isToday;
    final dayFont = _s(config.dayFontSize.toDouble(), scale);
    final dayCenterY = rect.top + rect.height * 0.40;

    // 今天高亮（圆 / 圆角方）
    if (isToday) {
      final accent = ui.Color(config.highlightColor);
      final radius = rect.width < rect.height ? rect.width * 0.30 : rect.height * 0.34;
      final center = ui.Offset(rect.center.dx, dayCenterY);
      final paint = ui.Paint()
        ..style = config.highlightStyle == CalendarHighlightStyle.filled
            ? ui.PaintingStyle.fill
            : ui.PaintingStyle.stroke
        ..strokeWidth = 1.5 * scale
        ..color = accent;
      if (config.highlightShape == CalendarHighlightShape.circle) {
        canvas.drawCircle(center, radius, paint);
      } else {
        canvas.drawRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromCenter(center: center, width: radius * 2, height: radius * 2),
            ui.Radius.circular(radius * 0.4),
          ),
          paint,
        );
      }
    }

    // 日号颜色
    final ui.Color dayColor;
    if (isToday) {
      dayColor = config.highlightStyle == CalendarHighlightStyle.filled
          ? const ui.Color(0xFFFFFFFF)
          : ui.Color(config.highlightColor);
    } else if (!cell.isCurrentMonth) {
      dayColor = _withAlpha(config.textColor, 0.32);
    } else if (cell.isWeekend && config.showWeekend) {
      dayColor = ui.Color(config.weekendColor);
    } else {
      dayColor = ui.Color(config.textColor);
    }

    // 副文字
    final sub = cell.subText;
    if (sub.isNotEmpty) {
      _drawText(
        canvas,
        sub,
        ui.Rect.fromLTWH(
          rect.left,
          rect.top + rect.height * 0.58,
          rect.width,
          rect.height * 0.38,
        ),
        _s(config.subFontSize.toDouble(), scale),
        _withAlpha(config.textColor, cell.isCurrentMonth ? 0.66 : 0.32),
      );
    }

    // 日号（放最后，覆盖在色块之上）
    _drawText(
      canvas,
      '${cell.date.day}',
      ui.Rect.fromLTWH(
        rect.left,
        rect.top + rect.height * 0.10,
        rect.width,
        rect.height * 0.42,
      ),
      dayFont,
      dayColor,
      weight: ui.FontWeight.w500,
    );
  }

  // ---- 文本工具（ParagraphBuilder，headless 安全） ----

  void _drawText(
    ui.Canvas canvas,
    String text,
    ui.Rect rect,
    double fontSize,
    ui.Color color, {
    ui.FontWeight weight = ui.FontWeight.normal,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        fontSize: fontSize,
        fontWeight: weight,
        height: 1.0,
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontFamilyFallback: const ['sans-serif', 'miui', 'Noto Sans CJK SC'],
        ),
      )
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: rect.width));
    final dy = rect.top + (rect.height - paragraph.height) / 2;
    canvas.drawParagraph(paragraph, ui.Offset(rect.left, dy));
  }

  double _s(double dp, double scale) => dp * scale;

  static ui.Color _withAlpha(int argb, double alpha) =>
      ui.Color(argb).withValues(alpha: alpha);
}

/// 布局分区（像素）：按 widget 实际尺寸 + scale 计算。
class _LayoutRegions {
  _LayoutRegions._({
    required this.scale,
    required this.headerRect,
    required this.weekdayRowTop,
    required this.gridTop,
    required this.gridBottom,
    required this.cellWidth,
    required this.rowHeight,
    required this.padLeft,
  });

  final double scale;
  final ui.Rect headerRect;
  final double weekdayRowTop;
  final double gridTop;
  final double gridBottom;
  final double cellWidth;
  final double rowHeight;
  final double padLeft;

  static _LayoutRegions compute(
    ui.Size size,
    double scale,
    CalendarConfig config,
  ) {
    final padH = 14 * scale;
    final padV = 10 * scale;
    final headerH = config.showHeader ? 22 * scale : 0.0;
    final weekdayH = config.showWeekdayHeader ? 15 * scale : 0.0;

    final gridTop = padV + headerH + weekdayH;
    final gridBottom = size.height - padV;
    final gridH = (gridBottom - gridTop).clamp(0, double.infinity);
    final cellWidth = (size.width - padH * 2) / 7;
    final rowHeight = gridH / 6;

    return _LayoutRegions._(
      scale: scale,
      headerRect: ui.Rect.fromLTWH(
        padH,
        padV,
        size.width - padH * 2,
        headerH,
      ),
      weekdayRowTop: padV + headerH,
      gridTop: gridTop,
      gridBottom: gridBottom,
      cellWidth: cellWidth,
      rowHeight: rowHeight,
      padLeft: padH,
    );
  }

  ui.Rect weekdayRectOf(int col) => ui.Rect.fromLTWH(
    padLeft + col * cellWidth,
    weekdayRowTop,
    cellWidth,
    15 * scale,
  );

  ui.Rect cellRectOf(int index) {
    final row = index ~/ 7;
    final col = index % 7;
    return ui.Rect.fromLTWH(
      padLeft + col * cellWidth,
      gridTop + row * rowHeight,
      cellWidth,
      rowHeight,
    );
  }
}

/// 渲染日历为 PNG 字节。
///
/// [widthPx] × [heightPx] 为输出像素尺寸（widget 实际尺寸或基准尺寸 × dpr）。
/// [backgroundImage]：背景图片（bgStyle == image 时传入已解码的 ui.Image）。
Future<Uint8List?> renderCalendarPng({
  required CalendarConfig config,
  required CalendarMonthData grid,
  required int widthPx,
  required int heightPx,
  ui.Image? backgroundImage,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  CalendarPainter(
    config: config,
    grid: grid,
    backgroundImage: backgroundImage,
  ).paint(canvas, ui.Size(widthPx.toDouble(), heightPx.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      widthPx.clamp(1, 4096),
      heightPx.clamp(1, 4096),
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

/// 从本地文件解码背景图片（cover 用），失败返回 null。
Future<ui.Image?> loadBackgroundImage(String path) async {
  try {
    final file = await ui.ImmutableBuffer.fromFilePath(path);
    final codec = await ui.instantiateImageCodecFromBuffer(
      file,
      targetWidth: 1024,
    );
    final frame = await codec.getNextFrame();
    file.dispose();
    codec.dispose();
    return frame.image;
  } catch (_) {
    return null;
  }
}
