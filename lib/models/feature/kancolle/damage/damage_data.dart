// ダメージシミュレーターに渡すデータを作る (味方: アプリの艦隊、敵: KCNav の敵編成 + 深海棲艦データ + マスターデータ)。

import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/air/air_data.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';

import 'damage_attacks.dart';

export 'damage_attacks.dart';

DamageEquip damageEquipOf(Equipment e, {int count = 0, int slot = 0}) {
  final type = e.type ?? const <int>[];
  return DamageEquip(
    itemId: e.itemId ?? 0,
    name: e.name ?? '',
    category: type.length > 2 ? type[2] : 0,
    icon: type.length > 3 ? type[3] : 0,
    firepower: e.firepower ?? 0,
    torpedo: e.torpedo ?? 0,
    bombing: e.bomber ?? 0,
    asw: e.asw ?? 0,
    los: e.los ?? 0,
    aa: e.aa ?? 0,
    armor: e.armor ?? 0,
    improvement: e.level ?? 0,
    proficiency: e.proficiency ?? 0,
    count: count,
    slot: slot,
  );
}

/// アプリの艦1隻 → ダメージシミュレーター用。[full] なら耐久満タン・無傷として計算する
DamageShip damageShipOf(Ship ship, {bool full = true}) {
  final equipment = ship.equipment ?? const <Equipment>[];
  final onSlot = ship.onSlot ?? const <int>[];
  final equips = [
    for (final (i, e) in equipment.indexed) damageEquipOf(e, count: i < onSlot.length ? onSlot[i] : 0, slot: i),
    for (final e in ship.exEquipment ?? const <Equipment>[]) damageEquipOf(e, slot: -1),
  ];
  int first(List<int>? values) => (values?.isNotEmpty ?? false) ? values!.first : 0;
  final torpedo = first(ship.attackT);
  final asw = first(ship.antiSubmarine);
  return DamageShip(
    name: ship.name ?? '',
    shipId: ship.shipId,
    shipType: ship.shipType ?? 0,
    level: ship.level,
    hp: full ? ship.maxHP : ship.nowHP,
    maxHp: ship.maxHP,
    armor: first(ship.armor).toDouble(),
    firepower: first(ship.attack),
    torpedo: torpedo,
    asw: asw,
    nakedTorpedo: torpedo - equips.fold(0, (s, e) => s + e.torpedo),
    nakedAsw: asw - equips.fold(0, (s, e) => s + e.asw),
    equips: equips,
  );
}

/// アプリの艦隊 → ダメージシミュレーター用 (退避した艦は除く)
List<DamageShip> damageFleetOf(Squad squad, {bool full = true}) => [
      for (final ship in squad.ships)
        if (ship.escape != true) damageShipOf(ship, full: full),
    ];

/// 敵の1隻 → ダメージシミュレーター用 (深海棲艦データに無ければ null)
DamageShip? damageEnemyOf(
  EnemyShipEntry entry, {
  required AbyssalTable abyssal,
  required Map<int, GetDataApiDataApiMstSlotitemEntity> slotItems,
  Map<int, GetDataApiDataApiMstShipEntity>? shipInfo,
}) {
  final stats = abyssal.stats[entry.id];
  if (stats == null) return null;
  final slots = abyssal.slotsOf(entry.id);
  final equips = <DamageEquip>[];
  for (final (i, itemId) in entry.equips.indexed) {
    final item = slotItems[itemId];
    if (itemId <= 0 || item == null) continue;
    final type = item.apiType;
    equips.add(DamageEquip(
      itemId: itemId,
      name: item.apiName,
      category: type.length > 2 ? type[2] : 0,
      icon: type.length > 3 ? type[3] : 0,
      firepower: item.apiHoug,
      torpedo: item.apiRaig,
      bombing: item.apiBaku,
      asw: item.apiTais,
      los: item.apiSaku,
      aa: item.apiTyku,
      armor: item.apiSouk,
      count: i < slots.length ? slots[i] : 0,
      slot: i,
    ));
  }
  int sum(int Function(DamageEquip e) f) => equips.fold(0, (s, e) => s + f(e));
  return DamageShip(
    name: abyssalName(entry.id, shipInfo),
    shipId: entry.id,
    shipType: shipInfo?[entry.id]?.apiStype ?? 0,
    hp: stats.hp,
    maxHp: stats.hp,
    armor: (stats.armor + sum((e) => e.armor)).toDouble(),
    firepower: stats.firepower + sum((e) => e.firepower),
    torpedo: stats.torpedo + sum((e) => e.torpedo),
    asw: stats.asw + sum((e) => e.asw),
    nakedTorpedo: stats.torpedo,
    nakedAsw: stats.asw,
    equips: equips,
    enemy: true,
    installType: stats.installType,
    pt: stats.flags & 1 != 0,
    supplyDepot: stats.flags & 2 != 0,
    nightCarrier: stats.flags & 4 != 0,
  );
}

/// 敵編成 → ダメージシミュレーター用 (データの無い艦は除く)
List<DamageShip> damageEnemyFleetOf(
  EnemyComp comp, {
  required AbyssalTable abyssal,
  required Map<int, GetDataApiDataApiMstSlotitemEntity> slotItems,
  Map<int, GetDataApiDataApiMstShipEntity>? shipInfo,
}) =>
    [
      for (final entry in comp.ships)
        if (damageEnemyOf(entry, abyssal: abyssal, slotItems: slotItems, shipInfo: shipInfo) case final ship?) ship,
    ];
