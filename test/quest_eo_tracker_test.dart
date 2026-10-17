import 'dart:convert';

import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/quest_assistant.dart';
import 'package:conning_tower/models/feature/kancolle/quest_eo_tracker.dart';
import 'package:conning_tower/models/feature/kancolle/quest_fleet_condition.dart';
import 'package:conning_tower/models/feature/kancolle/quest_progress.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/pages/dashboard_pages/quest_info.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ElectronicObserver EN の QuestTrackers.json と同じ形の、テスト用に作ったデータ
const _trackersJson = '''
[
 [[1038],[[0,[[1,1],6,4]],[0,[[1,3],6,4]]],[0,[[8,[[[124,false,0,0],[15,false,0,0]],2]],[0,[1,[[5,[124,1,0]],[5,[15,1,0]]]]]]]],
 [[930],[[0,[[1,4],6,1]],[2,[[7,3],6,1,[18,23,24,25],"-2"]]],[0,[[7,[124,false,1,0]]]]],
 [[878],[[7,[[1,6],3,[14,17],"N"]]],[0,[]]],
 [[967],[[8,[[7,4],1]]],[0,[]]],
 [[1112],[[4,[1,4]],[5,[3,2]],[6,[3,4]],[3,[20,2]]],[0,[]]],
 [[437],[[1,[[4],1]]],[0,[[2,[[2],4,false,0,0]]]]],
 [[373],[[9,[4,4]]],[0,[[6,[[6],3,true,0]]]]],
 [[1012],[[0,[[1,1],6,3]]],[0,[[2,[[1],4,false,2,0]],[4,[[1]]],[7,[0,true,0,117]]]]],
 [[402],[],[0,[]]],
 [[9998],[[99,[1]]],[0,[]]],
 [[9997],[[0,[[1,1],6,1]]],[0,[[42,[1]]]]],
 [[201],[[0,[[1,1],4,2]]],[0,[]]]
]
''';

const _metadataJson = '[{"id": 1038, "resetType": 1}]';

GetDataApiDataApiMstShipEntity _m(int id, String name, int stype, String after, {int ctype = 0, int? sortId}) =>
    GetDataApiDataApiMstShipEntity(
        apiId: id,
        apiSortno: id,
        apiSortId: sortId ?? 1000 + id,
        apiName: name,
        apiYomi: '',
        apiStype: stype,
        apiCtype: ctype,
        apiAftershipid: after);

final _shipInfo = {
  124: _m(124, '鈴谷', 5, '129', ctype: 8),
  129: _m(129, '鈴谷改', 5, '503', ctype: 8),
  503: _m(503, '鈴谷改二', 5, '508', ctype: 8),
  508: _m(508, '鈴谷航改二', 7, '503', ctype: 8),
  15: _m(15, '曙', 2, '231', ctype: 1),
  231: _m(231, '曙改', 2, '0', ctype: 1),
  392: _m(392, 'Richelieu', 9, '0', ctype: 79, sortId: 34001),
  950: _m(950, '鵜来', 1, '0', ctype: 117),
  951: _m(951, '稲木', 1, '0', ctype: 117),
};

Ship _ship(int uid, int shipId, {int level = 50}) => Ship(
    uid: uid,
    shipId: shipId,
    name: _shipInfo[shipId]?.apiName ?? '$shipId',
    level: level,
    nowHP: 30,
    maxHP: 30,
    shipType: _shipInfo[shipId]?.apiStype ?? 2,
    equipment: const []);

QuestFleet _fleet(List<int> shipIds, {int number = 1}) => QuestFleet.fromShips(
    number, [for (final (i, id) in shipIds.indexed) _ship(i + 1, id)], _shipInfo);

QuestListItem _accepted(int id, {int type = 2}) => QuestListItem(id: id, state: 2, type: type);

