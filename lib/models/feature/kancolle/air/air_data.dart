// 制空権シミュレーターに渡すデータを作る。
// - 味方: アプリが持っている艦隊 (艦・装備・搭載数・熟練度・改修値)
// - 敵: KCNav (https://tsunkit.net/nav/) の敵編成 (アプリには同梱せず、その場で取得する) と、
//   深海棲艦の素の対空値・搭載数 (KC3Kai/kancolle-replay、MIT License。data ブランチの airsim/abyssal.json)、
//   深海棲艦の装備の性能 (ゲームのマスターデータ)

import 'dart:convert';
import 'dart:math';

import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/anti_air_cut_in.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';

import 'air_engine.dart';

export 'air_engine.dart';

/// 深海棲艦データの取得先 (GitHub Actions「Development stats」が毎日作る)
const kAirAbyssalUrl = 'https://raw.githubusercontent.com/suteaka372-del/conning_tower-1.16.4/data/airsim/abyssal.json';

/// 対空の計算に使う装備1つ
class AirAaEquip {
  final int itemId;

  /// 種類 (api_type[2])
  final int category;

  /// アイコン (api_type[3]。16 = 高角砲)
  final int icon;
  final int aa;
  final int improvement;

  const AirAaEquip({required this.itemId, required this.category, required this.icon, required this.aa, this.improvement = 0});

  factory AirAaEquip.of(Equipment e) => AirAaEquip(
        itemId: e.itemId ?? 0,
        category: (e.type?.length ?? 0) > 2 ? e.type![2] : 0,
        icon: (e.type?.length ?? 0) > 3 ? e.type![3] : 0,
        aa: e.aa ?? 0,
        improvement: e.level ?? 0,
      );

  bool get _aaGun => category == 21;
  bool get _highAngle => icon == 16;
  bool get _director => category == 36;
  bool get _radar => const {12, 13, 93}.contains(category);

  /// 加重対空の装備倍率 (機銃6 / 高角砲・高射装置4 / 電探3)
  int get weightMultiplier => _aaGun ? 6 : (_highAngle || _director ? 4 : (_radar ? 3 : 0));

  /// 加重対空の改修係数
  double get weightImprovement {
    if (_aaGun) return aa >= 8 ? 6 : 4;
    if (_highAngle) return aa >= 8 ? 3 : 2;
    if (_director) return 2;
    return 0;
  }

  /// 艦隊防空の装備倍率 (三式弾0.6 / 電探0.4 / 高角砲・高射装置0.35 / 46cm三連装砲0.25 / その他0.2)
  double get fleetMultiplier {
    if (category == 18) return 0.6;
    if (_radar) return 0.4;
    if (_highAngle || _director) return 0.35;
    if (const {6, 276}.contains(itemId)) return 0.25;
    return 0.2;
  }

  /// 艦隊防空の改修係数
  double get fleetImprovement {
    if (_highAngle) return aa >= 8 ? 3 : 2;
    if (_director) return 2;
    if (_radar && aa > 0) return 1.5;
    return 0;
  }
}

/// 味方の加重対空値: A × [X / A] (X = 素対空 + Σ(装備倍率×装備対空 + 改修係数×√★) + 0.75×装備ボーナス、A = 装備なし1・ありなら2)
int airOwnWeightedAa(num nakedAa, List<AirAaEquip> equips, {num bonusAa = 0}) {
  var x = nakedAa + 0.75 * bonusAa;
  for (final e in equips) {
    x += e.weightMultiplier * e.aa + e.weightImprovement * sqrt(max(0, e.improvement));
  }
  final a = equips.isEmpty ? 1 : 2;
  return a * (x / a).floor();
}

/// 敵の加重対空値: 2 × [√(素対空 + 装備対空)] + Σ(装備倍率×装備対空)
int airEnemyWeightedAa(int baseAa, List<AirAaEquip> equips) {
  final equipAa = equips.fold(0, (sum, e) => sum + e.aa);
  final weighted = equips.fold(0, (sum, e) => sum + e.weightMultiplier * e.aa);
  return 2 * sqrt(max(0, baseAa + equipAa)).floor() + weighted;
}

/// 艦隊対空ボーナス値: [Σ(装備倍率×装備対空 + 改修係数×√★) + 0.5×装備ボーナス]
int airFleetAaBonus(List<AirAaEquip> equips, {num bonusAa = 0}) {
  var total = 0.5 * bonusAa;
  for (final e in equips) {
    total += e.fleetMultiplier * e.aa + e.fleetImprovement * sqrt(max(0, e.improvement));
  }
  return total.floor();
}

