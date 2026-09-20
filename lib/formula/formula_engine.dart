/// 公式引擎公共入口（M6）——模板渲染、求值与刷新周期分析。
///
/// 模板语法：任意文本中嵌入 `$表达式$`；`$$` 转义为字面量 `$`。
/// 表达式语法见 [formula_parser]。
///
/// V1 核心子集：
/// - 时间/日期格式化：`$tf("HH:mm:ss")$`、`$df("yyyy-MM-dd E")$`
/// - 四则与比较：`$1+2$`、`$batTemp*2-3$`、`$if(cpuUsage>80,"高","低")$`
/// - 系统变量：`hour / minute / second / ampm / weekday` +
///   监控快照（`batTemp / cpuFreqMax / cpuFreqMin / cpuUsage / memUsage`）
/// - 函数：`if / round / floor / ceil / abs / min / max / cat`
library;

import 'formula_context.dart';
import 'formula_parser.dart';

/// 求值期错误（变量未知 / 类型不对 / 数据不可用等）。
class FormulaValueException implements Exception {
  FormulaValueException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// 求值器
// ---------------------------------------------------------------------------

class FormulaEvaluator {
  FormulaEvaluator(this.context);

  final FormulaContext context;

  Object? evaluate(Expr expr) => switch (expr) {
    NumLiteral(:final value) => value,
    StringLiteral(:final value) => value,
    VariableExpr(:final name) => _variable(name),
    CallExpr(:final name, :final args) => _call(name, args),
    UnaryExpr(:final operand) => -_asNum(evaluate(operand), '取负运算'),
    BinaryExpr(:final op, :final left, :final right) => _binary(
      op,
      left,
      right,
    ),
  };

  Object? _variable(String name) {
    if (!context.variables.containsKey(name) &&
        !context.globals.containsKey(name)) {
      throw FormulaValueException('未知变量 "$name"');
    }
    final value = context.lookup(name);
    if (value == null) throw FormulaValueException('数据不可用（$name）');
    return value;
  }

  Object? _binary(String op, Expr left, Expr right) {
    final lv = evaluate(left);
    final rv = evaluate(right);
    switch (op) {
      case '+':
        if (lv is num && rv is num) return lv + rv;
        return _toText(lv) + _toText(rv); // 字符串拼接
      case '-':
        return _asNum(lv, op) - _asNum(rv, op);
      case '*':
        return _asNum(lv, op) * _asNum(rv, op);
      case '/':
        final d = _asNum(rv, op);
        if (d == 0) throw FormulaValueException('除数为 0');
        return _asNum(lv, op) / d;
      case '%':
        final d = _asNum(rv, op);
        if (d == 0) throw FormulaValueException('取模数为 0');
        return _asNum(lv, op) % d;
      case '<':
        return _asNum(lv, op) < _asNum(rv, op);
      case '>':
        return _asNum(lv, op) > _asNum(rv, op);
      case '<=':
        return _asNum(lv, op) <= _asNum(rv, op);
      case '>=':
        return _asNum(lv, op) >= _asNum(rv, op);
      case '==':
        return lv == rv || (_toText(lv) == _toText(rv));
      case '!=':
        return !(lv == rv || (_toText(lv) == _toText(rv)));
      default:
        throw FormulaValueException('不支持的运算符 "$op"');
    }
  }

  Object? _call(String name, List<Expr> args) {
    final values = args.map(evaluate).toList();
    switch (name) {
      case 'tf':
        return _formatTime(
          values.isEmpty ? 'HH:mm' : _text(values.first, 'tf'),
          label: 'tf',
        );
      case 'df':
        return _formatTime(
          values.isEmpty ? 'yyyy-MM-dd' : _text(values.first, 'df'),
          label: 'df',
        );
      case 'if':
        if (values.length < 2) throw FormulaValueException('if() 至少需要 2 个参数');
        return _truthy(values.first)
            ? values[1]
            : (values.length > 2 ? values[2] : '');
      case 'round':
        final digits = values.length > 1
            ? _asNum(values[1], 'round').toInt()
            : 0;
        final factor = _pow10(digits);
        return (((_asNum(values.first, 'round') * factor).round()) / factor);
      case 'floor':
        return _asNum(values.first, 'floor').floor();
      case 'ceil':
        return _asNum(values.first, 'ceil').ceil();
      case 'abs':
        return _asNum(values.first, 'abs').abs();
      case 'min':
        return values
            .map((v) => _asNum(v, 'min'))
            .reduce((a, b) => a < b ? a : b);
      case 'max':
        return values
            .map((v) => _asNum(v, 'max'))
            .reduce((a, b) => a > b ? a : b);
      case 'cat':
        return values.map(_toText).join();
      default:
        throw FormulaValueException('未知函数 "$name"');
    }
  }

  // ---- 时间 / 日期格式化 ----

