import 'dart:math';

import 'package:intl/intl.dart';

import '../../data/kcsapi/start2/get_data_entity.dart';
import 'ship.dart';
import 'squad.dart';

// Anchorage repair (泊地修理) and Nosaki condition repair (母港給糧艦) timers.
// Ported from ElectronicObserver (MIT License, Copyright (c) 2014 Andante)
// https://github.com/dais-k/ElectronicObserver
// FleetManager.cs / FleetData.cs / Utility/Data/Calculator.cs

const int _kShipTypeRepairShip = 19; // 工作艦
const int _kEquipTypeRepairFacility = 31; // 艦艇修理施設
const Set<int> _kNosakiIds = {996, 1002}; // 野埼

const Duration kAnchorageRepairSpan = Duration(minutes: 20);
const Duration kConditionRepairSpan = Duration(minutes: 15);

String repairText(String ja, String en) =>
    Intl.getCurrentLocale().startsWith('ja') ? ja : en;

class AnchorageRepairTarget {
  final int index; // 0-based position in the squad
  final Ship ship;
  final int damage;
  final double dockingSeconds;

  /// HP 50% 以下 (中破以上) は修理されない
  final bool eligible;

  AnchorageRepairTarget({
    required this.index,
    required this.ship,
    required this.damage,
    required this.dockingSeconds,
    required this.eligible,
  });
}

class AnchorageRepairInfo {
  final int bound;
  final bool is1st2ndRepairShip;
  final List<AnchorageRepairTarget> targets;

  AnchorageRepairInfo({
    required this.bound,
    required this.is1st2ndRepairShip,
    required this.targets,
  });
}

class RepairTimerState {
  DateTime? anchorageRepairTimer;
  DateTime? conditionRepairTimer;

  /// ship uid -> api_ndock_time (ms)
  Map<int, int> ndockTime = {};

  /// ship uids in the repair docks
  Set<int> dockingShipIds = {};

  Map<int, int> _prevHP = {};
  Map<int, int> _prevCondition = {};
  Set<int> _prevDockingShipIds = {};
  Map<int, bool> _prevCanAnchorageRepair = {};

  static int _repairFacilityCount(Ship ship) =>
      (ship.equipment ?? [])
          .where((e) => e.type != null && e.type!.length > 2 && e.type![2] == _kEquipTypeRepairFacility)
          .length;

  static bool _isRepairShip(Ship? ship) => ship?.shipType == _kShipTypeRepairShip;

  static bool _isOnExpedition(Squad squad) => (squad.operation ?? 0) != 0;

  bool isDocking(Ship ship) => dockingShipIds.contains(ship.uid);

  static double _hpRate(Ship ship) => ship.maxHP > 0 ? ship.nowHP / ship.maxHP : 0;

  /// 旗艦と2番艦が工作艦で、修理施設を装備しているか (所要時間×0.85)
  static bool is1st2ndRepairShip(Squad squad) {
    final ships = squad.ships;
    if (ships.length < 2) return false;
    return ships.take(2).every((ship) => _isRepairShip(ship) && _repairFacilityCount(ship) > 0);
  }

  /// 泊地修理の対象となる艦数
  static int anchorageRepairBound(Squad squad) {
    final ships = squad.ships;
    if (ships.isEmpty || !_isRepairShip(ships.first)) return 0;
    final flagship = ships.first;
    int bound;
    if (ships.length >= 2 && _isRepairShip(ships[1])) {
      bound = 2 + _repairFacilityCount(flagship) + _repairFacilityCount(ships[1]);
    } else {
      bound = switch (flagship.shipId) {
        182 || 187 => 2 + _repairFacilityCount(flagship), // 明石, 明石改
        958 => _repairFacilityCount(flagship), // 朝日改
        _ => 0,
      };
    }
    return min(bound, ships.length);
  }

  bool canAnchorageRepair(Squad squad) {
    final ships = squad.ships;
    if (ships.isEmpty) return false;
    final flagship = ships.first;
    if (!_isRepairShip(flagship)) return false;
    if (!(_hpRate(flagship) > 0.5)) return false;
    if (isDocking(flagship)) return false;
    if (_isOnExpedition(squad)) return false;
    final bound = anchorageRepairBound(squad);
    if (bound < 1) return false;
    return ships.take(bound).any((ship) {
      final rate = _hpRate(ship);
      return !isDocking(ship) && 0.5 < rate && rate < 1.0;
    });
  }

  static bool hasNosaki(Squad squad) =>
      squad.ships.take(2).any((ship) => _kNosakiIds.contains(ship.shipId));

  bool canConditionRepair(Squad squad, Map<int, GetDataApiDataApiMstShipEntity>? shipInfo) {
    if (_isOnExpedition(squad)) return false;
    final nosakiReady = squad.ships.take(2).any((ship) {
      if (!_kNosakiIds.contains(ship.shipId)) return false;
      final master = shipInfo?[ship.shipId];
      final fuelFull = master?.apiFuelMax == null || (ship.fuel ?? 0) >= master!.apiFuelMax!;
      final bullFull = master?.apiBullMax == null || (ship.bull ?? 0) >= master!.apiBullMax!;
      return _hpRate(ship) > 0.5 &&
          (ship.condition ?? 0) > 30 &&
          !isDocking(ship) &&
          fuelFull &&
          bullFull;
    });
    return nosakiReady && squad.ships.any((ship) => !isDocking(ship));
  }

