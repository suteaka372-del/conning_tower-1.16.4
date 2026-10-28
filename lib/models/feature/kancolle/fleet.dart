import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../generated/l10n.dart';
import 'constants_poi.dart';
import 'equipment.dart';
import 'ship.dart';

part 'fleet.freezed.dart';

@unfreezed
class Fleet with _$Fleet {
  const Fleet._();

  factory Fleet({
    required List<Ship> ships,
    required Map<int, Equipment> equipment,
    int? combined,
    Set<int>? notInFleetIds,
    Map<int, EquipmentCollection>? equipmentCollections,
  }) = _Fleet;

  String get combinedText => switch (combined) {
        1 => S.current.KCFleetCombinedCarrier,
        2 => S.current.KCFleetCombinedSurface,
        3 => S.current.KCFleetCombinedTransport,
        0 || _ => ""
      };

  Set<int> get shipIds => ships.map((e) => e.shipId).toSet();

  Set<int> get afterShipIds =>
      <int>{for (final ship in ships) ...?ship.afterIds};

  void updateNotInFleetIds(Map<int, List<int>>? shipUpgradeMap) {
    notInFleetIds = {};
    if (shipUpgradeMap == null) return;
    // 持っている艦の一覧は1回だけ作る (以前は確認のたびに全艦から作り直していて、母港に戻るたびに重かった)
    final owned = shipIds;
    for (final e in shipUpgradeMap.entries) {
      if (owned.contains(e.key)) {
        continue;
      }
      bool haveUpgraded = false;
      for (final id in e.value) {
        if (owned.contains(id)) {
          haveUpgraded = true;
          break;
        }
      }
      if (haveUpgraded) continue;
      notInFleetIds?.add(e.key);
    }
  }

  Iterable<Equipment> get uncountedEquipments =>
      equipment.values.where((e) => kUncountedSlotitemId.contains(e.itemId));

  void initEquipmentCollections(Iterable<Equipment> equipments) {
    equipmentCollections ??= {};

    // 装備の種類ごとにまとめる。1回たどるだけにする (以前は種類ごとに全装備をたどり直していて、
    // 渡されるのが作りながら読む一覧なので、そのたびに全装備を作り直していた)
    final byItem = <int, List<Equipment>>{};
    for (final e in equipments) {
      (byItem[e.itemId!] ??= []).add(e);
    }
    for (final MapEntry(key: itemId, value: subEquipments) in byItem.entries) {
      final first = subEquipments.first;
      equipmentCollections?[itemId] = EquipmentCollection(
        id: first.itemId!,
        type: first.type!,
        sortNo: first.sortNo!,
        name: first.name ?? "Item ${first.itemId}",
        equipments: subEquipments,
      );
    }
  }
}
