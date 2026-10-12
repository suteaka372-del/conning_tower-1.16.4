import 'package:conning_tower/helper.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/quest_tree.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/providers/quest_tree_provider.dart';
import 'package:conning_tower/widgets/kancolle_quest_detail_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kCategoryKey = 'KC_QUEST_TREE_CATEGORY';
const _kPeriodKey = 'KC_QUEST_TREE_PERIOD';

String _dateText(DateTime? time) {
  if (time == null) return '-';
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}';
}

/// 状態の印と色
(String, Color) questTreeStatusMark(QuestTreeStatus status, BuildContext context, {bool available = false}) =>
    switch (status) {
      QuestTreeStatus.cleared => ('✓', CupertinoColors.systemGreen.resolveFrom(context)),
      QuestTreeStatus.appeared =>
        (available ? '●' : '○', CupertinoColors.systemOrange.resolveFrom(context)),
      QuestTreeStatus.notAppeared => ('✗', CupertinoColors.systemRed.resolveFrom(context)),
    };

String questTreeStatusText(QuestTreeProgress progress, int id) {
  final status = progress.statusOf(id);
  return switch (status) {
    QuestTreeStatus.cleared => progress.estimated.contains(id)
        ? repairText('クリア済み (一覧になく推定)', 'Cleared (estimated)')
        : repairText('クリア済み (推定)', 'Cleared (estimated)'),
    QuestTreeStatus.appeared => progress.isAvailable(id)
        ? repairText('いま受けられる', 'Available now')
        : repairText('出現したことがある', 'Appeared before'),
    QuestTreeStatus.notAppeared => repairText('未出現', 'Not appeared'),
  };
}

/// 手動の「クリア済み / 未クリア」を切り替えるメニュー
Future<void> showQuestTreeManualMenu(BuildContext context, WidgetRef ref, QuestTreeEntry quest) async {
  final progress = ref.read(questTreeProgressProvider);
  if (progress == null) return;
  final cleared = progress.statusOf(quest.id) == QuestTreeStatus.cleared;
  final manual = progress.manual[quest.id];
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: Text('${quest.code} ${quest.name}'),
      message: Text(repairText('自動の判定が違うときに直せます', 'Correct the automatic estimate')),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () {
            ref.read(questTreeManualProvider.notifier).set(quest.id, !cleared);
            Navigator.of(context).pop();
          },
          child: Text(cleared
              ? repairText('未クリアに戻す', 'Mark as not cleared')
              : repairText('クリア済みにする', 'Mark as cleared')),
        ),
        if (manual != null)
          CupertinoActionSheetAction(
            onPressed: () {
              ref.read(questTreeManualProvider.notifier).set(quest.id, null);
              Navigator.of(context).pop();
            },
            child: Text(repairText('自動の判定に戻す', 'Use the automatic estimate')),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.of(context).pop(),
        child: Text(repairText('キャンセル', 'Cancel')),
      ),
    ),
  );
}

/// 任務タブの「未出現」
class QuestTreeNotAppearedView extends ConsumerStatefulWidget {
  const QuestTreeNotAppearedView({super.key});

  @override
  ConsumerState<QuestTreeNotAppearedView> createState() => _QuestTreeNotAppearedViewState();
}

class _QuestTreeNotAppearedViewState extends ConsumerState<QuestTreeNotAppearedView> {
  QuestTreeCategory? _category;
  QuestTreePeriod? _period;
  bool _refreshing = false;
  String? _refreshError;

  @override
  void initState() {
    super.initState();
    try {
      final category = localStorage.getString(_kCategoryKey);
      final period = localStorage.getString(_kPeriodKey);
      _category = QuestTreeCategory.values.where((c) => c.name == category).firstOrNull;
      _period = QuestTreePeriod.values.where((p) => p.name == period).firstOrNull;
    } catch (_) {}
  }

  void _save() {
    try {
      localStorage.setString(_kCategoryKey, _category?.name ?? '');
      localStorage.setString(_kPeriodKey, _period?.name ?? '');
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      await ref.read(questTreeProvider.notifier).refresh();
    } catch (_) {
      _refreshError = repairText('更新できませんでした', 'Could not update');
    }
    if (mounted) setState(() => _refreshing = false);
  }

