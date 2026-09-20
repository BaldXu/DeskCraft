// 自定义组件存储测试（M6 m3）：布局库 CRUD + 采样变量映射。
import 'package:desk_craft/editor/layout_model.dart';
import 'package:desk_craft/services/custom_widget_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('home_widget');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('布局库 CRUD', () {
    test('save 新增 / update 按 id 覆盖 / delete 删除', () async {
      final a = await CustomWidgetStore.saveLayout(
        WidgetLayout(id: 'a', name: '甲'),
      );
      await CustomWidgetStore.saveLayout(WidgetLayout(id: 'b', name: '乙'));

      var all = await CustomWidgetStore.loadAll();
      expect(all.map((l) => l.id), ['a', 'b']);
      expect(a.updatedAt, greaterThan(0));

      // 更新
      await CustomWidgetStore.saveLayout(
        WidgetLayout(
          id: 'a',
          name: '甲改',
          layers: [RectLayer(id: 'r', x: 0, y: 0, w: 10, h: 10)],
        ),
      );
      all = await CustomWidgetStore.loadAll();
      expect(all.length, 2);
      expect(all.firstWhere((l) => l.id == 'a').name, '甲改');
      expect(
        (all.firstWhere((l) => l.id == 'a').layers.single as RectLayer).w,
        10,
      );

      // 删除
      await CustomWidgetStore.deleteLayout('a');
      all = await CustomWidgetStore.loadAll();
      expect(all.map((l) => l.id), ['b']);
    });

    test('空库返回空列表，坏 JSON 不抛错', () async {
      expect(await CustomWidgetStore.loadAll(), isEmpty);
      final sp = await SharedPreferences.getInstance();
      await sp.setString('custom_widget_layouts_v1', '{bad json');
      expect(await CustomWidgetStore.loadAll(), isEmpty);
    });
  });

  group('采样变量映射', () {
    test('原生 key → 公式变量名', () async {
      const channel = MethodChannel('home_widget');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getWidgetData') {
              return '{"batteryTempC":33.5,"cpuUsagePercent":12,"memUsagePercent":40,"cpuFreqMaxGhz":2.84,"rooted":true}';
            }
            return null;
          });

      final vars = await CustomWidgetStore.loadWidgetVars();
      expect(vars['batTemp'], 33.5);
      expect(vars['cpuUsage'], 12);
      expect(vars['memUsage'], 40);
      expect(vars['cpuFreqMax'], 2.84);
      // 未知 key 原样保留
      expect(vars['rooted'], true);
    });

    test('无快照时返回空变量表', () async {
      const channel = MethodChannel('home_widget');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      final vars = await CustomWidgetStore.loadWidgetVars();
      expect(vars, isEmpty);
    });
  });

  test('defaultLayout 含秒级时钟 → 刷新周期 1 秒', () {
    final layout = CustomWidgetStore.defaultLayout();
    expect(layout.refreshSeconds, 1);
    expect(layout.layers.length, greaterThanOrEqualTo(2));
  });
}