void main() {
  setUp(() {
    Intl.defaultLocale = 'ja';
    questMasterData = DataInfo(shipInfo: _shipInfo, equipmentTypeNameMap: {1: '小口径主砲'});
  });
  tearDown(() => applyEoQuestTrackers({}, {}));

  group('reading the data', () {
    test('trackers become definitions; empty or unknown ones are skipped', () {
      final defs = parseEoQuestTrackers(_trackersJson);
      expect(defs.keys.toSet(), {1038, 930, 878, 967, 1112, 437, 373, 1012, 201});
      expect(defs[1038]!.fromEo, isTrue);
      expect(defs[1038]!.weightedEqually, isTrue);
      expect(defs[878]!.weightedEqually, isFalse);
      expect(defs[878]!.condition, isNull);
      expect(defs[1038]!.condition!.requirements, hasLength(2));
      expect(parseEoQuestsMetadata(_metadataJson), {1038: 1});
      expect(parseEoQuestTrackers('{"broken": true}'), isEmpty);
    });

    test('the EO definition is used before the built-in one, except for empty trackers', () {
      applyEoQuestTrackers(parseEoQuestTrackers(_trackersJson), {});
      expect(questDefinitionOf(201)!.fromEo, isTrue);
      expect(questDefinitionOf(402)!.fromEo, isFalse); // 中身のないトラッカーは組み込みの定義のまま
      expect(questDefinitionOf(1038)!.fromEo, isTrue);
      applyEoQuestTrackers({}, {});
      expect(questDefinitionOf(201)!.fromEo, isFalse);
      expect(questDefinitionOf(1038), isNull);
    });
  });

  test('condition and task texts', () {
    final defs = parseEoQuestTrackers(_trackersJson);
    List<String> tasks(int id) => [for (final c in defs[id]!.counters()) questCounterConditionText(c)];
    List<String> conditions(int id) => [for (final r in defs[id]!.condition!.requirements) r.label];

    expect(tasks(1038), ['1-1 ボス S勝利 4回', '1-3 ボス S勝利 4回']);
    expect(conditions(1038), ['鈴谷・曙 のうち2隻以上', '旗艦: 鈴谷・曙 のどれか']);
    expect(tasks(930), ['1-4 ボス S勝利 1回', '7-3-2 S勝利 1回']);
    expect(conditions(930), ['鈴谷以上']);
    expect(tasks(878), ['1-6 N 到達 3回']);
    expect(tasks(967), ['7-4 海域突破 (ゲージ破壊) 1回']);
    expect(tasks(1112), [
      '小口径主砲を廃棄 4個',
      '図鑑の分類「魚雷」の装備を廃棄 2個',
      'アイコン「大口径主砲」の装備を廃棄 4個',
      '装備20を廃棄 2個',
    ]);
    expect(questCounterConditionText(defs[437]!.counters().single, missionName: (id) => '対潜警戒任務'),
        '対潜警戒任務 成功 1回');
    expect(conditions(437), ['駆逐 4隻以上']);
    expect(tasks(373), ['演習 B勝利以上 4回']);
    expect(conditions(373), ['旗艦: フランスの艦、フランスの艦 3隻以上']);
    expect(conditions(1012), ['海防 4隻以下', '海防のみ', '旗艦: 鵜来型']);
    expect(questTargetText(defs[930]!.counters()), '1-4・7-3-2 S');
  });

  test('composition conditions follow ElectronicObserver EN', () {
    final defs = parseEoQuestTrackers(_trackersJson);
    bool met(int id, List<int> ships) => defs[id]!.condition!.isMet(_fleet(ships));

    // 鈴谷・曙のうち2隻、旗艦はどちらか (改装段階は問わない)
    expect(met(1038, [508, 231]), isTrue);
    expect(met(1038, [231, 129]), isTrue);
    expect(met(1038, [508, 392]), isFalse);
    expect(met(1038, [392, 508, 231]), isFalse);
    // 鈴谷以上の改装: 鈴谷航改二も含む
    expect(met(930, [392, 508]), isTrue);
    expect(met(930, [392, 231]), isFalse);
    // フランス艦が旗艦で3隻以上
    expect(met(373, [392, 392, 392]), isTrue);
    expect(met(373, [392, 392]), isFalse);
    expect(met(373, [231, 392, 392, 392]), isFalse);
    // 海防艦のみ4隻以下、旗艦は鵜来型
    expect(met(1012, [950, 951, 951]), isTrue);
    expect(met(1012, [951, 950, 950, 950, 950]), isFalse);
    expect(met(1012, [950, 231]), isFalse);
  });

  group('counting', () {
    late QuestProgressTracker tracker;
    setUp(() {
      applyEoQuestTrackers(parseEoQuestTrackers(_trackersJson), parseEoQuestsMetadata(_metadataJson));
      tracker = QuestProgressTracker()
        ..onQuestList([
          _accepted(1038),
          _accepted(930),
          _accepted(878),
          _accepted(967),
          _accepted(1112),
          _accepted(437),
          _accepted(373),
          _accepted(201, type: 1),
        ], now: DateTime(2026, 10, 17, 12));
    });
    int progress(int id, [int index = 0]) => tracker.progressOf(id)!.counters[index].progress;

    test('boss and node battles count only with the right fleet', () {
      final good = _fleet([508, 231]);
      final bad = _fleet([392, 508]);
      tracker.onMapPoint(mapId: 11, eventId: 5, isEndPoint: true, cell: 5, fleet: good);
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: const [], fleet: good);
      expect(progress(1038), 1);
      expect(progress(201), 1); // 1-1 ボス B以上 (組み込みの定義より優先)
      tracker.onBattleResult(rank: 'A', sunkEnemyShipTypes: const [], fleet: good);
      expect(progress(1038), 1); // A勝利は数えない
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: const [], fleet: bad);
      expect(progress(1038), 1); // 編成条件を満たさない

      // 7-3 の第2ボス (マス 18)
      tracker.onMapPoint(mapId: 73, eventId: 4, isEndPoint: false, cell: 18, fleet: _fleet([508]));
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: const [], fleet: _fleet([508]));
      expect(progress(930, 1), 1);
      expect(progress(930, 0), 0);
      expect(tracker.progressOf(930)!.percentage, 0.5); // EO と同じく条件ごとの割合の平均
    });

    test('node reach, first clear, exercise, expedition and scrapping', () {
      tracker.onMapPoint(mapId: 16, eventId: 0, isEndPoint: false, cell: 14);
      tracker.onMapPoint(mapId: 16, eventId: 0, isEndPoint: false, cell: 3);
      expect(progress(878), 1);

      tracker.onMapPoint(mapId: 74, eventId: 5, isEndPoint: true, cell: 12);
      tracker.onBattleResult(rank: 'A', sunkEnemyShipTypes: const []);
      expect(progress(967), 0);
      tracker.onBattleResult(rank: 'A', sunkEnemyShipTypes: const [], firstClear: true);
      expect(progress(967), 1);

      tracker.onPracticeResult('S', fleet: _fleet([392, 392, 392]));
      tracker.onPracticeResult('S', fleet: _fleet([231, 392, 392, 392]));
      expect(progress(373), 1);

      tracker.onExpeditionResult(missionId: 4, success: true, fleet: _fleet([15, 15, 15]));
      expect(progress(437), 0);
      tracker.onExpeditionResult(missionId: 4, success: true, fleet: _fleet([15, 15, 15, 231]));
      expect(progress(437), 1);

      tracker.onDiscard(const [
        DiscardedEquipment(itemId: 20, category: 1, icon: 1, cardType: 1),
        DiscardedEquipment(itemId: 15, category: 5, icon: 5, cardType: 3),
        DiscardedEquipment(itemId: 7, category: 3, icon: 3, cardType: 1),
      ]);
      expect([for (var i = 0; i < 4; i++) progress(1112, i)], [1, 1, 1, 1]);
    });

    test('reset type from the metadata', () {
      // 1038 は週の任務 (type 2) だが、メタデータでは毎日リセット
      tracker.onMapPoint(mapId: 11, eventId: 5, isEndPoint: true, cell: 5, fleet: _fleet([508, 231]));
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: const [], fleet: _fleet([508, 231]));
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: const [], fleet: _fleet([508, 231]));
      tracker.onBattleResult(rank: 'S', sunkEnemyShipTypes: const [], fleet: _fleet([508, 231]));
      expect(progress(1038), 3);
      tracker.onQuestList([_accepted(1038)], now: DateTime(2026, 10, 18, 12));
      expect(progress(1038), 0);
      expect(progress(930), 0);
    });
  });

  test('saved progress waits for the trackers and survives a definition change', () {
    final saved = jsonEncode({
      'lastUpdate': DateTime(2026, 10, 17, 12).toUtc().toIso8601String(),
      'states': {'1038': 2, '875': 2},
      'entries': {
        '1038': {'type': 2, 'progress': [2, 1]},
        '875': {'type': 2, 'progress': [1]},
      },
    });
    final tracker = QuestProgressTracker.decode(saved);
    expect(tracker.progressOf(1038), isNull);
    expect(tracker.pendingProgress.keys, [1038]);
    expect(tracker.progressOf(875)!.definition.fromEo, isFalse);
    // まだ読み込んでいなくても、保存すれば消えない
    expect(QuestProgressTracker.decode(tracker.encode()).pendingProgress.keys, [1038]);

    applyEoQuestTrackers({
      ...parseEoQuestTrackers(_trackersJson),
      // 875 も EO の定義に (条件の数が同じなので進捗を引き継ぐ)
      875: parseEoQuestTracker(jsonDecode('[[875],[[0,[[5,4],6,2]]],[0,[]]]'))!,
    }, {});
    tracker.reloadDefinitions(now: DateTime(2026, 10, 17, 13));
    expect([for (final c in tracker.progressOf(1038)!.counters) c.progress], [2, 1]);
    expect(tracker.pendingProgress, isEmpty);
    expect(tracker.progressOf(875)!.definition.fromEo, isTrue);
    expect(tracker.progressOf(875)!.counters.single.progress, 1);
  });

  test('progress counted with an EO definition is not lost on the next launch', () {
    // 1105 は組み込みでは条件1つ、EO の定義では2つ
    final eo1105 = parseEoQuestTracker(jsonDecode('[[1105],[[4,[47,3]],[4,[10,2]]],[0,[]]]'))!;
    applyEoQuestTrackers({1105: eo1105}, {});
    final tracker = QuestProgressTracker()..onQuestList([_accepted(1105, type: 6)], now: DateTime(2026, 10, 17, 12));
    tracker.onDiscard(const [
      DiscardedEquipment(itemId: 1, category: 47, icon: 0),
      DiscardedEquipment(itemId: 2, category: 10, icon: 0),
    ]);
    final saved = tracker.encode();

    // 次の起動: 保存した進捗を読む時点では、まだ EO のデータを読み込んでいない
    applyEoQuestTrackers({}, {});
    final next = QuestProgressTracker.decode(saved);
    expect(next.progressOf(1105), isNull);
    expect(next.pendingProgress.keys, [1105]);

    applyEoQuestTrackers({1105: eo1105}, {});
    next.reloadDefinitions(now: DateTime(2026, 10, 17, 13));
    expect([for (final c in next.progressOf(1105)!.counters) c.progress], [1, 1]);
  });

  testWidgets('quest detail shows the EO conditions and the fleet check', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    await S.load(const Locale('ja'));
    tester.view.physicalSize = const Size(393, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    applyEoQuestTrackers(parseEoQuestTrackers(_trackersJson), {});
    final tracker = QuestProgressTracker()..onQuestList([_accepted(930)]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        kancolleDataProvider.overrideWith((ref) => KancolleData(
              queue: OperationQueue(map: {}),
              squads: [
                Squad(id: 1, name: '第1艦隊', ships: [_ship(1, 508), _ship(2, 231)]),
                Squad(id: 2, name: '第2艦隊', ships: [_ship(3, 392)]),
              ],
              seaForceBase: SeaForceBase(
                resource: const SeaForceBaseResource(fuel: 0, ammo: 0, steel: 0, bauxite: 0, instantCreateShip: 0,
                    instantRepairs: 0, developmentMaterials: 0, improvementMaterials: 0),
                admiral: const Admiral(name: '', level: 1, rank: 10, maxShip: 0, maxItem: 0),
              ),
              fleet: Fleet(ships: [], equipment: {}),
              ref: ref,
              dataInfo: DataInfo(shipInfo: _shipInfo),
              battleInfo: BattleInfo(),
              questAssistant: QuestAssistant(ready: [
                Quest(id: 930, state: 2, type: 4, title: '主力オブ主力、縦横無尽ッ！'),
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
    expect(find.text('0%'), findsOneWidget); // 複数条件は割合

    await tester.tap(find.text('主力オブ主力、縦横無尽ッ！'));
    await tester.pumpAndSettle();
    expect(find.text('7-3-2 S勝利 1回'), findsOneWidget);
    expect(find.textContaining('ElectronicObserver EN の任務トラッカー'), findsOneWidget);
    expect(find.text('編成チェック'), findsOneWidget);
    expect(find.text('鈴谷以上'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
