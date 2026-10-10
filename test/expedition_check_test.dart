import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/expedition_check.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/map_info.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/pages/dashboard_pages/opreation_schedule.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/widgets/kancolle_expedition_check.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

int _uid = 1;

Ship ship(int shipType,
    {int level = 50,
    int condition = 49,
    int fp = 30,
    int aa = 30,
    int asw = 30,
    int los = 10,
    List<Equipment> equipment = const [],
    List<int>? onSlot}) {
  return Ship(
    uid: _uid++,
    shipId: 1,
    name: 'ship',
    level: level,
    nowHP: 30,
    maxHP: 30,
    shipType: shipType,
    condition: condition,
    attack: [fp, fp],
    antiAircraft: [aa, aa],
    antiSubmarine: [asw, asw],
    scout: [los, los],
    equipment: equipment,
    onSlot: onSlot ?? [for (final _ in equipment) 1],
  );
}

Equipment equip(int category, {int icon = 0, int level = 0, int asw = 0, int planeType = 0}) =>
    Equipment(id: _uid++, itemId: 1, type: [0, 0, category, icon, planeType], level: level, asw: asw);

Equipment drum() => equip(30, icon: 25);

const _dd = 2, _cl = 3, _de = 1, _cvl = 7;

void main() {
  setUp(() => Intl.defaultLocale = 'ja');

  group('success checks', () {
    test('05 海上護衛任務 needs an escort fleet', () {
      expect(checkExpedition(5, [ship(_cl), ship(_dd), ship(_dd), ship(_dd)]).success, isTrue);
      final noLeader = checkExpedition(5, [ship(_dd), ship(_dd), ship(_dd), ship(_dd)]);
      expect(noLeader.success, isFalse);
      expect(noLeader.failureLabels, ['護衛隊']);
      // 駆逐1 + 海防3
      expect(checkExpedition(5, [ship(_dd), ship(_de), ship(_de), ship(_de)]).success, isTrue);
      // 3隻では足りない
      expect(checkExpedition(5, [ship(_cl), ship(_dd), ship(_dd)]).failureLabels, ['艦数']);
    });

    test('escort carrier is a light carrier with base ASW', () {
      final escortCarrier = ship(_cvl, asw: 40);
      final normalCarrier = ship(_cvl, asw: 0);
      expect(checkExpedition(4, [escortCarrier, ship(_dd), ship(_dd)]).success, isTrue);
      expect(checkExpedition(4, [normalCarrier, ship(_dd), ship(_dd)]).success, isFalse);
      // 装備の対潜は数えない
      final equipped = ship(_cvl, asw: 13, equipment: [equip(8, asw: 13)]);
      expect(checkExpedition(4, [equipped, ship(_dd), ship(_dd)]).success, isFalse);
    });

    test('flagship level and empty fleet', () {
      final low = checkExpedition(3, [ship(_dd, level: 2), ship(_dd), ship(_dd)]);
      expect(low.success, isFalse);
      expect(low.failureLabels, ['旗艦Lv']);
      final empty = checkExpedition(3, []);
      expect(empty.emptyFleet, isTrue);
      expect(empty.success, isFalse);
    });

    test('A2 海峡警備行動 counts expedition stats', () {
      final fleet = [for (var i = 0; i < 4; i++) ship(_dd, fp: 20, aa: 20, asw: 50)];
      final result = checkExpedition(101, fleet);
      expect(result.success, isTrue); // 火力80 対空80 対潜200
      expect(result.noDamage, isFalse);

      // 水上偵察機の対潜は数えない
      final withSeaplane = [
        for (var i = 0; i < 3; i++) ship(_dd, fp: 20, aa: 20, asw: 50),
        ship(_dd, fp: 20, aa: 20, asw: 50, equipment: [equip(10, asw: 30)]),
      ];
      expect(ExpeditionFleet(withSeaplane).antiSubmarine, 170);
      expect(checkExpedition(101, withSeaplane).failureLabels, ['対潜合計']);

      // 2.2倍以上なら被害なし
      final strong = [for (var i = 0; i < 4; i++) ship(_dd, fp: 30, aa: 40, asw: 100)];
      expect(checkExpedition(101, strong).noDamage, isTrue);
    });

    test('improvement bonuses', () {
      final aaGun = equip(21, level: 10); // 0.9 * 10 = 9
      final highAngle = equip(4, icon: 16, level: 10); // 0.3 * 10 = 3
      final fleet = ExpeditionFleet([ship(_dd, aa: 50, equipment: [aaGun, highAngle])]);
      expect(fleet.antiAircraft, 62);
      final sonar = equip(14, level: 4); // sqrt(4) = 2
      expect(ExpeditionFleet([ship(_dd, asw: 50, equipment: [sonar])]).antiSubmarine, 52);
      final mainGun = equip(2, level: 9); // sqrt(9) = 3
      expect(ExpeditionFleet([ship(_cl, fp: 40, equipment: [mainGun])]).firepower, 43);
      final radar = equip(12, level: 4); // sqrt(4) = 2
      expect(ExpeditionFleet([ship(_cl, los: 20, equipment: [radar])]).lineOfSight, 22);
    });

    test('zero-slot aircraft fails stat expeditions', () {
      final fleet = [
        for (var i = 0; i < 3; i++) ship(_dd, fp: 30, aa: 40, asw: 100),
        ship(_dd, fp: 30, aa: 40, asw: 100, equipment: [equip(11)], onSlot: [0]),
      ];
      final result = checkExpedition(101, fleet);
      expect(result.zeroSlotAircraft, isTrue);
      expect(result.success, isFalse);
      // 条件に火力などがない遠征では関係ない
      expect(checkExpedition(3, fleet).success, isTrue);
    });

    test('37 東京急行 needs drums', () {
      final fleet = [
        ship(_cl, level: 60),
        ship(_dd, equipment: [drum(), drum()]),
        ship(_dd, equipment: [drum()]),
        ship(_dd, equipment: [drum()]),
        ship(_dd),
        ship(_dd),
      ];
      final result = checkExpedition(37, fleet);
      expect(result.success, isTrue);
      expect(ExpeditionFleet(fleet).drumCount, 4);

      final fewDrums = [...fleet]..[1] = ship(_dd, equipment: [drum()]);
      expect(checkExpedition(37, fewDrums).failureLabels, ['ドラム缶']);
    });

    test('44 航空装備輸送任務 accepts 2 AV or AV + carrier', () {
      List<Ship> fleet(List<int> types) => [
            ship(types[0], level: 40, equipment: [drum(), drum()]),
            ship(types[1], equipment: [drum(), drum()]),
            ship(_cl, equipment: [drum(), drum()]),
            ship(_dd, aa: 80, asw: 80, los: 60),
            ship(_dd, aa: 80, asw: 80, los: 60),
            ship(_dd, aa: 80, asw: 80, los: 60),
          ];
      expect(checkExpedition(44, fleet([16, 16])).success, isTrue);
      expect(checkExpedition(44, fleet([16, 11])).success, isTrue);
      expect(checkExpedition(44, fleet([16, 5])).failureLabels, ['水母・空母']);
    });

    test('support expeditions by name, unknown expeditions', () {
      expect(checkExpedition(301, [ship(_dd), ship(_dd)], missionName: '前衛支援任務').success, isTrue);
      final unknown = checkExpedition(999, [ship(_dd)], missionName: '謎の遠征');
      expect(unknown.supported, isFalse);
      expect(unknown.success, isFalse);
    });
  });

  group('great success rate', () {
    test('regular needs every ship sparkled', () {
      final sparkled = [for (var i = 0; i < 4; i++) ship(_dd, condition: 53)];
      expect(expeditionGreatSuccessRate(3, ExpeditionFleet(sparkled)), closeTo(0.81, 1e-9));
      final oneTired = [...sparkled]..[3] = ship(_dd, condition: 49);
      expect(expeditionGreatSuccessRate(3, ExpeditionFleet(oneTired)), 0);
      final six = [for (var i = 0; i < 6; i++) ship(_dd, condition: 53)];
      expect(expeditionGreatSuccessRate(3, ExpeditionFleet(six)), 1.0); // 上限100%
    });

    test('drum type adds a bonus for extra drums', () {
      final base = [
        ship(_cl, condition: 53),
        ship(_dd, condition: 53, equipment: [drum(), drum()]),
        ship(_dd, equipment: [drum(), drum()]),
        ship(_dd, equipment: [drum()]),
        ship(_dd),
        ship(_dd),
      ];
      expect(expeditionGreatSuccessRate(37, ExpeditionFleet(base)), closeTo(0.71, 1e-9)); // 5個
      final fourDrums = [...base]..[3] = ship(_dd);
      expect(expeditionGreatSuccessRate(37, ExpeditionFleet(fourDrums)), closeTo(0.36, 1e-9));
    });

    test('level type uses the flagship level', () {
      final fleet = [ship(_dd, level: 100), ship(_dd, condition: 53)];
      // 0.15 + 0.16 + sqrt(100)/100 + 100/1000
      expect(expeditionGreatSuccessRate(101, ExpeditionFleet(fleet)), closeTo(0.51, 1e-9));
    });

    test('only shown when the expedition succeeds', () {
      final fleet = [for (var i = 0; i < 4; i++) ship(_dd, condition: 53)];
      expect(checkExpedition(5, fleet).greatSuccessRate, isNull);
      expect(checkExpedition(3, fleet).greatSuccessRate, closeTo(0.81, 1e-9));
    });
  });

  group('widgets', () {
    GetDataApiDataApiMstMissionEntity mission(int id, String disp, String name, int area,
            {int resetType = 0, int damageType = 0}) =>
        GetDataApiDataApiMstMissionEntity(
          apiId: id,
          apiDispNo: disp,
          apiMapareaId: area,
          apiName: name,
          apiDetails: '説明文<br>2行目',
          apiResetType: resetType,
          apiDamageType: damageType,
          apiTime: 55,
          apiDeckNum: 4,
          apiDifficulty: 1,
          apiUseFuel: 0.5,
          apiUseBull: 0.3,
          apiWinItem1: [3, 1],
          apiWinItem2: [0, 0],
          apiWinMatLevel: [1, 1, 0, 1],
          apiReturnFlag: 1,
          apiSampleFleet: [2, 2, 2, 2, 0, 0],
        );

    Future<void> pumpTab(WidgetTester tester, Size size) async {
      SharedPreferences.setMockInitialValues({});
      localStorage = await SharedPreferences.getInstance();
      tzdata.initializeTimeZones();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final now = tz.TZDateTime.now(tz.UTC);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          kancolleDataProvider.overrideWith((ref) => KancolleData(
                queue: OperationQueue(map: {
                  2: Operation(id: 5, endTime: now.add(const Duration(minutes: 30))),
                  3: Operation(id: 999, endTime: now),
                  4: Operation(id: 999, endTime: now),
                }),
                squads: [
                  Squad(id: 1, name: '第1艦隊', ships: [ship(_dd)]),
                  Squad(id: 2, name: '第2艦隊', ships: [
                    ship(_cl, condition: 53),
                    for (var i = 0; i < 3; i++) ship(_dd, condition: 53),
                  ]),
                  Squad(id: 3, name: '第3艦隊', ships: [for (var i = 0; i < 4; i++) ship(_dd)]),
                  Squad(id: 4, name: '第4艦隊', ships: []),
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
                dataInfo: DataInfo(
                  missionInfo: {
                    for (final m in [
                      mission(5, '05', '海上護衛任務', 1),
                      mission(101, 'A2', '海峡警備行動', 1, damageType: 2),
                      mission(103, 'A4', '南西方面連絡線哨戒', 1, resetType: 1, damageType: 2),
                      mission(41, '41', 'ブルネイ泊地沖哨戒', 7),
                      mission(9, '09', 'タンカー護衛任務', 2),
                      mission(500, 'X1', '新しい遠征', 2),
                    ])
                      m.apiId: m
                  },
                  mapAreaInfo: {
                    1: const MapArea(id: 1, name: '鎮守府海域', map: [], areaType: AreaType.normal),
                    2: const MapArea(id: 2, name: '南西諸島海域', map: [], areaType: AreaType.normal),
                    7: const MapArea(id: 7, name: '南西海域', map: [], areaType: AreaType.normal),
                  },
                ),
                battleInfo: BattleInfo(),
              )),
        ],
        child: const CupertinoApp(home: OperationPage()),
      ));
      await tester.pump();
    }

    testWidgets('expedition tab lists expeditions with results per fleet', (tester) async {
      await pumpTab(tester, const Size(393, 900));
      expect(find.text('遠征チェック'), findsOneWidget);
      expect(find.text('海上護衛任務'), findsWidgets); // タイマーと一覧
      expect(find.text('鎮守府海域'), findsOneWidget);
      // 海域の並び: 鎮守府 → 南西諸島 → 南西
      final y1 = tester.getTopLeft(find.text('鎮守府海域')).dy;
      final y2 = tester.getTopLeft(find.text('南西諸島海域')).dy;
      final y7 = tester.getTopLeft(find.text('南西海域')).dy;
      expect(y1 < y2 && y2 < y7, isTrue);
      // 第2艦隊は全艦キラ4隻で 05 が大成功率81%
      expect(find.text('○81%'), findsWidgets);
      expect(find.text('×'), findsWidgets);
      expect(find.text('?'), findsWidgets); // 条件データのない遠征
      expect(find.text('-'), findsWidgets); // 第4艦隊は空
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a row opens the detail page', (tester) async {
      await pumpTab(tester, const Size(393, 900));
      await tester.tap(find.text('海峡警備行動'));
      await tester.pumpAndSettle();
      expect(find.text('A2 海峡警備行動'), findsOneWidget);
      expect(find.text('旗艦Lv'), findsOneWidget);
      expect(find.text('駆逐+海防'), findsOneWidget);
      expect(find.text('対潜合計'), findsOneWidget);
      expect(find.text('判定'), findsOneWidget);
      expect(find.text('被害なし (2.2倍)'), findsOneWidget);
      expect(find.textContaining('燃料 70'), findsWidgets);
      expect(find.textContaining('駆逐×4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow panel does not overflow', (tester) async {
      await pumpTab(tester, const Size(300, 700));
      expect(tester.takeException(), isNull);
      await tester.tap(find.textContaining('南西方面連絡線哨戒'));
      await tester.pumpAndSettle();
      expect(find.text('A4 南西方面連絡線哨戒'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
