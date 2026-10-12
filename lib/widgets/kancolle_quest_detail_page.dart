import 'package:conning_tower/helper.dart';
import 'package:conning_tower/models/feature/kancolle/quest_assistant.dart';
import 'package:conning_tower/models/feature/kancolle/quest_fleet_condition.dart';
import 'package:conning_tower/models/feature/kancolle/quest_progress.dart';
import 'package:conning_tower/models/feature/kancolle/quest_tree.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/providers/quest_tree_provider.dart';
import 'package:conning_tower/widgets/components/edge_insets_constants.dart';
import 'package:conning_tower/widgets/kancolle_quest_tree_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

/// 任務の詳細を開く。いまの任務一覧にある任務は任務の詳細、それ以外は解放までの流れ
void openQuestDetail(BuildContext context, WidgetRef ref, int questId) {
  final ready = ref.read(kancolleDataProvider).questAssistant?.ready ?? const <Quest>[];
  final inList = ready.any((q) => q.id == questId);
  navigatorToCupertino(context, inList ? QuestDetailPage(questId: questId) : QuestTreeDetailPage(questId: questId));
}

/// 詳細ページの角丸の枠
class QuestDetailSection extends StatelessWidget {
  const QuestDetailSection({super.key, required this.title, required this.children, this.footer});

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final secondaryStyle = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));
    return Container(
      margin: tabBottomListMargin,
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          ...children,
          if (footer != null)
            Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 10), child: Text(footer!, style: secondaryStyle)),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// 報酬 (資源4種と、装備・アイテム)
class QuestRewardList extends StatelessWidget {
  const QuestRewardList({super.key, this.materials, this.rewards = ''});

  /// 燃料・弾薬・鋼材・ボーキサイト
  final List<int>? materials;

  /// kcanotify の rewards
  final String rewards;

  @override
  Widget build(BuildContext context) {
    final secondaryStyle = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));
    final parsed = parseQuestRewards(rewards);
    final names = [
      repairText('燃料', 'Fuel'),
      repairText('弾薬', 'Ammo'),
      repairText('鋼材', 'Steel'),
      repairText('ボーキ', 'Bauxite'),
    ];
    final materials = this.materials;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (materials != null && materials.length >= 4)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(names[i], style: secondaryStyle),
                        Text(
                          '${materials[i]}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: materials[i] == 0
                                ? CupertinoColors.tertiaryLabel.resolveFrom(context)
                                : CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        for (final item in parsed.fixed)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
            child: Text('・$item', style: const TextStyle(fontSize: 13)),
          ),
        for (var i = 0; i < parsed.choices.length; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parsed.choices.length > 1
                      ? repairText('選択報酬${i + 1} (どれか1つ)', 'Choice ${i + 1} (pick one)')
                      : repairText('選択報酬 (どれか1つ)', 'Choice (pick one)'),
                  style: secondaryStyle,
                ),
                for (final item in parsed.choices[i])
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 1),
                    child: Text('・$item', style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 編成条件を第1〜第4艦隊で判定した表
class QuestFleetCheckTable extends StatelessWidget {
  const QuestFleetCheckTable({super.key, required this.condition, required this.fleets});

  final QuestFleetCondition condition;
  final List<QuestFleet> fleets;

  @override
  Widget build(BuildContext context) {
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final red = CupertinoColors.systemRed.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final secondaryStyle = TextStyle(fontSize: 12, color: secondary);
    const cellWidth = 34.0;

    Widget cell(QuestFleet fleet, bool met, {bool bold = false}) => SizedBox(
          width: cellWidth,
          child: Text(
            fleet.ships.isEmpty ? '-' : (met ? '✓' : '✗'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: FontWeight.w700,
              color: fleet.ships.isEmpty ? secondary : (met ? green : red),
            ),
          ),
        );

    Widget row(Widget label, List<Widget> cells) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 3, 10, 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: label), ...cells],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          Text(repairText('条件', 'Condition'), style: secondaryStyle),
          [
            for (final fleet in fleets)
              SizedBox(
                width: cellWidth,
                child: Text(repairText('第${fleet.fleetNumber}', '#${fleet.fleetNumber}'),
                    textAlign: TextAlign.center, style: secondaryStyle),
              ),
          ],
        ),
        row(
          Text(repairText('すべて満たす', 'All met'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          [for (final fleet in fleets) cell(fleet, condition.isMet(fleet), bold: true)],
        ),
        Container(
          height: 0.5,
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          color: CupertinoColors.separator.resolveFrom(context),
        ),
        for (final requirement in condition.requirements)
          row(
            Text(requirement.label, style: const TextStyle(fontSize: 13)),
            [for (final fleet in fleets) cell(fleet, requirement.isMet(fleet))],
          ),
      ],
    );
  }
}