  AnchorageRepairInfo? anchorageRepairInfo(Squad squad) {
    if (!canAnchorageRepair(squad)) return null;
    final bound = anchorageRepairBound(squad);
    final is1st2nd = is1st2ndRepairShip(squad);
    final targets = <AnchorageRepairTarget>[];
    for (final (index, ship) in squad.ships.take(bound).indexed) {
      final damage = ship.maxHP - ship.nowHP;
      if (damage <= 0 || isDocking(ship)) continue;
      targets.add(AnchorageRepairTarget(
        index: index,
        ship: ship,
        damage: damage,
        dockingSeconds: (ndockTime[ship.uid] ?? 0) / 1000,
        eligible: _hpRate(ship) > 0.5,
      ));
    }
    return AnchorageRepairInfo(bound: bound, is1st2ndRepairShip: is1st2nd, targets: targets);
  }

  /// 指定時間修理したときの回復量 (Calculator.CalculateAnchorageRepairHealAmount)
  static int healAmount(int damage, double dockingSeconds, Duration repairTime, bool is1st2ndRepairShip) {
    if (damage <= 0 || dockingSeconds <= 0) return 0;
    if (is1st2ndRepairShip) dockingSeconds *= 0.85;
    final heal = (repairTime.inMinutes * 60 / (dockingSeconds / damage)).floor();
    return min(max(heal, 1), damage);
  }

  /// 指定量回復するのに必要な時間 (Calculator.CalculateAnchorageRepairTime)
  static Duration repairTime(int damage, double dockingSeconds, int healAmount, bool is1st2ndRepairShip) {
    if (damage <= 0 || healAmount <= 0) return Duration.zero;
    healAmount = min(healAmount, damage);
    if (is1st2ndRepairShip && dockingSeconds > 0) dockingSeconds *= 0.85;
    if (healAmount == 1) return kAnchorageRepairSpan;
    final time = Duration(minutes: (healAmount * dockingSeconds / damage / 60).ceil());
    return time < kAnchorageRepairSpan ? kAnchorageRepairSpan : time;
  }

  /// api_port/port の処理前に呼ぶ (FleetManager.EvacuatePreviousShips)
  void evacuate(List<Squad> squads, List<Ship> ships) {
    _prevHP = {for (final ship in ships) ship.uid: ship.nowHP};
    _prevCondition = {for (final ship in ships) ship.uid: ship.condition ?? 0};
    _prevDockingShipIds = {...dockingShipIds};
    _prevCanAnchorageRepair = {for (final squad in squads) squad.id: canAnchorageRepair(squad)};
  }

  /// api_port/port の処理後に呼ぶ
  void onPort(List<Squad> squads, Map<int, GetDataApiDataApiMstShipEntity>? shipInfo) {
    final now = DateTime.now();

    final conditionTimer = conditionRepairTimer;
    if (conditionTimer == null || now.difference(conditionTimer) >= kConditionRepairSpan) {
      conditionRepairTimer = now;
    } else if (_detectConditionHealing(squads, shipInfo)) {
      conditionRepairTimer = now;
    }

    final anchorageTimer = anchorageRepairTimer;
    if (anchorageTimer == null || now.difference(anchorageTimer) >= kAnchorageRepairSpan) {
      anchorageRepairTimer = now;
    } else if (_detectAnchorageHealing(squads)) {
      anchorageRepairTimer = now;
    }
  }

  bool _detectAnchorageHealing(List<Squad> squads) {
    for (final squad in squads) {
      if (_prevCanAnchorageRepair[squad.id] == false) continue;
      for (final ship in squad.ships) {
        if (_prevDockingShipIds.contains(ship.uid)) continue;
        final prev = _prevHP[ship.uid];
        if (prev != null && prev < ship.nowHP) return true;
      }
    }
    return false;
  }

  bool _detectConditionHealing(List<Squad> squads, Map<int, GetDataApiDataApiMstShipEntity>? shipInfo) {
    for (final squad in squads) {
      if (!canConditionRepair(squad, shipInfo)) continue;
      for (final ship in squad.ships) {
        if (_prevCondition[ship.uid] == 49 && (ship.condition ?? 0) > 49) return true;
      }
    }
    return false;
  }

  /// api_req_hensei/change の処理後に呼ぶ
  void onHenseiChange(Squad squad, int shipId) {
    if (shipId == -2) return; // 随伴艦一括解除を除く
    if (squad.ships.isNotEmpty && _isRepairShip(squad.ships.first)) {
      anchorageRepairTimer = DateTime.now();
    }
    if (hasNosaki(squad)) {
      conditionRepairTimer = DateTime.now();
    }
  }
}
