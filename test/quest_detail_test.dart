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
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
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

// 257 「水雷戦隊」南西へ！ の前提が 202、257 をクリアすると 258 が出る
final _kcQuestsJson = jsonEncode({
  '202': {'code': 'B1', 'name': '出击1', 'pre': []},
  '257': {'code': 'Bm2', 'name': '水雷战队', 'pre': ['B1']},
  '258': {'code': 'B30', 'name': '后续', 'pre': ['Bm2']},
});
final _kcanotifyJson = jsonEncode({
  '202': {'code': 'B1', 'name': 'はじめての「出撃」！', 'desc': '', 'rewards': '開発資材', 'resources': [[20, 20, 0.0, 0], [0, 0, 1, 0]]},
  '257': {
    'code': 'Bm2',
    'name': '「水雷戦隊」南西へ！',
    'desc': '軽巡を旗艦に、南西諸島防衛線に出撃せよ！',
    'memo': '※出撃：1-4のボスマスでS勝利',
    'rewards': '高速修復材×2, 二回選択報酬：[新型砲熕兵装資材、開発資材×4][改修資材×2、補強増設]',
    'resources': [[0, 300, 0.0, 0], [2, 0, 0, 0]],
  },
  '258': {'code': 'B30', 'name': '次の任務', 'desc': '', 'rewards': '勲章'},
});

class _FakeQuestTreeNotifier extends QuestTreeNotifier {
  @override
  Future<QuestTreeData> build() async =>
      QuestTreeData.parse(_kcQuestsJson, _kcanotifyJson, updatedAt: DateTime(2026, 10, 12));
}

