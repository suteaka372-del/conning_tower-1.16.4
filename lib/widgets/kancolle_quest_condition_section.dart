import 'package:conning_tower/models/feature/kancolle/quest_fleet_condition.dart';
import 'package:conning_tower/models/feature/kancolle/quest_progress.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/widgets/components/edge_insets_constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 艦隊タブの「受注中の任務の編成条件」。第 [fleetNumber] 艦隊で条件を満たすかを ✓/✗ で出す。
/// 艦隊タブの中身は最初の build の変数を使い続けるので、ここで最新のデータを読む
class KancolleQuestConditionSection extends ConsumerWidget {
  const KancolleQuestConditionSection({super.key, required this.fleetNumber});

  final int fleetNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(kancolleDataProvider);
    if (fleetNumber < 1 || fleetNumber > data.squads.length) return const SizedBox.shrink();
    final items = questConditionItems(
      fleet: QuestFleet.fromShips(fleetNumber, data.squads[fleetNumber - 1].ships, data.dataInfo.shipInfo),
      tracker: data.questProgress,
      activeQuests: [
        for (final quest in data.questAssistant?.ready ?? const [])
          if (quest.state == 2) (id: quest.id, title: quest.title),
      ],
    );
    return QuestConditionListSection(items: items);
  }
}

/// 判定結果の一覧 (×の任務は条件を開いておく。タップで開閉)
class QuestConditionListSection extends StatefulWidget {
  const QuestConditionListSection({super.key, required this.items});

  final List<QuestConditionItem> items;

  @override
  State<QuestConditionListSection> createState() => _QuestConditionListSectionState();
}

class _QuestConditionListSectionState extends State<QuestConditionListSection> {
  /// 開閉を切り替えた任務 (×の任務は最初から開いている)
  final Set<int> _toggled = {};

  bool _isExpanded(QuestConditionItem item) => item.isMet == _toggled.contains(item.questId);

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final red = CupertinoColors.systemRed.resolveFrom(context);
    final secondaryStyle = TextStyle(
      fontSize: 12,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    );

    return CupertinoListSection.insetGrouped(
      margin: tabBottomListMargin,
      header: Text(repairText('受注中の任務の編成条件', 'Fleet conditions of active quests')),
      footer: Text(
        repairText('この艦隊で条件を満たすかの判定です (ElectronicObserver の条件を移植)。行をタップすると条件の一覧を開閉します。',
            'Whether this fleet meets each condition (ported from ElectronicObserver). Tap a row to show the details.'),
        style: secondaryStyle,
      ),
      children: [
        for (final item in widget.items)
          CupertinoListTile(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 12, 6),
            leading: Icon(
              item.isMet ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.xmark_circle_fill,
              color: item.isMet ? green : red,
              size: 22,
            ),
            leadingToTitle: 8,
            title: Text(item.title, maxLines: 2, style: const TextStyle(fontSize: 14)),
            additionalInfo: item.target.isEmpty
                ? null
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(item.target, textAlign: TextAlign.end, maxLines: 2, style: secondaryStyle),
                  ),
            subtitle: _isExpanded(item)
                ? Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (requirement, met) in item.requirements)
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: met ? '✓ ' : '✗ ',
                                style: TextStyle(color: met ? green : red, fontWeight: FontWeight.w700),
                              ),
                              TextSpan(text: requirement.label),
                            ]),
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.label.resolveFrom(context),
                            ),
                          ),
                      ],
                    ),
                  )
                : null,
            onTap: () => setState(() {
              if (!_toggled.remove(item.questId)) _toggled.add(item.questId);
            }),
          ),
      ],
    );
  }
}
