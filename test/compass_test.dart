import 'dart:math';

import 'package:conning_tower/models/feature/kancolle/compass/compass_log.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:flutter_test/flutter_test.dart';

CompassFleet fleet(List<int> types, {int speed = 10, double los = 0, int drumShips = 0}) => CompassFleet(
      [
        for (final (i, t) in types.indexed) CompassShip(shipType: t, speed: speed, drums: i < drumShips ? 1 : 0),
      ],
      losScore: (_) => los,
    );

double boss(String map, CompassFleet f) => simulateCompass(kCompassMaps.firstWhere((m) => m.name == map), f).bossProbability;

void main() {
  test('all World 1-2 maps are there', () {
    expect(kCompassMaps.map((m) => m.name), ['1-1', '1-2', '1-3', '1-4', '1-5', '1-6', '2-1', '2-2', '2-3', '2-4', '2-5']);
    expect(compassMapOf(25)?.title, '沖ノ島沖');
    expect(compassMapOf(15)?.letterOf(10), 'J');
  });

  test('rules only lead to connected nodes, every branch point has a rule, shares add up to 1', () {
    final random = Random(1);
    const types = [kDE, kDD, kCL, kCLT, kCA, kCAV, kCVL, kFBB, kBB, kBBV, kCV, kSS, kSSV, kAV, kLHA, kCVB, kAR, kAS, kCT, kAO];
    for (final map in kCompassMaps) {
      final branchPoints = {for (final (from, _) in map.edges.values) from}.where((n) => map.nextOf(n).length > 1);
      for (final node in branchPoints) {
        expect(map.rules.containsKey(node), isTrue, reason: '${map.name} $node has no rule');
      }
      for (final node in map.rules.keys) {
        expect(map.nextOf(node), isNotEmpty, reason: '${map.name} rule for unknown node $node');
      }
      for (var i = 0; i < 3000; i++) {
        final n = 1 + random.nextInt(6);
        // 偏った編成も作る (同じ艦種ばかり)
        final pool = random.nextBool() ? types : [for (var k = 0; k < 3; k++) types[random.nextInt(types.length)]];
        final f = CompassFleet(
          [
            for (var k = 0; k < n; k++)
              CompassShip(
                shipType: pool[random.nextInt(pool.length)],
                speed: const [5, 10, 15, 20][random.nextInt(4)],
                drums: random.nextInt(3),
              ),
          ],
          losScore: (_) => random.nextDouble() * 70,
        );
        for (final node in map.rules.keys) {
          final outcome = map.decide(node, f)!;
          final next = map.nextOf(node);
          for (final option in outcome.options) {
            expect(next, contains(option.node), reason: '${map.name} $node -> ${option.node} (${outcome.reason})');
            expect(option.probability, inInclusiveRange(0, 1));
          }
          final total = outcome.options.fold(0.0, (s, o) => s + o.probability);
          expect(total, closeTo(1, 1e-9), reason: '${map.name} $node (${outcome.reason})');
          expect(outcome.reason, isNotEmpty);
        }
        final result = simulateCompass(map, f);
        expect(result.bossProbability, inInclusiveRange(0, 1 + 1e-9));
      }
    }
  });

  test('1-1: share depends on the fleet size', () {
    expect(boss('1-1', fleet([kDD, kDD, kDD, kDD, kDD, kDD])), closeTo(0.55, 1e-9));
    expect(boss('1-1', fleet([kDD])), closeTo(0.80, 1e-9));
  });

  test('1-2: four fast destroyers go straight to the boss', () {
    final result = simulateCompass(compassMapOf(12)!, fleet([kDD, kDD, kDD, kDD]));
    expect(result.bossProbability, 1);
    expect(result.steps.map((s) => '${s.node}:${s.outcome.reason}'), [
      'Start:(駆逐+海防)ちょうど4隻 かつ 5隻以下',
      'A:高速以上統一',
    ]);
    expect(result.estimated, isFalse);
    // 低速が混ざると (駆逐+海防)4隻 なので E マス寄りのランダム… ではなく 4隻以上なので条件順に判定
    expect(boss('1-2', fleet([kDD, kDD, kDD, kDD], speed: 5)), closeTo(0.65 + 0.35, 1e-9)); // D からも E へ
  });

  test('1-5: small anti-sub fleets reach the boss', () {
    expect(boss('1-5', fleet([kDD, kDD, kDD, kDD])), 1); // A→D→F→G→J
    expect(boss('1-5', fleet([kDE, kDE, kDE])), 1); // 海防艦のみ: D→E→J
    expect(boss('1-5', fleet([kDD, kDD, kDD, kDD, kDD])), 0.5 * 0); // 5隻: D はランダム、E→C→B、F→G→H
    expect(boss('1-5', fleet([kDD, kDD, kSS])), 0); // 潜水艦: F→I
  });

  test('1-6: LoS decides the M branch (coefficient 3)', () {
    // 軽巡1 駆逐5 は G→F→B→N
    expect(boss('1-6', fleet([kCL, kDD, kDD, kDD, kDD, kDD])), 1);
    // 航巡2 駆逐4: Start→C→H→K→M、索敵で J/L (どちらからもゴールへ)
    final f = fleet([kCAV, kCAV, kDD, kDD, kDD, kDD], los: 25);
    final result = simulateCompass(compassMapOf(16)!, f);
    expect(result.reach['L'], 1);
    expect(result.bossProbability, 1);
    expect(result.steps.firstWhere((s) => s.node == 'M').outcome.reason, contains('索敵スコア25.0'));
    expect(simulateCompass(compassMapOf(16)!, fleet([kCAV, kCAV, kDD, kDD, kDD, kDD], los: 31)).reach['J'], 1);
  });

  test('2-5: south route needs LoS 34 at I (coefficient 1)', () {
    final south = [kCL, kDD, kDD, kDD, kDD, kCA];
    expect(boss('2-5', fleet(south, los: 40)), 1); // Start→B→F→E→I→O
    expect(boss('2-5', fleet(south, los: 32)), closeTo(0.5, 1e-9));
    expect(simulateCompass(compassMapOf(25)!, fleet(south, los: 32)).estimated, isTrue);
    expect(boss('2-5', fleet(south, los: 25)), 0);
    // 戦艦を入れると C から (戦艦級で) G、索敵41以上で L、L で 軽巡+駆逐2 なら O
    expect(boss('2-5', fleet([kBB, kBB, kCAV, kCL, kDD, kDD], los: 45)), 1);
  });

  test('sortie log: matches and mismatches against the prediction', () {
    String? saved;
    final recorder = CompassRecorder(load: () => saved, save: (json) => saved = json);
    final dd4 = fleet([kDD, kDD, kDD, kDD]);
    // 1-5: A(1) D(4) F(6) G(7) J(12)
    recorder.onMapPoint(mapId: 15, cell: 1, start: true, fleet: () => dd4);
    for (final cell in [4, 6, 7, 12]) {
      recorder.onMapPoint(mapId: 15, cell: cell, start: false);
    }
    expect(recorder.entries.single.route, 'Start→A→D→F→G→J');
    expect(recorder.entries.single.mismatch, isFalse);
    expect(recorder.entries.single.steps[2].predicted, 1); // D→F は予測どおり

    // 予測と違う進み方 (D→E)
    recorder.onMapPoint(mapId: 15, cell: 1, start: true, fleet: () => dd4);
    recorder.onMapPoint(mapId: 15, cell: 4, start: false);
    recorder.onMapPoint(mapId: 15, cell: 5, start: false);
    final last = recorder.entries.first;
    expect(last.mismatch, isTrue);
    expect(last.steps.last.reason, 'それ以外');

    // 保存したものを読み直せる
    final reloaded = CompassRecorder(load: () => saved);
    expect(reloaded.entries.length, 2);
    expect(reloaded.entries.first.mismatch, isTrue);

    // 対応していない海域は記録しない
    recorder.onMapPoint(mapId: 71, cell: 1, start: true, fleet: () => dd4);
    expect(recorder.entries.length, 2);
  });

  test('fleet from the app data: ship type, speed, drums, LoS', () {
    var uid = 1;
    Ship ship(int type, {int speed = 10, List<Equipment> equipment = const []}) => Ship(
          uid: uid++,
          shipId: 1,
          level: 99,
          nowHP: 30,
          maxHP: 30,
          shipType: type,
          speed: speed,
          scout: [16, 16],
          equipment: equipment,
        );
    final drum = Equipment(id: 100, itemId: 75, type: [0, 0, 30, 25, 0], los: 0);
    final radar = Equipment(id: 101, itemId: 27, type: [0, 0, 12, 11, 0], los: 7);
    final squad = Squad(id: 1, name: '第1艦隊', ships: [
      ship(kCL, equipment: [radar]),
      ship(kDD, speed: 5, equipment: [drum, drum]),
      ship(kDD).copyWith(escape: true), // 退避した艦は数えない
    ]);
    final f = compassFleetOf(squad, admiralLevel: 120);
    expect(f.n, 2);
    expect(f.cl, 1);
    expect(f.anySlow, isTrue);
    expect(f.drumShips, 1);
    expect(f.radarShips, 1);
    expect(f.losScore(1), squad.los(admiralLevel: 120).total.toDouble());
  });
}
