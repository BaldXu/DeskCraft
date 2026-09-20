/// 公式上下文 —— 求值时可用的变量集合（M6 公式引擎）。
///
/// - [now]：当前时间，时间类变量与 tf/df 函数的基准；
/// - [variables]：系统变量（batTemp / cpuUsage / memUsage ...），
///   取不到时值为 null，对应信息位渲染为占位符；
/// - [globals]：全局变量（M6 第③步接入，先留接口）。
class FormulaContext {
  const FormulaContext({
    required this.now,
    this.variables = const {},
    this.globals = const {},
  });

  final DateTime now;

  /// 系统变量：key 为变量名，值为 num / String / bool；null 表示数据不可用。
  final Map<String, Object?> variables;

  /// 用户全局变量（预留）。
  final Map<String, Object?> globals;

  /// 变量查找顺序：系统变量优先，其次全局变量；都不存在返回 [fallback]。
  Object? lookup(String name, {Object? fallback}) {
    if (variables.containsKey(name)) return variables[name];
    if (globals.containsKey(name)) return globals[name];
    return fallback;
  }
}
