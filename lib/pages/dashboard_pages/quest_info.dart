import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/models/feature/kancolle/quest_assistant.dart';
import 'package:conning_tower/models/feature/kancolle/quest_progress.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/widgets/components/edge_insets_constants.dart';
import 'package:conning_tower/widgets/scroll_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

const _sectionMargin = EdgeInsetsDirectional.fromSTEB(0.0, 10.0, 10.0, 10.0);

class QuestInfoPage extends ConsumerStatefulWidget {
  const QuestInfoPage({super.key});

  @override
  ConsumerState createState() => _QuestInfoPageState();
}

class _QuestInfoPageState extends ConsumerState<QuestInfoPage>
    with AutomaticKeepAliveClientMixin {
  int _selectedSegment = 0;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final PageController controller =
        PageController(initialPage: _selectedSegment);
    final data = ref.watch(kancolleDataProvider);
    final questAssistant = data.questAssistant;
    // final List<Quest> questList = switch (_selectedSegment) {
    //   0 => questAssistant?.inProgress ?? [],
    //   1 => questAssistant?.todo ?? [],
    //   2 => questAssistant?.done ?? [],
    //   _ => [],
    // };
    final questLists = [
      questAssistant?.inProgress ?? [],
      questAssistant?.todo ?? [],
      questAssistant?.done ?? []
    ];

    return Padding(
      padding: tabContentMargin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10.0),
        child: CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            automaticallyImplyLeading: false,
            transitionBetweenRoutes: false,
            backgroundColor:
                CupertinoColors.systemGroupedBackground.resolveFrom(context),
            border: null,
            middle: CupertinoSlidingSegmentedControl(
              groupValue: _selectedSegment,
              onValueChanged: (int? value) {
                if (value != null) {
                  setState(() {
                    _selectedSegment = value;
                    controller.animateToPage(value,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.ease);
                  });
                }
              },
              children: {
                0: Text(S.current.KCDashboardQuestInProgress),
                1: Text(S.current.KCDashboardQuestToDo),
                2: Text(S.current.KCDashboardQuestDone)
              },
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: PageView(
              controller: controller,
              onPageChanged: (value) {
                setState(() {
                  _selectedSegment = value;
                });
              },
              children: List.generate(3, (index) {
                final questList = questLists[index];
                if (questList.isEmpty) {
                  return Container();
                }
                return ScrollViewWithCupertinoScrollbar(
                  children: [
                    CupertinoListSection.insetGrouped(
                      margin: tabBottomListMargin,
                      children: List.generate(
                        questList.length,
                        (index) => buildQuestTile(
                            context, questList[index], data.questProgress),
                      ),
                    )
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  /// 任務1件分。進捗 (x/y) とバーを表示する
  Widget buildQuestTile(BuildContext context, Quest quest, QuestProgressTracker tracker) {
    final entry = tracker.progressOf(quest.id);
    final isCompleted = quest.state == 3;
    String progressText;
    double? percent;
    if (isCompleted) {
      progressText = questProgressFlagText(quest.progressFlag, quest.state);
      percent = 1.0;
    } else if (entry != null) {
      progressText = entry.definition.weightedEqually
          ? '${(entry.percentage * 100).floor()}%'
          : entry.text;
      percent = entry.percentage;
    } else {
      progressText = questProgressFlagText(quest.progressFlag, quest.state);
      percent = switch (quest.progressFlag) {
        1 => 0.5,
        2 => 0.8,
        _ => null,
      };
    }
    final secondaryStyle = TextStyle(
      fontSize: 12,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    );

    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      title: Text(quest.title ?? ''),
      additionalInfo: progressText.isEmpty
          ? null
          : Text(
              progressText,
              style: isCompleted || (entry != null && entry.percentage >= 1.0)
                  ? const TextStyle(color: CupertinoColors.activeGreen)
                  : null,
            ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (quest.detail != null)
            Text(
              quest.detail!.replaceAll("<br>", ""),
              softWrap: true,
              maxLines: 6,
            ),
          if (percent != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: LinearPercentIndicator(
                padding: EdgeInsets.zero,
                lineHeight: 4.0,
                percent: percent.clamp(0.0, 1.0),
                barRadius: const Radius.circular(2.0),
                backgroundColor: CupertinoColors.systemGrey5.resolveFrom(context),
                progressColor: percent >= 1.0
                    ? CupertinoColors.activeGreen
                    : CupertinoColors.activeBlue,
              ),
            ),
          if (entry != null && entry.isMulti && !isCompleted)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(entry.details.join(' / '), style: secondaryStyle, softWrap: true),
            ),
        ],
      ),
    );
  }
}

// CupertinoListTile(
// title: Text('精强「十七驱」，向北，向南！'),
// trailing: Text('B123'),
// subtitle: Text("包含矶风乙改、浜风乙改、浦风丁改、谷风丁改四艘编成的舰队"),
// ),
// CupertinoListTile(
// title: Text('1-5'),
// trailing: Text('1/1'),
// additionalInfo: Text('A'),
// ),
// CupertinoListTile(
// title: Text('3-2'),
// trailing: Text('0/1'),
// additionalInfo: Text('A'),
// ),
// CupertinoListTile(
// title: Text('7-1'),
// trailing: Text('0/1'),
// additionalInfo: Text('A'),
// ),
// CupertinoListTile(
// title: Text('5-1'),
// trailing: Text('0/1'),
// additionalInfo: Text('A'),
// ),