  Widget _chip<T>(String label, T value, T selected, ValueChanged<T> onTap) {
    final active = value == selected;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? CupertinoColors.activeBlue.resolveFrom(context)
                : CupertinoColors.tertiarySystemFill.resolveFrom(context),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: active ? CupertinoColors.white : CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterRow(List<Widget> chips) => SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          children: chips,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(questTreeProvider);
    final progress = ref.watch(questTreeProgressProvider);
    final seen = ref.watch(questTreeSeenProvider);
    final secondaryStyle = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));
    final allText = repairText('全て', 'All');

    final filters = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _filterRow([
          _chip<QuestTreeCategory?>(allText, null, _category, (v) {
            setState(() => _category = v);
            _save();
          }),
          for (final c in QuestTreeCategory.values)
            _chip<QuestTreeCategory?>(c.label, c, _category, (v) {
              setState(() => _category = v);
              _save();
            }),
        ]),
        _filterRow([
          _chip<QuestTreePeriod?>(allText, null, _period, (v) {
            setState(() => _period = v);
            _save();
          }),
          for (final p in QuestTreePeriod.values)
            _chip<QuestTreePeriod?>(p.label, p, _period, (v) {
              setState(() => _period = v);
              _save();
            }),
        ]),
      ],
    );

    final data = asyncData.valueOrNull;
    if (data == null || progress == null) {
      return Column(
        children: [
          filters,
          Expanded(
            child: Center(
              child: asyncData.isLoading
                  ? const CupertinoActivityIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            repairText('任務データを取得できませんでした。\nネットにつながっているか確認してください。',
                                'Could not download the quest data.'),
                            textAlign: TextAlign.center,
                            style: secondaryStyle,
                          ),
                          CupertinoButton(
                            onPressed: () => ref.invalidate(questTreeProvider),
                            child: Text(repairText('再読み込み', 'Retry')),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      );
    }

    final quests = notAppearedQuests(data, progress, category: _category, period: _period);
    return Column(
      children: [
        filters,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${repairText('未出現', 'Not appeared')} ${quests.length}${repairText('件', '')}'
                  '  ${repairText('データ', 'Data')} ${_dateText(data.updatedAt)}'
                  '${_refreshError == null ? '' : '  $_refreshError'}',
                  style: secondaryStyle,
                ),
              ),
              _refreshing
                  ? const Padding(padding: EdgeInsets.all(10), child: CupertinoActivityIndicator())
                  : CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minSize: 32,
                      onPressed: _refresh,
                      child: const Icon(CupertinoIcons.refresh, size: 20),
                    ),
            ],
          ),
        ),
        if (seen.available == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              repairText('ゲームの任務画面で「全て」タブを開くと、クリア済みの判定が正確になります。',
                  'Open the "All" tab of the in-game quest screen for a better estimate.'),
              style: secondaryStyle.copyWith(color: CupertinoColors.systemOrange.resolveFrom(context)),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              '${repairText('「全て」タブの確認', 'All tab checked')}: ${_dateText(seen.availableAt)}',
              style: secondaryStyle,
            ),
          ),
        Expanded(
          child: quests.isEmpty
              ? Center(child: Text(repairText('未出現の任務はありません', 'No quests'), style: secondaryStyle))
              : CupertinoScrollbar(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: quests.length + 1,
                    itemBuilder: (context, index) {
                      if (index == quests.length) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Text(
                            repairText(
                                '前提任務: kcwiki (kcwikizh/kcQuests)、任務名: kcanotify-gamedata。\n長押しで「クリア済み / 未クリア」を手動で直せます。',
                                'Prerequisites: kcwiki (kcQuests), names: kcanotify-gamedata.\nLong press to correct the estimate.'),
                            style: secondaryStyle,
                          ),
                        );
                      }
                      return _QuestTreeRow(quest: quests[index], data: data, progress: progress);
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _QuestTreeRow extends ConsumerWidget {
  const _QuestTreeRow({required this.quest, required this.data, required this.progress});

  final QuestTreeEntry quest;
  final QuestTreeData data;
  final QuestTreeProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = progress.remainingPrerequisites(data, quest.id).length;
    final secondaryStyle = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));
    final String note;
    if (!quest.hasPrerequisiteData) {
      note = repairText('前提任務のデータなし', 'No prerequisite data');
    } else if (remaining == 0) {
      note = repairText('前提はクリア済み (出現条件待ち)', 'Prerequisites cleared');
    } else {
      note = repairText('あと$remaining件', '$remaining left');
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => navigatorToCupertino(context, QuestTreeDetailPage(questId: quest.id)),
      onLongPress: () => showQuestTreeManualMenu(context, ref, quest),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 7, 12, 7),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: CupertinoColors.separator.resolveFrom(context), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text(quest.code, style: secondaryStyle, overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(quest.name, style: const TextStyle(fontSize: 14), maxLines: 2),
                  Text(
                    '${quest.category?.label ?? '-'}・${quest.period.label}　$note',
                    style: secondaryStyle,
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_forward, size: 16, color: CupertinoColors.systemGrey),
          ],
        ),
      ),
    );
  }
}

/// 任務の詳細 (解放までの前提任務の流れ)
class QuestTreeDetailPage extends ConsumerWidget {
  const QuestTreeDetailPage({super.key, required this.questId});

