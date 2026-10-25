import 'package:conning_tower/models/feature/kancolle/compass/compass_log.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';
import 'package:flutter_test/flutter_test.dart';

import 'compass_helpers.dart';

void main() {
  test('World 6-7 maps are there, with a map per gauge', () {
    final names = {for (final m in kCompassMaps) m.name};
    expect(names, containsAll(['6-1', '6-2', '6-3', '6-4', '6-5', '7-1', '7-2', '7-3', '7-4', '7-5']));
    expect([for (final m in compassMapsOf(72)) m.boss], ['G', 'M']);
    expect([for (final m in compassMapsOf(73)) m.boss], ['E', 'P']);
    expect([for (final m in compassMapsOf(75)) m.boss], ['K', 'Q', 'T']);
    expect(kCompassMaps.last.name, '7-5');
  });

  test('7-5: choice nodes follow the selected gauge', () {
    final f = fleet([kCL, kDD, kDD, kDD, kCA, kCA], los: 70);
    final first = simulateCompass(mapNamed('7-5', 0), f);
    expect(first.bossProbability, closeTo(1, 1e-9));
    expect(first.steps.firstWhere((s) => s.node == 'F').outcome.reason, contains('Gマスを選んだ'));
    final second = simulateCompass(mapNamed('7-5', 1), f);
    expect(second.bossProbability, closeTo(1, 1e-9));
    expect(second.steps.firstWhere((s) => s.node == 'F').outcome.reason, contains('Jマスを選んだ'));
    expect(boss('7-5', f, 2), closeTo(1, 1e-9));
    // 索敵58以上63未満は半分 S へ
    expect(boss('7-5', fleet([kCL, kDD, kDD, kDD, kCA, kCA], los: 60), 2), closeTo(0.5, 1e-9));
  });

  test('7-3: the first gauge and the second gauge have different rules', () {
    final small = fleet([kCA, kDD, kDD, kDD], names: ['羽黒', '神風']);
    expect(boss('7-3', small, 0), 1); // A→C→E
    expect(boss('7-3', small, 1), 0); // 第2ゲージでは E で終わり
    final fast = fleet([kCA, kDD, kDD, kDD, kCL], speed: 15, names: ['羽黒改二', '神風改']);
    final result = simulateCompass(mapNamed('7-3', 1), fast);
    expect(result.reach['I'], closeTo(1, 1e-9)); // C→I (高速+ かつ 軽巡+駆逐4隻)
    expect(result.bossProbability, closeTo(1, 1e-9)); // I→J→P
  });

  test('7-4: J depends on the way and on LoS', () {
    final map = mapNamed('7-4');
    final de = fleet([kDE, kDE, kDE, kDD], los: 40);
    expect(map.decide('J', de, path: ['Start', 'C', 'D', 'F'])!.probabilityOf('K'), 1);
    expect(map.decide('J', de, path: ['Start', 'A', 'B', 'E'])!.probabilityOf('P'), 1);
    expect(map.decide('J', fleet([kDE, kDE, kDE, kDD], los: 35), path: ['Start', 'A', 'B', 'E'])!.probabilityOf('K'), 0.5);
    expect(map.decide('J', fleet([kDE, kDE, kDE, kDD, kDD], los: 40), path: ['Start', 'A', 'B', 'E'])!.probabilityOf('L'), 1);
    expect(boss('7-4', de), 1); // Start→A→B→E→J→P
    expect(simulateCompass(map, fleet([kSS, kSS, kSS, kSS])).reach['C'], 1); // 潜水艦は出撃地点から直接 C
  });

  test('6-4: the 長門改二 and 陸奥改二 pair does not count as two battleships', () {
    final types = [kBB, kBB, kCL, kDD, kDD, kDD];
    expect(simulateCompass(mapNamed('6-4'), fleet(types, names: ['長門改二', '陸奥改二'])).reach['A'], 1);
    expect(simulateCompass(mapNamed('6-4'), fleet(types, names: ['長門改', '陸奥改'])).reach['M'], 1);
  });

  test('sortie log on 7-3: nodes that only the second gauge has are recorded', () {
    String? saved;
    final recorder = CompassRecorder(load: () => saved, save: (json) => saved = json);
    final f = fleet([kCA, kCA, kCA, kDD, kDD, kDD]);
    recorder.onMapPoint(mapId: 73, cell: 1, start: true, fleet: () => f);
    for (final cell in [3, 4, 9]) {
      recorder.onMapPoint(mapId: 73, cell: cell, start: false);
    }
    expect(recorder.entries.first.route, 'Start→A→C→D→G');
    // 第1ゲージなら A→B・D→F の編成だが、第2ゲージの判定と合うので「予測と違う」にはしない
    expect(recorder.entries.first.mismatch, isFalse);
  });
}
