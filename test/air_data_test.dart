import 'dart:convert';

import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/air/air_data.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:flutter_test/flutter_test.dart';

GetDataApiDataApiMstSlotitemEntity item(int id, String name, List<int> type, int aa) =>
    GetDataApiDataApiMstSlotitemEntity.fromJson({
      'api_id': id, 'api_sortno': 0, 'api_name': name, 'api_type': type, 'api_taik': 0, 'api_souk': 0, //
      'api_houg': 0, 'api_raig': 0, 'api_soku': 0, 'api_baku': 0, 'api_tyku': aa, 'api_tais': 0, 'api_atap': 0,
      'api_houm': 0, 'api_raim': 0, 'api_houk': 0, 'api_raik': 0, 'api_bakk': 0, 'api_saku': 0, 'api_sakb': 0,
      'api_luck': 0, 'api_leng': 0, 'api_rare': 0, 'api_broken': [0, 0, 0, 0], 'api_usebull': '0',
    });

GetDataApiDataApiMstShipEntity abyssal(int id, String name, String yomi, int stype) => GetDataApiDataApiMstShipEntity(
      apiId: id, apiSortId: 0, apiName: name, apiYomi: yomi, apiStype: stype, apiCtype: 1); //

// KCNav の enemycomps の形 (実際の応答から必要なところだけ)
const kcnavSample = '''
{"result":{"entryCount":3,"entries":[
 {"map":"2-5","node":"O","mainFleet":[
   {"id":1528,"name":"空母ヲ級","aa":50,"equips":[1520,1517,1524,-1,-1]},
   {"id":1502,"name":"駆逐イ級","equips":[1502,-1,-1,-1,-1]}],
  "escortFleet":[],"formation":3,"count":120},
 {"map":"2-5","node":"O","mainFleet":[
   {"id":1502,"name":"駆逐イ級","equips":[1502,-1,-1,-1,-1]}],
  "escortFleet":[],"formation":1,"count":900},
 {"map":"2-5","node":"G","mainFleet":[
   {"id":1502,"name":"駆逐イ級","equips":[1502,-1,-1,-1,-1]}],
  "escortFleet":[],"formation":1,"count":30}
]},"retrieved":"2026-10-25"}
''';

