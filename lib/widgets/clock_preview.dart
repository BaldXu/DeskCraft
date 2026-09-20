import 'dart:async';

import 'package:flutter/material.dart';

import '../models/clock_config.dart';

/// 桌面数字时钟的实时预览（首页卡片与配置页共用）。
///
/// 排版还原原生 RemoteViews：
/// 大号时间（TextClock）→ 日期 + 星期行 → 附加文案，左对齐。
class ClockPreview extends StatefulWidget {
  const ClockPreview({super.key, required this.config});

  final ClockConfig config;

  @override
  State<ClockPreview> createState() => _ClockPreviewState();
}

class _ClockPreviewState extends State<ClockPreview> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 与原生 TextClock 格式对齐：24h 为 HH:mm:ss，12h 为 上午 h:mm:ss。
  String get _timeText {
    final t = _now;
    if (widget.config.use24h) {
      final hh = t.hour.toString().padLeft(2, '0');
      return '$hh:${_two(t.minute)}:${_two(t.second)}';
    }
    final suffix = t.hour < 12 ? '上午' : '下午';
    var h = t.hour % 12;
    if (h == 0) h = 12;
    return '$suffix $h:${_two(t.minute)}:${_two(t.second)}';
  }

  /// 与原生 TextClock 对齐：日期用 M月d日，星期用 EEEE（星期X）。
  String get _dateText {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final parts = <String>[
      if (widget.config.showDate) '${_now.month}月${_now.day}日',
      if (widget.config.showWeekday) weekdays[_now.weekday - 1],
    ];
    return parts.join(' ');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    final color = Color(c.textColor);
    final dateText = _dateText;
    final extra = c.extraText.trim();

    return Container(
      decoration: c.previewDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _timeText,
            style: TextStyle(
              color: color,
              fontSize: c.timeSizeSp.toDouble(),
              height: 1.15,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (dateText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              dateText,
              style: TextStyle(
                color: color.withValues(alpha: 0.78),
                fontSize: 13,
              ),
            ),
          ],
          if (extra.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              extra,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color.withValues(alpha: 0.58),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
