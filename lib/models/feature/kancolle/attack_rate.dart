import 'dart:math';

import '../../data/kcsapi/start2/get_data_entity.dart';
import 'equipment.dart';
import 'ship.dart';
import 'squad.dart';

// Day/night special attack kinds and trigger rates.
// Ported from ElectronicObserver (MIT License, Copyright (c) 2014 Andante)
// https://github.com/dais-k/ElectronicObserver
// Utility/Data/Calculator2.cs (GetDayAttackKindList / GetNightAttackKindList)
// Window/Dialog/DialogShipAttackDetail.cs (昼戦発動率 / 夜戦発動率)

// api_mst_slotitem api_type[2]
const _kMainGunSmall = 1;
const _kMainGunMedium = 2;
const _kMainGunLarge = 3;
const _kSecondaryGun = 4;
const _kTorpedo = 5;
const _kCarrierBasedFighter = 6;
const _kCarrierBasedBomber = 7;
const _kCarrierBasedTorpedo = 8;
const _kSeaplaneRecon = 10;
const _kSeaplaneBomber = 11;
const _kRadarSmall = 12;
const _kRadarLarge = 13;
const _kAPShell = 19;
const _kSearchlight = 29;
const _kTransportContainer = 30;
const _kSubmarineTorpedo = 32;
const _kStarShell = 33;
const _kAviationPersonnel = 35;
const _kMainGunLarge2 = 38;
const _kSurfaceShipPersonnel = 39;
const _kSearchlightLarge = 42;
const _kSpecialAmphibiousTank = 46;
const _kSubmarineEquipment = 51;
const _kJetFighter = 56;
const _kJetBomber = 57;
const _kRadarLarge2 = 93;
const _kSecondaryGun2 = 95;

// api_stype
const _kDestroyer = 2;
const _kLightCruiser = 3;
const _kTorpedoCruiser = 4;
const _kAviationCruiser = 6;
const _kLightAircraftCarrier = 7;
const _kAviationBattleship = 10;
const _kAircraftCarrier = 11;
const _kSubmarine = 13;
const _kSubmarineAircraftCarrier = 14;
const _kSeaplaneTender = 16;
const _kArmoredAircraftCarrier = 18;

const Set<int> _kLateModelTorpedoIds = {213, 214, 383, 441, 443, 457, 461, 512};
const Set<int> _kNightAirAttackCarrierIds = {545, 599, 610, 883, 1008, 1036};
const Set<int> _kNightShellingCarrierIds = {
  432, 353, 433, 735, 966, 1025, 1030, 646, 889, 536, 529, 1055, 1060, 1061
};

enum DayAttackKind {
  zuiunMultiAngle('瑞雲立体攻撃', 120),
  seaAirMultiAngle('海空立体攻撃', 130),
  cutinMainMain('カットイン(主砲/主砲)', 150),
  cutinMainAP('カットイン(主砲/徹甲)', 140),
  cutinMainRadar('カットイン(主砲/電探)', 130),
  cutinMainSub('カットイン(主砲/副砲)', 120),
  doubleShelling('連続射撃', 130),
  cutinJetFighterJetBomberJetBomber('空母カットイン(jFjBjB)', 135),
  cutinJetFighterJetBomber('空母カットイン(jFjB)', 125),
  cutinJetFighterBomberAttacker('空母カットイン(jFBA)', 115),
  cutinFighterBomberAttacker('空母カットイン(FBA)', 125),
  cutinBomberBomberAttacker('空母カットイン(BBA)', 140),
  cutinBomberAttacker('空母カットイン(BA)', 155),
  shelling('砲撃', null),
  airAttack('空撃', null);

  const DayAttackKind(this.label, this.coefficient);

  final String label;

  /// 種別係数 (null = 通常攻撃、残りの確率すべて)
  final int? coefficient;
}

