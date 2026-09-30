import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/quest_assistant.dart';
import 'package:conning_tower/models/feature/kancolle/quest_progress.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/pages/dashboard_pages/quest_info.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

QuestListItem _quest(int id, {int state = 2, int type = 1, int label = 0, int flag = 0}) =>
    QuestListItem(id: id, state: state, type: type, label: label, progressFlag: flag);

KancolleData _data(Ref ref, {List<Squad> squads = const [], QuestAssistant? questAssistant}) => KancolleData(
      queue: OperationQueue(map: {}),
      squads: [...squads],
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
      fleet: Fleet(ships: [], equipment: {
        1: Equipment(id: 1, itemId: 2, type: [1, 1, 1, 1, 0]), // 小口径主砲
        2: Equipment(id: 2, itemId: 37, type: [4, 2, 21, 15, 0]), // 機銃
      }),
      ref: ref,
      dataInfo: DataInfo(shipInfo: {
        1501: GetDataApiDataApiMstShipEntity(
            apiId: 1501, apiSortId: 0, apiName: '駆逐イ級', apiYomi: '', apiStype: 2, apiCtype: 0),
        1513: GetDataApiDataApiMstShipEntity(
            apiId: 1513, apiSortId: 0, apiName: '輸送ワ級', apiYomi: '', apiStype: 15, apiCtype: 0),
      }),
      battleInfo: BattleInfo(),
      questAssistant: questAssistant,
      questProgress: QuestProgressTracker(),
    );

