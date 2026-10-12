import 'dart:convert';

import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/quest_assistant.dart';
import 'package:conning_tower/models/feature/kancolle/quest_progress.dart';
import 'package:conning_tower/models/feature/kancolle/quest_tree.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/pages/dashboard_pages/quest_info.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/providers/quest_tree_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// kcwiki (quests-scn.json) と kcanotify (quests-jp.json) の形を真似たデータ
//   A1 ─ A2 ─┬ Bd1 (デイリー)
//            ├ B1 ─ B2 (+ 不明な前提 X9)
//            └ B3 ─┐
//      A2 ─ B4 ────┴ B5 (B3 と B4 の両方が前提)
final kcQuestsJson = jsonEncode({
  '101': {'code': 'A1', 'name': '首次编成', 'pre': []},
  '102': {'code': 'A2', 'name': '驱逐队', 'pre': ['A1']},
  '201': {'code': 'Bd1', 'name': '日常', 'pre': ['A2']},
  '202': {'code': 'B1', 'name': '出击1', 'pre': ['A2']},
  '203': {'code': 'B2', 'name': '出击2', 'pre': ['B1', 'X9']},
  '204': {'code': 'B3', 'name': '出击3', 'pre': ['A2']},
  '205': {'code': 'B4', 'name': '出击4', 'pre': ['A2']},
  '206': {'code': 'B5', 'name': '出击5', 'pre': ['B3', 'B4']},
  '207': {'code': 'By1', 'name': '年常', 'pre': ['B1']},
  '208': {'code': '2409B1', 'name': '限定', 'pre': ['A2']},
  '209': {'code': 'B6', 'name': '出击6', 'pre': ['2409B1']},
});
final kcanotifyJson = jsonEncode({
  '101': {'code': 'A1', 'name': 'はじめての「編成」！', 'desc': '2隻以上の艦で編成せよ！', 'memo': ''},
  '102': {'code': 'A2', 'name': '「駆逐隊」を編成せよ！', 'desc': '', 'memo': ''},
  '202': {'code': 'B1', 'name': 'はじめての「出撃」！', 'desc': '', 'memo': ''},
  '207': {'code': 'By1', 'name': '年に一度の任務', 'desc': '', 'memo': '※イヤーリー(2月)'},
  '208': {'code': 'L2409B1', 'name': '【期間限定】秋の任務', 'desc': '', 'memo': ''},
  '301': {'code': 'C1', 'name': 'はじめての「演習」！', 'desc': '', 'memo': ''},
});

QuestTreeData sampleData() => QuestTreeData.parse(kcQuestsJson, kcanotifyJson, updatedAt: DateTime(2026, 10, 12, 9));