enum NightAttackKind {
  cutinNightAirAttackFFA('夜襲カットイン(戦戦攻)', 105),
  cutinNightAirAttackFA('夜襲カットイン(戦攻)', 120),
  cutinNightAirAttackFS('夜襲カットイン(戦彗)', 120),
  cutinNightAirAttackAS('夜襲カットイン(攻彗)', 120),
  cutinNightAirAttackFB('夜襲カットイン(戦爆)', 120),
  cutinNightAirAttackAB('夜襲カットイン(攻爆)', 120),
  cutinNightAirAttackBS('夜襲カットイン(爆彗)', 120),
  cutinNightAirAttackFOther('夜襲カットイン(戦他他)', 130),
  nightAirAttack('夜間航空攻撃', null),
  nightSwordfish('Swordfish', null),
  cutinTorpedoMasterPicketSubmarine('潜水艦カットイン(電探/魚雷/魚雷)', 105),
  cutinTorpedoTorpedoSubmarine('潜水艦カットイン(魚雷/魚雷/魚雷)', 110),
  specialNightZuiun2Radar('夜間瑞雲攻撃(瑞雲2/電探)', 135),
  specialNightZuiun2('夜間瑞雲攻撃(瑞雲2)', 135),
  specialNightZuiunRadar('夜間瑞雲攻撃(瑞雲/電探)', 135),
  specialNightZuiun('夜間瑞雲攻撃', 135),
  cutinTorpedoRadar('駆逐カットイン(主砲/魚雷/電探)', 115),
  cutinTorpedoPicket('駆逐カットイン(魚雷/見張員/電探)', 140),
  cutinTorpedoTorpedoMasterPicket('駆逐カットイン(魚雷/魚雷/水雷見張員)', 126),
  cutinTorpedoDrumMasterPicket('駆逐カットイン(魚雷/ドラム缶/水雷見張員)', 122),
  cutinMainMain('カットイン(主砲/主砲/主砲)', 140),
  cutinMainSub('カットイン(主砲/主砲/副砲)', 130),
  cutinTorpedoTorpedo('カットイン(魚雷/魚雷/魚雷)', 122),
  cutinMainTorpedo('カットイン(主砲/魚雷)', 115),
  doubleShelling('連続射撃', null),
  shelling('砲撃', null),
  normalAttack('通常攻撃', null);

  const NightAttackKind(this.label, this.coefficient);

  final String label;

  /// 種別係数 (null = カットイン以外)
  final int? coefficient;
}

class AttackRate<T> {
  final T kind;

  /// 発動率[%] 昼戦は制空権確保時、夜戦はそのまま
  final double rate;

  /// 昼戦の制空権優勢時の発動率[%] (夜戦では null)
  final double? rateAS;

  AttackRate(this.kind, this.rate, [this.rateAS]);
}

class ShipAttackRates {
  final List<AttackRate<DayAttackKind>> day;
  final List<AttackRate<NightAttackKind>> night;
  final bool canAttackAtNight;

  ShipAttackRates({required this.day, required this.night, required this.canAttackAtNight});
}

extension on Equipment {
  int get category => (type != null && type!.length > 2) ? type![2] : -1;

  int get icon => (type != null && type!.length > 3) ? type![3] : -1;

  bool get isNightFighter => icon == 45;

  bool get isNightAttacker => icon == 46;

  bool get isNightBomber => icon == 58;

  bool get isNightZuiun => icon == 51;

  bool get isNightPhotocellBomber => itemId == 320;

  bool get isSwordfish => category == _kCarrierBasedTorpedo && (name ?? '').contains('Swordfish');

  bool get isRadar => category == _kRadarSmall || category == _kRadarLarge || category == _kRadarLarge2;

  bool get isSurfaceRadar => isRadar && (los ?? 0) >= 5;

  bool get isNightAviationPersonnel => itemId == 258 || itemId == 259;

  bool get isNightAircraftTypeA => isNightFighter || isNightAttacker || isNightBomber;
}

