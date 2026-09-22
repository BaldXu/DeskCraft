/// 全局变量管理页（M6 第③步）——定义/编辑/删除可被公式模板引用的自定义变量。
///
/// - 变量为应用级全局（所有自定义布局共享），存入 [GlobalVarStore]；
/// - 保存后自动重渲染桌面上的激活布局（[CustomWidgetStore.refreshDesktop]），
///   没有上桌组件则仅落库；
/// - 编辑表单走 [showParameterSheet]（与项目参数弹窗风格一致）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../formula/formula_context.dart';
import '../formula/formula_engine.dart';
import '../models/global_var.dart';
import '../services/custom_widget_store.dart';
import '../services/global_var_store.dart';
import '../widgets/parameter_sheet.dart';

/// 全局变量管理页。
class GlobalVarsPage extends StatefulWidget {
  const GlobalVarsPage({super.key});

  @override
  State<GlobalVarsPage> createState() => _GlobalVarsPageState();
}

class _GlobalVarsPageState extends State<GlobalVarsPage> {
  List<GlobalVar> _vars = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final vars = await GlobalVarStore.loadAll();
    if (!mounted) return;
    setState(() => _vars = vars);
  }

  Future<void> _openEditor([GlobalVar? existing]) async {
    final saved = await showParameterSheet<GlobalVar>(
      context: context,
      builder: (context) => _GlobalVarForm(existing: existing, all: _vars),
      heightFactor: 0.7,
    );
    if (saved == null || !mounted) return;
    // 落库 + 重渲染桌面激活布局（无激活布局则忽略）
    await GlobalVarStore.upsert(saved);
    await _reload();
    final pushed = await CustomWidgetStore.refreshDesktop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pushed ? '已保存，桌面组件已刷新' : '已保存（当前无上桌组件）',
          ),
        ),
      );
    }
  }

  Future<void> _confirmDelete(GlobalVar v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除变量'),
        content: Text('确定删除「${v.key}」吗？引用它的公式将显示为占位符。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await GlobalVarStore.remove(v.key);
    await _reload();
    final pushed = await CustomWidgetStore.refreshDesktop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pushed ? '已删除，桌面组件已刷新' : '已删除')),
      );
    }
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('全局变量怎么用'),
        content: const SingleChildScrollView(
          child: Text(
            '全局变量是跨组件共享的自定义值，可在任意布局的文本模板里通过 '
            '\$变量名\$ 引用。\n\n'
            '支持四种类型：\n'
            '· 文本 —— 原样字符串\n'
            '· 数字 —— 可用于四则运算 / 比较\n'
            '· 开关 —— 布尔值，配合 if() 使用\n'
            '· 公式 —— 一段表达式，求值结果作为变量值（可引用系统变量和其他变量）\n\n'
            '示例：\n'
            '1. 文本变量 名称=我 → 模板写 \$名称\$ 显示「我」\n'
            '2. 数字变量 阈值=40 → 模板写 \$if(batTemp>\$阈值\$,"热","凉")\$\n'
            '3. 公式变量 问候=\$if(hour<12,"早上好","你好")\$ → 模板直接引用 \$问候\$\n\n'
            '变量名只能包含字母/数字/下划线，不能与系统变量、函数名重名。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('全局变量'),
        actions: [
          IconButton(
            tooltip: '使用说明',
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新建变量'),
      ),
      body: _vars.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.functions,
                    size: 56,
                    color: textTheme.bodySmall?.color?.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text('还没有全局变量', style: textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Text('定义后可被任意布局的公式模板引用', style: textTheme.bodySmall),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: _vars.length,
              itemBuilder: (context, index) {
                final v = _vars[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: Icon(_typeIcon(v.type)),
                    title: Text(
                      v.key,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${v.type.label} · ${v.summary}'),
                    trailing: IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(v),
                    ),
                    onTap: () => _openEditor(v),
                  ),
                );
              },
            ),
    );
  }

  IconData _typeIcon(GlobalVarType type) => switch (type) {
    GlobalVarType.text => Icons.text_fields,
    GlobalVarType.number => Icons.numbers,
    GlobalVarType.bool_ => Icons.toggle_on,
    GlobalVarType.formula => Icons.functions,
  };
}

/// 新建 / 编辑变量的表单弹窗。
///
/// [existing] 为空表示新建；编辑时变量名锁定（改名会断掉已有引用）。
/// 保存成功后通过 [Navigator.pop] 返回新的 [GlobalVar]。
class _GlobalVarForm extends StatefulWidget {
  const _GlobalVarForm({required this.existing, required this.all});

