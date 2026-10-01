import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/feature/kancolle/ship_filter.dart';
import 'package:conning_tower/widgets/components/edge_insets_constants.dart';
import 'package:conning_tower/widgets/scroll_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// 選択肢を下から出す (WebView の上でもタップできるように PointerInterceptor で包む)
Future<T?> showShipFilterPicker<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) label,
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (sheetContext) => PointerInterceptor(
      child: CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final option in options)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(option),
              child: Text(label(option)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(repairText('キャンセル', 'Cancel')),
        ),
      ),
    ),
  );
}

class _ConditionDraft {
  ShipStat stat;
  CompareOp op;
  final TextEditingController controller;

  _ConditionDraft({required this.stat, required this.op, required int value})
      : controller = TextEditingController(text: '$value');
}

/// フィルターの作成・編集画面。保存すると [ShipFilterPreset] を返す
class KancolleShipFilterEditor extends StatefulWidget {
  const KancolleShipFilterEditor({
    super.key,
    this.initial,
    required this.shipTypeOptions,
  });

  final ShipFilterPreset? initial;

  /// 艦種名 -> api_stype の ID
  final Map<String, List<int>> shipTypeOptions;

  @override
  State<KancolleShipFilterEditor> createState() => _KancolleShipFilterEditorState();
}

