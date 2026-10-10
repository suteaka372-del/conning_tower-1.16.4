import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/quest_fleet_condition.dart';
import 'package:conning_tower/models/feature/kancolle/quest_progress.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// api_stype
const de = 1, dd = 2, cl = 3, ca = 5, cvl = 7, fbb = 8, bb = 9, bbv = 10, cv = 11, av = 16, ao = 22;

QuestShip qs(int type, {int id = 1, int shipClass = 0, String yomi = '', int tier = 0, int level = 99}) =>
    QuestShip(shipId: id, shipType: type, shipClass: shipClass, yomi: yomi, remodelTier: tier, level: level);

QuestFleet fleet(List<QuestShip> ships, {int number = 1}) => QuestFleet(number, ships);

bool met(int questId, QuestFleet f) => kQuestDefinitions[questId]!.condition!.isMet(f);

QuestListItem quest(int id, {int type = 3}) => QuestListItem(id: id, state: 2, type: type);

void main() {
  group('definitions', () {
    test('phase 2 quests are defined', () {
      for (final id in [249, 257, 280, 284, 318, 330, 426, 434, 626, 654, 845, 854, 861, 872, 893, 903, 1051, 1104, 1164]) {
        expect(kQuestDefinitions[id], isNotNull, reason: 'quest $id');
      }
      // 1104 は 13号対空電探改 (ID 106) を廃棄する
      final c1104 = kQuestDefinitions[1104]!.counters().single;
      expect(c1104.targets, {106});
      expect(c1104.categoryIndex, -1);
    });

    test('every conditional counter has a condition', () {
      for (final def in kQuestDefinitions.values) {
        final counters = def.counters();
        if (!counters.any((c) => c.special)) continue;
        if (def.id == 893) {
          expect(def.condition, isNull); // 7-2 のゲージだけで判定
          continue;
        }
        expect(def.condition, isNotNull, reason: 'quest ${def.id}');
        final isDiscard = counters.any((c) => c.special && c.kind == QuestCounterKind.discard);
        expect(def.condition!.secretary, isDiscard, reason: 'quest ${def.id}');
      }
    });

    test('labels for multi-area quests', () {
      final labels = kQuestDefinitions[893]!.counters().map((c) => c.label).toList();
      expect(labels, ['1-5', '7-1', '7-2(第一)', '7-2(第二)']);
      expect(kQuestDefinitions[905]!.counters().last.label, '1-6終点');
      expect(kQuestDefinitions[434]!.counters().first.label, '警備任務');
      expect(kQuestDefinitions[626]!.counters().first.label, '零式艦戦21型');
    });
  });

  group('fleet conditions', () {
    test('257 「水雷戦隊」南西へ！', () {
      expect(met(257, fleet([qs(cl), qs(dd), qs(dd), qs(dd), qs(dd), qs(dd)])), isTrue);
      expect(met(257, fleet([qs(dd), qs(cl), qs(dd)])), isFalse); // 旗艦が駆逐
      expect(met(257, fleet([qs(cl), qs(cl), qs(cl), qs(cl)])), isFalse); // 軽巡4隻
      expect(met(257, fleet([qs(cl), qs(ca), qs(dd)])), isFalse); // 重巡がいる
    });

    test('249 needs 那智・妙高・羽黒', () {
      final ok = fleet([qs(ca, yomi: 'なち'), qs(ca, yomi: 'みょうこう'), qs(ca, yomi: 'はぐろ')]);
      expect(met(249, ok), isTrue);
      expect(met(249, fleet([qs(ca, yomi: 'なち'), qs(ca, yomi: 'みょうこう')])), isFalse);
    });

    test('259 battleships of specific classes only', () {
      final yamatoKaiNi = qs(fbb, id: 911, shipClass: 37);
      final nagato = qs(bb, shipClass: 19);
      final ise = qs(bbv, shipClass: 2);
      expect(met(259, fleet([yamatoKaiNi, nagato, ise, qs(cl)])), isTrue);
      expect(met(259, fleet([nagato, ise, qs(bb, shipClass: 6), qs(cl)])), isFalse); // 金剛型の戦艦
      expect(met(259, fleet([yamatoKaiNi, nagato, ise])), isFalse); // 軽巡なし
      expect(met(259, fleet([nagato, ise, qs(fbb, id: 149, shipClass: 6), qs(cl)])), isFalse); // 巡洋戦艦
    });

    test('280 light cruiser class + 3 escorts', () {
      expect(met(280, fleet([qs(cvl), qs(dd), qs(de), qs(dd)])), isTrue);
      expect(met(280, fleet([qs(ca), qs(dd), qs(de), qs(dd)])), isFalse);
    });

    test('903 needs 夕張改二 as flagship', () {
      final yuubariKaiNi = qs(cl, yomi: 'ゆうばり', tier: 2);
      expect(met(903, fleet([yuubariKaiNi, qs(dd, id: 488)])), isTrue); // 由良改二
      expect(met(903, fleet([yuubariKaiNi, qs(dd, yomi: 'むつき'), qs(dd, yomi: 'やよい')])), isTrue);
      expect(met(903, fleet([qs(cl, yomi: 'ゆうばり', tier: 1), qs(dd, id: 488)])), isFalse); // 夕張改
    });

    test('973 nationality and no carriers', () {
      final us = qs(dd, shipClass: 91); // Fletcher級
      final uk = qs(bb, shipClass: 67); // Queen Elizabeth級
      expect(met(973, fleet([us, us, uk, qs(dd)])), isTrue);
      expect(met(973, fleet([us, us, uk, qs(cv)])), isFalse);
      expect(met(973, fleet([us, uk, qs(dd)])), isFalse);
    });

    test('practice 355 needs 黒潮改二 and 親潮改二 in front', () {
      expect(met(355, fleet([qs(dd, id: 670), qs(dd, id: 568), qs(dd)])), isTrue);
      expect(met(355, fleet([qs(dd), qs(dd, id: 670), qs(dd, id: 568)])), isFalse);
    });

    test('factory 1154 checks the secretary equipment', () {
      QuestShip secretary({int level = 99, int slot1Level = 10, int slot2Level = 6}) => QuestShip(
            shipId: 1,
            shipType: dd,
            level: level,
            equipment: [
              QuestEquipment(itemId: 287, level: slot1Level),
              QuestEquipment(itemId: 1, level: slot2Level),
            ],
          );
      expect(met(1154, fleet([secretary()])), isTrue);
      expect(met(1154, fleet([secretary(level: 95)])), isFalse);
      expect(met(1154, fleet([secretary(slot2Level: 5)])), isFalse);
      expect(kQuestDefinitions[1154]!.condition!.secretary, isTrue);
    });
  });

  group('counting', () {
    test('multi-area quest counts only with a matching fleet', () {
      final tracker = QuestProgressTracker()..onQuestList([quest(280)]);
      final good = fleet([qs(cl), qs(dd), qs(dd), qs(dd)]);
      final bad = fleet([qs(ca), qs(dd), qs(dd), qs(dd)]);
      tracker.onMapPoint(mapId: 12, eventId: 5, isEndPoint: true, fleet: good);
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: [], fleet: good);
      tracker.onMapPoint(mapId: 13, eventId: 5, isEndPoint: true, fleet: bad);
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: [], fleet: bad);
      tracker.onMapPoint(mapId: 14, eventId: 5, isEndPoint: true, fleet: good);
      tracker.onBattleResult(rank: 'A', sunkEnemyShipTypes: [], fleet: good); // A 勝利は数えない
      final entry = tracker.progressOf(280)!;
      expect(entry.details, ['1-2 1/1', '1-3 0/1', '1-4 0/1', '2-1 0/1']);
    });

    test('7-2 gauges are told apart by the boss cell', () {
      final tracker = QuestProgressTracker()..onQuestList([quest(893, type: 5)]);
      tracker.onMapPoint(mapId: 72, eventId: 5, isEndPoint: true, cell: 15);
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: []);
      tracker.onMapPoint(mapId: 72, eventId: 5, isEndPoint: true, cell: 7);
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: []);
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: []);
      expect(tracker.progressOf(893)!.details, ['1-5 0/3', '7-1 0/3', '7-2(第一) 2/3', '7-2(第二) 1/3']);
    });

    test('1-6 node reach with a composition condition', () {
      final tracker = QuestProgressTracker()..onQuestList([quest(861, type: 5)]);
      final good = fleet([qs(bbv), qs(ao), qs(dd)]);
      tracker.onMapPoint(mapId: 16, eventId: 8, isEndPoint: true, fleet: good);
      tracker.onMapPoint(mapId: 16, eventId: 8, isEndPoint: false, fleet: good); // 途中のマス
      tracker.onMapPoint(mapId: 16, eventId: 8, isEndPoint: true, fleet: fleet([qs(bbv), qs(dd)]));
      expect(tracker.progressOf(861)!.text, '1/2');
    });

    test('practice quests need the practice fleet', () {
      final tracker = QuestProgressTracker()..onQuestList([quest(318)]);
      tracker.onPracticeResult('S', fleet: fleet([qs(cl), qs(cl), qs(dd)]));
      tracker.onPracticeResult('S', fleet: fleet([qs(cl), qs(dd)]));
      tracker.onPracticeResult('S'); // 艦隊が分からない
      tracker.onPracticeResult('C', fleet: fleet([qs(cl), qs(cl)])); // 敗北
      expect(tracker.progressOf(318)!.text, '1/3');
    });

    test('factory quests check the secretary ship', () {
      final tracker = QuestProgressTracker()..onQuestList([quest(1138, type: 6)]);
      const director91 = DiscardedEquipment(itemId: 120, category: 36, icon: 30);
      tracker.onDiscard([director91, director91], secretaryFleet: fleet([qs(dd, shipClass: 54)]));
      tracker.onDiscard([director91], secretaryFleet: fleet([qs(dd, shipClass: 1)]));
      expect(tracker.progressOf(1138)!.text, '2/4');
    });

    test('limited quests past their date are not tracked', () {
      final tracker = QuestProgressTracker()
        ..onQuestList([quest(840, type: 2), quest(249)], now: DateTime(2026, 10, 11));
      expect(tracker.progressOf(840), isNull);
      expect(tracker.progressOf(249), isNotNull);
      final early = QuestProgressTracker()..onQuestList([quest(840, type: 2)], now: DateTime(2026, 2, 1));
      expect(early.progressOf(840), isNotNull);
    });

    test('newly listed practice quests reset daily', () {
      final tracker = QuestProgressTracker()
        ..onQuestList([quest(381, type: 2)], now: DateTime.utc(2026, 10, 10, 10)); // 19:00 JST
      tracker.onPracticeResult('S', fleet: fleet([
        qs(dd, yomi: 'あきづき'),
        qs(dd, yomi: 'てるづき'),
        qs(dd, yomi: 'あきぐも'),
      ]));
      expect(tracker.progressOf(381)!.text, '1/3');
      tracker.onQuestList([quest(381, type: 2)], now: DateTime.utc(2026, 10, 10, 21)); // 翌 6:00 JST
      expect(tracker.progressOf(381)!.text, '0/3');
    });
  });

  test('remodel tier follows the master data (with conversion loops)', () {
    GetDataApiDataApiMstShipEntity m(int id, String after) => GetDataApiDataApiMstShipEntity(
        apiId: id, apiSortno: id, apiSortId: id, apiName: '$id', apiYomi: '', apiStype: 3, apiCtype: 0,
        apiAftershipid: after);
    final info = {
      115: m(115, '293'), // 夕張
      293: m(293, '622'), // 夕張改
      622: m(622, '623'), // 夕張改二
      623: m(623, '624'), // 夕張改二特
      624: m(624, '622'), // 夕張改二丁 (改二に戻せる)
    };
    expect(remodelTierOf(115, info), 0);
    expect(remodelTierOf(293, info), 1);
    expect(remodelTierOf(622, info), 2);
    expect(remodelTierOf(624, info), 4);
    expect(remodelTierOf(999, info), 0);
  });

  test('KancolleData passes the sortie and practice fleets', () {
    final yura = Ship(uid: 1, shipId: 488, name: '由良改二', level: 90, nowHP: 40, maxHP: 40, shipType: cl);
    final yuubari = Ship(uid: 2, shipId: 622, name: '夕張改二', level: 90, nowHP: 40, maxHP: 40, shipType: cl);
    final destroyer = Ship(uid: 3, shipId: 1, name: '駆逐', level: 90, nowHP: 30, maxHP: 30, shipType: dd);
    GetDataApiDataApiMstShipEntity m(int id, String yomi, String after) => GetDataApiDataApiMstShipEntity(
        apiId: id, apiSortno: id, apiSortId: id, apiName: '$id', apiYomi: yomi, apiStype: 3, apiCtype: 0,
        apiAftershipid: after);
    final provider = Provider((ref) => KancolleData(
          queue: OperationQueue(map: {}),
          squads: [
            Squad(id: 1, name: 'first', ships: [destroyer]),
            Squad(id: 2, name: 'second', ships: [yuubari, yura]),
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
          fleet: Fleet(ships: [], equipment: {1: Equipment(id: 1, itemId: 120, type: [3, 11, 36, 30, 0])}),
          ref: ref,
          dataInfo: DataInfo(shipInfo: {
            115: m(115, 'ゆうばり', '293'),
            293: m(293, 'ゆうばり', '622'),
            622: m(622, 'ゆうばり', '0'),
            488: m(488, 'ゆら', '0'),
          }),
          battleInfo: BattleInfo(),
          questProgress: QuestProgressTracker(),
        ));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final data = container.read(provider);

    data.trackQuestProgress('/api_get_member/questlist', {
      'api_data': {
        'api_list': [
          {'api_no': 903, 'api_state': 2, 'api_type': 5, 'api_label_type': 0, 'api_progress_flag': 0},
          {'api_no': 318, 'api_state': 2, 'api_type': 3, 'api_label_type': 0, 'api_progress_flag': 0},
        ]
      }
    }, null);

    // 第2艦隊 (夕張改二旗艦 + 由良改二) で 5-1 ボス S 勝利
    data.trackQuestProgress('/api_req_map/start', {
      'api_data': {'api_maparea_id': 5, 'api_mapinfo_no': 1, 'api_event_id': 5, 'api_next': 0, 'api_no': 12}
    }, {'api_deck_id': '2'});
    data.trackQuestProgress('/api_req_sortie/battleresult', {
      'api_data': {'api_win_rank': 'S'}
    }, null);
    expect(data.questProgress.progressOf(903)!.details.first, '5-1 1/1');

    // 第1艦隊 (駆逐だけ) では数えない
    data.trackQuestProgress('/api_req_map/start', {
      'api_data': {'api_maparea_id': 5, 'api_mapinfo_no': 4, 'api_event_id': 5, 'api_next': 0, 'api_no': 15}
    }, {'api_deck_id': '1'});
    data.trackQuestProgress('/api_req_sortie/battleresult', {
      'api_data': {'api_win_rank': 'S'}
    }, null);
    expect(data.questProgress.progressOf(903)!.details[1], '5-4 0/1');

    // 演習: 第2艦隊は軽巡2隻 → 数える
    data.trackQuestProgress('/api_req_practice/battle', {'api_data': {}}, {'api_deck_id': '2'});
    data.trackQuestProgress('/api_req_practice/battle_result', {
      'api_data': {'api_win_rank': 'A'}
    }, null);
    expect(data.questProgress.progressOf(318)!.text, '1/3');
  });
}