class AttackRateCalculator {
  AttackRateCalculator._();

  static List<Equipment> _allSlot(Ship ship) => [...?ship.equipment, ...?ship.exEquipment];

  static bool _isCarrier(int? shipType) =>
      shipType == _kLightAircraftCarrier || shipType == _kAircraftCarrier || shipType == _kArmoredAircraftCarrier;

  static bool _isSubmarine(int? shipType) => shipType == _kSubmarine || shipType == _kSubmarineAircraftCarrier;

  static double _hpRate(Ship ship) => ship.maxHP > 0 ? ship.nowHP / ship.maxHP : 0;

  static List<DayAttackKind> dayAttackKinds(Ship ship) {
    int reconCount = 0,
        mainGunCount = 0,
        subGunCount = 0,
        apShellCount = 0,
        radarCount = 0,
        attackerCount = 0,
        bomberCount = 0,
        jetBomberCount = 0,
        suisei634Count = 0,
        zuiunCount = 0,
        fighterCount = 0,
        jetFighterCount = 0;
    final slot = _allSlot(ship);

    for (final eq in slot) {
      switch (eq.category) {
        case _kMainGunSmall || _kMainGunMedium || _kMainGunLarge || _kMainGunLarge2:
          mainGunCount++;
        case _kSecondaryGun || _kSecondaryGun2:
          subGunCount++;
        case _kJetBomber:
          jetBomberCount++;
        case _kJetFighter:
          jetFighterCount++;
        case _kCarrierBasedBomber:
          bomberCount++;
          if ((eq.name ?? '').contains('六三四空')) suisei634Count++;
        case _kCarrierBasedTorpedo:
          attackerCount++;
        case _kCarrierBasedFighter:
          fighterCount++;
        case _kSeaplaneRecon || _kSeaplaneBomber:
          reconCount++;
          if ((eq.name ?? '').contains('瑞雲')) zuiunCount++;
        case _kRadarSmall || _kRadarLarge || _kRadarLarge2:
          radarCount++;
        case _kAPShell:
          apShellCount++;
      }
    }

    final list = <DayAttackKind>[];
    final shipId = ship.shipId;

    if (shipId == 553 || shipId == 554) {
      // 伊勢改二・日向改二
      if (mainGunCount >= 1 && zuiunCount >= 2) list.add(DayAttackKind.zuiunMultiAngle);
      if (mainGunCount >= 1 && suisei634Count >= 2) list.add(DayAttackKind.seaAirMultiAngle);
    }

    if (reconCount > 0) {
      if (mainGunCount >= 2 && apShellCount >= 1) list.add(DayAttackKind.cutinMainMain);
      if (mainGunCount >= 1 && subGunCount >= 1 && apShellCount >= 1) list.add(DayAttackKind.cutinMainAP);
      if (mainGunCount >= 1 && subGunCount >= 1 && radarCount >= 1) list.add(DayAttackKind.cutinMainRadar);
      if (mainGunCount >= 1 && subGunCount >= 1) list.add(DayAttackKind.cutinMainSub);
      if (mainGunCount >= 2) list.add(DayAttackKind.doubleShelling);
    }

    if (bomberCount + attackerCount + jetFighterCount + jetBomberCount > 0) {
      if (jetFighterCount >= 1 && jetBomberCount >= 2) list.add(DayAttackKind.cutinJetFighterJetBomberJetBomber);
      if (jetFighterCount >= 1 && jetBomberCount >= 1) list.add(DayAttackKind.cutinJetFighterJetBomber);
      if (jetFighterCount >= 1 && bomberCount >= 1 && attackerCount >= 1) {
        list.add(DayAttackKind.cutinJetFighterBomberAttacker);
      }
      if (fighterCount >= 1 && bomberCount >= 1 && attackerCount >= 1) list.add(DayAttackKind.cutinFighterBomberAttacker);
      if (bomberCount >= 2 && attackerCount >= 1) list.add(DayAttackKind.cutinBomberBomberAttacker);
      if (bomberCount >= 1 && attackerCount >= 1) list.add(DayAttackKind.cutinBomberAttacker);
    }

    final isCarrier = _isCarrier(ship.shipType);
    final isSubmarine = _isSubmarine(ship.shipType);
    if (!isCarrier && !isSubmarine) {
      if (shipId == 352) {
        // 速吸改
        list.add(slot.any((eq) => eq.category == _kCarrierBasedTorpedo) ? DayAttackKind.airAttack : DayAttackKind.shelling);
      } else if (shipId == 717 || shipId == 1008) {
        // 山汐丸改・しまね丸改
        list.add(slot.any((eq) => eq.category == _kCarrierBasedBomber) ? DayAttackKind.airAttack : DayAttackKind.shelling);
      } else {
        list.add(DayAttackKind.shelling);
      }
    }
    if (isCarrier && bomberCount + attackerCount + jetBomberCount > 0) list.add(DayAttackKind.airAttack);
    if (isSubmarine && slot.any((eq) => eq.category == _kSpecialAmphibiousTank)) list.add(DayAttackKind.shelling);

    return list;
  }