void main() {
  final slotItems = {
    1502: item(1502, '5inch単装砲', [1, 1, 1, 1, 0], 0),
    1517: item(1517, '深海棲艦攻', [3, 5, 8, 8, 0], 0),
    1520: item(1520, '深海棲艦戦 Mark.III', [3, 5, 6, 6, 0], 5),
    1524: item(1524, '深海棲艦爆 Mark.II', [3, 5, 7, 7, 0], 0),
    1540: item(1540, '40mm四連装機関砲', [4, 6, 21, 15, 0], 12),
  };
  final shipInfo = {
    1528: abyssal(1528, '空母ヲ級', 'flagship', 11),
    1502: abyssal(1502, '駆逐イ級', '-', 2),
  };
  final table = parseAbyssalTable(jsonEncode({
    'v': 1,
    'updated': '2026-10-25',
    'ships': {
      '1528': [50, [32, 32, 32]],
      '1502': [7, [0]],
    },
  }));

  test('abyssal table', () {
    expect(table.updated, '2026-10-25');
    expect(table.aaOf(1528), 50);
    expect(table.slotsOf(1528), [32, 32, 32]);
    expect(table.slotsOf(9999), isEmpty);
  });

  test('KCNav enemy comps are grouped by node, most reported first', () {
    final comps = parseEnemyComps(kcnavSample);
    expect(comps.length, 3);
    final byNode = enemyCompsByNode(comps);
    expect(byNode.keys.toSet(), {'O', 'G'});
    expect(byNode['O']!.map((c) => c.count), [900, 120]);
    expect(byNode['O']![1].ships.first.equips, [1520, 1517, 1524, -1, -1]);
    expect(byNode['O']![1].formation, 3);
  });

  test('enemy fleet: planes from the table and the master data, the strongest comp', () {
    final comps = enemyCompsByNode(parseEnemyComps(kcnavSample))['O']!;
    final fleets = [for (final c in comps) enemyAirFleet(c, abyssal: table, slotItems: slotItems, shipInfo: shipInfo)];
    final wo = fleets[1].ships.first;
    expect(wo.name, '空母ヲ級flagship');
    expect(wo.slots.map((s) => (s.plane.category, s.count)), [(6, 32), (8, 32), (7, 32)]);
    expect(airFleetPower(fleets[1]), (5 * sqrt32()).floor());
    expect(fleets[1].enemy, isTrue);
    expect(fleets[1].formation, 3);
    expect(fleets[1].ships[1].name, '駆逐イ級');
    expect(strongestEnemyComp(fleets), 1); // 報告は少ないが制空値が高い方
    // 敵の加重対空 2×[√50] = 14
    expect(wo.weightedAa, 14);
  });

  test('own fleet from the app data', () {
    final fighter = Equipment(id: 1, itemId: 22, name: '烈風', type: const [3, 5, 6, 6, 1], aa: 10, level: 0, proficiency: 7);
    final bomber = Equipment(id: 2, itemId: 23, name: '彗星', type: const [3, 7, 7, 7, 2], aa: 0, proficiency: 7);
    final gun = Equipment(id: 3, itemId: 131, name: '25mm三連装機銃 集中配備', type: const [4, 6, 21, 15, 0], aa: 9);
    final cv = Ship(
      uid: 1, shipId: 277, name: '赤城改', level: 99, nowHP: 69, maxHP: 69, shipType: 11, //
      onSlot: const [20, 20, 32, 0], antiAircraft: const [70, 89],
      equipment: [fighter, bomber, fighter, gun],
    );
    final escaped = Ship(uid: 2, shipId: 1, name: '睦月', level: 1, nowHP: 1, maxHP: 13, shipType: 2).copyWith(escape: true);
    final fleet = ownAirFleet(Squad(id: 1, name: '第1艦隊', ships: [cv, escaped]), formation: 3);
    expect(fleet.ships.length, 1);
    expect(fleet.formation, 3);
    final ship = fleet.ships.single;
    expect(ship.slots.map((s) => (s.index, s.count)), [(0, 20), (1, 20), (2, 32)]);
    expect(ship.slots[1].plane.isAttacker, isTrue);
    // 素の対空 = 70 - (10 + 10 + 9) = 41、加重 = 2 × [(41 + 6×9 + 4×0) / 2] = 94
    expect(ship.weightedAa, 94);
    expect(ship.fleetAaBonus, (0.2 * 10 + 0.2 * 10 + 0.2 * 9).floor());
  });

  test('trying other planes: swapped slots fly full, removed slots are empty', () {
    final fighter = Equipment(id: 1, itemId: 22, name: '烈風', type: const [3, 5, 6, 6, 1], aa: 10, proficiency: 7);
    final bomber = Equipment(id: 2, itemId: 23, name: '彗星', type: const [3, 7, 7, 7, 2], aa: 0, proficiency: 7);
    final strong = Equipment(id: 3, itemId: 336, name: '烈風改二', type: const [3, 5, 6, 6, 1], aa: 13, proficiency: 7);
    final cv = Ship(
      uid: 7, shipId: 277, name: '赤城改', level: 99, nowHP: 69, maxHP: 69, shipType: 11, //
      onSlot: const [5, 20, 32, 10], antiAircraft: const [60, 89], equipment: [fighter, fighter, fighter, bomber],
    );
    final normal = airShipOf(cv);
    expect(normal.slots.map((s) => s.count), [5, 20, 32, 10]);
    final tried = airShipOf(cv, overrides: {0: strong, 3: null}, maxSlots: const [20, 20, 32, 10]);
    expect(tried.slots.map((s) => (s.index, s.plane.name, s.count)), [(0, '烈風改二', 20), (1, '烈風', 20), (2, '烈風', 32)]);
    // 素の対空は元の装備から求める (60 - 30 = 30)。加重は 2 × [30 / 2] = 30 のまま
    expect(tried.weightedAa, normal.weightedAa);
    final fleet = ownAirFleet(Squad(id: 1, name: '', ships: [cv]), overrides: {7: {3: strong}});
    expect(fleet.ships.single.slots.last.plane.name, '烈風改二');

    // 候補: 同じ装備はまとめて、制空値の高い順
    final candidates = airSwapCandidates([fighter, fighter.copyWith(id: 9), bomber, strong, Equipment(id: 4, itemId: 2, type: const [1, 1, 1, 1, 0])]);
    expect(candidates.map((c) => (c.$1.name, c.$2)), [('烈風改二', 1), ('烈風', 2), ('彗星', 1)]);
  });

  test('KCNav url: every node number of the map, and the gauge for maps with gauges', () {
    final since = DateTime.utc(2026, 4, 28);
    final url = kcnavEnemyCompsUrl(compassMapOf(15)!, since: since);
    expect(url.toString(),
        'https://tsunkit.net/api/routing/maps/1-5/edges/1,2,3,4,5,6,7,8,9,10,11,12/enemycomps?start=2026-04-28');
    final third = compassMapsOf(75)[2];
    expect(airGaugeOf(third), 3);
    expect(kcnavEnemyCompsUrl(third, since: since, gauge: 3).query, 'start=2026-04-28&minGauge=3&maxGauge=3');
    expect(airGaugeOf(compassMapOf(15)!), isNull);
    // 5-6 の仮の番号 (-1) は送らない
    expect(kcnavEnemyCompsUrl(compassMapsOf(56)[0], since: since).path, isNot(contains('-1,')));
  });
}

double sqrt32() => 5.656854249492381;