class _KancolleShipFilterEditorState extends State<KancolleShipFilterEditor> {
  late final TextEditingController _nameController;
  late Set<int> _shipTypes;
  late List<_ConditionDraft> _conditions;
  late List<SortKey> _sortKeys;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _shipTypes = {...?initial?.shipTypes};
    _conditions = [
      for (final c in initial?.conditions ?? <StatCondition>[]) _ConditionDraft(stat: c.stat, op: c.op, value: c.value)
    ];
    _sortKeys = [...?initial?.sortKeys];
    if (_sortKeys.isEmpty) _sortKeys = [const SortKey(ShipStat.condition)];
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _conditions) {
      c.controller.dispose();
    }
    super.dispose();
  }

  String get _shipTypeText {
    if (_shipTypes.isEmpty) return repairText('すべて', 'All');
    final names = widget.shipTypeOptions.entries
        .where((e) => e.value.any(_shipTypes.contains))
        .map((e) => e.key)
        .toList();
    return names.isEmpty ? repairText('すべて', 'All') : names.join(', ');
  }

  void _save() {
    final conditions = [
      for (final c in _conditions)
        StatCondition(stat: c.stat, op: c.op, value: int.tryParse(c.controller.text.trim()) ?? 0)
    ];
    var name = _nameController.text.trim();
    if (name.isEmpty) {
      name = [
        if (_shipTypes.isNotEmpty) _shipTypeText,
        ...conditions.map((c) => c.text),
      ].join(' ');
      if (name.isEmpty) name = repairText('フィルター', 'Filter');
    }
    Navigator.of(context).pop(ShipFilterPreset(
      name: name,
      shipTypes: _shipTypes.toList(),
      conditions: conditions,
      sortKeys: [..._sortKeys],
    ));
  }

  Future<void> _selectShipTypes() async {
    final result = await Navigator.of(context).push<Set<int>>(CupertinoPageRoute(
      builder: (_) => _ShipTypeSelectPage(options: widget.shipTypeOptions, selected: _shipTypes),
    ));
    if (result != null) setState(() => _shipTypes = result);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        border: null,
        backgroundColor: CupertinoColors.systemGroupedBackground,
        middle: Text(widget.initial == null
            ? repairText('フィルターを作成', 'New filter')
            : repairText('フィルターを編集', 'Edit filter')),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _save,
          child: Text(repairText('保存', 'Save')),
        ),
      ),
      child: SafeArea(
        child: ScrollViewWithCupertinoScrollbar(
          children: [
            CupertinoListSection.insetGrouped(
              margin: tabBottomListMargin,
              header: Text(repairText('名前', 'Name')),
              children: [
                CupertinoListTile(
                  title: CupertinoTextField.borderless(
                    controller: _nameController,
                    placeholder: repairText('未入力なら条件から自動で付けます', 'Auto-named if empty'),
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              margin: tabBottomListMargin,
              header: Text(repairText('艦種', 'Ship type')),
              children: [
                CupertinoListTile(
                  title: Text(_shipTypeText, maxLines: 2),
                  trailing: const CupertinoListTileChevron(),
                  onTap: _selectShipTypes,
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              margin: tabBottomListMargin,
              header: Text(repairText('条件 (最大${ShipFilterPreset.maxConditions}つ、すべて満たす艦を表示)',
                  'Conditions (up to ${ShipFilterPreset.maxConditions}, all must match)')),
              children: [
                for (final (index, condition) in _conditions.indexed) _buildConditionRow(index, condition),
                if (_conditions.length < ShipFilterPreset.maxConditions)
                  CupertinoListTile(
                    leading: const Icon(CupertinoIcons.add),
                    title: Text(repairText('条件を追加', 'Add condition')),
                    onTap: () => setState(() {
                      _conditions.add(_ConditionDraft(stat: ShipStat.baseAsw, op: CompareOp.gte, value: 0));
                    }),
                  ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              margin: tabBottomListMargin,
              header: Text(repairText(
                  '並び替え (最大${ShipFilterPreset.maxSortKeys}つ、上から順に優先)',
                  'Sort (up to ${ShipFilterPreset.maxSortKeys}, top has priority)')),
              footer: Text(repairText(
                  '第1キーが同じ値の艦は、第2キー、第3キーの順に並べます',
                  'Ships with the same 1st key value are ordered by the 2nd, then 3rd key')),
              children: [
                for (final (index, key) in _sortKeys.indexed) ...[
                  CupertinoListTile(
                    leading: Text(repairText('第${index + 1}', '#${index + 1}')),
                    title: Text(key.stat.label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_sortKeys.length > 1)
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => setState(() => _sortKeys.removeAt(index)),
                            child: const Icon(CupertinoIcons.delete, color: CupertinoColors.destructiveRed),
                          ),
                        const CupertinoListTileChevron(),
                      ],
                    ),
                    onTap: () async {
                      final stat = await showShipFilterPicker<ShipStat>(context,
                          title: repairText('第${index + 1}キーの値', 'Sort key #${index + 1}'),
                          options: ShipStat.values,
                          label: (e) => e.label);
                      if (stat != null) {
                        setState(() => _sortKeys[index] = SortKey(stat, descending: _sortKeys[index].descending));
                      }
                    },
                  ),
                  CupertinoListTile(
                    title: CupertinoSlidingSegmentedControl<bool>(
                      groupValue: key.descending,
                      children: {
                        true: Text(repairText('降順 (高い順)', 'Descending')),
                        false: Text(repairText('昇順 (低い順)', 'Ascending')),
                      },
                      onValueChanged: (value) => setState(
                          () => _sortKeys[index] = SortKey(_sortKeys[index].stat, descending: value ?? true)),
                    ),
                  ),
                ],
                if (_sortKeys.length < ShipFilterPreset.maxSortKeys)
                  CupertinoListTile(
                    leading: const Icon(CupertinoIcons.add),
                    title: Text(repairText('並び替えを追加', 'Add sort key')),
                    onTap: () => setState(() => _sortKeys.add(const SortKey(ShipStat.level))),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionRow(int index, _ConditionDraft condition) {
    return CupertinoListTile(
      title: Row(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onPressed: () async {
              final stat = await showShipFilterPicker<ShipStat>(context,
                  title: repairText('条件にする値', 'Value'), options: ShipStat.values, label: (e) => e.label);
              if (stat != null) setState(() => condition.stat = stat);
            },
            child: Text(condition.stat.label),
          ),
          SizedBox(
            width: 64,
            child: CupertinoTextField(
              controller: condition.controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onPressed: () async {
              final op = await showShipFilterPicker<CompareOp>(context,
                  title: repairText('比較', 'Compare'), options: CompareOp.values, label: (e) => e.label);
              if (op != null) setState(() => condition.op = op);
            },
            child: Text(condition.op.label),
          ),
        ],
      ),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => setState(() {
          _conditions.removeAt(index).controller.dispose();
        }),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.destructiveRed),
      ),
    );
  }
}

class _ShipTypeSelectPage extends StatefulWidget {
  const _ShipTypeSelectPage({required this.options, required this.selected});

  final Map<String, List<int>> options;
  final Set<int> selected;

  @override
  State<_ShipTypeSelectPage> createState() => _ShipTypeSelectPageState();
}

class _ShipTypeSelectPageState extends State<_ShipTypeSelectPage> {
  late final Set<int> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        border: null,
        backgroundColor: CupertinoColors.systemGroupedBackground,
        middle: Text(repairText('艦種を選択', 'Ship types')),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(_selected),
          child: Text(repairText('決定', 'Done')),
        ),
      ),
      child: SafeArea(
        child: ScrollViewWithCupertinoScrollbar(
          children: [
            CupertinoListSection.insetGrouped(
              margin: tabBottomListMargin,
              footer: Text(repairText('何も選ばない場合はすべての艦種', 'None selected = all ship types')),
              children: [
                CupertinoListTile(
                  title: Text(repairText('すべて', 'All')),
                  trailing: _selected.isEmpty ? const Icon(CupertinoIcons.checkmark_alt) : null,
                  onTap: () => setState(_selected.clear),
                ),
                for (final entry in widget.options.entries)
                  if (entry.value.isNotEmpty)
                    CupertinoListTile(
                      title: Text(entry.key),
                      trailing: entry.value.every(_selected.contains) ? const Icon(CupertinoIcons.checkmark_alt) : null,
                      onTap: () => setState(() {
                        if (entry.value.every(_selected.contains)) {
                          _selected.removeAll(entry.value);
                        } else {
                          _selected.addAll(entry.value);
                        }
                      }),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