void main() {
  group('QuestProgressTracker', () {
    test('Bd5: sinking supply ships counts only accepted quest', () {
      final tracker = QuestProgressTracker()..onQuestList([_quest(218), _quest(213, type: 2), _quest(221, state: 1, type: 2)]);
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: [15, 15, 7]);
      expect(tracker.progressOf(218)!.text, '2/3');
      expect(tracker.progressOf(213)!.text, '2/20');
      expect(tracker.progressOf(221)!.text, '0/50'); // not accepted
      tracker.onBattleResult(rank: 'A', sunkEnemyShipTypes: [15, 15]);
      expect(tracker.progressOf(218)!.text, '3/3'); // capped
      expect(tracker.progressOf(218)!.percentage, 1.0);
    });

    test('boss battles in target areas', () {
      final tracker = QuestProgressTracker()..onQuestList([_quest(226, type: 2), _quest(201)]);
      tracker.onMapPoint(mapId: 21, eventId: 4, isEndPoint: false);
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: []);
      expect(tracker.progressOf(226)!.progress, 0); // not boss
      expect(tracker.progressOf(201)!.progress, 1);

      tracker.onMapPoint(mapId: 21, eventId: 5, isEndPoint: true);
      tracker.onBattleResult(rank: 'C', sunkEnemyShipTypes: []);
      expect(tracker.progressOf(226)!.progress, 0); // lose

      tracker.onBattleResult(rank: 'A', sunkEnemyShipTypes: []);
      expect(tracker.progressOf(226)!.progress, 1);

      tracker.onMapPoint(mapId: 31, eventId: 5, isEndPoint: true);
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: []);
      expect(tracker.progressOf(226)!.progress, 1); // other area
    });

    test('A-go counts sortie, S win, boss and boss win', () {
      final tracker = QuestProgressTracker()..onQuestList([_quest(214, type: 2)]);
      tracker.onSortieStart();
      tracker.onMapPoint(mapId: 11, eventId: 4, isEndPoint: false);
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: []);
      tracker.onMapPoint(mapId: 11, eventId: 5, isEndPoint: true);
      tracker.onBattleResult(rank: 'D', sunkEnemyShipTypes: []);
      final entry = tracker.progressOf(214)!;
      expect(entry.details, ['出撃 1/36', 'S勝利 1/6', 'ボス 1/24', 'ボス勝利 0/12']);
      expect(entry.percentage, closeTo((1 / 36 + 1 / 6 + 1 / 24) / 4, 1e-9));
    });

    test('practice and expedition', () {
      final tracker = QuestProgressTracker()
        ..onQuestList([_quest(303), _quest(304), _quest(402), _quest(410, type: 2), _quest(426, type: 5)]);
      tracker.onPracticeResult('C');
      tracker.onPracticeResult('A');
      expect(tracker.progressOf(303)!.text, '2/3');
      expect(tracker.progressOf(304)!.text, '1/5');

      tracker.onExpeditionResult(missionId: 37, success: true);
      tracker.onExpeditionResult(missionId: 5, success: true);
      tracker.onExpeditionResult(missionId: 3, success: false);
      expect(tracker.progressOf(402)!.text, '2/3');
      expect(tracker.progressOf(410)!.text, '1/1');
      expect(tracker.progressOf(426)!.details, ['警備任務 0/1', '対潜警戒任務 0/1', '海上護衛任務 1/1', '強行偵察任務 0/1']);
    });

    test('factory, supply, docking and discard', () {
      final tracker = QuestProgressTracker()
        ..onQuestList([
          _quest(503),
          _quest(504),
          _quest(605),
          _quest(607),
          _quest(609),
          _quest(613),
          _quest(673),
          _quest(676, type: 2),
          _quest(702),
        ]);
      tracker.onDocking();
      tracker.onSupply();
      tracker.onDevelopment(3);
      tracker.onDestruction(2);
      tracker.onModernization(false);
      tracker.onModernization(true);
      const smallGun = DiscardedEquipment(itemId: 2, category: 1, icon: 1);
      const mediumGun = DiscardedEquipment(itemId: 50, category: 2, icon: 2);
      const subGun = DiscardedEquipment(itemId: 11, category: 4, icon: 4);
      tracker.onDiscard([smallGun, mediumGun, mediumGun, subGun]);

      expect(tracker.progressOf(503)!.text, '1/5');
      expect(tracker.progressOf(504)!.text, '1/15');
      expect(tracker.progressOf(605)!.text, '1/1');
      expect(tracker.progressOf(607)!.text, '3/3');
      expect(tracker.progressOf(609)!.text, '2/2');
      expect(tracker.progressOf(613)!.text, '1/24'); // counts times
      expect(tracker.progressOf(673)!.text, '1/4');
      expect(tracker.progressOf(676)!.details, ['中口径主砲 2/3', '副砲 1/3', '簡易輸送部材 0/1']);
      expect(tracker.progressOf(702)!.text, '1/2');
    });

    test('game progress flag (50%/80%) raises the count', () {
      final tracker = QuestProgressTracker()
        ..onQuestList([_quest(213, type: 2, flag: 1), _quest(411, type: 2, flag: 2), _quest(673, flag: 1)]);
      expect(tracker.progressOf(213)!.text, '10/20');
      expect(tracker.progressOf(411)!.text, '5/6'); // ceil(7*0.8)-1
      expect(tracker.progressOf(673)!.text, '2/4'); // ceil(5*0.5)-1
    });

    test('resets at 05:00 JST (daily / weekly)', () {
      // Monday 2026-09-28 04:00 JST = 2026-09-27 19:00 UTC
      final beforeReset = DateTime.utc(2026, 9, 27, 19);
      final tracker = QuestProgressTracker()
        ..onQuestList([_quest(218), _quest(213, type: 2), _quest(221, type: 2), _quest(265, type: 3)],
            now: beforeReset);
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: [15]);

      // same game day
      tracker.onQuestList([], now: DateTime.utc(2026, 9, 27, 19, 50));
      expect(tracker.progressOf(218)!.progress, 1);

      // Monday 05:30 JST: daily and weekly reset, monthly kept
      tracker.onQuestList([], now: DateTime.utc(2026, 9, 27, 20, 30));
      expect(tracker.progressOf(218), isNull);
      expect(tracker.progressOf(213), isNull);
      expect(tracker.progressOf(265), isNotNull);

      // 2026-10-01 05:00 JST: monthly reset
      tracker.onQuestList([], now: DateTime.utc(2026, 9, 30, 20, 1));
      expect(tracker.progressOf(265), isNull);
    });

    test('completed quest shows full, turned in quest is removed', () {
      final tracker = QuestProgressTracker()..onQuestList([_quest(218)]);
      tracker.onQuestList([_quest(218, state: 3)]);
      expect(tracker.progressOf(218)!.text, '3/3');
      tracker.onQuestCleared(218);
      expect(tracker.progressOf(218), isNull);
    });

    test('encode / decode keeps progress', () {
      final tracker = QuestProgressTracker()..onQuestList([_quest(218), _quest(676, type: 2)]);
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: [15]);
      tracker.onDiscard([const DiscardedEquipment(itemId: 11, category: 4, icon: 4)]);
      final restored = QuestProgressTracker.decode(tracker.encode());
      expect(restored.progressOf(218)!.text, '1/3');
      expect(restored.progressOf(676)!.details, ['中口径主砲 0/3', '副砲 1/3', '簡易輸送部材 0/1']);
      expect(restored.questStates[218], 2);
      expect(restored.lastUpdate, isNotNull);
      expect(QuestProgressTracker.decode('broken').entries, isEmpty);
    });
  });

  test('KancolleData tracks API responses', () {
    final provider = Provider((ref) => _data(ref, squads: [
          Squad(id: 1, name: 'first', ships: []),
          Squad(id: 2, name: 'second', operation: 5, ships: []),
        ]));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final data = container.read(provider);

    data.trackQuestProgress('/api_get_member/questlist', {
      'api_result': 1,
      'api_data': {
        'api_list': [
          {'api_no': 218, 'api_state': 2, 'api_type': 1, 'api_label_type': 2, 'api_progress_flag': 0},
          {'api_no': 402, 'api_state': 2, 'api_type': 1, 'api_label_type': 2, 'api_progress_flag': 0},
          {'api_no': 673, 'api_state': 2, 'api_type': 1, 'api_label_type': 2, 'api_progress_flag': 0},
          -1,
        ]
      }
    }, null);

    // battle: one transport sunk, one destroyer alive
    data.battleInfo.enemySquads = [
      Squad(id: 1, name: 'enemy', ships: [
        Ship(uid: -1, shipId: 1513, level: 1, nowHP: 0, maxHP: 70),
        Ship(uid: -1, shipId: 1501, level: 1, nowHP: 5, maxHP: 20),
      ])
    ];
    data.trackQuestProgress('/api_req_map/start', {
      'api_data': {'api_maparea_id': 1, 'api_mapinfo_no': 5, 'api_event_id': 4, 'api_next': 1}
    }, {'api_deck_id': '1'});
    data.trackQuestProgress('/api_req_sortie/battleresult', {
      'api_data': {'api_win_rank': 'S'}
    }, null);
    expect(data.questProgress.progressOf(218)!.text, '1/3');

    data.trackQuestProgress('/api_req_mission/result', {
      'api_data': {'api_clear_result': 1}
    }, {'api_deck_id': '2'});
    expect(data.questProgress.progressOf(402)!.text, '1/3');

    data.trackQuestProgress('/api_req_kousyou/destroyitem2', {'api_data': {}}, {'api_slotitem_ids': '1,2'});
    expect(data.questProgress.progressOf(673)!.text, '1/4'); // only the small gun
  });

  testWidgets('quest list shows x/y and details', (tester) async {
    await S.load(const Locale('ja'));
    final tracker = QuestProgressTracker()..onQuestList([_quest(218), _quest(676, type: 2)]);
    tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: [15, 15]);
    final quests = QuestAssistant(ready: [
      Quest(id: 218, state: 2, type: 1, title: '敵補給艦を3隻撃沈せよ！', detail: '補給艦を撃沈せよ'),
      Quest(id: 676, state: 2, type: 2, title: '装備開発力の集中整備'),
      Quest(id: 999, state: 2, type: 1, title: '未対応の任務', progressFlag: 1),
    ], done: []);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        kancolleDataProvider.overrideWith((ref) {
          final data = _data(ref, questAssistant: quests);
          return KancolleData(
            queue: data.queue,
            squads: data.squads,
            seaForceBase: data.seaForceBase,
            fleet: data.fleet,
            ref: ref,
            dataInfo: data.dataInfo,
            battleInfo: data.battleInfo,
            questAssistant: quests,
            questProgress: tracker,
          );
        }),
      ],
      child: CupertinoApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        locale: const Locale('ja'),
        home: const QuestInfoPage(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('0/7'), findsOneWidget);
    expect(find.textContaining('中口径主砲 0/3'), findsOneWidget);
    expect(find.text('50%以上'), findsOneWidget); // no definition -> game flag
    expect(tester.takeException(), isNull);
  });
}