  static List<NightAttackKind> nightAttackKinds(Ship ship) {
    int mainGunCount = 0,
        subGunCount = 0,
        torpedoCount = 0,
        lateModelTorpedoCount = 0,
        submarineEquipmentCount = 0,
        nightFighterCount = 0,
        nightAttackerCount = 0,
        swordfishCount = 0,
        nightCapableBomberCount = 0,
        nightPcBomberCount = 0,
        nightBomberCount = 0,
        nightPersonnelCount = 0,
        surfaceRadarCount = 0,
        picketCrewCount = 0,
        masterPicketCrewCount = 0,
        drumCount = 0,
        nightZuiunCount = 0;

    for (final eq in _allSlot(ship)) {
      switch (eq.category) {
        case _kMainGunSmall || _kMainGunMedium || _kMainGunLarge || _kMainGunLarge2:
          mainGunCount++;
        case _kSecondaryGun || _kSecondaryGun2:
          subGunCount++;
        case _kTorpedo || _kSubmarineTorpedo:
          torpedoCount++;
          if (_kLateModelTorpedoIds.contains(eq.itemId)) lateModelTorpedoCount++;
        case _kSeaplaneBomber:
          if (eq.isNightZuiun) nightZuiunCount++;
        case _kCarrierBasedFighter:
          if (eq.isNightFighter) nightFighterCount++;
        case _kCarrierBasedBomber:
          if (eq.itemId == 154) {
            nightCapableBomberCount++; // 零戦62型(爆戦/岩井隊)
          } else if (eq.isNightPhotocellBomber) {
            nightPcBomberCount++;
          } else if (eq.isNightBomber) {
            nightBomberCount++;
          }
        case _kCarrierBasedTorpedo:
          if (eq.isNightAttacker) nightAttackerCount++;
          if (eq.isSwordfish) swordfishCount++;
        case _kRadarSmall || _kRadarLarge || _kRadarLarge2:
          if (eq.isSurfaceRadar) surfaceRadarCount++;
        case _kSurfaceShipPersonnel:
          if (eq.itemId == 412) {
            masterPicketCrewCount++; // 水雷戦隊 熟練見張員
          } else {
            picketCrewCount++;
          }
        case _kAviationPersonnel:
          if (eq.isNightAviationPersonnel) nightPersonnelCount++;
        case _kSubmarineEquipment:
          submarineEquipmentCount++;
        case _kTransportContainer:
          if (eq.itemId == 75) drumCount++;
      }
    }

    final shipId = ship.shipId;
    final shipType = ship.shipType;
    if (_kNightAirAttackCarrierIds.contains(shipId)) nightPersonnelCount++;

    final list = <NightAttackKind>[];

    // 空母カットイン
    if (nightPersonnelCount != 0) {
      if (nightFighterCount >= 2 && nightAttackerCount >= 1) list.add(NightAttackKind.cutinNightAirAttackFFA);
      if (nightFighterCount >= 1 && nightAttackerCount >= 1) list.add(NightAttackKind.cutinNightAirAttackFA);
      if (nightFighterCount >= 1 && nightPcBomberCount >= 1) list.add(NightAttackKind.cutinNightAirAttackFS);
      if (nightFighterCount == 0 && nightAttackerCount >= 1 && nightPcBomberCount >= 1) {
        list.add(NightAttackKind.cutinNightAirAttackAS);
      }
      if (nightFighterCount >= 1 && nightBomberCount >= 1) {
        list.add(nightPcBomberCount >= 1 ? NightAttackKind.cutinNightAirAttackFS : NightAttackKind.cutinNightAirAttackFB);
      }
      if (nightFighterCount == 0 && nightAttackerCount >= 1 && nightBomberCount >= 1) {
        list.add(nightPcBomberCount >= 1 ? NightAttackKind.cutinNightAirAttackAS : NightAttackKind.cutinNightAirAttackAB);
      }
      if (nightFighterCount == 0 && nightAttackerCount == 0 && nightPcBomberCount >= 1 && nightBomberCount >= 1) {
        list.add(NightAttackKind.cutinNightAirAttackBS);
      }
      int nightAirplaneCount;
      if (nightFighterCount != 0) {
        nightAirplaneCount = (nightFighterCount - 1) +
            nightAttackerCount +
            nightBomberCount +
            nightCapableBomberCount +
            nightPcBomberCount +
            swordfishCount;
        if (nightAirplaneCount >= 2) list.add(NightAttackKind.cutinNightAirAttackFOther);
      } else {
        nightAirplaneCount =
            nightAttackerCount + nightBomberCount + nightCapableBomberCount + nightPcBomberCount + swordfishCount;
      }
      if (nightAirplaneCount != 0) list.add(NightAttackKind.nightAirAttack);
    }

    // Ark Royal(改)
    if ((shipId == 515 || shipId == 393) && swordfishCount > 0) list.add(NightAttackKind.nightSwordfish);

    // 潜水艦カットイン
    if (_isSubmarine(shipType)) {
      if (lateModelTorpedoCount >= 1 && submarineEquipmentCount >= 1) {
        list.add(NightAttackKind.cutinTorpedoMasterPicketSubmarine);
      } else if (lateModelTorpedoCount >= 2) {
        list.add(NightAttackKind.cutinTorpedoTorpedoSubmarine);
      }
    }

    // 夜間瑞雲攻撃
    final canNightZuiunAttack = shipType == _kAviationBattleship ||
        shipType == _kAviationCruiser ||
        shipType == _kLightCruiser ||
        shipType == _kSeaplaneTender;
    if (canNightZuiunAttack && mainGunCount >= 2 && nightZuiunCount >= 1) {
      if (nightZuiunCount >= 2 && surfaceRadarCount >= 1) list.add(NightAttackKind.specialNightZuiun2Radar);
      if (nightZuiunCount >= 2) list.add(NightAttackKind.specialNightZuiun2);
      if (surfaceRadarCount >= 1) list.add(NightAttackKind.specialNightZuiunRadar);
      list.add(NightAttackKind.specialNightZuiun);
    }

    // 駆逐艦カットイン (発動優先度が高い順)
    if (shipType == _kDestroyer) {
      if (mainGunCount >= 1 && torpedoCount >= 1 && surfaceRadarCount >= 1) list.add(NightAttackKind.cutinTorpedoRadar);
      if (torpedoCount >= 1 && surfaceRadarCount >= 1 && (picketCrewCount >= 1 || masterPicketCrewCount >= 1)) {
        list.add(NightAttackKind.cutinTorpedoPicket);
      }
      if (torpedoCount >= 2 && masterPicketCrewCount >= 1) list.add(NightAttackKind.cutinTorpedoTorpedoMasterPicket);
      if (torpedoCount >= 1 && masterPicketCrewCount >= 1 && drumCount >= 1) {
        list.add(NightAttackKind.cutinTorpedoDrumMasterPicket);
      }
    }

    // 汎用カットイン
    if (mainGunCount >= 3) list.add(NightAttackKind.cutinMainMain);
    if (!list.contains(NightAttackKind.cutinMainMain) && mainGunCount == 2 && subGunCount > 0) {
      list.add(NightAttackKind.cutinMainSub);
    }
    if (!list.contains(NightAttackKind.cutinMainMain) &&
        !list.contains(NightAttackKind.cutinMainSub) &&
        !list.contains(NightAttackKind.cutinTorpedoMasterPicketSubmarine) &&
        !list.contains(NightAttackKind.cutinTorpedoTorpedoSubmarine) &&
        torpedoCount >= 2) {
      list.add(NightAttackKind.cutinTorpedoTorpedo);
    }
    if (!list.contains(NightAttackKind.cutinMainMain) &&
        !list.contains(NightAttackKind.cutinMainSub) &&
        !list.contains(NightAttackKind.cutinTorpedoTorpedo) &&
        mainGunCount >= 1 &&
        torpedoCount >= 1) {
      list.add(NightAttackKind.cutinMainTorpedo);
    }

    // 連撃
    if ((mainGunCount == 2 && subGunCount == 0 && torpedoCount == 0) ||
        (mainGunCount == 1 && subGunCount > 0) ||
        (subGunCount >= 2 && torpedoCount <= 1)) {
      list.add(NightAttackKind.doubleShelling);
    }

    // 空母夜間砲撃
    if (_kNightShellingCarrierIds.contains(shipId)) list.add(NightAttackKind.shelling);

    if (!_isCarrier(shipType) && shipId != 605 && shipId != 645 && shipId != 650) {
      list.add(NightAttackKind.normalAttack);
    }

    return list;
  }

