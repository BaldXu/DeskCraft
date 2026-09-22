/// 全局变量存储与解析服务（M6 第③步）。
///
/// - 存储：SharedPreferences（key [_varsKey]，JSON 数组），与布局库同源；
/// - 解析：把 GV 列表解析成公式引擎可直接引用的 `Map<String, Object?>`，
///   公式类型变量按引用关系递归求值，循环引用 / 语法错误回落 null；
/// - 刷新周期：布局模板引用的公式型 GV 参与整卡刷新周期合并
///   （否则秒级 GV 引用会被模板层误判为 3600）。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../editor/layout_model.dart';
import '../formula/formula_context.dart';
import '../formula/formula_engine.dart';
import '../formula/formula_parser.dart';
import '../models/global_var.dart';

class GlobalVarStore {
  GlobalVarStore._();

  /// App 侧全局变量库 key。
  static const String _varsKey = 'global_vars_v1';

  /// 公式型变量递归求值深度上限（防深链 + 兜底循环）。
  static const int maxResolutionDepth = 12;

  // ---- 持久化 ----

  static Future<List<GlobalVar>> loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_varsKey);
    if (raw == null || raw.isEmpty) return [];
    return GlobalVar.decodeAll(raw);
  }

  static Future<void> saveAll(List<GlobalVar> vars) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_varsKey, GlobalVar.encodeAll(vars));
  }

  /// 新增或按 key 更新一个变量，返回保存后的完整列表。
  static Future<List<GlobalVar>> upsert(GlobalVar v) async {
    final all = await loadAll();
    final index = all.indexWhere((g) => g.key == v.key);
    if (index >= 0) {
      all[index] = v;
    } else {
      all.add(v);
    }
    await saveAll(all);
    return all;
  }

  static Future<List<GlobalVar>> remove(String key) async {
    final all = await loadAll().then(
      (list) => list.where((g) => g.key != key).toList(),
    );
    await saveAll(all);
    return all;
  }

  // ---- 解析 ----

  /// 解析整个 GV 列表为公式引擎可引用的变量表。
  ///
  /// - 非公式类型：按 [GlobalVarType] 转为 String / num / bool；
  /// - 公式类型：解析期递归求值（依赖按需解析，循环引用返回 null）；
  /// - 任意求值失败（语法错误 / 数据不可用）该变量回落 null（渲染为占位符）。
  static Map<String, Object?> resolveAll(
    List<GlobalVar> gvs,
    FormulaContext base,
  ) {
    final byKey = <String, GlobalVar>{for (final g in gvs) g.key: g};
    final resolved = <String, Object?>{};
    final visiting = <String>{};

    Object? resolveOne(String key, int depth) {
      if (depth > maxResolutionDepth) return null;
      if (resolved.containsKey(key)) return resolved[key];
      final gv = byKey[key];
      if (gv == null) return null;
      if (visiting.contains(key)) return null; // 循环引用
      visiting.add(key);

      Object? value;
      switch (gv.type) {
        case GlobalVarType.text:
          value = gv.value;
        case GlobalVarType.number:
          value = num.tryParse(gv.value.trim());
        case GlobalVarType.bool_:
          value = gv.value.trim().toLowerCase() == 'true';
        case GlobalVarType.formula:
          // 先解析依赖变量，再把「基础系统变量 + 已解析 GV」作为求值上下文
          final deps = FormulaEngine.usedVariables(gv.value);
          final globals = <String, Object?>{...resolved};
          for (final dep in deps) {
            if (byKey.containsKey(dep) && !globals.containsKey(dep)) {
              globals[dep] = resolveOne(dep, depth + 1);
            }
          }
          value = _evalFormula(
            gv.value,
            FormulaContext(
              now: base.now,
              variables: base.variables,
              globals: globals,
            ),
          );
      }

      visiting.remove(key);
      resolved[key] = value;
      return value;
    }

    for (final key in byKey.keys) {
      resolveOne(key, 0);
    }
    return resolved;
  }

  static Object? _evalFormula(String source, FormulaContext context) {
    try {
      return FormulaEvaluator(context).evaluate(parseFormula(source));
    } catch (_) {
      return null; // 语法错误 / 数据不可用
    }
  }

  /// 便捷：加载存储中的 GV 并解析为变量表。
  static Future<Map<String, Object?>> loadResolvedGlobals({
    DateTime? now,
    Map<String, Object?> variables = const {},
  }) async {
    final gvs = await loadAll();
    return resolveAll(
      gvs,
      FormulaContext(now: now ?? DateTime.now(), variables: variables),
    );
  }

  // ---- 刷新周期合并 ----

  /// 整卡有效刷新周期 = 模板自身周期 ∪ 模板引用的公式型 GV 的周期。
  /// 未被任何模板引用的 GV 不计入（避免无关秒级公式拖慢所有组件）。
  static int effectiveRefreshSeconds(
    WidgetLayout layout,
    List<GlobalVar> gvs,
  ) {
    var min = layout.refreshSeconds;
    final byKey = <String, GlobalVar>{for (final g in gvs) g.key: g};

    // 收集布局所有文本模板引用的变量名
    final referenced = <String>{};
    for (final layer in layout.layers) {
      if (layer is! TextLayer) continue;
      referenced.addAll(FormulaEngine.usedVariablesInTemplate(layer.template));
    }

    for (final name in referenced) {
      final gv = byKey[name];
      if (gv == null || gv.type != GlobalVarType.formula) continue;
      if (gv.value.trim().isEmpty) continue;
      // 公式型 GV 以 `$表达式$` 形式参与模板刷新分析
      final s = FormulaEngine.analyzeRefreshSeconds(r'$' + gv.value + r'$');
      if (s < min) min = s;
    }
    return min;
  }

  /// 便捷：加载存储中的 GV 后计算整卡有效刷新周期。
  static Future<int> effectiveRefreshSecondsFor(WidgetLayout layout) async {
    final gvs = await loadAll();
    return effectiveRefreshSeconds(layout, gvs);
  }
}
