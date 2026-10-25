import 'package:conning_tower/models/feature/kancolle/squad.dart';

import 'compass_engine.dart';
import 'compass_maps_w12.dart';
import 'compass_maps_w34.dart';
import 'compass_maps_w5.dart';
import 'compass_maps_w67.dart';

export 'compass_engine.dart';

/// 羅針盤シミュレーターで使える海域 (ゲージが複数ある海域は、ゲージごとに並ぶ)
final List<CompassMap> kCompassMaps = [...kCompassMapsWorld12, ...kCompassMapsWorld34, ...kCompassMapsWorld5, ...kCompassMapsWorld67];

/// 海域番号 (11 = 1-1) から (ゲージが複数ある海域は最初のゲージ)
CompassMap? compassMapOf(int mapId) {
  for (final map in kCompassMaps) {
    if (map.mapId == mapId) return map;
  }
  return null;
}

/// 海域番号から、その海域のゲージごとの判定すべて
List<CompassMap> compassMapsOf(int mapId) => [
      for (final map in kCompassMaps)
        if (map.mapId == mapId) map,
    ];

// api_mst_slotitem api_type[2]
const _kDrum = 30;
const _kRadars = {12, 13, 93};

/// 分岐条件で「大発動艇系」として数える装備 (api_mst_slotitem api_id)。
/// 大発動艇・特大発動艇・大発動艇(八九式中戦車&陸戦隊)・大発動艇(II号戦車/北アフリカ仕様)・特大発動艇+一式砲戦車・
/// 武装大発・特二式内火艇・特四式内火艇・特四式内火艇改 (Wiki 5-5 の表による。戦車第11連隊や M4A1 DD などは数えない)
const kCompassDaihatsu = {68, 193, 166, 436, 449, 409, 167, 525, 526};

/// アプリの艦隊から、羅針盤の判定用の艦隊を作る (退避した艦は除く)
CompassFleet compassFleetOf(Squad squad, {required int admiralLevel}) {
  final ships = [for (final ship in squad.ships) if (ship.escape != true) ship];
  return CompassFleet(
    [
      for (final ship in ships)
        CompassShip(
          shipType: ship.shipType ?? 0,
          speed: ship.speed ?? 10,
          shipId: ship.shipId,
          name: ship.name ?? '',
          drums: [...?ship.equipment, ...?ship.exEquipment].where((e) => e.type?[2] == _kDrum).length,
          radars: [...?ship.equipment, ...?ship.exEquipment].where((e) => _kRadars.contains(e.type?[2])).length,
          daihatsu: [...?ship.equipment, ...?ship.exEquipment].where((e) => kCompassDaihatsu.contains(e.itemId)).length,
        ),
    ],
    losScore: (coefficient) => squad.los(admiralLevel: admiralLevel, mapModifier: coefficient).total.toDouble(),
  );
}
