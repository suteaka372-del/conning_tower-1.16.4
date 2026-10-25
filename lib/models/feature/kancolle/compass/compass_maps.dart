import 'package:conning_tower/models/feature/kancolle/squad.dart';

import 'compass_engine.dart';
import 'compass_maps_w12.dart';

export 'compass_engine.dart';

/// 羅針盤シミュレーターで使える海域
final List<CompassMap> kCompassMaps = [...kCompassMapsWorld12];

/// 海域番号 (11 = 1-1) から
CompassMap? compassMapOf(int mapId) {
  for (final map in kCompassMaps) {
    if (map.mapId == mapId) return map;
  }
  return null;
}

// api_mst_slotitem api_type[2]
const _kDrum = 30;
const _kRadars = {12, 13, 93};

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
          drums: [...?ship.equipment, ...?ship.exEquipment].where((e) => e.type?[2] == _kDrum).length,
          radars: [...?ship.equipment, ...?ship.exEquipment].where((e) => _kRadars.contains(e.type?[2])).length,
        ),
    ],
    losScore: (coefficient) => squad.los(admiralLevel: admiralLevel, mapModifier: coefficient).total.toDouble(),
  );
}
