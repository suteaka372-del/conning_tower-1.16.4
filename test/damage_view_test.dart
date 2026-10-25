import 'dart:convert';

import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/air/air_data.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/damage/damage_data.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/pages/dashboard_pages/damage_sim_page.dart';
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

  final slotItems = {
    1502: item(1502, '5inch単装砲', [1, 1, 1, 1, 0], 0),
    1517: item(1517, '深海棲艦攻', [3, 5, 8, 8, 0], 0),
    1520: item(1520, '深海棲艦戦 Mark.III', [3, 5, 6, 6, 0], 5),
    1524: item(1524, '深海棲艦爆 Mark.II', [3, 5, 7, 7, 0], 0),
  };
  final shipInfo = <int, GetDataApiDataApiMstShipEntity>{
    1528: abyssal(1528, '空母ヲ級', 'flagship', 11),
    1502: abyssal(1502, '駆逐イ級', '-', 2),
  };
  // [対空, 搭載数, 耐久, 火力, 雷装, 装甲, 対潜, 陸上型, 印]
  final table = parseAbyssalTable(jsonEncode({
    'updated': '2026-10-25',
    'ships': {
      '1528': [50, [32, 32, 32], 96, 25, 0, 80, 0, 0, 4],
      '1502': [7, [0], 20, 5, 15, 5, 25, 0, 0],
    },
  }));

  test('enemy ships from KCNav comps, the abyssal stats and the master data', () {
    expect(table.stats[1528]!.hp, 96);
    expect(table.stats[1528]!.flags, 4);
    final comp = parseEnemyComps(kcnavSample)[0];
    final enemies = damageEnemyFleetOf(comp, abyssal: table, slotItems: slotItems, shipInfo: shipInfo);
    expect(enemies.map((e) => e.name), ['空母ヲ級flagship', '駆逐イ級']);
    final wo = enemies.first;
    expect(wo.hp, 96);
    expect(wo.armor, 80);
    expect(wo.shipType, 11);
    expect(wo.nightCarrier, isTrue);
    expect(wo.equips.where((e) => e.isAttackPlane).length, 2);
    // 古い形のデータ (能力値なし) なら敵を作らない
    final old = parseAbyssalTable(jsonEncode({'ships': {'1528': [50, [32, 32, 32]]}}));
    expect(damageEnemyFleetOf(comp, abyssal: old, slotItems: slotItems, shipInfo: shipInfo), isEmpty);
  });

  test('own ship from the app data: totals, naked torpedo and plane counts', () {
    final gun = Equipment(id: 1, itemId: 7, name: '35.6cm連装砲', type: const [1, 3, 3, 3, 0], firepower: 15, level: 4);
    final torp = Equipment(id: 2, itemId: 15, name: '61cm四連装(酸素)魚雷', type: const [2, 3, 5, 5, 0], torpedo: 10);
    final s = Ship(
      uid: 1, shipId: 151, name: '榛名改二', level: 99, nowHP: 40, maxHP: 82, shipType: 8, //
      attack: const [120, 120], attackT: const [10, 10], armor: const [80, 80], antiSubmarine: const [0, 0],
      onSlot: const [3, 3, 3, 3], equipment: [gun, torp],
    );
    final full = damageShipOf(s);
    expect(full.hp, 82); // 満タンとして計算
    expect(damageShipOf(s, full: false).hp, 40);
    expect(full.firepower, 120);
    expect(full.nakedTorpedo, 0);
    expect(full.equips.first.shellingImprovement, closeTo(1.5 * 2, 1e-9)); // 大口径 1.5√4
  });

  testWidgets('damage view: target, summary and attacks of each ship', (tester) async {
    SharedPreferences.setMockInitialValues({'dmg_map': 25});
    localStorage = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(402, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    AirDataLoader.abyssal = table;
    AirDataLoader.abyssalAt = DateTime.now();
    AirDataLoader.comps['2-5'] = parseEnemyComps(kcnavSample);
    AirDataLoader.compsAt['2-5'] = DateTime.now();

    final gun = Equipment(id: 1, itemId: 7, name: '35.6cm連装砲', type: const [1, 3, 3, 3, 0], firepower: 15);
    final bb = Ship(
      uid: 1, shipId: 151, name: '榛名改二', level: 99, nowHP: 82, maxHP: 82, shipType: 8, //
      attack: const [130, 130], attackT: const [0, 0], armor: const [80, 80], antiSubmarine: const [0, 0],
      onSlot: const [3, 3, 3, 3], equipment: [gun, gun],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        kancolleDataProvider.overrideWith((ref) => KancolleData(
              queue: OperationQueue(map: {}),
              squads: [Squad(id: 1, name: '第1艦隊', ships: [bb])],
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
              fleet: Fleet(ships: [], equipment: {}),
              ref: ref,
              dataInfo: DataInfo(slotItemInfo: slotItems, shipInfo: shipInfo),
              battleInfo: BattleInfo(),
            )),
      ],
      child: const CupertinoApp(home: CupertinoPageScaffold(child: DamageView())),
    ));
    await tester.pump();

    expect(find.text('ダメージシミュレーター'), findsOneWidget);
    expect(find.text('1 空母ヲ級flagship (96)'), findsOneWidget);
    expect(find.text('1回の攻撃で撃沈・大破できるか (通常の命中)'), findsOneWidget);
    // 砲撃 135 (徹甲弾なし) vs 装甲80: 防御 56〜103.4 → 31〜79
    expect(find.textContaining('31〜79 →'), findsWidgets);
    expect(find.text('榛名改二 → 空母ヲ級flagship'), findsOneWidget);
    // 連撃は2回 (×2)
    expect(find.text('連撃 ×1.2×2'), findsNothing); // 水偵がないので弾着・連撃はない

    // 駆逐イ級を狙う: 1回で撃沈できる
    await tester.tap(find.text('2 駆逐イ級 (20)'));
    await tester.pumpAndSettle();
    expect(find.text('榛名改二 → 駆逐イ級'), findsOneWidget);
    expect(find.textContaining('撃沈 100%'), findsWidgets);

    // 夜戦の攻撃も並ぶ (主砲2つなので連撃)
    expect(find.text('夜戦 通常'), findsOneWidget);
    expect(find.text('夜戦 連撃 ×1.2×2'), findsOneWidget);

    // 反航戦にすると攻撃力が下がる
    await tester.tap(find.text('反航戦'));
    await tester.pumpAndSettle();
    expect(localStorage.getInt('dmg_engagement'), 1);

    // 特効の倍率 (自分 → 敵)
    await tester.tap(find.text('1 空母ヲ級flagship (96)'));
    await tester.pumpAndSettle();
    final before = tester.widgetList<Text>(find.textContaining('→ ')).map((t) => t.data).join('|');
    await tester.enterText(find.byType(CupertinoTextField), '1.5');
    await tester.pumpAndSettle();
    expect(localStorage.getDouble('dmg_bonus'), 1.5);
    final after = tester.widgetList<Text>(find.textContaining('→ ')).map((t) => t.data).join('|');
    expect(after, isNot(before));

    // 敵 → 自分: ヲ級の攻撃が榛名に当たったら (旗艦なので沈まない)
    await tester.tap(find.text('敵 → 自分'));
    await tester.pumpAndSettle();
    expect(find.text('敵の攻撃1回で大破するか (通常の命中)'), findsOneWidget);
    expect(find.text('1 榛名改二 (82/82)'), findsOneWidget);
    expect(find.text('空母ヲ級flagship → 榛名改二'), findsOneWidget);
    expect(find.textContaining('→ 撃沈'), findsNothing);
    expect(find.textContaining('撃沈 最大'), findsNothing);
    expect(localStorage.getBool('dmg_reverse'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
