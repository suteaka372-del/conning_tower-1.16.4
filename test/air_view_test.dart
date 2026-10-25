import 'dart:convert';

import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/air/air_base_store.dart';
import 'package:conning_tower/models/feature/kancolle/air/air_data.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/pages/dashboard_pages/air_sim_page.dart';
import 'package:conning_tower/providers/air_data_provider.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'air_data_test.dart' show abyssal, item, kcnavSample;

void main() {
  setUp(() => Intl.defaultLocale = 'ja');

  testWidgets('air view: nodes, patterns, air state and losses', (tester) async {
    SharedPreferences.setMockInitialValues({'air_map': 25});
    localStorage = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(402, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final slotItems = {
      1502: item(1502, '5inch単装砲', [1, 1, 1, 1, 0], 0),
      1517: item(1517, '深海棲艦攻', [3, 5, 8, 8, 0], 0),
      1520: item(1520, '深海棲艦戦 Mark.III', [3, 5, 6, 6, 0], 5),
      1524: item(1524, '深海棲艦爆 Mark.II', [3, 5, 7, 7, 0], 0),
    };
    final shipInfo = {
      1528: abyssal(1528, '空母ヲ級', 'flagship', 11),
      1502: abyssal(1502, '駆逐イ級', '-', 2),
      277: GetDataApiDataApiMstShipEntity(
          apiId: 277, apiSortId: 0, apiName: '赤城改', apiYomi: 'あかぎ', apiStype: 11, apiCtype: 14, apiMaxeq: [18, 18, 27, 10]),
    };
    AirDataLoader.abyssal = parseAbyssalTable(jsonEncode({
      'updated': '2026-10-25',
      'ships': {
        '1528': [50, [32, 32, 32]],
        '1502': [7, [0]],
      },
    }));
    AirDataLoader.abyssalAt = DateTime.now();
    AirDataLoader.comps['2-5'] = [
      ...parseEnemyComps(kcnavSample),
      const EnemyComp(node: 'E', count: 50, formation: 1, ships: [EnemyShipEntry(1528, [1520, 1517, 1524, -1, -1])]),
    ];
    AirDataLoader.compsAt['2-5'] = DateTime.now();

    final fighter = Equipment(id: 1, itemId: 22, name: '烈風', type: const [3, 5, 6, 6, 1], aa: 10, proficiency: 7);
    final bomber = Equipment(id: 2, itemId: 23, name: '彗星', type: const [3, 7, 7, 7, 2], aa: 0, proficiency: 7);
    final cv = Ship(
      uid: 1, shipId: 277, name: '赤城改', level: 99, nowHP: 69, maxHP: 69, shipType: 11, //
      onSlot: const [20, 20, 32, 10], antiAircraft: const [60, 89], equipment: [fighter, fighter, fighter, bomber],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        kancolleDataProvider.overrideWith((ref) => KancolleData(
              queue: OperationQueue(map: {}),
              squads: [Squad(id: 1, name: '第1艦隊', ships: [cv])],
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
                admiral: const Admiral(name: '', level: 120, rank: 10, maxShip: 0, maxItem: 0),
              ),
              fleet: Fleet(ships: [], equipment: {1: fighter, 2: bomber}),
              ref: ref,
              dataInfo: DataInfo(
                slotItemInfo: slotItems,
                shipInfo: Map<int, GetDataApiDataApiMstShipEntity>.from(shipInfo),
              ),
              battleInfo: BattleInfo(),
            )),
      ],
      child: const CupertinoApp(home: CupertinoPageScaffold(child: AirView())),
    ));
    await tester.pump();

    expect(find.text('制空権シミュレーター'), findsOneWidget);
    expect(find.text('O (ボス)'), findsOneWidget);
    expect(find.text('Oマスの敵編成 (2パターン)'), findsOneWidget);
    // 最初は制空値の高いヲ級の編成 ([5√32] = 28)
    expect(find.textContaining('制空値 28・輪形陣・最強'), findsOneWidget);
    expect(find.textContaining('敵 28'), findsOneWidget);
    expect(find.textContaining('確保 84・優勢 42'), findsOneWidget);
    expect(find.textContaining('棒立ち'), findsWidgets);
    expect(find.textContaining('敵の航空攻撃が来なくなる'), findsOneWidget);
    expect(find.textContaining('烈風: 20 →'), findsWidgets);

    // 艦載機のない編成に切り替えると、敵は 0
    await tester.tap(find.textContaining('制空値 0・単縦陣'));
    await tester.pumpAndSettle();
    expect(find.textContaining('敵 0'), findsOneWidget);
    expect(find.textContaining('確保 100%'), findsOneWidget);

    // 別のマスへ
    await tester.tap(find.text('G'));
    await tester.pumpAndSettle();
    expect(find.text('Gマスの敵編成 (1パターン)'), findsOneWidget);

    // ルート (連戦): 羅針盤で一番通りやすい道のり C→E→G→K のうち、報告のある E と G
    await tester.tap(find.text('ルート (連戦)'));
    await tester.pumpAndSettle();
    expect(find.text('ルート C→E→G→K'), findsOneWidget);
    expect(find.textContaining('1戦目 Eマス'), findsOneWidget);
    expect(find.textContaining('2戦目 Gマス'), findsOneWidget);
    expect(find.text('制空権 (Gマス (2戦目))'), findsOneWidget);
    await tester.tap(find.textContaining('1戦目 Eマス'));
    await tester.pumpAndSettle();
    expect(find.text('Eマスの敵編成 (1パターン)'), findsOneWidget);
    expect(find.text('基地航空隊'), findsNothing);

    // 基地航空隊 (ゲームの通信から): 最初は最後の戦闘マス (G) を攻撃する
    airBaseStore.onApi('/api_get_member/mapinfo', {
      'api_data': {
        'api_air_base': [
          {
            'api_area_id': 2, 'api_rid': 1, 'api_name': '第1基地航空隊', 'api_distance': {'api_base': 7, 'api_bonus': 0}, //
            'api_action_kind': 1,
            'api_plane_info': [
              {'api_squadron_id': 1, 'api_state': 1, 'api_slotid': 1, 'api_count': 12, 'api_max_count': 18, 'api_cond': 1},
            ],
          },
        ],
      },
    }, null);
    await tester.pumpAndSettle();
    expect(find.text('基地航空隊'), findsOneWidget);
    expect(find.textContaining('第1基地航空隊 (出撃・半径7)'), findsOneWidget);
    expect(find.textContaining('第1基地航空隊 1波'), findsNothing); // E は攻撃していない
    await tester.tap(find.textContaining('2戦目 Gマス'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第1基地航空隊 1波・制空値'), findsOneWidget);
    expect(find.textContaining('第1基地航空隊 2波・制空値'), findsOneWidget);
    // 攻撃するマスを E に変える
    await tester.tap(find.textContaining('1戦目 Eマス'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoButton, 'E'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第1基地航空隊 1波・制空値'), findsOneWidget);
    expect(find.text('基地航空隊のあとの敵の制空値'), findsOneWidget);
    // 出撃させない
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(find.textContaining('第1基地航空隊 1波'), findsNothing);

    // 装備を試す: 4スロット目の彗星を外す
    expect(find.textContaining('彗星: 10'), findsOneWidget);
    await tester.tap(find.text('艦載機を入れ替えて計算する'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('赤城改 4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外す'));
    await tester.pumpAndSettle();
    expect(find.text('1 か所を試しています'), findsOneWidget);
    expect(find.textContaining('(なし)・試し中 (10機)'), findsOneWidget);
    expect(find.textContaining('彗星: 10'), findsNothing);
    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.textContaining('彗星: 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
