import 'dart:math';

import 'package:conning_tower/models/feature/kancolle/air/air_data.dart';
import 'package:flutter_test/flutter_test.dart';

AirPlane plane(int category, int aa, {int prof = 0, int imp = 0, String name = ''}) =>
    AirPlane(itemId: 1, name: name, category: category, aa: aa, proficiency: prof, improvement: imp);

AirShip carrier(List<(AirPlane, int)> slots, {int weightedAa = 0, int fleetAaBonus = 0, List<AirAaci> aaci = const []}) =>
    AirShip(
      name: 'CV',
      shipType: 11,
      slots: [for (final (i, (p, n)) in slots.indexed) AirSlot(i, p, n)],
      weightedAa: weightedAa,
      fleetAaBonus: fleetAaBonus,
      aaci: aaci,
    );

/// [f] を何度も呼んで、出た値の集合
Set<int> outcomes(int Function(Random r) f, {int tries = 4000}) {
  final r = Random(7);
  return {for (var i = 0; i < tries; i++) f(r)};
}

void main() {
  test('fighter power follows the wiki examples', () {
    // 試製烈風 後期型 (対空10, 熟練度なし) を 24機と12機のスロットに: [10√24] + [10√12] = 48 + 34 = 82
    final f = AirFleet([carrier([(plane(kAirFighter, 10), 24), (plane(kAirFighter, 10), 12)])]);
    expect(airFleetPower(f), 82);
    // 熟練度 >> の艦戦は +25 (√12 + 22)、艦攻は +3 (√12)
    expect(airSlotPower(plane(kAirFighter, 10, prof: 7), 24), (10 * sqrt(24) + sqrt(12) + 22).floor());
    expect(airSlotPower(plane(kAirTorpedoBomber, 0, prof: 7), 18), 3);
    // 水爆は >> で +9 (√12 + 6)
    expect(airSlotPower(plane(kAirSeaplaneBomber, 0, prof: 7), 10), 9);
    // 改修: 艦戦は ★×0.2
    expect(airSlotPower(plane(kAirFighter, 10, imp: 10), 16), (12 * 4.0).floor());
    // 偵察機は制空値に数えない。敵は熟練度なし
    expect(airSlotPower(plane(kAirCarrierRecon, 2, prof: 7), 10), 0);
    expect(airSlotPower(plane(kAirFighter, 10, prof: 7), 24, enemy: true), (10 * sqrt(24)).floor());
  });

  test('air state thresholds', () {
    // 敵 114 → 確保 342 / 優勢 171 / 均衡 77 / 劣勢 39 (KCNav の表示と同じ)
    expect(airPowerNeeded(114), {AirState.supremacy: 342, AirState.superiority: 171, AirState.parity: 77, AirState.denial: 39});
    expect(airStateOf(342, 114), AirState.supremacy);
    expect(airStateOf(341, 114), AirState.superiority);
    expect(airStateOf(171, 114), AirState.superiority);
    expect(airStateOf(170, 114), AirState.parity);
    expect(airStateOf(77, 114), AirState.parity);
    expect(airStateOf(76, 114), AirState.denial);
    expect(airStateOf(39, 114), AirState.denial);
    expect(airStateOf(38, 114), AirState.incapability);
    expect(airStateOf(0, 0), AirState.supremacy); // 敵の制空値 0 なら確保
    expect(airStateOf(10, 0, battle: false), AirState.none);
  });

  test('air combat losses match the wiki ranges', () {
    // 制空権確保: 20機なら 0〜1機、17機以下は落ちない
    expect(outcomes((r) => airOwnStage1Loss(20, AirState.supremacy, jet: false, random: r)), {0, 1});
    expect(outcomes((r) => airOwnStage1Loss(17, AirState.supremacy, jet: false, random: r)), {0});
    // 制空権喪失: 20機なら 5〜11機
    final lost = outcomes((r) => airOwnStage1Loss(20, AirState.incapability, jet: false, random: r));
    expect(lost.reduce(min), 5);
    expect(lost.reduce(max), 11);
    // 噴式機は 0.6 倍 (確保で 28機までは落ちない)
    expect(outcomes((r) => airOwnStage1Loss(28, AirState.supremacy, jet: true, random: r)), {0});
    // 120機・確保の最大は 7機ちょうど (端数のずれがない)
    expect(outcomes((r) => airOwnStage1Loss(120, AirState.supremacy, jet: false, random: r)), {3, 7});
    // 敵機: 確保なら 0〜100%、喪失なら 0〜10%
    final enemyWin = outcomes((r) => airEnemyStage1Loss(40, AirState.supremacy, random: r), tries: 20000);
    expect(enemyWin.reduce(min), 0);
    expect(enemyWin.reduce(max), 40);
    expect(outcomes((r) => airEnemyStage1Loss(40, AirState.incapability, random: r)).reduce(max), 4);
    expect(airOwnStage1Loss(20, AirState.none, jet: false, random: Random(1)), 0);
  });

  test('anti-air fire follows the wiki example (秋月改 vs 180 torpedo bombers)', () {
    // 秋月改 (素対空116) に 10cm連装高角砲+高射装置★6 ×2、13号対空電探改、装備ボーナス 対空+4
    const ha = AirAaEquip(itemId: 122, category: 4, icon: 16, aa: 10, improvement: 6);
    const radar = AirAaEquip(itemId: 106, category: 12, icon: 11, aa: 4);
    const equips = [ha, ha, radar];
    expect(airOwnWeightedAa(116, equips, bonusAa: 4), 224);
    expect(airFleetAaBonus(equips, bonusAa: 4), 25);
    final akizuki = AirShip(name: '秋月改', shipType: 2, slots: const [], weightedAa: 224, fleetAaBonus: 25);
    final fleet = AirFleet([akizuki]);
    expect(fleet.fleetAa, closeTo(38.46, 0.01));
    // 割合撃墜100機・固定撃墜26機・最低保証1機の組み合わせ (25% ずつ)
    expect(outcomes((r) => airOwnAaRemaining(180, akizuki, fleet.fleetAa, null, random: r)), {53, 79, 153, 179});
    // 対空カットイン (固定+7、変動1.7): 固定撃墜44機、最低保証8機
    const aaci = AirAaci(kind: 1, fixedBonus: 7, variableBonus: 1.7, rate: 1);
    expect(outcomes((r) => airOwnAaRemaining(180, akizuki, fleet.fleetAa, aaci, random: r)), {28, 72, 128, 172});
    // 陣形補正 (輪形陣 1.6)
    expect(AirFleet([akizuki], formation: 3).fleetAa, closeTo((1.6 * 25).floor() * 2 / 1.3, 1e-9));
  });

  test('enemy anti-air uses its own formula (no minimum, small effect of base AA)', () {
    const gun = AirAaEquip(itemId: 1540, category: 21, icon: 15, aa: 12);
    expect(airEnemyWeightedAa(40, const [gun]), 2 * sqrt(52).floor() + 6 * 12);
    final enemy = AirFleet([AirShip(name: 'ツ級', shipType: 3, slots: const [], weightedAa: 86, fleetAaBonus: 2)], enemy: true);
    expect(enemy.fleetAa, 4); // [1.0 × 2] × 2
    final ship = enemy.ships.first;
    // 20機: 割合 [86×20/400] = 4機、固定 [(86+4)×0.09375] = 8機、最低保証なし
    expect(outcomes((r) => airEnemyAaRemaining(20, ship, enemy.fleetAa, random: r)), {8, 12, 16, 20});
  });

  test('a battle against a fleet without planes: supremacy, only small losses', () {
    final own = AirFleet([
      carrier([(plane(kAirFighter, 10, prof: 7), 18), (plane(kAirTorpedoBomber, 13, prof: 7), 24)]),
    ]);
    final destroyers = AirFleet([const AirShip(name: '駆逐イ級', shipType: 2, slots: [])], enemy: true);
    final result = simulateAirBattles(own, [destroyers], runs: 2000, seed: 1).single;
    expect(result.states, {AirState.supremacy: 1.0});
    expect(result.enemyPower, 0);
    expect(result.enemyStrikeZero, isNull);
    // 艦戦18機は確保で 0〜1機、艦攻は敵の対空砲火 (加重対空0・艦隊防空0) では落ちない
    final fighter = result.own[0][0];
    expect(fighter.after, inInclusiveRange(17, 18));
    expect(fighter.annihilation, 0);
    expect(result.own[0][1].after, inInclusiveRange(23, 24));
  });

  test('our anti-air can ground an enemy carrier, and planes carry over to the next battle', () {
    const aaci = AirAaci(kind: 1, fixedBonus: 7, variableBonus: 1.7, rate: 0.6);
    final own = AirFleet([
      carrier([(plane(kAirFighter, 12, prof: 7), 30), (plane(kAirFighter, 12, prof: 7), 24)]),
      AirShip(name: '秋月改', shipType: 2, slots: const [], weightedAa: 224, fleetAaBonus: 25, aaci: const [aaci]),
    ]);
    final wo = AirFleet([
      AirShip(name: '軽母ヌ級', shipType: 7, slots: [
        AirSlot(0, plane(kAirFighter, 3), 9),
        AirSlot(1, plane(kAirDiveBomber, 0), 9),
      ]),
    ], enemy: true);
    final results = simulateAirBattles(own, [wo, wo], runs: 3000, seed: 2);
    final first = results.first;
    expect(first.states.keys, [AirState.supremacy]);
    expect(first.enemyGrounded.single, inInclusiveRange(0.3, 1.0));
    expect(first.enemyStrikeZero, first.enemyGrounded.single); // 敵の空母が1隻なら同じ
    expect(first.aaciRate, closeTo(0.6, 0.05));
    expect(first.enemy[0][1].after, lessThan(first.enemy[0][1].afterAirCombat));
    // 2戦目は1戦目のあとの機数から始まる
    expect(results[1].own[0][0].before, closeTo(first.own[0][0].after, 1e-9));
    expect(results[1].ownPower, lessThanOrEqualTo(first.ownPower));
    // 同じ乱数の種なら同じ結果
    final again = simulateAirBattles(own, [wo, wo], runs: 3000, seed: 2);
    expect(again.first.enemyGrounded.single, first.enemyGrounded.single);
  });

  test('heavy enemy anti-air wipes out small attacker slots', () {
    final own = AirFleet([
      carrier([(plane(kAirFighter, 10), 20), (plane(kAirDiveBomber, 0), 3)]),
    ]);
    final tsu = AirShip(name: '軽巡ツ級elite', shipType: 3, slots: const [], weightedAa: 120, fleetAaBonus: 8);
    final enemy = AirFleet([tsu, tsu, tsu], enemy: true, formation: 3);
    final result = simulateAirBattles(own, [enemy], runs: 3000, seed: 3).single;
    // 固定撃墜 [(120 + 76) × 0.09375] = 18機 が 50% で出るので、3機のスロットは半分の確率で全滅
    expect(result.own[0][1].annihilation, closeTo(0.5, 0.03));
    expect(result.own[0][0].after, inInclusiveRange(19, 20)); // 戦闘機は対空砲火で落ちない
  });

  test('without enemy surface ships our bombers do not attack (no AA losses)', () {
    final own = AirFleet([carrier([(plane(kAirTorpedoBomber, 0), 10)])]);
    final subs = AirFleet([
      const AirShip(name: '潜水カ級', shipType: 13, slots: [], weightedAa: 200, fleetAaBonus: 50, submarine: true),
    ], enemy: true);
    final result = simulateAirBattles(own, [subs], runs: 500, seed: 4).single;
    expect(result.own[0][0].after, 10);
  });
}