  /// 支持的 pattern 记号：
  /// `yyyy yy MM M dd d HH H hh h mm m ss s a E`（E = 周一~周日）。
  String _formatTime(String pattern, {required String label}) {
    final now = context.now;
    final buf = StringBuffer();
    var i = 0;
    while (i < pattern.length) {
      final ch = pattern[i];
      var run = 1;
      while (i + run < pattern.length && pattern[i + run] == ch) {
        run++;
      }
      switch (ch) {
        case 'y':
          final y = now.year.toString();
          buf.write(run >= 3 ? y : y.substring(y.length - 2));
        case 'M':
          buf.write(
            run >= 2
                ? now.month.toString().padLeft(2, '0')
                : now.month.toString(),
          );
        case 'd':
          buf.write(
            run >= 2 ? now.day.toString().padLeft(2, '0') : now.day.toString(),
          );
        case 'H':
          buf.write(
            run >= 2
                ? now.hour.toString().padLeft(2, '0')
                : now.hour.toString(),
          );
        case 'h':
          final h12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
          buf.write(run >= 2 ? h12.toString().padLeft(2, '0') : h12.toString());
        case 'm':
          buf.write(
            run >= 2
                ? now.minute.toString().padLeft(2, '0')
                : now.minute.toString(),
          );
        case 's':
          buf.write(
            run >= 2
                ? now.second.toString().padLeft(2, '0')
                : now.second.toString(),
          );
        case 'a':
          buf.write(now.hour < 12 ? '上午' : '下午');
        case 'E':
          buf.write('周${_weekdayCn[now.weekday - 1]}');
        default:
          // 非记号字符原样输出
          buf.write(pattern.substring(i, i + run));
      }
      i += run;
    }
    return buf.toString();
  }

  static const _weekdayCn = ['一', '二', '三', '四', '五', '六', '日'];

  num _pow10(int digits) {
    var f = 1.0;
    for (var i = 0; i < digits; i++) {
      f *= 10;
    }
    return f;
  }

  // ---- 类型工具 ----

  bool _truthy(Object? v) => switch (v) {
    bool b => b,
    num n => n != 0,
    String s => s.isNotEmpty && s != 'false',
    _ => false,
  };

  num _asNum(Object? v, String opFor) {
    if (v == null) throw FormulaValueException('数据不可用（$opFor）');
    if (v is num) return v;
    final parsed = num.tryParse(v.toString());
    if (parsed != null) return parsed;
    throw FormulaValueException('"${_toText(v)}" 不是数字（$opFor）');
  }

  String _text(Object? v, String fnName) {
    if (v == null) throw FormulaValueException('数据不可用（$fnName）');
    return _toText(v);
  }

  /// 值 → 展示文本：整数不带小数点，bool 转 true/false，null 转空串。
  static String toText(Object? v) => _toText(v);

  static String _toText(Object? v) => switch (v) {
    null => '',
    bool b => b ? 'true' : 'false',
    num n => n % 1 == 0 ? n.toInt().toString() : _trimNum(n),
    _ => v.toString(),
  };

  /// 去掉浮点尾零：32.50 → 32.5。
  static String _trimNum(num n) {
    var s = n.toString();
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }
}

// ---------------------------------------------------------------------------
// 模板渲染
// ---------------------------------------------------------------------------

/// 一次模板渲染的错误记录。
class FormulaError {
  const FormulaError(this.span, this.message);

  /// 出错的表达式源码（不含 $ 包裹）。
  final String span;
  final String message;
}

/// 渲染结果：拼接文本 + 引用到的变量 + 错误列表。
class RenderResult {
  const RenderResult({
    required this.text,
    required this.usedVariables,
    required this.errors,
  });

  final String text;
  final Set<String> usedVariables;
  final List<FormulaError> errors;

  bool get hasError => errors.isNotEmpty;
}

abstract final class FormulaEngine {
  /// 变量数据不可用时的占位文本。
  static const errorPlaceholder = '--';

  /// 已注册的系统变量（变量名 → 中文说明），供编辑器变量面板展示。
  static const Map<String, String> knownVariables = {
    'hour': '时（24h）',
    'minute': '分',
    'second': '秒',
    'ampm': '上午/下午',
    'weekday': '周几（一~日）',
    'batTemp': '电池温度 °C',
    'cpuFreqMax': 'CPU 最高频率 GHz',
    'cpuFreqMin': 'CPU 最低频率 GHz',
    'cpuUsage': 'CPU 占用 %',
    'memUsage': '内存占用 %',
  };

  /// 已注册的函数（函数名 → 说明），供编辑器公式面板展示。
  static const Map<String, String> knownFunctions = {
    'tf': r'时间格式化 tf("HH:mm:ss")',
    'df': r'日期格式化 df("yyyy-MM-dd E")',
    'if': '条件 if(条件, 值1, 值2)',
    'round': '四舍五入 round(x, 小数位)',
    'floor': '向下取整',
    'ceil': '向上取整',
    'abs': '绝对值',
    'min': '最小值 min(a, b)',
    'max': '最大值 max(a, b)',
    'cat': '拼接 cat(a, b, ...)',
  };