  final int questId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(questTreeProvider).valueOrNull;
    final progress = ref.watch(questTreeProgressProvider);
    final quest = data?.quests[questId];
    final secondaryStyle = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));
    if (data == null || progress == null || quest == null) {
      return const CupertinoPageScaffold(navigationBar: CupertinoNavigationBar(), child: SizedBox.shrink());
    }
    final status = progress.statusOf(questId);
    final (mark, markColor) = questTreeStatusMark(status, context, available: progress.isAvailable(questId));
    final tree = prerequisiteTree(data, progress, questId);
    final remaining = progress.remainingPrerequisites(data, questId);
    final successors = data.successors[questId] ?? const <int>[];

    final String treeNote;
    if (!quest.hasPrerequisiteData) {
      treeNote = repairText('この任務の前提任務のデータはまだありません。', 'No prerequisite data for this quest.');
    } else if (tree.isEmpty && quest.unknownPrerequisites.isEmpty) {
      treeNote = repairText('前提任務はありません (任務以外の条件で出現します)。', 'No prerequisite quests.');
    } else if (remaining.isEmpty) {
      treeNote = repairText('前提任務はクリア済みです。出現時期 (イヤリーは決まった月) や、艦の所持など任務以外の条件を確認してください。',
          'All prerequisites are cleared. Check the season or other conditions.');
    } else {
      treeNote = repairText('✗ と ○ ● の任務をクリアすると出現します (あと${remaining.length}件)。● はいま受けられる任務です。',
          'Clear the ✗/○/● quests (${remaining.length} left). ● = available now.');
    }

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        middle: Text(quest.code),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => showQuestTreeManualMenu(context, ref, quest),
          child: const Icon(CupertinoIcons.ellipsis),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: CupertinoScrollbar(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              QuestDetailSection(title: quest.name, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '$mark ', style: TextStyle(color: markColor, fontWeight: FontWeight.w700)),
                      TextSpan(text: questTreeStatusText(progress, questId)),
                      if (progress.manual.containsKey(questId))
                        TextSpan(text: repairText(' (手動)', ' (manual)'), style: secondaryStyle),
                      TextSpan(
                        text: '　${quest.category?.label ?? '-'}・${quest.period.label}',
                        style: secondaryStyle,
                      ),
                    ]),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (quest.detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
                    child: Text(quest.detail.replaceAll('<br>', ''), style: const TextStyle(fontSize: 13)),
                  ),
                if (quest.memo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
                    child: Text(quest.memo, style: secondaryStyle),
                  ),
              ]),
              QuestDetailSection(
                title: repairText('解放までに必要な任務', 'Quests needed to unlock'),
                footer: treeNote,
                children: [
                  for (final node in tree) QuestTreeLine(questId: node.id, depth: node.depth, repeated: node.repeated),
                  for (final code in quest.unknownPrerequisites)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 5, 12, 5),
                      child: Text('? $code ${repairText('(データにない任務)', '(unknown quest)')}', style: secondaryStyle),
                    ),
                ],
              ),
              if (successors.isNotEmpty)
                QuestDetailSection(
                  title: repairText('この任務をクリアすると出現する任務', 'Quests unlocked by this quest'),
                  children: [for (final id in successors) QuestTreeLine(questId: id)],
                ),
              if (quest.rewards.isNotEmpty || quest.rewardResources != null)
                QuestDetailSection(
                  title: repairText('報酬', 'Rewards'),
                  footer: repairText('kcanotify-gamedata のデータです。', 'From kcanotify-gamedata.'),
                  children: [QuestRewardList(materials: quest.rewardResources, rewards: quest.rewards)],
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  repairText(
                      '✓ クリア済み (推定)　● いま受けられる　○ 出現したことがある　✗ 未出現\n右上の「…」から、クリア済みかどうかを手動で直せます。',
                      '✓ cleared (estimated)  ● available  ○ appeared before  ✗ not appeared\nUse "…" to correct the estimate.'),
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

/// 前後の任務の1行 (状態の印・コード・名前)。タップでその任務の詳細を開く
class QuestTreeLine extends ConsumerWidget {
  const QuestTreeLine({super.key, required this.questId, this.depth = 0, this.repeated = false});

  final int questId;
  final int depth;

  /// 上にすでに出ている任務
  final bool repeated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(questTreeProvider).valueOrNull;
    final progress = ref.watch(questTreeProgressProvider);
    if (data == null || progress == null) return const SizedBox.shrink();
    final secondaryStyle = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));
    final q = data.quests[questId];
    final s = progress.statusOf(questId);
    final available = progress.isAvailable(questId);
    final (m, c) = questTreeStatusMark(s, context, available: available);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: q == null ? null : () => openQuestDetail(context, ref, questId),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14.0 + depth * 16, 5, 12, 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 18,
              child: Text(m, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${q?.code ?? questId} ', style: secondaryStyle),
                  TextSpan(text: q?.name ?? repairText('不明な任務', 'Unknown quest')),
                  if (repeated) TextSpan(text: repairText(' (上と同じ)', ' (see above)'), style: secondaryStyle),
                  if (s == QuestTreeStatus.appeared && available)
                    TextSpan(
                      text: repairText(' いま受けられる', ' available'),
                      style: TextStyle(fontSize: 12, color: c),
                    ),
                ]),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
