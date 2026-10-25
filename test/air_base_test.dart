import 'dart:math';

import 'package:conning_tower/models/feature/kancolle/air/air_base_store.dart';
import 'package:conning_tower/models/feature/kancolle/air/air_data.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:flutter_test/flutter_test.dart';

AirPlane plane(int category, int aa, {int prof = 0, int imp = 0, int interception = 0}) =>
    AirPlane(itemId: 1, name: 'p$category', category: category, aa: aa, proficiency: prof, improvement: imp, interception: interception);

Map<String, dynamic> squadron(int id, int slotId, int count, {int max = 18, int state = 1}) =>
    {'api_squadron_id': id, 'api_state': state, 'api_slotid': slotId, 'api_count': count, 'api_max_count': max, 'api_cond': 1};

void main() {
  test('land-based air power: interception ×1.5, recon multiplier, recon planes count', () {
    // 局戦 (対空10・迎撃4・熟練度>>) 18機: [(10 + 4×1.5) × √18 + √12 + 22] = 93
    expect(airLbasSlotPower(plane(kAirLandFighter, 10, prof: 7, interception: 4), 18), 93);
    // 陸攻の改修は 0.5×√★
    expect(airLbasSlotPower(plane(kAirLandAttacker, 2, imp: 4), 18), ((2 + 1) * sqrt(18)).floor());
    // 偵察機も数える (艦隊の航空戦とちがう)
    expect(airLbasSlotPower(plane(kAirLandRecon, 3), 4), 6);
    expect(airSlotPower(plane(kAirLandRecon, 3), 4), 0);
    final base = AirBase('第1基地航空隊', [AirSlot(0, plane(kAirLandFighter, 10), 18), AirSlot(1, plane(kAirLandRecon, 3), 4)],
        reconMultiplier: 1.18);
    expect(airBasePower(base, const [18, 4]), (((10 * sqrt(18)).floor() + 6) * 1.18).floor());
  });

  test('two waves per base thin out enemy planes before the fleet air battle', () {
    final base = AirBase('第1基地航空隊', [
      for (var i = 0; i < 4; i++) AirSlot(i, plane(kAirLandFighter, 11, prof: 7, interception: 3), 18),
    ]);
    final own = AirFleet([
      AirShip(name: '赤城改', shipType: 11, slots: [AirSlot(0, plane(kAirFighter, 10, prof: 7), 20)]),
    ]);
    final enemy = AirFleet([
      AirShip(name: '空母ヲ級flagship', shipType: 11, slots: [
        AirSlot(0, plane(kAirFighter, 5), 32),
        AirSlot(1, plane(kAirTorpedoBomber, 0), 32),
      ]),
    ], enemy: true);
    final without = simulateAirBattles(own, [enemy], runs: 2000, seed: 5).single;
    final withBase = simulateAirBattles(own, [enemy], runs: 2000, seed: 5, bases: {0: [base]}).single;
    expect(without.waves, isEmpty);
    expect(without.enemyPowerAtFleet, without.enemyPower);
    expect(withBase.waves.map((w) => (w.baseName, w.wave)), [('第1基地航空隊', 1), ('第1基地航空隊', 2)]);
    expect(withBase.waves[0].enemyPower, withBase.enemyPower);
    expect(withBase.waves[1].enemyPower, lessThan(withBase.waves[0].enemyPower));
    expect(withBase.enemyPowerAtFleet, lessThan(withBase.waves[1].enemyPower));
    // 2波目は1波目で減った機数から
    expect(withBase.waves[1].squadrons[0].before, closeTo(withBase.waves[0].squadrons[0].after, 1e-9));
    // 敵が減ったぶん、艦隊の制空状態がよくなる
    expect((withBase.states[AirState.supremacy] ?? 0) + (withBase.states[AirState.superiority] ?? 0),
        greaterThanOrEqualTo((without.states[AirState.supremacy] ?? 0) + (without.states[AirState.superiority] ?? 0)));
  });

  test('the base store follows map info and base edits, and remembers them', () {
    String? saved;
    final store = AirBaseStore(load: () => saved, save: (json) => saved = json);
    store.onApi('/api_get_member/mapinfo', {
      'api_result': 1,
      'api_data': {
        'api_map_info': [],
        'api_air_base': [
          {
            'api_area_id': 7, 'api_rid': 1, 'api_name': '第1基地航空隊', //
            'api_distance': {'api_base': 6, 'api_bonus': 1}, 'api_action_kind': 1,
            'api_plane_info': [squadron(1, 101, 18), squadron(2, 102, 18), squadron(3, 0, 0, state: 0), squadron(4, 0, 0, state: 0)],
          },
          {'api_area_id': 6, 'api_rid': 1, 'api_name': '第1基地航空隊', 'api_distance': {'api_base': 5, 'api_bonus': 0}, 'api_action_kind': 0, 'api_plane_info': []},
        ],
      },
    }, null);
    expect(store.basesIn(7).single.distance, 7);
    expect(store.basesIn(7).single.squadrons.where((s) => s.state == 1).length, 2);

    // 配備 (set_plane) と補給 (supply)
    store.onApi('/api_req_air_corps/set_plane', {
      'api_data': {
        'api_distance': {'api_base': 5, 'api_bonus': 0},
        'api_plane_info': [squadron(3, 103, 4, max: 4)],
      },
    }, {'api_area_id': '7', 'api_base_id': '1', 'api_squadron_id': '3', 'api_item_id': '103'});
    store.onApi('/api_req_air_corps/supply', {
      'api_data': {'api_plane_info': [squadron(1, 101, 18)]},
    }, {'api_area_id': '7', 'api_base_id': '1', 'api_squadron_id': '1'});
    expect(store.basesIn(7).single.distance, 5);
    expect(store.basesIn(7).single.squadrons.firstWhere((s) => s.id == 3).slotId, 103);

    // 行動・名前・増設
    store.onApi('/api_req_air_corps/set_action', null, {'api_area_id': '7', 'api_base_id': '1', 'api_action_kind': '2'});
    store.onApi('/api_req_air_corps/change_name', null, {'api_area_id': '7', 'api_base_id': '1', 'api_name': '攻撃隊'});
    store.onApi('/api_req_air_corps/expand_base', {
      'api_data': {
        'api_base_info': [
          {'api_area_id': 7, 'api_rid': 2, 'api_name': '第2基地航空隊', 'api_distance': 0, 'api_action_kind': 0, 'api_plane_info': []},
        ],
      },
    }, null);
    expect(store.basesIn(7).map((b) => (b.rid, b.name, b.actionKind)), [(1, '攻撃隊', 2), (2, '第2基地航空隊', 0)]);

    // 保存したものを読み直せる。壊れた通信は無視する
    final reloaded = AirBaseStore(load: () => saved);
    expect(reloaded.basesIn(7).first.squadrons.firstWhere((s) => s.id == 3).count, 4);
    store.onApi('/api_get_member/mapinfo', {'api_data': 'broken'}, null);
    expect(store.basesIn(7).length, 2);
  });

  test('base from the app data: only assigned squadrons, full counts, recon multiplier', () {
    final fighter = Equipment(id: 101, itemId: 263, name: '紫電改(三四三空) 戦闘301', type: const [21, 22, 48, 44, 0], aa: 11, evasion: 3, proficiency: 7);
    final recon = Equipment(id: 102, itemId: 311, name: '二式陸上偵察機(熟練)', type: const [17, 34, 49, 59, 0], aa: 3, los: 9);
    final base = AirBaseData.fromApi({
      'api_area_id': 7, 'api_rid': 1, 'api_name': '', 'api_action_kind': 1, //
      'api_plane_info': [squadron(1, 101, 10), squadron(2, 102, 4, max: 4), squadron(3, 999, 18), squadron(4, 0, 0, state: 0)],
    });
    final air = airBaseOf(base, {101: fighter, 102: recon});
    expect(air.name, '第1基地航空隊');
    expect(air.squadrons.map((s) => (s.index, s.count)), [(0, 18), (1, 4)]);
    expect(air.squadrons.first.plane.interception, 3);
    expect(air.reconMultiplier, 1.18);
    expect(airBaseOf(base, {101: fighter, 102: recon}, full: false).squadrons.first.count, 10);
  });
}
