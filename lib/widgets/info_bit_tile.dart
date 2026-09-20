import 'package:flutter/material.dart';

import '../models/info_bit.dart';
import 'parameter_sheet.dart';

/// 信息位设置行：左侧名称与当前刷新频率，右侧启用开关；
/// 点击行弹出频率档位选择（8 档共用，最高 1 秒 1 次）。
class InfoBitTile extends StatelessWidget {
  const InfoBitTile({super.key, required this.bit, required this.onChanged});

  final InfoBit bit;
  final ValueChanged<InfoBit> onChanged;

  Future<void> _pickRate(BuildContext context) async {
    final current = RefreshRate.fromSeconds(bit.refreshSeconds);
    final selected = await showParameterSheet<RefreshRate>(
      context: context,
      builder: (context) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${bit.label} · 刷新频率',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final rate in RefreshRate.values)
            ListTile(
              title: Text('每 ${rate.label}'),
              trailing: rate == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(rate),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '为省电起见，最高刷新频率为 1 秒 1 次',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
    if (selected != null && selected != current) {
      onChanged(bit.copyWith(refreshSeconds: selected.seconds));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rate = RefreshRate.fromSeconds(bit.refreshSeconds);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(bit.label),
      subtitle: Text('每 ${rate.label} 刷新，点按修改频率'),
      onTap: () => _pickRate(context),
      trailing: Switch(
        value: bit.enabled,
        onChanged: (v) => onChanged(bit.copyWith(enabled: v)),
      ),
    );
  }
}