  /// 渲染模板：`$表达式$` 求值后替换为文本。
  /// 单个表达式出错不影响其他片段，出错处渲染为 [errorPlaceholder]。
  static RenderResult render(
    String template,
    FormulaContext context, {
    String errorPlaceholder = errorPlaceholder,
  }) {
    final buf = StringBuffer();
    final usedVars = <String>{};
    final errors = <FormulaError>[];
    var i = 0;
    while (i < template.length) {
      final ch = template[i];
      if (ch != r'$') {
        buf.write(ch);
        i++;
        continue;
      }
      // $$ → 字面量 $
      if (i + 1 < template.length && template[i + 1] == r'$') {
        buf.write(r'$');
        i += 2;
        continue;
      }
      // 找收尾 $
      final end = template.indexOf(r'$', i + 1);
      if (end < 0) {
        buf.write(template.substring(i));
        break;
      }
      final source = template.substring(i + 1, end);
      try {
        final expr = parseFormula(source);
        _collectVars(expr, usedVars);
        final value = FormulaEvaluator(context).evaluate(expr);
        buf.write(FormulaEvaluator.toText(value));
      } on FormulaSyntaxException catch (e) {
        errors.add(FormulaError(source, e.message));
        buf.write(errorPlaceholder);
      } on FormulaValueException catch (e) {
        errors.add(FormulaError(source, e.message));
        buf.write(errorPlaceholder);
      } catch (e) {
        errors.add(FormulaError(source, '求值失败：$e'));
        buf.write(errorPlaceholder);
      }
      i = end + 1;
    }
    return RenderResult(
      text: buf.toString(),
      usedVariables: usedVars,
      errors: errors,
    );
  }

  /// 按模板里引用的变量/函数推断最小刷新周期（秒），供原生 AlarmManager 调度。
  /// 静态模板返回 3600（1 小时兜底），最快 1 秒。
  static int analyzeRefreshSeconds(String template) {
    var minSeconds = 3600;
    for (final source in _extractSpans(template)) {
      try {
        _collectVars(parseFormula(source), _varsBuf);
        for (final name in _varsBuf) {
          final s = _variableRefreshSeconds[name];
          if (s != null && s < minSeconds) minSeconds = s;
        }
        _varsBuf.clear();
        if (_hasTimeCall(source)) {
          final fmt = _timeFormatArg(source);
          final s = fmt != null && RegExp(r'[s]').hasMatch(fmt) ? 1 : 60;
          if (s < minSeconds) minSeconds = s;
        }
      } catch (_) {
        // 语法错误片段不参与刷新推断
      }
    }
    return minSeconds.clamp(1, 3600);
  }

  /// 提取模板中的表达式源码片段。
  static List<String> _extractSpans(String template) {
    final spans = <String>[];
    var i = 0;
    while (i < template.length) {
      if (template[i] != r'$') {
        i++;
        continue;
      }
      if (i + 1 < template.length && template[i + 1] == r'$') {
        i += 2;
        continue;
      }
      final end = template.indexOf(r'$', i + 1);
      if (end < 0) break;
      spans.add(template.substring(i + 1, end));
      i = end + 1;
    }
    return spans;
  }

  static final Set<String> _varsBuf = {};

  /// 变量 → 建议刷新周期（秒）。快照类数据原生侧按 30s 采样。
  static const Map<String, int> _variableRefreshSeconds = {
    'second': 1,
    'minute': 60,
    'hour': 60,
    'ampm': 60,
    'weekday': 60,
    'batTemp': 30,
    'cpuFreqMax': 30,
    'cpuFreqMin': 30,
    'cpuUsage': 30,
    'memUsage': 30,
  };

  static void _collectVars(Expr expr, Set<String> out) {
    switch (expr) {
      case VariableExpr(:final name):
        out.add(name);
      case CallExpr(:final args):
        for (final a in args) {
          _collectVars(a, out);
        }
      case UnaryExpr(:final operand):
        _collectVars(operand, out);
      case BinaryExpr(:final left, :final right):
        _collectVars(left, out);
        _collectVars(right, out);
      default:
        break;
    }
  }

  static bool _hasTimeCall(String source) =>
      RegExp(r'\b(tf|df)\s*\(').hasMatch(source);

  /// 提取 tf/df 的第一个字符串字面量参数（用于判断是否含秒记号）。
  static String? _timeFormatArg(String source) {
    final match = RegExp(
      r'''(?:tf|df)\s*\(\s*(['"])([^'"]*)\1''',
    ).firstMatch(source);
    return match?.group(2);
  }
}