  static bool canAttackAtNight(Ship ship, GetDataApiDataApiMstShipEntity? master) {
    final hpRate = _hpRate(ship);
    if (hpRate <= 0.25) return false;
    final firepower = master?.apiHoug?.firstOrNull ?? 0;
    final torpedo = master?.apiRaig?.firstOrNull ?? 0;
    if (firepower + torpedo > 0) return true;
    final slot = _allSlot(ship);
    if ((ship.shipId == 515 || ship.shipId == 393) && slot.any((eq) => eq.isSwordfish)) return true;
    if (_isCarrier(ship.shipType)) {
      if (ship.shipType != _kArmoredAircraftCarrier && hpRate <= 0.5) return false;
      final hasNightPersonnel =
          {545, 599, 610, 883}.contains(ship.shipId) || slot.any((eq) => eq.isNightAviationPersonnel);
      final hasNightAircraft = slot.any((eq) => eq.isNightAircraftTypeA);
      if (hasNightPersonnel && hasNightAircraft) return true;
    }
    return false;
  }

  static ShipAttackRates calculate({
    required Ship ship,
    required Squad squad,
    required Map<int, GetDataApiDataApiMstShipEntity>? shipInfo,
  }) {
    final members = squad.ships.where((s) => s.escape != true).toList();
    final isFlagship = members.isNotEmpty && members.first.uid == ship.uid;
    final luck = ship.currentLuck;

    // 昼戦: 観測項
    num shipsLOSBase = 0;
    double seaplaneTotal = 0;
    for (final member in members) {
      shipsLOSBase += member.losShip;
      for (final (index, eq) in (member.equipment ?? <Equipment>[]).indexed) {
        if (eq.category == _kSeaplaneBomber || eq.category == _kSeaplaneRecon) {
          final count = (member.onSlot != null && index < member.onSlot!.length) ? member.onSlot![index] : 0;
          seaplaneTotal += (eq.los ?? 0) * sqrt(max(count, 0)).floor();
        }
      }
    }
    final equipsLOS = _allSlot(ship).fold<int>(0, (sum, eq) => sum + (eq.los ?? 0));
    final searchBase = shipsLOSBase + seaplaneTotal;
    final fleetSearchCorrection = (sqrt(max(searchBase, 0)) + 0.1 * searchBase).floor();
    final flagshipBonus = isFlagship ? 15 : 0;
    final luckTerm = (sqrt(max(luck, 0)) + 10).floor();
    final observationAP = (luckTerm + 0.7 * (fleetSearchCorrection + 1.6 * equipsLOS) + 10).floor() + flagshipBonus;
    final observationAS = (luckTerm + 0.6 * (fleetSearchCorrection + 1.2 * equipsLOS)).floor() + flagshipBonus;

    final day = <AttackRate<DayAttackKind>>[];
    double leftAP = 100, leftAS = 100;
    for (final kind in dayAttackKinds(ship)) {
      final coefficient = kind.coefficient;
      if (coefficient == null) {
        day.add(AttackRate(kind, leftAP, leftAS));
      } else {
        final rateAP = min(observationAP / coefficient, 1.0) * leftAP;
        final rateAS = min(observationAS / coefficient, 1.0) * leftAS;
        day.add(AttackRate(kind, rateAP, rateAS));
        leftAP -= rateAP;
        leftAS -= rateAS;
      }
    }

    // 夜戦: カットイン項
    final master = shipInfo?[ship.shipId];
    final night = <AttackRate<NightAttackKind>>[];
    final nightCapable = canAttackAtNight(ship, master);
    if (nightCapable) {
      final allMembers = squad.ships;
      final hasSearchlight = allMembers.any((s) =>
          _allSlot(s).any((eq) => eq.category == _kSearchlight || eq.category == _kSearchlightLarge));
      final hasStarShell = allMembers.any((s) => _allSlot(s).any((eq) => eq.category == _kStarShell));
      final slot = _allSlot(ship);
      final hasPicketCrew = slot.any((eq) => eq.itemId == 129);
      final isTorpedoSquadronType =
          ship.shipType == _kDestroyer || ship.shipType == _kLightCruiser || ship.shipType == _kTorpedoCruiser;
      final hasMasterPicketCrew = isTorpedoSquadronType && slot.any((eq) => eq.itemId == 412);

      int equipState = 0;
      if (hasSearchlight) {
        equipState += 7;
      } else if (hasStarShell) {
        equipState += 4;
      }
      if (hasPicketCrew) equipState += 5;
      if (hasMasterPicketCrew) equipState += 8;

      final hpRate = _hpRate(ship);
      final damageBonus = (hpRate > 0.25 && hpRate <= 0.5) ? 18 : 0; // 中破
      final level = ship.level;
      final double ci;
      if (luck < 50) {
        ci = 15 + luck + (0.75 * sqrt(level)).floor() + flagshipBonus + damageBonus + equipState.toDouble();
      } else {
        ci = 65 + sqrt(luck - 50).floor() + (0.8 * sqrt(level)).floor() + flagshipBonus + damageBonus + equipState.toDouble();
      }

      double left = 100;
      for (final kind in nightAttackKinds(ship)) {
        final coefficient = kind.coefficient;
        if (kind == NightAttackKind.doubleShelling) {
          final rate = left * 0.991;
          night.add(AttackRate(kind, rate));
          left -= rate;
        } else if (coefficient == null) {
          night.add(AttackRate(kind, left));
        } else {
          final rate = min(ci / coefficient, 1.0) * left;
          night.add(AttackRate(kind, rate));
          left -= rate;
        }
      }
    }

    return ShipAttackRates(day: day, night: night, canAttackAtNight: nightCapable);
  }
}