/// 任務タブで任務をタップしたときの詳細 (必要条件・達成度・編成チェック・報酬・前後の任務)。
/// 任務タブの中身は最初の build の変数を使い続けるので、ここで最新のデータを読む
class QuestDetailPage extends ConsumerWidget {
  const QuestDetailPage({super.key, required this.questId});

  final int questId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(kancolleDataProvider);
    final treeAsync = ref.watch(questTreeProvider);
    final tree = treeAsync.valueOrNull;
    final treeProgress = ref.watch(questTreeProgressProvider);
    final secondaryStyle = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));
    final green = CupertinoColors.systemGreen.resolveFrom(context);

    final questAssistant = data.questAssistant;
    final readyQuest = questAssistant?.ready.where((q) => q.id == questId).firstOrNull;
    final doneQuest = readyQuest == null ? questAssistant?.done.where((q) => q.id == questId).firstOrNull : null;
    final quest = readyQuest ?? doneQuest;
    final info = tree?.quests[questId];
    final tracker = data.questProgress;
    final definition = kQuestDefinitions[questId];
    final entry = tracker.progressOf(questId);

    // 達成 (報酬待ち) またはクリア済み
    final finished = doneQuest != null || quest?.state == 3;
    final title = (quest?.title?.isNotEmpty ?? false) ? quest!.title! : (info?.name ?? repairText('任務 $questId', 'Quest $questId'));
    final detail = (quest?.detail?.isNotEmpty ?? false) ? quest!.detail! : (info?.detail ?? '');
    final String statusText;
    if (doneQuest != null) {
      statusText = repairText('クリア済み', 'Cleared');
    } else {
      statusText = switch (quest?.state) {
        1 => repairText('未受注', 'Not accepted'),
        2 => repairText('遂行中', 'In progress'),
        3 => repairText('達成 (報酬を受け取れます)', 'Completed (collect the reward)'),
        _ => repairText('任務一覧にありません', 'Not in the quest list'),
      };
    }

    // ---- 必要条件と達成度 ----
    final validUntil = definition?.validUntil;
    final expired = validUntil != null && !DateTime.now().isBefore(validUntil);
    final counters = definition == null || expired ? null : (entry?.counters ?? definition.counters());
    final conditionChildren = <Widget>[];
    if (counters != null) {
      for (final c in counters) {
        final progress = finished ? c.max : c.progress;
        final done = progress >= c.max;
        conditionChildren.add(Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 18,
                    child: Text(done ? '✓' : '・',
                        style: TextStyle(color: done ? green : null, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  Expanded(
                    child: Text(
                      questCounterConditionText(c, missionName: (id) => data.dataInfo.missionInfo?[id]?.apiName),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$progress/${c.max}',
                      style: TextStyle(fontSize: 13, color: done ? green : null, fontWeight: FontWeight.w600)),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 18, top: 3),
                child: LinearPercentIndicator(
                  padding: EdgeInsets.zero,
                  lineHeight: 3.0,
                  percent: c.max == 0 ? 0 : (progress / c.max).clamp(0.0, 1.0),
                  barRadius: const Radius.circular(2.0),
                  backgroundColor: CupertinoColors.systemGrey5.resolveFrom(context),
                  progressColor: done ? CupertinoColors.activeGreen : CupertinoColors.activeBlue,
                ),
              ),
            ],
          ),
        ));
      }
      if (counters.length > 1 && !finished && entry != null) {
        conditionChildren.add(Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
          child: Text(
            '${repairText('全体', 'Total')} ${(entry.percentage * 100).floor()}%',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ));
      }
    } else {
      final String progressText;
      if (doneQuest != null) {
        progressText = repairText('クリア済み', 'Cleared');
      } else if (quest?.state == 3) {
        progressText = repairText('達成', 'Completed');
      } else if (quest?.state == 2) {
        progressText = switch (quest?.progressFlag) {
          1 => repairText('50%以上', '50% or more'),
          2 => repairText('80%以上', '80% or more'),
          _ => repairText('50%未満', 'Under 50%'),
        };
      } else {
        progressText = '-';
      }
      conditionChildren.add(Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
        child: Text('${repairText('達成度', 'Progress')}: $progressText', style: const TextStyle(fontSize: 13)),
      ));
    }
    if (info != null && info.memo.isNotEmpty) {
      conditionChildren.add(Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
        child: Text(info.memo, style: secondaryStyle),
      ));
    }
    final String conditionFooter;
    if (expired) {
      conditionFooter = repairText('期間を過ぎた任務なので回数は数えていません。達成度はゲームの表示 (50%/80%) だけです。',
          'This quest is past its period; only the game\'s 50%/80% is shown.');
    } else if (counters == null) {
      conditionFooter = repairText('この任務は回数を数えていません。達成度はゲームの表示 (50%/80%) です。条件は説明文と補足を見てください。',
          'This quest is not counted; progress is the game\'s 50%/80%.');
    } else if (definition?.condition != null) {
      conditionFooter = repairText('編成条件を満たした艦隊での戦闘・演習だけ数えます (下の「編成チェック」)。',
          'Only counted with a fleet that meets the composition (see below).');
    } else {
      conditionFooter = repairText('回数はこの端末で数えたものです (ElectronicObserver の条件を移植)。',
          'Counted on this device (ported from ElectronicObserver).');
    }

    // ---- 編成チェック ----
    final condition = definition?.condition;
    final fleets = <QuestFleet>[
      for (var i = 0; i < data.squads.length && i < 4; i++)
        if (!(condition?.secretary ?? false) || i == 0)
          QuestFleet.fromShips(i + 1, data.squads[i].ships, data.dataInfo.shipInfo),
    ];
    final showFleetCheck = condition != null && !finished && !expired && fleets.isNotEmpty;

    // ---- 報酬 ----
    final materials = tracker.rewardMaterials[questId] ?? info?.rewardResources;
    final rewards = info?.rewards ?? '';
    final String rewardFooter;
    if (tree == null && treeAsync.isLoading) {
      rewardFooter = repairText('装備・アイテムの報酬を読み込み中です。', 'Loading item rewards…');
    } else if (rewards.isEmpty) {
      rewardFooter = repairText('装備・アイテムの報酬のデータはありません (新しい任務はデータが追いついていないことがあります)。',
          'No item reward data for this quest.');
    } else {
      rewardFooter = repairText('資源: ${tracker.rewardMaterials.containsKey(questId) ? 'ゲームのデータ' : 'kcanotify-gamedata'}、装備・アイテム: kcanotify-gamedata',
          'Resources: ${tracker.rewardMaterials.containsKey(questId) ? 'game data' : 'kcanotify-gamedata'}, items: kcanotify-gamedata');
    }

    // ---- 前後の任務 ----
    final linkSections = <Widget>[];
    if (tree != null && treeProgress != null) {
      final nodes = prerequisiteTree(tree, treeProgress, questId);
      final successors = tree.successors[questId] ?? const <int>[];
      final String preFooter;
      if (info == null) {
        preFooter = repairText('この任務は任務データにありません。', 'This quest is not in the quest data.');
      } else if (!info.hasPrerequisiteData) {
        preFooter = repairText('この任務の前提任務のデータはまだありません。', 'No prerequisite data for this quest.');
      } else if (nodes.isEmpty && info.unknownPrerequisites.isEmpty) {
        preFooter = repairText('前提任務はありません。', 'No prerequisite quests.');
      } else {
        preFooter = repairText('タップすると、その任務の詳細を開きます。', 'Tap a quest to open it.');
      }
      linkSections.add(QuestDetailSection(
        title: repairText('前提任務', 'Prerequisites'),
        footer: preFooter,
        children: [
          for (final node in nodes) QuestTreeLine(questId: node.id, depth: node.depth, repeated: node.repeated),
          for (final code in info?.unknownPrerequisites ?? const <String>[])
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 5, 12, 5),
              child: Text('? $code ${repairText('(データにない任務)', '(unknown quest)')}', style: secondaryStyle),
            ),
        ],
      ));
      if (successors.isNotEmpty) {
        linkSections.add(QuestDetailSection(
          title: repairText('この任務をクリアすると出現する任務', 'Quests unlocked by this quest'),
          children: [for (final id in successors) QuestTreeLine(questId: id)],
        ));
      }
    } else if (treeAsync.isLoading) {
      linkSections.add(const Padding(padding: EdgeInsets.all(16), child: CupertinoActivityIndicator()));
    } else {
      linkSections.add(QuestDetailSection(
        title: repairText('前後の任務', 'Related quests'),
        footer: repairText('任務データを取得できませんでした。「未出現」タブで再読み込みできます。',
            'Could not download the quest data. Retry from the "Locked" tab.'),
        children: const [],
      ));
    }

    final header = [
      if (info != null && info.code.isNotEmpty) info.code,
      if (info?.category != null) info!.category!.label,
      if (info != null) info.period.label,
    ].join('・');

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        middle: Text(info?.code.isNotEmpty ?? false ? info!.code : repairText('任務の詳細', 'Quest')),
      ),
      child: SafeArea(
        bottom: false,
        child: CupertinoScrollbar(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              QuestDetailSection(title: title, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: statusText,
                        style: TextStyle(color: finished ? green : null, fontWeight: FontWeight.w600),
                      ),
                      if (header.isNotEmpty) TextSpan(text: '　$header', style: secondaryStyle),
                    ]),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
                    child: Text(detail.replaceAll('<br>', ''), style: const TextStyle(fontSize: 13)),
                  ),
              ]),
              QuestDetailSection(
                title: repairText('必要条件と達成度', 'Requirements and progress'),
                footer: conditionFooter,
                children: conditionChildren,
              ),
              if (showFleetCheck)
                QuestDetailSection(
                  title: repairText('編成チェック', 'Fleet check'),
                  footer: condition.secretary
                      ? repairText('第1艦隊の旗艦 (秘書艦) の条件です。', 'Condition on the secretary (fleet 1 flagship).')
                      : repairText('いまの編成で条件を満たすかの判定です。✓ 満たす　✗ 満たさない　- 艦がいない',
                          'Whether each fleet meets the condition now. ✓ met  ✗ not met  - empty'),
                  children: [QuestFleetCheckTable(condition: condition, fleets: fleets)],
                ),
              QuestDetailSection(
                title: repairText('報酬', 'Rewards'),
                footer: rewardFooter,
                children: [QuestRewardList(materials: materials, rewards: rewards)],
              ),
              ...linkSections,
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  repairText('✓ クリア済み (推定)　● いま受けられる　○ 出現したことがある　✗ 未出現',
                      '✓ cleared (estimated)  ● available  ○ appeared before  ✗ not appeared'),
                  style: secondaryStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
