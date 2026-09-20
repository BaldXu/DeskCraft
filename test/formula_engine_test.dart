import 'package:flutter_test/flutter_test.dart';
import 'package:desk_craft/formula/formula_context.dart';
import 'package:desk_craft/formula/formula_engine.dart';

FormulaContext _ctx({Map<String, Object?> vars = const {}}) => FormulaContext(
  now: DateTime(2026, 9, 20, 14, 5, 9), // 周日 14:05:09
  variables: {
    'batTemp': 32.5,
    'cpuUsage': 83,
    'memUsage': 61,
    'cpuFreqMax': 2.806,
    'cpuFreqMin': 1.2,
    ...vars,
  },
);

void main() {
  group('时间格式化', () {
    test('tf 常规格式', () {
      expect(FormulaEngine.render(r'$tf("HH:mm")$', _ctx()).text, '14:05');
      expect(
        FormulaEngine.render(r'$tf("HH:mm:ss")$', _ctx()).text,
        '14:05:09',
      );
      expect(FormulaEngine.render(r'$tf("h:mm a")$', _ctx()).text, '2:05 下午');
    });

    test('df 日期与周几', () {
      expect(
        FormulaEngine.render(r'$df("yyyy-MM-dd")$', _ctx()).text,
        '2026-09-20',
      );
      expect(FormulaEngine.render(r'$df("M月d日 E")$', _ctx()).text, '9月20日 周日');
    });

    test('tf/df 缺省格式', () {
      expect(FormulaEngine.render(r'$tf()$', _ctx()).text, '14:05');
      expect(FormulaEngine.render(r'$df()$', _ctx()).text, '2026-09-20');
    });
  });

  group('四则与函数', () {
    test('数字运算与整数化显示', () {
      expect(FormulaEngine.render(r'$1+2*3$', _ctx()).text, '7');
      expect(FormulaEngine.render(r'$(1+2)*3$', _ctx()).text, '9');
      expect(FormulaEngine.render(r'$10/4$', _ctx()).text, '2.5');
      expect(FormulaEngine.render(r'$4/2$', _ctx()).text, '2');
      expect(FormulaEngine.render(r'$-5+2$', _ctx()).text, '-3');
      expect(FormulaEngine.render(r'$7%3$', _ctx()).text, '1');
    });

    test('round / floor / ceil / abs / min / max', () {
      expect(FormulaEngine.render(r'$round(3.456, 1)$', _ctx()).text, '3.5');
      expect(FormulaEngine.render(r'$round(2.5)$', _ctx()).text, '3');
      expect(FormulaEngine.render(r'$floor(3.9)$', _ctx()).text, '3');
      expect(FormulaEngine.render(r'$ceil(3.1)$', _ctx()).text, '4');
      expect(FormulaEngine.render(r'$abs(-4)$', _ctx()).text, '4');
      expect(FormulaEngine.render(r'$min(3, 7)$', _ctx()).text, '3');
      expect(FormulaEngine.render(r'$max(3, 7)$', _ctx()).text, '7');
    });

    test('cat 与字符串拼接', () {
      expect(
        FormulaEngine.render(r'$cat("电池", " ", 32.5)$', _ctx()).text,
        '电池 32.5',
      );
      expect(FormulaEngine.render(r'$"共" + 3 + "核"$', _ctx()).text, '共3核');
    });
  });

  group('条件与比较', () {
    test('if 基本分支', () {
      expect(
        FormulaEngine.render(r'$if(cpuUsage>80, "高", "低")$', _ctx()).text,
        '高',
      );
      expect(FormulaEngine.render(r'$if(0, "a", "b")$', _ctx()).text, 'b');
      expect(FormulaEngine.render(r'$if(memUsage>80, "告警")$', _ctx()).text, '');
    });

    test('比较运算', () {
      expect(FormulaEngine.render(r'$3<5$', _ctx()).text, 'true');
      expect(FormulaEngine.render(r'$3>=5$', _ctx()).text, 'false');
      expect(FormulaEngine.render(r'$"a" == "a"$', _ctx()).text, 'true');
      expect(FormulaEngine.render(r'$3 != 3$', _ctx()).text, 'false');
    });

    test('嵌套 if', () {
      final r = FormulaEngine.render(
        r'$if(batTemp>45, "热", if(batTemp>40, "温", "正常"))$',
        _ctx(),
      );
      expect(r.text, '正常');
    });
  });

  group('系统变量与快照数据', () {
    test('监控变量渲染', () {
      expect(FormulaEngine.render(r'$batTemp$°C', _ctx()).text, '32.5°C');
      expect(
        FormulaEngine.render(r'$round(cpuFreqMax, 1)$GHz', _ctx()).text,
        '2.8GHz',
      );
    });

    test('数据不可用渲染占位符并记录错误', () {
      final r = FormulaEngine.render(
        r'$batTemp$°C',
        _ctx(vars: {'batTemp': null}),
      );
      expect(r.text, '--°C');
      expect(r.hasError, isTrue);
      expect(r.errors.first.message, contains('数据不可用'));
    });

    test('未知变量报错不影响其他片段', () {
      final r = FormulaEngine.render(r'时间 $tf("HH")$ / $nope$', _ctx());
      expect(r.text, '时间 14 / --');
      expect(r.errors.single.message, contains('未知变量'));
      expect(r.usedVariables, {'nope'});
    });
  });

  group('模板转义与解析错误', () {
    test(r'$$ 转义字面量 $', () {
      expect(
        FormulaEngine.render(r'a $$ b $tf("HH")$', _ctx()).text,
        'a \$ b 14',
      );
    });

    test(r'未闭合的 $ 原样保留', () {
      expect(FormulaEngine.render(r'价格 5 元$', _ctx()).text, r'价格 5 元$');
    });

    test('语法错误渲染占位符', () {
      final r = FormulaEngine.render(r'$1 +$', _ctx());
      expect(r.text, '--');
      expect(r.hasError, isTrue);
    });
  });

  group('刷新周期分析', () {
    test('静态模板 1 小时', () {
      expect(FormulaEngine.analyzeRefreshSeconds('纯文本'), 3600);
    });

    test('时间分钟级', () {
      expect(FormulaEngine.analyzeRefreshSeconds(r'$tf("HH:mm")$'), 60);
      expect(FormulaEngine.analyzeRefreshSeconds(r'$minute$'), 60);
    });

    test('含秒 → 1 秒', () {
      expect(FormulaEngine.analyzeRefreshSeconds(r'$tf("HH:mm:ss")$'), 1);
      expect(FormulaEngine.analyzeRefreshSeconds(r'$second$'), 1);
    });

    test('快照变量 30 秒，多片段取最小', () {
      expect(FormulaEngine.analyzeRefreshSeconds(r'$batTemp$°C'), 30);
      expect(FormulaEngine.analyzeRefreshSeconds(r'$batTemp$ / $second$'), 1);
      expect(FormulaEngine.analyzeRefreshSeconds(r'$batTemp$ / $minute$'), 30);
    });
  });

  group('usedVariables 收集', () {
    test('嵌套函数与条件里的变量', () {
      final r = FormulaEngine.render(
        r'$if(batTemp>40, round(cpuFreqMax,1), cpuFreqMin)$',
        _ctx(),
      );
      expect(r.usedVariables, {'batTemp', 'cpuFreqMax', 'cpuFreqMin'});
    });
  });
}
