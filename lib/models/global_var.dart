/// 全局变量（GV）模型 —— M6 第③步：用户自定义变量，可被公式模板引用。
///
/// 设计约定：
/// - 变量名为字母/数字/下划线（`^[a-zA-Z_][a-zA-Z0-9_]*$`），公式中直接写 `$名字$`；
/// - 变量名不得与系统变量 / 函数名重名（见 [GlobalVar.validateKey]）；
/// - 值统一以字符串存储（[GlobalVar.value]），按 [type] 在解析期转成
///   公式引擎能用的类型（String / num / bool），公式类型在求值时递归求值；
/// - JSON 序列化遵循项目兼容约定：缺字段宽松回落默认值。
library;

import 'dart:convert';

import '../formula/formula_engine.dart';
import '../formula/formula_parser.dart';

/// 全局变量类型。
enum GlobalVarType {
  /// 文本：原样字符串。
  text('text', '文本'),

  /// 数字：字符串存储，解析期 `num.tryParse`。
  number('number', '数字'),

  /// 开关：存储 'true' / 'false'。
  bool_('bool', '开关'),

  /// 公式：存储表达式源码（不带 `$`），求值时用公式引擎递归求值。
  formula('formula', '公式');

  const GlobalVarType(this.key, this.label);

  /// 序列化 key（勿改名，与存储对齐）。
  final String key;
  final String label;

  static GlobalVarType fromKey(String? key) =>
      values.firstWhere((t) => t.key == key, orElse: () => GlobalVarType.text);
}

/// 全局变量：名字 + 类型 + 值（字符串存储）。
class GlobalVar {
  const GlobalVar({required this.key, required this.type, this.value = ''});

  /// 变量名（公式中直接引用，创建后建议不改名，改名即断引用）。
  final String key;

  final GlobalVarType type;

  /// 值：text=原文；number=数字文本；bool='true'/'false'；formula=表达式源码。
  final String value;

  GlobalVar copyWith({GlobalVarType? type, String? value}) =>
      GlobalVar(key: key, type: type ?? this.type, value: value ?? this.value);

  Map<String, Object?> toJson() => {
    'key': key,
    'type': type.key,
    'value': value,
  };

  factory GlobalVar.fromJson(Map<String, Object?> json) => GlobalVar(
    key: json['key'] is String ? json['key'] as String : '',
    type: GlobalVarType.fromKey(json['type'] as String?),
    value: json['value'] is String ? json['value'] as String : '',
  );

  /// 校验变量名是否可用；返回错误文案，null 表示合法。
  ///
  /// [existing] 为当前全部变量（用于查重），[ignoreKey] 为编辑态自身 key
  /// （编辑自己时跳过重名检查）。
  static String? validateKey(
    String key, {
    List<GlobalVar> existing = const [],
    String? ignoreKey,
  }) {
    final name = key.trim();
    if (name.isEmpty) return '变量名不能为空';
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(name)) {
      return '只能包含字母、数字、下划线，且不能以数字开头';
    }
    if (FormulaEngine.knownVariables.containsKey(name)) {
      return '「$name」与系统变量重名，无法引用';
    }
    if (FormulaEngine.knownFunctions.containsKey(name)) {
      return '「$name」与函数名重名，无法引用';
    }
    for (final g in existing) {
      if (g.key == name && g.key != ignoreKey) return '变量「$name」已存在';
    }
    return null;
  }

  /// 值摘要（列表展示用），长文本截断。
  String get summary {
    switch (type) {
      case GlobalVarType.bool_:
        return value.trim().toLowerCase() == 'true' ? '开' : '关';
      case GlobalVarType.formula:
        return value.isEmpty ? '（空公式）' : value;
      default:
        return value.isEmpty ? '（空）' : value;
    }
  }

  /// 校验公式类型变量的表达式语法；返回错误文案，null 表示合法。
  static String? validateFormula(String source) {
    if (source.trim().isEmpty) return '公式不能为空';
    try {
      parseFormula(source);
      return null;
    } on FormulaSyntaxException catch (e) {
      return e.message;
    }
  }

  static String encodeAll(List<GlobalVar> vars) =>
      jsonEncode(vars.map((v) => v.toJson()).toList());

  static List<GlobalVar> decodeAll(String source) {
    try {
      final list = jsonDecode(source);
      if (list is! List<Object?>) return [];
      return list
          .whereType<Map<String, Object?>>()
          .map(GlobalVar.fromJson)
          .where((v) => v.key.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