void main() {
  setUp(() => Intl.defaultLocale = 'ja');

  test('quest codes give the category and the period', () {
    expect(classifyQuestCode('Bm1'), (QuestTreeCategory.sortie, QuestTreePeriod.monthly));
    expect(classifyQuestCode('By16'), (QuestTreeCategory.sortie, QuestTreePeriod.yearly));
    expect(classifyQuestCode('Bq13'), (QuestTreeCategory.sortie, QuestTreePeriod.quarterly));
    expect(classifyQuestCode('Bw1'), (QuestTreeCategory.sortie, QuestTreePeriod.weekly));
    expect(classifyQuestCode('Fd1'), (QuestTreeCategory.factory, QuestTreePeriod.daily));
    expect(classifyQuestCode('A35'), (QuestTreeCategory.formation, QuestTreePeriod.once));
    expect(classifyQuestCode('Cs8'), (QuestTreeCategory.exercise, QuestTreePeriod.yearly));
    expect(classifyQuestCode('2609 Cw1'), (QuestTreeCategory.exercise, QuestTreePeriod.limited));
    expect(classifyQuestCode('L2409B1'), (QuestTreeCategory.sortie, QuestTreePeriod.limited));
    expect(classifyQuestCode('WA01'), (QuestTreeCategory.formation, QuestTreePeriod.once));
    expect(classifyQuestCode('SF1'), (QuestTreeCategory.factory, QuestTreePeriod.once));
    expect(classifyQuestCode('???'), (null, QuestTreePeriod.once));
  });

  test('parse merges kcwiki prerequisites and Japanese names', () {
    final data = sampleData();
    expect(data.quests.length, 12);
    expect(data.quests[101]!.name, 'はじめての「編成」！');
    expect(data.quests[203]!.name, '出击2'); // 日本語名がなければ kcwiki の名前
    expect(data.quests[203]!.prerequisites, [202]);
    expect(data.quests[203]!.unknownPrerequisites, ['X9']);
    expect(data.quests[209]!.prerequisites, [208]); // 2409B1 = L2409B1
    expect(data.quests[301]!.hasPrerequisiteData, isFalse); // kcanotify にしかない
    expect(data.successors[102], [201, 202, 204, 205, 208]);
    expect(data.ancestorsOf(206), {204, 205, 102, 101});
  });

  group('inference', () {
    final data = sampleData();

    test('ancestors of seen quests are cleared', () {
      final p = QuestTreeProgress.infer(data, seen: {201});
      expect(p.statusOf(102), QuestTreeStatus.cleared);
      expect(p.statusOf(101), QuestTreeStatus.cleared);
      expect(p.statusOf(201), QuestTreeStatus.appeared);
      expect(p.statusOf(202), QuestTreeStatus.notAppeared);
    });

    test('the all tab marks missing one-time quests as cleared', () {
      // いま受けられるのは Bd1 と B3 だけ → B1・B4 はクリア済み、B5 は B3 待ち
      final p = QuestTreeProgress.infer(data, seen: {201}, available: {201, 204});
      expect(p.statusOf(202), QuestTreeStatus.cleared);
      expect(p.estimated, containsAll([202, 205]));
      expect(p.statusOf(204), QuestTreeStatus.appeared);
      expect(p.isAvailable(204), isTrue);
      expect(p.statusOf(206), QuestTreeStatus.notAppeared);
      expect(p.remainingPrerequisites(data, 206), {204});
      // 前提に不明な任務がある B2 や、イヤリー・期間限定は推定しない
      expect(p.statusOf(203), QuestTreeStatus.notAppeared);
      expect(p.statusOf(207), QuestTreeStatus.notAppeared);
      expect(p.statusOf(208), QuestTreeStatus.notAppeared);
    });

    test('manual overrides', () {
      final p = QuestTreeProgress.infer(data,
          seen: {201}, available: {201, 204}, manual: {205: false, 203: true});
      expect(p.statusOf(205), QuestTreeStatus.notAppeared); // 推定を取り消した
      expect(p.statusOf(203), QuestTreeStatus.cleared);
      expect(p.statusOf(202), QuestTreeStatus.cleared); // 203 の前提
    });

    test('prerequisite tree stops at cleared quests and marks repeats', () {
      final p = QuestTreeProgress.infer(data, seen: {101});
      final tree = prerequisiteTree(data, p, 206);
      expect(tree.map((n) => '${'-' * n.depth}${n.id}${n.repeated ? '*' : ''}:${n.status.name}'), [
        '204:notAppeared',
        '-102:notAppeared',
        '--101:appeared',
        '205:notAppeared',
        '-102*:notAppeared',
      ]);
    });

    test('filters', () {
      final p = QuestTreeProgress.infer(data, seen: {201}, available: {201, 204});
      List<int> ids({QuestTreeCategory? category, QuestTreePeriod? period}) =>
          notAppearedQuests(data, p, category: category, period: period).map((q) => q.id).toList();
      expect(ids(), [203, 206, 207, 209, 301]); // 期間限定 (208) は入れない
      expect(ids(period: QuestTreePeriod.limited), [208]);
      expect(ids(period: QuestTreePeriod.yearly), [207]);
      expect(ids(category: QuestTreeCategory.exercise), [301]);
      expect(ids(category: QuestTreeCategory.formation), isEmpty);
    });
  });

  group('all tab snapshot', () {
    test('a full response completes the snapshot', () {
      final s = QuestListSnapshot();
      s.onPage(count: 3, ids: [1, 2, 3], now: DateTime(2026, 10, 12, 10));
      expect(s.completeIds, {1, 2, 3});
      s.onCleared(2);
      expect(s.completeIds, {1, 3});
    });

    test('pages are collected within a session', () {
      final s = QuestListSnapshot();
      s.onPage(count: 4, ids: [1, 2], now: DateTime(2026, 10, 12, 10));
      expect(s.completeIds, isNull);
      s.onPage(count: 4, ids: [3, 4], now: DateTime(2026, 10, 12, 10, 2));
      expect(s.completeIds, {1, 2, 3, 4});
      // 時間が空いたら集め直す (前にそろった一覧は残す)
      s.onPage(count: 4, ids: [5], now: DateTime(2026, 10, 12, 11));
      expect(s.ids, {5});
      expect(s.completeIds, {1, 2, 3, 4});
    });

    test('saved with the tracker', () {
      final tracker = QuestProgressTracker();
      tracker.allTab.onPage(count: 2, ids: [201, 204], now: DateTime(2026, 10, 12, 10));
      final restored = QuestProgressTracker.decode(tracker.encode());
      expect(restored.allTab.completeIds, {201, 204});
      expect(restored.allTab.completedAt, isNotNull);
    });

    test('KancolleData records only the all tab', () {
      final provider = Provider((ref) => KancolleData(
            queue: OperationQueue(map: {}),
            squads: [],
            seaForceBase: SeaForceBase(
              resource: const SeaForceBaseResource(
                  fuel: 0,
                  ammo: 0,
                  steel: 0,
                  bauxite: 0,
                  instantCreateShip: 0,
                  instantRepairs: 0,
                  developmentMaterials: 0,
                  improvementMaterials: 0),
              admiral: const Admiral(name: '', level: 1, rank: 10, maxShip: 0, maxItem: 0),
            ),
            fleet: Fleet(ships: [], equipment: {}),
            ref: ref,
            dataInfo: DataInfo(),
            battleInfo: BattleInfo(),
            questProgress: QuestProgressTracker(),
          ));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final data = container.read(provider);
      Map<String, dynamic> response(List<int> ids) => {
            'api_data': {
              'api_count': ids.length,
              'api_list': [
                for (final id in ids) {'api_no': id, 'api_state': 1, 'api_type': 1, 'api_label_type': 1}
              ],
            }
          };
      data.trackQuestProgress('/api_get_member/questlist', response([201]), {'api_tab_id': '9'});
      expect(data.questProgress.allTab.completeIds, isNull);
      data.trackQuestProgress('/api_get_member/questlist', response([201, 204]), {'api_tab_id': '0'});
      expect(data.questProgress.allTab.completeIds, {201, 204});
      data.trackQuestProgress('/api_req_quest/clearitemget', {'api_data': {}}, {'api_quest_id': '204'});
      expect(data.questProgress.allTab.completeIds, {201});
    });
  });

  testWidgets('quest tab shows locked quests and their prerequisites', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    await S.load(const Locale('ja'));
    tester.view.physicalSize = const Size(393, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tracker = QuestProgressTracker();
    tracker.allTab.onPage(count: 2, ids: [201, 204], now: DateTime.now());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        questTreeProvider.overrideWith(_FakeQuestTreeNotifier.new),
        kancolleDataProvider.overrideWith((ref) => KancolleData(
              queue: OperationQueue(map: {}),
              squads: [],
              seaForceBase: SeaForceBase(
                resource: const SeaForceBaseResource(
                    fuel: 0,
                    ammo: 0,
                    steel: 0,
                    bauxite: 0,
                    instantCreateShip: 0,
                    instantRepairs: 0,
                    developmentMaterials: 0,
                    improvementMaterials: 0),
                admiral: const Admiral(name: 'admiral', level: 1, rank: 10, maxShip: 0, maxItem: 0),
              ),
              fleet: Fleet(ships: [], equipment: {}),
              ref: ref,
              dataInfo: DataInfo(),
              battleInfo: BattleInfo(),
              questAssistant: QuestAssistant(ready: [
                Quest(id: 201, state: 1, type: 1, title: '日常'),
                Quest(id: 204, state: 1, type: 4, title: '出撃3'),
              ], done: []),
              questProgress: tracker,
            )),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        locale: const Locale('ja'),
        home: const CupertinoPageScaffold(child: QuestInfoPage()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('未出現'));
    await tester.pumpAndSettle();
    expect(find.text('出击5'), findsOneWidget);
    expect(find.textContaining('あと1件'), findsWidgets);
    expect(find.text('はじめての「演習」！'), findsOneWidget);
    expect(find.textContaining('「全て」タブの確認'), findsOneWidget);

    // 出撃 × イヤリー で絞る
    await tester.tap(find.text('出撃'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.text('イヤリー'), find.text('ウィークリー'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('イヤリー'));
    await tester.pumpAndSettle();
    expect(find.text('年に一度の任務'), findsOneWidget);
    expect(find.text('出击5'), findsNothing);
    expect(localStorage.getString('KC_QUEST_TREE_PERIOD'), 'yearly');

    // 詳細: 前提任務の流れ
    await tester.tap(find.text('年に一度の任務'));
    await tester.pumpAndSettle();
    expect(find.text('解放までに必要な任務'), findsOneWidget);
    expect(find.textContaining('はじめての「出撃」！', findRichText: true), findsOneWidget);
    expect(find.textContaining('※イヤーリー(2月)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 戻って、期間限定以外の全てに戻し、長押しでクリア済みにする
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('全て').first);
    await tester.pumpAndSettle();
    await tester.drag(find.text('イヤリー'), const Offset(500, 0)); // 周期の列を左端に戻す
    await tester.pumpAndSettle();
    expect(find.text('全て'), findsNWidgets(2));
    await tester.tap(find.text('全て').at(1));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('出击5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('クリア済みにする'));
    await tester.pumpAndSettle();
    expect(find.text('出击5'), findsNothing);
    expect(localStorage.getString('KC_QUEST_TREE_MANUAL_admiral'), '{"206":true}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('quest tab follows new quest lists and fits a small panel', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    await S.load(const Locale('ja'));
    tester.view.physicalSize = const Size(300, 380);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    KancolleData make(Ref ref, List<Quest> quests) => KancolleData(
          queue: OperationQueue(map: {}),
          squads: [],
          seaForceBase: SeaForceBase(
            resource: const SeaForceBaseResource(
                fuel: 0,
                ammo: 0,
                steel: 0,
                bauxite: 0,
                instantCreateShip: 0,
                instantRepairs: 0,
                developmentMaterials: 0,
                improvementMaterials: 0),
            admiral: const Admiral(name: '', level: 1, rank: 10, maxShip: 0, maxItem: 0),
          ),
          fleet: Fleet(ships: [], equipment: {}),
          ref: ref,
          dataInfo: DataInfo(),
          battleInfo: BattleInfo(),
          questAssistant: QuestAssistant(ready: quests, done: []),
          questProgress: QuestProgressTracker(),
        );
    late WidgetRef widgetRef;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        questTreeProvider.overrideWith(_FakeQuestTreeNotifier.new),
        kancolleDataProvider.overrideWith((ref) => make(ref, [Quest(id: 201, state: 2, type: 1, title: '最初の任務')])),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        locale: const Locale('ja'),
        home: Consumer(builder: (context, ref, _) {
          widgetRef = ref;
          return const CupertinoPageScaffold(child: QuestInfoPage());
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('最初の任務'), findsOneWidget);

    final notifier = widgetRef.read(kancolleDataProvider.notifier);
    notifier.state = make(notifier.state.ref, [Quest(id: 202, state: 2, type: 4, title: '新しい任務')]);
    await tester.pumpAndSettle();
    expect(find.text('最初の任務'), findsNothing);
    expect(find.text('新しい任務'), findsOneWidget);

    await tester.tap(find.text('未出現'));
    await tester.pumpAndSettle();
    expect(find.textContaining('「全て」タブを開くと'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeQuestTreeNotifier extends QuestTreeNotifier {
  @override
  Future<QuestTreeData> build() async => sampleData();
}