void main() {
  setUp(() => Intl.defaultLocale = 'ja');

  group('rewards', () {
    test('fixed rewards and choices are separated', () {
      final one = parseQuestRewards('三式弾改, 選択報酬：[41cm連装砲×2、新型砲熕兵装資材、開発資材×8]');
      expect(one.fixed, ['三式弾改']);
      expect(one.choices, [
        ['41cm連装砲×2', '新型砲熕兵装資材', '開発資材×8']
      ]);

      final two = parseQuestRewards('二回選択報酬：[F6F-3、F4U-1D][TBF、新型航空兵装資材]');
      expect(two.fixed, isEmpty);
      expect(two.choices, [
        ['F6F-3', 'F4U-1D'],
        ['TBF', '新型航空兵装資材'],
      ]);

      final plain = parseQuestRewards('プレゼント箱, 戦果+80');
      expect(plain.fixed, ['プレゼント箱', '戦果+80']);
      expect(plain.choices, isEmpty);
      expect(parseQuestRewards('').isEmpty, isTrue);
    });

    test('quest data keeps the rewards and the four resources', () {
      final data = QuestTreeData.parse(_kcQuestsJson, _kcanotifyJson);
      expect(data.quests[257]!.rewardResources, [0, 300, 0, 0]);
      expect(data.quests[257]!.rewards, startsWith('高速修復材×2'));
      expect(data.quests[258]!.rewardResources, isNull);
    });

    test('the quest list keeps the resource rewards from the game', () {
      final tracker = QuestProgressTracker()
        ..onQuestList([
          const QuestListItem(id: 213, state: 2, type: 2, materials: [500, 0, 400, 0]),
          const QuestListItem(id: 201, state: 1, type: 1),
        ]);
      expect(tracker.rewardMaterials[213], [500, 0, 400, 0]);
      expect(tracker.rewardMaterials.containsKey(201), isFalse);
    });
  });

  test('condition text for each counter', () {
    String text(int id, [int index = 0]) => questCounterConditionText(kQuestDefinitions[id]!.counters()[index]);
    expect(text(213), '敵輸送艦を撃沈 20隻');
    expect(text(211), '敵空母を撃沈 3隻');
    expect(text(226), '2-1・2-2・2-3・2-4・2-5 ボス B勝利以上 5回');
    expect(text(257), '1-4 ボス S勝利 1回');
    expect(text(280, 1), '1-3 ボス S勝利 1回');
    expect(text(201), '戦闘 B勝利以上 1回');
    expect(text(214), '出撃 36回');
    expect(text(214, 1), 'S勝利 6回');
    expect(text(303), '演習 3回');
    expect(text(304), '演習 B勝利以上 5回');
    expect(text(402), '遠征 成功 3回');
    expect(text(426), '警備任務 成功 1回');
    expect(questCounterConditionText(kQuestDefinitions[410]!.counters().first, missionName: (id) => '遠征$id号'),
        '遠征37号・遠征38号 成功 1回');
    expect(text(613), '装備を廃棄 24回');
    expect(text(675), '艦上戦闘機を廃棄 6個');
    expect(text(503), '入渠 5回');
    expect(text(605), '装備開発 1回');
  });

  testWidgets('tapping a quest shows requirements, fleet check, rewards and related quests', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    await S.load(const Locale('ja'));
    tester.view.physicalSize = const Size(393, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Ship ship(int uid, int type) => Ship(uid: uid, shipId: uid, name: 's$uid', level: 50, nowHP: 30, maxHP: 30,
        shipType: type, condition: 49, speed: 10, attack: [1, 1], antiAircraft: [1, 1], antiSubmarine: [1, 1],
        scout: [1, 1], exp: [0, 1], equipment: const []);
    final squads = [
      Squad(id: 1, name: '第1艦隊', ships: [ship(1, 3), ship(2, 2), ship(3, 2)]), // 軽巡旗艦の水雷戦隊
      Squad(id: 2, name: '第2艦隊', ships: [ship(4, 5), ship(5, 2)]), // 重巡旗艦
      Squad(id: 3, name: '第3艦隊', ships: []),
    ];
    final tracker = QuestProgressTracker()
      ..onQuestList([const QuestListItem(id: 257, state: 2, type: 3, materials: [0, 300, 0, 0])]);
    KancolleData make(Ref ref, int state) => KancolleData(
          queue: OperationQueue(map: {}),
          squads: squads,
          seaForceBase: SeaForceBase(
            resource: const SeaForceBaseResource(fuel: 0, ammo: 0, steel: 0, bauxite: 0, instantCreateShip: 0,
                instantRepairs: 0, developmentMaterials: 0, improvementMaterials: 0),
            admiral: const Admiral(name: '', level: 1, rank: 10, maxShip: 0, maxItem: 0),
          ),
          fleet: Fleet(ships: [], equipment: {}),
          ref: ref,
          dataInfo: DataInfo(),
          battleInfo: BattleInfo(),
          questAssistant: QuestAssistant(ready: [
            Quest(id: 257, state: state, type: 3, title: '「水雷戦隊」南西へ！', detail: '軽巡を旗艦に出撃せよ！'),
          ], done: []),
          questProgress: tracker,
        );
    late WidgetRef widgetRef;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        questTreeProvider.overrideWith(_FakeQuestTreeNotifier.new),
        kancolleDataProvider.overrideWith((ref) => make(ref, 2)),
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

    await tester.tap(find.text('「水雷戦隊」南西へ！'));
    await tester.pumpAndSettle();

    // 見出し・必要条件と達成度
    expect(find.text('Bm2'), findsOneWidget);
    expect(find.textContaining('遂行中', findRichText: true), findsOneWidget);
    expect(find.text('必要条件と達成度'), findsOneWidget);
    expect(find.text('1-4 ボス S勝利 1回'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
    expect(find.text('※出撃：1-4のボスマスでS勝利'), findsOneWidget);

    // 編成チェック: 第1艦隊は満たす、第2艦隊は満たさない、第3艦隊は空
    expect(find.text('編成チェック'), findsOneWidget);
    expect(find.text('第1'), findsOneWidget);
    expect(find.text('第3'), findsOneWidget);
    expect(find.text('旗艦: 軽巡'), findsOneWidget);
    expect(find.text('-'), findsWidgets);

    // 報酬
    expect(find.text('300'), findsOneWidget);
    expect(find.text('・高速修復材×2'), findsOneWidget);
    expect(find.text('選択報酬1 (どれか1つ)'), findsOneWidget);
    expect(find.text('・補強増設'), findsOneWidget);
    expect(find.textContaining('資源: ゲームのデータ'), findsOneWidget);

    // 前後の任務
    expect(find.text('前提任務'), findsOneWidget);
    expect(find.textContaining('はじめての「出撃」！', findRichText: true), findsOneWidget);
    expect(find.text('この任務をクリアすると出現する任務'), findsOneWidget);
    expect(find.textContaining('次の任務', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 戦闘で数えたら、開いたままの詳細も変わる
    tracker.progressOf(257)!.counters.first.progress = 1;
    final notifier = widgetRef.read(kancolleDataProvider.notifier);
    notifier.state = make(notifier.state.ref, 3);
    await tester.pumpAndSettle();
    expect(find.text('1/1'), findsOneWidget);
    expect(find.textContaining('達成 (報酬を受け取れます)', findRichText: true), findsOneWidget);
    expect(find.text('編成チェック'), findsNothing);

    // 前後の任務をタップすると、その任務の詳細 (任務一覧にないので解放までの流れ)
    await tester.tap(find.textContaining('次の任務', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('解放までに必要な任務'), findsOneWidget);
    expect(find.text('・勲章'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quests without counters show the game progress and fit a small panel', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    await S.load(const Locale('ja'));
    tester.view.physicalSize = const Size(300, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        questTreeProvider.overrideWith(_FakeQuestTreeNotifier.new),
        kancolleDataProvider.overrideWith((ref) => KancolleData(
              queue: OperationQueue(map: {}),
              squads: [],
              seaForceBase: SeaForceBase(
                resource: const SeaForceBaseResource(fuel: 0, ammo: 0, steel: 0, bauxite: 0, instantCreateShip: 0,
                    instantRepairs: 0, developmentMaterials: 0, improvementMaterials: 0),
                admiral: const Admiral(name: '', level: 1, rank: 10, maxShip: 0, maxItem: 0),
              ),
              fleet: Fleet(ships: [], equipment: {}),
              ref: ref,
              dataInfo: DataInfo(),
              battleInfo: BattleInfo(),
              questAssistant: QuestAssistant(ready: [
                Quest(id: 9999, state: 2, type: 4, title: '数えていない任務', progressFlag: 1),
              ], done: []),
              questProgress: QuestProgressTracker(),
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
    await tester.tap(find.text('数えていない任務'));
    await tester.pumpAndSettle();
    expect(find.text('達成度: 50%以上'), findsOneWidget);
    expect(find.textContaining('回数を数えていません'), findsOneWidget);
    await tester.dragUntilVisible(find.textContaining('報酬のデータはありません'), find.byType(ListView).last, const Offset(0, -200));
    expect(find.textContaining('この任務は任務データにありません'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
