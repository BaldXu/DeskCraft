import 'package:desk_craft/editor/layout_model.dart';
import 'package:desk_craft/formula/formula_context.dart';
import 'package:desk_craft/formula/formula_engine.dart';
import 'package:desk_craft/models/global_var.dart';
import 'package:desk_craft/services/global_var_store.dart';
import 'package:flutter_test/flutter_test.dart';

FormulaContext _base({Map<String, Object?> vars = const {}}) => FormulaContext(
  now: DateTime(2026, 9, 20, 14, 5, 9),
  variables: {'batTemp': 42, 'cpuUsage': 83, ...vars},
);

void main() {
  group('类型解析', () {
    test('文本 / 数字 / 开关按类型转值', () {
      final resolved = GlobalVarStore.resolveAll(const [
        GlobalVar(key: 'title', type: GlobalVarType.text, value: '早安'),
        GlobalVar(key: 'step', type: GlobalVarType.number, value: '5'),
        GlobalVar(key: 'pro', type: GlobalVarType.bool_, value: 'true'),
      ], _base());
      expect(resolved['title'], '早安');
      expect(resolved['step'], 5);
      expect(resolved['pro'], true);
    });

    test('数字值非法回落 null（渲染为占位符）', () {
      final resolved = GlobalVarStore.resolveAll(const [
        GlobalVar(key: 'bad', type: GlobalVarType.number, value: 'abc'),
      ], _base());
      expect(resolved['bad'], isNull);
    });
  });

  group('公式型变量递归求值', () {
    test('引用系统变量', () {
      final resolved = GlobalVarStore.resolveAll(const [
        GlobalVar(
          key: 'tempTip',
          type: GlobalVarType.formula,
          value: 'if(batTemp>40,"热","凉")',
        ),
      ], _base());
      expect(resolved['tempTip'], '热');
    });

    test('引用其他全局变量（链式）', () {
      final resolved = GlobalVarStore.resolveAll(const [
        GlobalVar(key: 'offset', type: GlobalVarType.number, value: '3'),
        GlobalVar(
          key: 'total',
          type: GlobalVarType.formula,
          value: 'cpuUsage + offset',
        ),
      ], _base());
      expect(resolved['total'], 86);
    });

    test('引用开关型变量做条件', () {
      final resolved = GlobalVarStore.resolveAll(const [
        GlobalVar(key: 'showSec', type: GlobalVarType.bool_, value: 'true'),
        GlobalVar(
          key: 'fmt',
          type: GlobalVarType.formula,
          value: 'if(showSec, "HH:mm:ss", "HH:mm")',
        ),
      ], _base());
      expect(resolved['fmt'], 'HH:mm:ss');
    });

    test('循环引用回落 null 不崩溃', () {
      final resolved = GlobalVarStore.resolveAll(const [
        GlobalVar(key: 'a', type: GlobalVarType.formula, value: 'b + 1'),
        GlobalVar(key: 'b', type: GlobalVarType.formula, value: 'a + 1'),
      ], _base());
      expect(resolved['a'], isNull);
      expect(resolved['b'], isNull);
    });

    test('语法错误回落 null', () {
      final resolved = GlobalVarStore.resolveAll(const [
        GlobalVar(
          key: 'broken',
          type: GlobalVarType.formula,
          value: 'if(cpuUsage>80,"高"',
        ),
      ], _base());
      expect(resolved['broken'], isNull);
    });
  });

  group('模板渲染集成', () {
    test('公式模板引用全局变量', () {
      final globals = GlobalVarStore.resolveAll(const [
        GlobalVar(key: 'greet', type: GlobalVarType.text, value: '你好'),
        GlobalVar(
          key: 'tip',
          type: GlobalVarType.formula,
          value: 'if(cpuUsage>80,"忙","闲")',
        ),
      ], _base());
      final ctx = FormulaContext(
        now: DateTime(2026, 9, 20, 14, 5, 9),
        variables: const {'cpuUsage': 83},
        globals: globals,
      );
      expect(
        FormulaEngine.render(r'$greet$ · CPU $tip$', ctx).text,
        '你好 · CPU 忙',
      );
      expect(ctx.lookup('greet'), '你好');
    });
  });

  group('变量名校验', () {
    test('合法名通过', () {
      expect(GlobalVar.validateKey('themeColor'), isNull);
      expect(GlobalVar.validateKey('_private1'), isNull);
    });

    test('非法名拒绝', () {
      expect(GlobalVar.validateKey(''), isNotNull);
      expect(GlobalVar.validateKey('1abc'), isNotNull);
      expect(GlobalVar.validateKey('a-b'), isNotNull);
      expect(GlobalVar.validateKey('a b'), isNotNull);
    });

    test('与系统变量 / 函数重名拒绝', () {
      expect(GlobalVar.validateKey('hour'), isNotNull); // 系统变量
      expect(GlobalVar.validateKey('if'), isNotNull); // 函数名
      expect(GlobalVar.validateKey('tf'), isNotNull);
    });

    test('与已有变量重名拒绝，编辑自身除外', () {
      const existing = [
        GlobalVar(key: 'dup', type: GlobalVarType.text, value: 'x'),
      ];
      expect(GlobalVar.validateKey('dup', existing: existing), isNotNull);
      expect(
        GlobalVar.validateKey('dup', existing: existing, ignoreKey: 'dup'),
        isNull,
      );
    });
  });

  group('JSON 序列化', () {
    test('encodeAll / decodeAll 往返', () {
      const vars = [
        GlobalVar(key: 'a', type: GlobalVarType.number, value: '42'),
        GlobalVar(key: 'b', type: GlobalVarType.formula, value: 'a*2'),
        GlobalVar(key: 'c', type: GlobalVarType.bool_, value: 'false'),
      ];
      final decoded = GlobalVar.decodeAll(GlobalVar.encodeAll(vars));
      expect(decoded.length, 3);
      expect(decoded[0].key, 'a');
      expect(decoded[0].type, GlobalVarType.number);
      expect(decoded[0].value, '42');
      expect(decoded[2].type, GlobalVarType.bool_);
      expect(decoded[2].value, 'false');
    });

    test('非法 JSON 回落空列表', () {
      expect(GlobalVar.decodeAll('not json'), isEmpty);
      expect(GlobalVar.decodeAll('[]'), isEmpty);
    });
  });

  group('刷新周期合并', () {
    WidgetLayout layoutWith(String template) => WidgetLayout(
      id: 't',
      name: 't',
      layers: [
        TextLayer(id: 'l', x: 0, y: 0, w: 10, h: 10, template: template),
      ],
    );

    test('模板引用的公式型 GV 参与周期合并（秒级生效）', () {
      final layout = layoutWith(r'$clock$'); // 模板自身只引用 GV
      const gvs = [
        GlobalVar(
          key: 'clock',
          type: GlobalVarType.formula,
          value: 'tf("HH:mm:ss")',
        ),
      ];
      expect(GlobalVarStore.effectiveRefreshSeconds(layout, gvs), 1);
    });

    test('未被引用的公式型 GV 不拖慢组件', () {
      final layout = layoutWith(r'$tf("HH:mm")$'); // 模板只引用时间
      const gvs = [
        GlobalVar(
          key: 'unused',
          type: GlobalVarType.formula,
          value: 'tf("HH:mm:ss")',
        ),
      ];
      expect(GlobalVarStore.effectiveRefreshSeconds(layout, gvs), 60);
    });

    test('分钟级 GV 引用不把周期拉进秒级', () {
      final layout = layoutWith(r'$clock$');
      const gvs = [
        GlobalVar(
          key: 'clock',
          type: GlobalVarType.formula,
          value: 'tf("HH:mm")',
        ),
      ];
      expect(GlobalVarStore.effectiveRefreshSeconds(layout, gvs), 60);
    });
  });

  group('引擎引用分析工具', () {
    test('usedVariablesInTemplate 收集模板内所有变量', () {
      expect(FormulaEngine.usedVariablesInTemplate(r'$a$ $b$ $a$'), {'a', 'b'});
      expect(FormulaEngine.usedVariablesInTemplate(r'$if(cpuUsage>80,"x")$'), {
        'cpuUsage',
      });
    });

    test('usedVariables 解析单表达式', () {
      expect(FormulaEngine.usedVariables('batTemp + step'), {
        'batTemp',
        'step',
      });
      expect(FormulaEngine.usedVariables('1+2('), isEmpty);
    });
  });
}