  final GlobalVar? existing;
  final List<GlobalVar> all;

  @override
  State<_GlobalVarForm> createState() => _GlobalVarFormState();
}

class _GlobalVarFormState extends State<_GlobalVarForm> {
  late final TextEditingController _keyController;
  late final TextEditingController _valueController;
  late GlobalVarType _type;
  bool _boolValue = false;

  /// 实时校验错误文案（null = 可保存）。
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _keyController = TextEditingController(text: e?.key ?? '');
    _type = e?.type ?? GlobalVarType.text;
    _boolValue = e?.value.trim().toLowerCase() == 'true';
    _valueController = TextEditingController(
      text: e == null || e.type == GlobalVarType.bool_ ? '' : e.value,
    );
    _validate();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _validate() {
    String? error;
    if (widget.existing == null) {
      error = GlobalVar.validateKey(
        _keyController.text,
        existing: widget.all,
      );
    }
    if (error == null && _type == GlobalVarType.formula) {
      error = GlobalVar.validateFormula(_valueController.text);
    }
    if (error == null &&
        (_type == GlobalVarType.number ||
            _type == GlobalVarType.text) &&
        _valueController.text.isEmpty) {
      error = '值不能为空';
    }
    setState(() => _error = error);
  }

  GlobalVar _buildVar() {
    final value = switch (_type) {
      GlobalVarType.bool_ => _boolValue ? 'true' : 'false',
      _ => _valueController.text,
    };
    return GlobalVar(
      key: widget.existing?.key ?? _keyController.text.trim(),
      type: _type,
      value: value,
    );
  }

  void _save() {
    if (_error != null) return;
    Navigator.of(context).pop(_buildVar());
  }

  /// 公式型变量的实时求值预览（以当前表单值临时合成变量表）。
  String? get _formulaPreview {
    final value = _valueController.text;
    if (value.trim().isEmpty) return null;
    final candidate = _buildVar();
    final merged = [
      ...widget.all.where((g) => g.key != widget.existing?.key),
      candidate,
    ];
    final base = FormulaContext(now: DateTime.now());
    final resolved = GlobalVarStore.resolveAll(merged, base);
    final ctx = FormulaContext(now: DateTime.now(), globals: resolved);
    final result = FormulaEngine.render(r'$' + value + r'$', ctx);
    if (result.hasError) return '求值错误：${result.errors.first.message}';
    return '预览：${result.text}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? '新建变量' : '编辑变量',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _keyController,
            enabled: widget.existing == null,
            decoration: InputDecoration(
              labelText: '变量名',
              hintText: '如 themeColor / step / isPro',
              helperText: widget.existing == null
                  ? '字母/数字/下划线，不能以数字开头'
                  : '变量名创建后不可修改',
              border: const OutlineInputBorder(),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
            ],
            onChanged: (_) => _validate(),
          ),
          const SizedBox(height: 16),
          SegmentedButton<GlobalVarType>(
            segments: [
              for (final t in GlobalVarType.values)
                ButtonSegment(value: t, label: Text(t.label)),
            ],
            selected: {_type},
            onSelectionChanged: (s) {
              setState(() => _type = s.first);
              _validate();
            },
          ),
          const SizedBox(height: 16),
          if (_type == GlobalVarType.bool_)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开关状态'),
              value: _boolValue,
              onChanged: (v) => setState(() => _boolValue = v),
            )
          else ...[
            TextField(
              controller: _valueController,
              minLines: 1,
              maxLines: _type == GlobalVarType.formula ? 4 : 2,
              keyboardType:
                  _type == GlobalVarType.number
                      ? const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        )
                      : TextInputType.multiline,
              decoration: InputDecoration(
                labelText: switch (_type) {
                  GlobalVarType.text => '文本内容',
                  GlobalVarType.number => '数字',
                  GlobalVarType.formula => '表达式（不用写 \$）',
                  GlobalVarType.bool_ => '',
                },
                hintText: switch (_type) {
                  GlobalVarType.formula =>
                    '如 if(batTemp>40,"热","正常")',
                  GlobalVarType.number => '如 40',
                  _ => null,
                },
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _validate(),
            ),
            if (_type == GlobalVarType.formula && _formulaPreview != null) ...[
              const SizedBox(height: 8),
              Text(
                _formulaPreview!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _formulaPreview!.startsWith('求值错误')
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ],
          const Spacer(),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: _error == null ? _save : null,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
