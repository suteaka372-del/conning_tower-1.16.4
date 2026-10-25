import 'package:conning_tower/models/feature/kancolle/compass/compass_log.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';
import 'package:flutter_test/flutter_test.dart';

import 'compass_helpers.dart';

void main() {
  test('World 5 maps are there (5-6 has three gauges)', () {
    final names = {for (final m in kCompassMaps) m.name};
    expect(names, containsAll(['5-1', '5-2', '5-3', '5-4', '5-5', '5-6']));
    expect([for (final m in compassMapsOf(56)) m.boss], ['G', 'N', 'Z']);
    expect(compassMapOf(55)?.boss, 'S');
  });

  test('5-2: 祥鳳 and 夕張 open the D→G way', () {
    final f = fleet([kCVL, kCL, kDD, kDD, kCA, kCA], names: ['祥鳳改', '夕張改二']);
    final result = simulateCompass(mapNamed('5-2'), f);
    expect(result.reach['G'], closeTo(1, 1e-9));
    expect(result.bossProbability, closeTo(1, 1e-9));
    // 名前がないと D→F で索敵次第
    final plain = fleet([kCVL, kCL, kDD, kDD, kCA, kCA], los: 50);
    expect(simulateCompass(mapNamed('5-2'), plain).reach['F'], closeTo(1, 1e-9));
    expect(boss('5-2', plain), 0);
  });

  test('5-4: a submarine makes the M→P share 0.7 times', () {
    final f = fleet([kSS, kCL, kDD, kDD, kDD, kCA], los: 50);
    final outcome = mapNamed('5-4').decide('M', f)!;
    expect(outcome.probabilityOf('P'), closeTo(0.7, 1e-9));
    expect(outcome.estimated, isFalse);
    expect(mapNamed('5-4').decide('M', fleet([kSS], los: 43))!.probabilityOf('P'), closeTo(0.35, 1e-9));
  });

  test('5-5: the M↔N loop ends because of the nodes already passed', () {
    // 戦艦4 駆逐1 軽巡1 (ドラム缶4隻): Start→A→C→E→G→I→M→L→N→O→S
    final f = fleet([kBB, kBB, kBB, kBB, kDD, kCL], drumShips: 4, los: 70);
    final result = simulateCompass(mapNamed('5-5'), f);
    for (final node in ['A', 'I', 'M', 'L', 'N', 'O']) {
      expect(result.reach[node], closeTo(1, 1e-9), reason: node);
    }
    expect(result.steps.firstWhere((s) => s.node == 'N').outcome.reason, 'Mマスを通ってきた');
    expect(result.bossProbability, closeTo(1, 1e-9));
    expect(boss('5-5', fleet([kBB, kBB, kBB, kBB, kDD, kCL], drumShips: 4, los: 50)), 0);
  });

  test('5-6: start point and gauges', () {
    final light = fleet([kCL, kDD, kDD, kDD, kCA, kCA]);
    // 第1ゲージ (出撃地点2が開く前) はいつも出撃地点1
    expect(simulateCompass(mapNamed('5-6', 0), light).reach['Start 1'], 1);
    // 第2ゲージ: 出撃地点2 → I (能動分岐で J) → K → L (索敵は不明なので推定)
    final second = simulateCompass(mapNamed('5-6', 1), light);
    expect(second.reach['Start 2'], 1);
    expect(second.reach['J'], closeTo(1, 1e-9));
    expect(second.bossProbability, closeTo(0.75, 1e-9));
    expect(second.estimated, isTrue);
    // 第3ゲージ: I で O、O で Q を選ぶ → W → X
    final third = simulateCompass(mapNamed('5-6', 2), light);
    expect(third.reach['Q'], closeTo(1, 1e-9));
    expect(third.bossProbability, closeTo(0.75, 1e-9));
    // 戦艦2隻と低速の艦は出撃地点1
    expect(simulateCompass(mapNamed('5-6', 2), fleet([kBB, kBB, kDD, kDD, kDD, kDD], speed: 5)).reach['Start 1'], 1);
  });

  test('sortie log on 5-6: the start point is filled in, any gauge can match', () {
    String? saved;
    final recorder = CompassRecorder(load: () => saved, save: (json) => saved = json);
    // 出撃地点1: 最初に来る番号は Start 1→A (3)。手前の出撃地点1を足す
    final slow = fleet([kBB, kBB, kDD, kDD, kDD, kDD], speed: 5);
    recorder.onMapPoint(mapId: 56, cell: 3, start: true, fleet: () => slow);
    recorder.onMapPoint(mapId: 56, cell: 13, start: false); // A→B
    expect(recorder.entries.first.route, 'Start→Start 1→A→B');
    expect(recorder.entries.first.mismatch, isFalse);

    // 出撃地点2 (35) → I (20) → O (28, 能動分岐なのでどちらでも予測どおり)
    final light = fleet([kCL, kDD, kDD, kDD, kCA, kCA]);
    recorder.onMapPoint(mapId: 56, cell: 35, start: true, fleet: () => light);
    recorder.onMapPoint(mapId: 56, cell: 20, start: false);
    recorder.onMapPoint(mapId: 56, cell: 28, start: false);
    expect(recorder.entries.first.route, 'Start→Start 2→I→O');
    expect(recorder.entries.first.mismatch, isFalse);
  });
}