/// アプリの艦1隻 → シミュレーター用
AirShip airShipOf(Ship ship, {int? shipClass}) {
  final equipment = ship.equipment ?? const <Equipment>[];
  final all = [...equipment, ...?ship.exEquipment];
  final slots = <AirSlot>[];
  for (final (i, e) in equipment.indexed) {
    final category = (e.type?.length ?? 0) > 2 ? e.type![2] : 0;
    final count = (ship.onSlot != null && i < ship.onSlot!.length) ? ship.onSlot![i] : 0;
    if (!kAirPlaneCategories.contains(category) || count <= 0) continue;
    slots.add(AirSlot(
      i,
      AirPlane(
        itemId: e.itemId ?? 0,
        name: e.name ?? '',
        category: category,
        aa: e.aa ?? 0,
        improvement: e.level ?? 0,
        proficiency: e.proficiency ?? 0,
      ),
      count,
    ));
  }
  final equips = [for (final e in all) AirAaEquip.of(e)];
  // 艦の対空値 (api_taiku) は装備の対空と装備ボーナスを含むので、装備の分を引いて素の対空とする
  // (装備ボーナスは分けられないので素の対空に含めて計算する。差は装備ボーナスの 1/4 程度)
  final total = (ship.antiAircraft?.isNotEmpty ?? false) ? ship.antiAircraft![0] : 0;
  final naked = max(0, total - equips.fold(0, (sum, e) => sum + e.aa));
  return AirShip(
    name: ship.name ?? '',
    shipType: ship.shipType ?? 0,
    slots: slots,
    weightedAa: airOwnWeightedAa(naked, equips),
    fleetAaBonus: airFleetAaBonus(equips),
    aaci: [
      for (final chance in shipAntiAirCutIns(ship, shipClass: shipClass).chances)
        AirAaci(
          kind: chance.kind.id,
          fixedBonus: chance.kind.fixedBonus,
          variableBonus: chance.kind.variableBonus,
          rate: chance.kind.rate ?? 0,
        ),
    ],
    submarine: const {13, 14}.contains(ship.shipType),
  );
}

/// アプリの艦隊 → シミュレーター用 (退避した艦は除く)
AirFleet ownAirFleet(Squad squad, {Map<int, GetDataApiDataApiMstShipEntity>? shipInfo, int formation = 1}) => AirFleet(
      [
        for (final ship in squad.ships)
          if (ship.escape != true) airShipOf(ship, shipClass: shipInfo?[ship.shipId]?.apiCtype),
      ],
      formation: formation,
    );

/// 深海棲艦の素の対空値と搭載数
class AbyssalTable {
  final Map<int, (int, List<int>)> ships;
  final String updated;

  const AbyssalTable(this.ships, {this.updated = ''});

  int aaOf(int id) => ships[id]?.$1 ?? 0;

  List<int> slotsOf(int id) => ships[id]?.$2 ?? const [];

  bool contains(int id) => ships.containsKey(id);
}

/// data ブランチの airsim/abyssal.json を読む
AbyssalTable parseAbyssalTable(String text) {
  final json = jsonDecode(text) as Map<String, dynamic>;
  final ships = <int, (int, List<int>)>{};
  for (final MapEntry(:key, :value) in (json['ships'] as Map<String, dynamic>).entries) {
    final id = int.tryParse(key);
    if (id == null || value is! List || value.length < 2) continue;
    ships[id] = ((value[0] as num).toInt(), [for (final n in value[1] as List) (n as num).toInt()]);
  }
  return AbyssalTable(ships, updated: '${json['updated'] ?? ''}');
}

/// 敵編成の1隻 (艦ID と、スロット順の装備ID。空きは -1)
class EnemyShipEntry {
  final int id;
  final List<int> equips;

  const EnemyShipEntry(this.id, this.equips);
}

/// 敵編成 (あるマスの1パターン)
class EnemyComp {
  final String node;

  /// KCNav に報告された回数
  final int count;
  final int formation;
  final List<EnemyShipEntry> ships;

  const EnemyComp({required this.node, required this.count, required this.formation, required this.ships});

  /// 同じ編成かどうか (艦と装備が同じ)
  String get key => [formation, for (final s in ships) '${s.id}:${s.equips.join(',')}'].join('|');
}

