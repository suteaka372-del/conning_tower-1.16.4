import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/quest_assistant.dart';
import 'package:conning_tower/models/feature/kancolle/quest_fleet_condition.dart';
import 'package:conning_tower/models/feature/kancolle/quest_progress.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/pages/dashboard_pages/squad_info.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/widgets/kancolle_quest_condition_section.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const dd = 2, cl = 3, ca = 5;

QuestShip qs(int type, {int id = 1, int shipClass = 0, String yomi = ''}) =>
    QuestShip(shipId: id, shipType: type, shipClass: shipClass, yomi: yomi);

QuestListItem accepted(int id, {int type = 3}) => QuestListItem(id: id, state: 2, type: type);

void main() {
  setUp(() => Intl.defaultLocale = 'ja');

  group('target text', () {
    test('battle, practice and factory', () {
      expect(questTargetText(kQuestDefinitions[280]!.counters()), '1-2・1-3・1-4・2-1 ボスS');
      expect(questTargetText(kQuestDefinitions[249]!.counters()), '2-5 ボスS');
      expect(questTargetText(kQuestDefinitions[905]!.counters()), '1-1・1-2・1-3・1-5・1-6終点');
      expect(questTargetText(kQuestDefinitions[318]!.counters()), '演習 B勝利');
      expect(questTargetText(kQuestDefinitions[1138]!.counters()), '工廠 (秘書艦)');
    });
  });

  group('items', () {
    final tracker = QuestProgressTracker()
      ..onQuestList([
        accepted(249),
        accepted(257),
        accepted(201, type: 1), // 編成条件のない任務
        accepted(1138, type: 6), // 工廠 (秘書艦)
        accepted(840, type: 2), // 期限切れ
        accepted(266), // 他の端末で破棄した任務 (保存した状態では遂行中のまま)
      ], now: DateTime(2026, 10, 11));
    tracker.questStates[840] = 2;

    // 任務タブの最新の一覧で遂行中のもの
    final active = [
      (id: 249, title: null),
      (id: 257, title: '「水雷戦隊」南西へ！'),
      (id: 201, title: '敵艦隊を撃破せよ！'),
      (id: 1138, title: null),
      (id: 840, title: null),
    ];

    final torpedoSquadron = QuestFleet(1, [qs(cl), qs(dd), qs(dd), qs(dd)]);

    test('only quests in progress on the quest tab, with conditions', () {
      final items = questConditionItems(
        fleet: torpedoSquadron,
        tracker: tracker,
        activeQuests: active,
        now: DateTime(2026, 10, 11),
      );
      expect(items.map((i) => i.questId), [249, 257, 1138]);
      final fifth = items[0];
      expect(fifth.title, '「第五戦隊」出撃せよ！'); // 定義の任務名
      expect(fifth.isMet, isFalse);
      expect(fifth.requirements.map((r) => '${r.$1.label}:${r.$2}'), ['那智:false', '妙高:false', '羽黒:false']);
      expect(items[1].isMet, isTrue);
      expect(items[1].target, '1-4 ボスS');
    });

    test('factory conditions only for the first fleet', () {
      final second = QuestFleet(2, torpedoSquadron.ships);
      final items =
          questConditionItems(fleet: second, tracker: tracker, activeQuests: active, now: DateTime(2026, 10, 11));
      expect(items.map((i) => i.questId), [249, 257]);
    });

    test('finished conditional counters are hidden', () {
      final t = QuestProgressTracker()..onQuestList([accepted(257)], now: DateTime(2026, 10, 11));
      t.onMapPoint(mapId: 14, eventId: 5, isEndPoint: true, fleet: torpedoSquadron);
      t.onBattleResult(rank: 'S', sunkEnemyShipTypes: [], fleet: torpedoSquadron);
      expect(
          questConditionItems(
              fleet: torpedoSquadron, tracker: t, activeQuests: [(id: 257, title: null)], now: DateTime(2026, 10, 11)),
          isEmpty);
    });

    test('nothing until the quest list has been loaded', () {
      expect(
          questConditionItems(fleet: torpedoSquadron, tracker: tracker, activeQuests: const [], now: DateTime(2026, 10, 11)),
          isEmpty);
    });
  });

  testWidgets('section shows marks and toggles details', (tester) async {
    final tracker = QuestProgressTracker()..onQuestList([accepted(249), accepted(257)], now: DateTime(2026, 10, 11));
    final items = questConditionItems(
      fleet: QuestFleet(1, [qs(cl), qs(dd), qs(dd), qs(dd)]),
      tracker: tracker,
      activeQuests: [(id: 249, title: null), (id: 257, title: null)],
      now: DateTime(2026, 10, 11),
    );
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(child: ListView(children: [QuestConditionListSection(items: items)])),
    ));
    expect(find.text('受注中の任務の編成条件'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.xmark_circle_fill), findsOneWidget); // 249
    expect(find.byIcon(CupertinoIcons.check_mark_circled_solid), findsOneWidget); // 257
    // ×の任務は最初から条件が見える
    expect(find.textContaining('那智', findRichText: true), findsOneWidget);
    expect(find.textContaining('軽巡のみ', findRichText: true), findsNothing);

    await tester.tap(find.text('「第五戦隊」出撃せよ！'));
    await tester.pump();
    expect(find.textContaining('那智', findRichText: true), findsNothing);
    await tester.tap(find.text('「水雷戦隊」南西へ！'));
    await tester.pump();
    expect(find.textContaining('駆逐・軽巡のみ', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fleet tab shows the section for the displayed fleet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    await S.load(const Locale('ja'));
    tester.view.physicalSize = const Size(393, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 保存した状態では 249・280 も遂行中のまま
    final tracker = QuestProgressTracker()
      ..onQuestList([accepted(257), accepted(249), accepted(280)], now: DateTime(2026, 10, 11));
    Ship ship(int uid, int type) => Ship(
          uid: uid,
          shipId: uid,
          name: 'ship$uid',
          level: 50,
          nowHP: 30,
          maxHP: 30,
          shipType: type,
          condition: 49,
          speed: 10,
          attack: [10, 10],
          antiAircraft: [10, 10],
          antiSubmarine: [10, 10],
          scout: [10, 10],
          exp: [0, 100],
          equipment: const [],
        );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        kancolleDataProvider.overrideWith((ref) => KancolleData(
              queue: OperationQueue(map: {}),
              squads: [
                Squad(id: 1, name: '第1艦隊', ships: [ship(1, cl), ship(2, dd), ship(3, dd)]),
              ],
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
              questAssistant: QuestAssistant(ready: [
                Quest(id: 257, state: 2, type: 3, title: '「水雷戦隊」南西へ！'),
                Quest(id: 249, state: 1, type: 3, title: '「第五戦隊」出撃せよ！'), // 未受諾
                Quest(id: 280, state: 3, type: 3, title: '兵站線確保！海上警備を強化実施せよ！'), // 達成
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
        home: const CupertinoPageScaffold(child: SquadInfo()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('受注中の任務の編成条件'), findsOneWidget);
    expect(find.text('「水雷戦隊」南西へ！'), findsOneWidget);
    expect(find.text('「第五戦隊」出撃せよ！'), findsNothing);
    expect(find.text('兵站線確保！海上警備を強化実施せよ！'), findsNothing);
    expect(find.byIcon(CupertinoIcons.check_mark_circled_solid), findsOneWidget);
    expect(find.text('対空カットイン (推定)'), findsOneWidget); // 合計欄の行
    expect(tester.takeException(), isNull);
  });
}
