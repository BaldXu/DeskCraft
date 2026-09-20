import 'package:flutter/services.dart';

/// M2：libsu root 数据源验证的原生桥。
///
/// 对应原生侧 [RootDataSource]，只执行白名单只读命令。
class RootBridge {
  RootBridge._();

  static const MethodChannel _channel = MethodChannel('desk_craft/root');

  /// 单个热区读数。
  static Future<RootProbe> probe() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('probe');
      return RootProbe.fromMap(raw?.cast<String, dynamic>() ?? const {});
    } on PlatformException catch (e) {
      return RootProbe(rooted: false, error: '通道异常：${e.code} ${e.message}');
    } on MissingPluginException {
      return const RootProbe(error: '通道未注册');
    }
  }
}

/// 一次 root 探测的完整结果。
class RootProbe {
  const RootProbe({
    this.rooted = false,
    this.tookMs,
    this.cpuFreqsKHz = const [],
    this.thermalZones = const [],
    this.memInfoKb = const {},
    this.error,
  });

  factory RootProbe.fromMap(Map<String, dynamic> map) {
    final zones = (map['thermalZones'] as List<dynamic>? ?? [])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (z) => ThermalZone(
            name: z['name'] as String? ?? '',
            type: z['type'] as String? ?? '',
            tempMilli: (z['tempMilli'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();

    final mem = <String, int>{};
    (map['memInfoKb'] as Map<dynamic, dynamic>? ?? {}).forEach((k, v) {
      if (k is String && v is num) mem[k] = v.toInt();
    });

    return RootProbe(
      rooted: map['rooted'] as bool? ?? false,
      tookMs: (map['tookMs'] as num?)?.toInt(),
      cpuFreqsKHz: (map['cpuFreqsKHz'] as List<dynamic>? ?? [])
          .whereType<num>()
          .map((n) => n.toInt())
          .toList(),
      thermalZones: zones,
      memInfoKb: mem,
      error: map['error'] as String?,
    );
  }

  final bool rooted;
  final int? tookMs;
  final List<int> cpuFreqsKHz;
  final List<ThermalZone> thermalZones;
  final Map<String, int> memInfoKb;
  final String? error;
}

/// /sys/class/thermal 的一个热区。
class ThermalZone {
  const ThermalZone({
    required this.name,
    required this.type,
    required this.tempMilli,
  });

  final String name;
  final String type;
  final int tempMilli;

  /// 摄氏度（部分热区可能返回负值或异常值，原样保留）。
  double get celsius => tempMilli / 1000;
}
