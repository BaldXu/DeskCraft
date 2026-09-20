/// 信息位（InfoBit）模型 —— 卡片内一个可独立开关的信息模块，自带刷新频率。
///
/// 设计约定（M4.1 解耦）：
/// - 每个信息位都是独立的 [InfoBit]，自带启用开关与刷新频率；
/// - 整卡有效刷新周期 = 所有启用信息位中最快（秒数最小）的一档，
///   原生侧按该周期做 AlarmManager 调度；
/// - 硬上限：任何信息位最快 1 秒 1 次（[RefreshRate.s1]）。
library;

/// 刷新频率档位 —— 所有信息位共用一套档位（最快 1 秒 1 次）。
enum RefreshRate {
  s1(1, '1秒'),
  s5(5, '5秒'),
  s15(15, '15秒'),
  s30(30, '30秒'),
  m1(60, '1分钟'),
  m5(300, '5分钟'),
  m15(900, '15分钟'),
  h1(3600, '1小时');

  const RefreshRate(this.seconds, this.label);

  final int seconds;
  final String label;

  /// 从秒数还原档位：取不超过该秒数的最大档（小于 1 秒按 1 秒计）。
  static RefreshRate fromSeconds(int seconds) {
    final s = seconds < 1 ? 1 : seconds;
    var best = s1;
    for (final rate in values) {
      if (rate.seconds == s) return rate;
      if (rate.seconds < s) best = rate;
    }
    return best;
  }
}

/// 信息位：启用开关 + 刷新频率（秒）。
class InfoBit {
  const InfoBit({
    required this.key,
    required this.label,
    required this.enabled,
    required this.refreshSeconds,
  });

  /// 序列化 key（与原生 bits JSON 对齐，勿改名）。
  final String key;

  /// UI 展示名。
  final String label;

  /// 是否显示该信息位。
  final bool enabled;

  /// 该信息位的刷新周期（秒），有效范围 1 ~ 3600。
  final int refreshSeconds;

  InfoBit copyWith({bool? enabled, int? refreshSeconds}) => InfoBit(
    key: key,
    label: label,
    enabled: enabled ?? this.enabled,
    refreshSeconds: refreshSeconds ?? this.refreshSeconds,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'refreshSeconds': refreshSeconds.clamp(1, 3600),
  };

  /// 从 bits JSON 还原；缺字段回落到 [fallback]（fallback 可携带旧版
  /// 整卡布尔/间隔迁移值，用于老配置无 bits 时的兼容解析）。
  factory InfoBit.fromJson(
    String key,
    String label,
    Map<String, dynamic>? json,
    InfoBit fallback,
  ) => InfoBit(
    key: key,
    label: label,
    enabled: json?['enabled'] as bool? ?? fallback.enabled,
    refreshSeconds:
        (json?['refreshSeconds'] as num?)?.toInt() ?? fallback.refreshSeconds,
  );
}

/// 取整卡有效刷新周期（秒）：启用信息位中最小的一档；全禁用回落 [fallbackSeconds]。
int effectiveCardRefreshSeconds(
  List<InfoBit> bits, {
  int fallbackSeconds = 60,
}) {
  final seconds = [
    for (final bit in bits)
      if (bit.enabled) bit.refreshSeconds.clamp(1, 3600),
  ];
  if (seconds.isEmpty) return fallbackSeconds;
  return seconds.reduce((a, b) => a < b ? a : b);
}