/// KCNav の enemycomps の結果を読む (随伴艦隊がある場合は後ろに足す)
List<EnemyComp> parseEnemyComps(String text) {
  final json = jsonDecode(text) as Map<String, dynamic>;
  final entries = ((json['result'] as Map<String, dynamic>?)?['entries'] as List?) ?? const [];
  EnemyShipEntry ship(dynamic s) {
    final m = s as Map<String, dynamic>;
    return EnemyShipEntry((m['id'] as num).toInt(), [for (final e in (m['equips'] as List? ?? const [])) (e as num).toInt()]);
  }

  return [
    for (final e in entries.cast<Map<String, dynamic>>())
      EnemyComp(
        node: '${e['node']}',
        count: (e['count'] as num?)?.toInt() ?? 0,
        formation: (e['formation'] as num?)?.toInt() ?? 1,
        ships: [
          for (final s in (e['mainFleet'] as List? ?? const [])) ship(s),
          for (final s in (e['escortFleet'] as List? ?? const [])) ship(s),
        ],
      ),
  ];
}

/// マスごとの敵編成 (多く報告された順)
Map<String, List<EnemyComp>> enemyCompsByNode(List<EnemyComp> comps) {
  final byNode = <String, List<EnemyComp>>{};
  for (final comp in comps) {
    (byNode[comp.node] ??= []).add(comp);
  }
  for (final list in byNode.values) {
    list.sort((a, b) => b.count.compareTo(a.count));
  }
  return byNode;
}

/// 敵の1隻の名前 (空母ヲ級flagship など)
String abyssalName(int id, Map<int, GetDataApiDataApiMstShipEntity>? shipInfo) {
  final info = shipInfo?[id];
  if (info == null) return '深海棲艦 $id';
  final yomi = info.apiYomi;
  return '${info.apiName}${yomi == '-' ? '' : yomi}';
}

/// 敵編成 → シミュレーター用
AirFleet enemyAirFleet(
  EnemyComp comp, {
  required AbyssalTable abyssal,
  required Map<int, GetDataApiDataApiMstSlotitemEntity> slotItems,
  Map<int, GetDataApiDataApiMstShipEntity>? shipInfo,
}) {
  return AirFleet(
    [
      for (final entry in comp.ships)
        () {
          final slotsData = abyssal.slotsOf(entry.id);
          final slots = <AirSlot>[];
          final equips = <AirAaEquip>[];
          for (final (i, itemId) in entry.equips.indexed) {
            final item = slotItems[itemId];
            if (itemId <= 0 || item == null) continue;
            final type = item.apiType;
            final category = type.length > 2 ? type[2] : 0;
            final aa = item.apiTyku;
            equips.add(AirAaEquip(itemId: itemId, category: category, icon: type.length > 3 ? type[3] : 0, aa: aa));
            final count = i < slotsData.length ? slotsData[i] : 0;
            if (kAirPlaneCategories.contains(category) && count > 0) {
              slots.add(AirSlot(i, AirPlane(itemId: itemId, name: item.apiName, category: category, aa: aa), count));
            }
          }
          final stype = shipInfo?[entry.id]?.apiStype ?? 0;
          return AirShip(
            name: abyssalName(entry.id, shipInfo),
            shipType: stype,
            slots: slots,
            weightedAa: airEnemyWeightedAa(abyssal.aaOf(entry.id), equips),
            fleetAaBonus: airFleetAaBonus(equips),
            submarine: const {13, 14}.contains(stype),
          );
        }(),
    ],
    formation: comp.formation,
    enemy: true,
  );
}

/// いちばん制空値の高い編成の番号 (同じなら多く報告された方)
int strongestEnemyComp(List<AirFleet> fleets) {
  var best = 0;
  var bestPower = -1;
  for (final (i, fleet) in fleets.indexed) {
    final power = airFleetPower(fleet);
    if (power > bestPower) {
      best = i;
      bestPower = power;
    }
  }
  return best;
}

/// KCNav から [map] の敵編成を取る URL ([since] 以降の報告。ゲージが複数ある海域は [gauge] 番目のゲージ)
Uri kcnavEnemyCompsUrl(CompassMap map, {required DateTime since, int? gauge}) {
  final edges = [for (final no in map.edges.keys) if (no > 0) no]..sort();
  final d = since.toUtc();
  final start = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return Uri.parse('https://tsunkit.net/api/routing/maps/${map.name}/edges/${edges.join(',')}/enemycomps'
      '?start=$start${gauge == null ? '' : '&minGauge=$gauge&maxGauge=$gauge'}');
}

/// [map] がゲージの複数ある海域なら、何番目のゲージか (1 から)
int? airGaugeOf(CompassMap map) {
  final phases = compassMapsOf(map.mapId);
  if (phases.length <= 1) return null;
  return phases.indexOf(map) + 1;
}
