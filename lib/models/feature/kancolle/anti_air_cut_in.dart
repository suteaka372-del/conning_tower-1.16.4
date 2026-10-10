import '../../data/kcsapi/start2/get_data_entity.dart';
import 'equipment.dart';
import 'repair_timer.dart';
import 'ship.dart';

// Anti-air cut-in (対空カットイン) kinds, conditions, trigger rates and priorities.
// Ported from ElectronicObserver (MIT License,
// Original work Copyright (c) 2014 Andante, Translation work Copyright (c) 2015 Ryuu Kitsune)
// https://github.com/ElectronicObserverEN/ElectronicObserver
// ElectronicObserver.Core/Types/AntiAir/AntiAirCutIn.cs, AntiAirCutInCondition.cs
// ElectronicObserver.Core/Types/Extensions/ShipDataExtensions.cs (Has* helpers)
// Rates: https://docs.google.com/spreadsheets/d/1agGoLv57g5eOXLXtNIKHRoBYy61OQYxibWP6Vi_DMuY

int _category(Equipment e) => (e.type?.length ?? 0) > 2 ? e.type![2] : 0;

int _icon(Equipment e) => (e.type?.length ?? 0) > 3 ? e.type![3] : 0;

bool _isHighAngleGun(Equipment e) => _icon(e) == 16;

bool _isRadar(Equipment e) => const {12, 13, 93}.contains(_category(e));

bool _isAirRadar(Equipment e) => _isRadar(e) && (e.aa ?? 0) >= 2;

bool _isAaGun(Equipment e, {int min = 0, int max = 9999}) =>
    _category(e) == 21 && (e.aa ?? 0) >= min && (e.aa ?? 0) <= max;

bool _isItem(Equipment e, Set<int> ids) => ids.contains(e.itemId);

/// 対空カットインの条件になる装備
enum AaciEquipment {
  highAngle('高角砲', 'HA gun'),
  highAngleDirector('高角砲(高射装置付)', 'HA gun w/ AAFD'),
  highAngleWithoutDirector('高角砲(高射装置なし)', 'HA gun w/o AAFD'),
  aaDirector('高射装置', 'AAFD'),
  radar('電探', 'Radar'),
  antiAirRadar('対空電探', 'Air radar'),
  mainGunLarge('大口径主砲', 'Large main gun'),
  mainGunLargeFcr('16inch三連装砲改+FCR', '16inch Mk.I Kai+FCR'),
  aaShell('対空強化弾', 'AA shell'),
  aaGun('機銃', 'AA gun'),
  aaGun3Aa('機銃(対空3以上)', 'AA gun (AA 3+)'),
  aaGun4Aa('機銃(対空4以上)', 'AA gun (AA 4+)'),
  aaGun5Aa('機銃(対空5以上)', 'AA gun (AA 5+)'),
  aaGun6Aa('機銃(対空6以上)', 'AA gun (AA 6+)'),
  aaGun3To8Aa('機銃(対空3〜8)', 'AA gun (AA 3-8)'),
  aaGunConcentrated('集中機銃', 'CD AA gun'),
  aaGunPompom('ポンポン砲', 'Pom-pom'),
  aaRocketBritish('UPロケット', 'UP rocket'),
  aaRocketMod('噴進砲改二', 'Rocket Kai Ni'),
  highAngleMusashi('10cm高角砲改+増設機銃', '10cm HA Kai+AA guns'),
  highAngleAmerican('5inch単装砲Mk.30', '5inch Mk.30'),
  highAngleAmericanKai('5inch単装砲Mk.30改', '5inch Mk.30 Kai'),
  highAngleAmericanGfcs('5inch単装砲Mk.30改+GFCS', '5inch Mk.30 Kai+GFCS'),
  radarGfcs('GFCS Mk.37', 'GFCS Mk.37'),
  highAngleAtlanta('5inch連装両用砲(集中)', '5inch DP (CD)'),
  highAngleAtlantaGfcs('GFCS+5inch連装両用砲(集中)', 'GFCS+5inch DP (CD)'),
  highAngleConcentrated('10cm高角砲群 集中配備', '10cm HA battery (CD)'),
  radarYamato('15m測距儀+21号電探改二', '15m rangefinder+Type21 Kai Ni'),
  harunaGun('35.6cm連装砲改三/改四', '35.6cm Kai San/Yon'),
  harusameGun('12.7cm連装砲C型改三H', '12.7cm Model C Kai San H'),
  aaGunShigure('25mm対空機銃増備', '25mm AA gun (extra)'),
  radar4AaOrMore('対空電探(対空4以上)', 'Air radar (AA 4+)'),
  hatsuzukiGun('10cm高角砲改+高射装置改', '10cm HA Kai+AAFD Kai'),
  akizukiGunKai('10cm連装高角砲改系', '10cm HA Kai'),
  akizukiPotatoGun('10cm連装高角砲改', '10cm twin HA Kai'),
  aafd94('94式高射装置', 'Type 94 AAFD');

  const AaciEquipment(this.ja, this.en);

  final String ja;
  final String en;

  String get label => repairText(ja, en);

  bool matches(Equipment e) => switch (this) {
        highAngle => _isHighAngleGun(e),
        highAngleDirector => _isHighAngleGun(e) && (e.aa ?? 0) >= 8,
        highAngleWithoutDirector => _isHighAngleGun(e) && (e.aa ?? 0) < 8,
        aaDirector => _category(e) == 36,
        radar => _isRadar(e),
        antiAirRadar => _isAirRadar(e),
        mainGunLarge => _category(e) == 3 || _category(e) == 38,
        mainGunLargeFcr => _isItem(e, {300}),
        aaShell => _category(e) == 18,
        aaGun => _isAaGun(e),
        aaGun3Aa => _isAaGun(e, min: 3),
        aaGun4Aa => _isAaGun(e, min: 4),
        aaGun5Aa => _isAaGun(e, min: 5),
        aaGun6Aa => _isAaGun(e, min: 6),
        aaGun3To8Aa => _isAaGun(e, min: 3, max: 8),
        aaGunConcentrated => _isAaGun(e, min: 9),
        aaGunPompom => _isItem(e, {191}),
        aaRocketBritish => _isItem(e, {301}),
        aaRocketMod => _isItem(e, {274}),
        highAngleMusashi => _isItem(e, {275}),
        highAngleAmerican => _isItem(e, {284}),
        highAngleAmericanKai => _isItem(e, {313}),
        highAngleAmericanGfcs => _isItem(e, {308}),
        radarGfcs => _isItem(e, {307}),
        highAngleAtlanta => _isItem(e, {362}),
        highAngleAtlantaGfcs => _isItem(e, {363}),
        highAngleConcentrated => _isItem(e, {464}),
        radarYamato => _isItem(e, {142, 460}),
        harunaGun => _isItem(e, {502, 503}),
        harusameGun => _isItem(e, {529}),
        aaGunShigure => _isItem(e, {505}),
        radar4AaOrMore => _isAirRadar(e) && (e.aa ?? 0) >= 4,
        hatsuzukiGun => _isItem(e, {533}),
        akizukiGunKai => _isItem(e, {533, 553}),
        akizukiPotatoGun => _isItem(e, {553}),
        aafd94 => _isItem(e, {121}),
      };
}

/// 発動条件1つ分 (艦の指定と必要な装備の数)
class AntiAirCutInCondition {
  /// 対象の艦 (api_ship_id)。null なら指定なし
  final Set<int>? ships;

  /// 対象の艦型 (api_ctype)。null なら指定なし
  final Set<int>? shipClasses;

  final Map<AaciEquipment, int> equipment;

  const AntiAirCutInCondition({this.ships, this.shipClasses, required this.equipment});

  bool _shipMatches(int shipId, int? shipClass) {
    if (ships == null && shipClasses == null) return true;
    if (ships != null && ships!.contains(shipId)) return true;
    if (shipClasses != null && shipClass != null && shipClasses!.contains(shipClass)) return true;
    return false;
  }

  bool canBeActivatedBy(int shipId, int? shipClass, List<Equipment> equipments) {
    if (!_shipMatches(shipId, shipClass)) return false;
    for (final e in equipment.entries) {
      if (equipments.where(e.key.matches).length < e.value) return false;
    }
    return true;
  }

  /// 装備の説明 (高角砲×2 + 電探 など)
  String get description =>
      equipment.entries.map((e) => e.value > 1 ? '${e.key.label}×${e.value}' : e.key.label).join(' + ');
}

/// 対空カットインの種別
class AntiAirCutInKind {
  final int id;
  final int fixedBonus;
  final double variableBonus;

  /// 発動率 (分かっていなければ null)
  final double? rate;
  final List<AntiAirCutInCondition> conditions;

  const AntiAirCutInKind(
    this.id, {
    required this.fixedBonus,
    required this.variableBonus,
    required this.rate,
    required this.conditions,
  });

  static const _akizukiClass = 54;
  static const _mayaKaiNi = 428;

  /// 条件を満たす発動条件 (満たさなければ null)
  AntiAirCutInCondition? matchingCondition(int shipId, int? shipClass, List<Equipment> equipments) {
    if (shipClass == _akizukiClass && const {5, 7, 8}.contains(id)) return null;
    if (shipId == _mayaKaiNi && id == 13) return null;
    for (final condition in conditions) {
      if (condition.canBeActivatedBy(shipId, shipClass, equipments)) return condition;
    }
    return null;
  }

  int get priority {
    final index = kAntiAirCutInPriorities.indexOf(id);
    return index < 0 ? 9999 : index;
  }
}

/// 1艦が発動できる対空カットイン1種分
class AntiAirCutInChance {
  final AntiAirCutInKind kind;
  final AntiAirCutInCondition condition;

  /// その種別だけの発動率 (null = 不明)
  final double? rate;

  /// 優先順位が上の種別が出なかったときに出る確率 (null = 不明)
  final double? effectiveRate;

  const AntiAirCutInChance({
    required this.kind,
    required this.condition,
    required this.rate,
    required this.effectiveRate,
  });
}

/// 1艦の対空カットイン
class ShipAntiAirCutIns {
  /// 判定の順 (優先順位の高い順)
  final List<AntiAirCutInChance> chances;

  /// いずれかが発動する確率 (null = 不明な種別がある)
  final double? total;

  const ShipAntiAirCutIns(this.chances, this.total);

  bool get isEmpty => chances.isEmpty;
}

/// 1艦が発動できる対空カットインと発動率。
/// 優先順位の高い種別から順に判定し、出なかったら次の種別を判定するものとして計算する
ShipAntiAirCutIns shipAntiAirCutIns(Ship ship, {int? shipClass}) {
  final equipments = [...?ship.equipment, ...?ship.exEquipment];
  final candidates = <(AntiAirCutInKind, AntiAirCutInCondition)>[];
  for (final kind in kAntiAirCutInKinds) {
    final condition = kind.matchingCondition(ship.shipId, shipClass, equipments);
    if (condition != null) candidates.add((kind, condition));
  }
  candidates.sort((a, b) => a.$1.priority.compareTo(b.$1.priority));

  double? notYet = 1.0; // まだ発動していない確率 (null = 不明)
  final chances = <AntiAirCutInChance>[];
  for (final (kind, condition) in candidates) {
    final rate = kind.rate;
    final effective = (rate == null || notYet == null) ? null : notYet * rate;
    chances.add(AntiAirCutInChance(kind: kind, condition: condition, rate: rate, effectiveRate: effective));
    notYet = (rate == null || notYet == null) ? null : notYet * (1 - rate);
  }
  return ShipAntiAirCutIns(chances, notYet == null ? null : 1 - notYet);
}

/// 艦隊の誰かが対空カットインを発動する確率 (null = 不明な種別がある)。1隻も発動できなければ 0
double? fleetAntiAirCutInRate(List<Ship> ships, Map<int, GetDataApiDataApiMstShipEntity>? shipInfo) {
  double notYet = 1.0;
  for (final ship in ships) {
    final result = shipAntiAirCutIns(ship, shipClass: shipInfo?[ship.shipId]?.apiCtype);
    if (result.isEmpty) continue;
    final total = result.total;
    if (total == null) return null;
    notYet *= 1 - total;
  }
  return 1 - notYet;
}

const List<AntiAirCutInKind> kAntiAirCutInKinds = [
  AntiAirCutInKind(1, fixedBonus: 7, variableBonus: 1.7, rate: 0.643, conditions: [
    AntiAirCutInCondition(
        shipClasses: {54}, equipment: {AaciEquipment.highAngle: 2, AaciEquipment.radar: 1}), // AkizukiClass
  ]),
  AntiAirCutInKind(2, fixedBonus: 6, variableBonus: 1.7, rate: 0.574, conditions: [
    AntiAirCutInCondition(
        shipClasses: {54}, equipment: {AaciEquipment.highAngle: 1, AaciEquipment.radar: 1}), // AkizukiClass
  ]),
  AntiAirCutInKind(3, fixedBonus: 4, variableBonus: 1.6, rate: 0.495, conditions: [
    AntiAirCutInCondition(shipClasses: {54}, equipment: {AaciEquipment.highAngle: 2}), // AkizukiClass
  ]),
  AntiAirCutInKind(4, fixedBonus: 6, variableBonus: 1.5, rate: 0.514, conditions: [
    AntiAirCutInCondition(equipment: {
      AaciEquipment.mainGunLarge: 1,
      AaciEquipment.aaShell: 1,
      AaciEquipment.aaDirector: 1,
      AaciEquipment.antiAirRadar: 1
    }),
  ]),
  AntiAirCutInKind(5, fixedBonus: 4, variableBonus: 1.5, rate: 0.544, conditions: [
    AntiAirCutInCondition(equipment: {AaciEquipment.highAngleDirector: 2, AaciEquipment.antiAirRadar: 1}),
  ]),
  AntiAirCutInKind(6, fixedBonus: 4, variableBonus: 1.45, rate: 0.396, conditions: [
    AntiAirCutInCondition(
        equipment: {AaciEquipment.mainGunLarge: 1, AaciEquipment.aaShell: 1, AaciEquipment.aaDirector: 1}),
  ]),
  AntiAirCutInKind(7, fixedBonus: 3, variableBonus: 1.35, rate: 0.445, conditions: [
    AntiAirCutInCondition(
        equipment: {AaciEquipment.highAngle: 1, AaciEquipment.aaDirector: 1, AaciEquipment.antiAirRadar: 1}),
  ]),
  AntiAirCutInKind(8, fixedBonus: 4, variableBonus: 1.4, rate: 0.495, conditions: [
    AntiAirCutInCondition(equipment: {AaciEquipment.highAngleDirector: 1, AaciEquipment.antiAirRadar: 1}),
  ]),
  AntiAirCutInKind(9, fixedBonus: 2, variableBonus: 1.3, rate: 0.396, conditions: [
    AntiAirCutInCondition(equipment: {AaciEquipment.highAngle: 1, AaciEquipment.aaDirector: 1}),
  ]),
  AntiAirCutInKind(10, fixedBonus: 8, variableBonus: 1.65, rate: 0.594, conditions: [
    AntiAirCutInCondition(ships: {
      428
    }, equipment: {
      AaciEquipment.highAngle: 1,
      AaciEquipment.aaGunConcentrated: 1,
      AaciEquipment.antiAirRadar: 1
    }), // MayaKaiNi
  ]),
  AntiAirCutInKind(11, fixedBonus: 6, variableBonus: 1.5, rate: 0.544, conditions: [
    AntiAirCutInCondition(
        ships: {428}, equipment: {AaciEquipment.highAngle: 1, AaciEquipment.aaGunConcentrated: 1}), // MayaKaiNi
  ]),
  AntiAirCutInKind(12, fixedBonus: 3, variableBonus: 1.25, rate: 0.445, conditions: [
    AntiAirCutInCondition(
        equipment: {AaciEquipment.aaGunConcentrated: 1, AaciEquipment.aaGun3Aa: 2, AaciEquipment.antiAirRadar: 1}),
  ]),
  AntiAirCutInKind(13, fixedBonus: 4, variableBonus: 1.35, rate: 0.346, conditions: [
    AntiAirCutInCondition(
        equipment: {AaciEquipment.highAngle: 1, AaciEquipment.aaGunConcentrated: 1, AaciEquipment.antiAirRadar: 1}),
  ]),
  AntiAirCutInKind(14, fixedBonus: 4, variableBonus: 1.45, rate: 0.623, conditions: [
    AntiAirCutInCondition(
        ships: {141},
        equipment: {AaciEquipment.highAngle: 1, AaciEquipment.aaGun: 1, AaciEquipment.antiAirRadar: 1}), // IsuzuKaiNi
  ]),
  AntiAirCutInKind(15, fixedBonus: 3, variableBonus: 1.3, rate: 0.534, conditions: [
    AntiAirCutInCondition(ships: {141}, equipment: {AaciEquipment.highAngle: 1, AaciEquipment.aaGun: 1}), // IsuzuKaiNi
  ]),
  AntiAirCutInKind(16, fixedBonus: 4, variableBonus: 1.4, rate: 0.613, conditions: [
    AntiAirCutInCondition(ships: {
      470,
      622
    }, equipment: {
      AaciEquipment.highAngle: 1,
      AaciEquipment.aaGun: 1,
      AaciEquipment.radar: 1
    }), // KasumiKaiNiB/YuubariKaiNi
  ]),
  AntiAirCutInKind(17, fixedBonus: 2, variableBonus: 1.25, rate: 0.564, conditions: [
    AntiAirCutInCondition(
        ships: {470, 979}, equipment: {AaciEquipment.highAngle: 1, AaciEquipment.aaGun: 1}), // KasumiKaiNiB/InagiKaiNi
  ]),
  AntiAirCutInKind(18, fixedBonus: 2, variableBonus: 1.2, rate: 0.584, conditions: [
    AntiAirCutInCondition(
        ships: {418, 979}, equipment: {AaciEquipment.aaGunConcentrated: 1}), // SatsukiKaiNi/InagiKaiNi
  ]),
  AntiAirCutInKind(19, fixedBonus: 5, variableBonus: 1.45, rate: 0.564, conditions: [
    AntiAirCutInCondition(
        ships: {487},
        equipment: {AaciEquipment.highAngleWithoutDirector: 1, AaciEquipment.aaGunConcentrated: 1}), // KinuKaiNi
  ]),
  AntiAirCutInKind(20, fixedBonus: 3, variableBonus: 1.25, rate: 0.643, conditions: [
    AntiAirCutInCondition(ships: {487}, equipment: {AaciEquipment.aaGunConcentrated: 1}), // KinuKaiNi
  ]),
  AntiAirCutInKind(21, fixedBonus: 5, variableBonus: 1.45, rate: 0.594, conditions: [
    AntiAirCutInCondition(
        ships: {488}, equipment: {AaciEquipment.highAngle: 1, AaciEquipment.antiAirRadar: 1}), // YuraKaiNi
  ]),
  AntiAirCutInKind(22, fixedBonus: 2, variableBonus: 1.2, rate: 0.643, conditions: [
    AntiAirCutInCondition(ships: {548}, equipment: {AaciEquipment.aaGunConcentrated: 1}), // FumizukiKaiNi
  ]),
  AntiAirCutInKind(23, fixedBonus: 1, variableBonus: 1.05, rate: 0.792, conditions: [
    AntiAirCutInCondition(ships: {539, 530}, equipment: {AaciEquipment.aaGun3To8Aa: 1}), // UIT25/I504
  ]),
  AntiAirCutInKind(24, fixedBonus: 3, variableBonus: 1.25, rate: 0.613, conditions: [
    AntiAirCutInCondition(
        ships: {477, 478},
        equipment: {AaciEquipment.highAngle: 1, AaciEquipment.aaGun3To8Aa: 1}), // TenryuuKaiNi/TatsutaKaiNi
  ]),
  AntiAirCutInKind(25, fixedBonus: 7, variableBonus: 1.55, rate: 0.594, conditions: [
    AntiAirCutInCondition(ships: {
      82,
      553,
      88,
      554
    }, equipment: {
      AaciEquipment.aaRocketMod: 1,
      AaciEquipment.antiAirRadar: 1,
      AaciEquipment.aaShell: 1
    }), // IseKai/IseKaiNi/HyuugaKai/HyuugaKaiNi
  ]),
  AntiAirCutInKind(26, fixedBonus: 6, variableBonus: 1.4, rate: 0.554, conditions: [
    AntiAirCutInCondition(ships: {
      136,
      911,
      916,
      148,
      546
    }, equipment: {
      AaciEquipment.highAngleMusashi: 1,
      AaciEquipment.antiAirRadar: 1
    }), // YamatoKai/YamatoKaiNi/YamatoKaiNiJuu/MusashiKai/MusashiKaiNi
  ]),
  AntiAirCutInKind(27, fixedBonus: 5, variableBonus: 1.55, rate: 0.519, conditions: [
    AntiAirCutInCondition(ships: {
      321
    }, equipment: {
      AaciEquipment.highAngleMusashi: 1,
      AaciEquipment.aaRocketMod: 1,
      AaciEquipment.antiAirRadar: 1
    }), // OoyodoKai
  ]),
  AntiAirCutInKind(28, fixedBonus: 4, variableBonus: 1.4, rate: 0.554, conditions: [
    AntiAirCutInCondition(ships: {
      82,
      553,
      88,
      554,
      148,
      546
    }, equipment: {
      AaciEquipment.aaRocketMod: 1,
      AaciEquipment.antiAirRadar: 1
    }), // IseKai/IseKaiNi/HyuugaKai/HyuugaKaiNi/MusashiKai/MusashiKaiNi
  ]),
  AntiAirCutInKind(29, fixedBonus: 5, variableBonus: 1.55, rate: 0.594, conditions: [
    AntiAirCutInCondition(
        ships: {557, 558},
        equipment: {AaciEquipment.highAngle: 1, AaciEquipment.antiAirRadar: 1}), // IsokazeBKai/HamakazeBKai
  ]),
  AntiAirCutInKind(30, fixedBonus: 3, variableBonus: 1.3, rate: 0.495, conditions: [
    AntiAirCutInCondition(
        ships: {477, 579, 630}, equipment: {AaciEquipment.highAngle: 3}), // TenryuuKaiNi/GotlandKai/Gotlandandra
  ]),
  AntiAirCutInKind(31, fixedBonus: 2, variableBonus: 1.25, rate: 0.495, conditions: [
    AntiAirCutInCondition(ships: {477, 979}, equipment: {AaciEquipment.highAngle: 2}), // TenryuuKaiNi/InagiKaiNi
  ]),
  AntiAirCutInKind(32, fixedBonus: 3, variableBonus: 1.2, rate: 0.594, conditions: [
    AntiAirCutInCondition(ships: {
      149,
      591,
      150,
      592,
      151,
      593,
      954,
      152,
      519,
      394,
      520,
      893,
      901,
      906,
      571,
      576,
      572,
      577,
      439,
      364,
      515,
      393
    }, equipment: {
      AaciEquipment.mainGunLargeFcr: 1,
      AaciEquipment.aaGunPompom: 1
    }), // KongouKaiNi/KongouKaiNiC/HieiKaiNi/HieiKaiNiC/HarunaKaiNi/HarunaKaiNiB/HarunaKaiNiC/KirishimaKaiNi/Jervis/JervisKai/Janus/JanusKai/Javelin/JavelinKai/Nelson/NelsonKai/Rodney/RodneyKai/Warspite/WarspiteKai/ArkRoyal/ArkRoyalKai
    AntiAirCutInCondition(ships: {
      149,
      591,
      150,
      592,
      151,
      593,
      954,
      152,
      519,
      394,
      520,
      893,
      901,
      906,
      571,
      576,
      572,
      577,
      439,
      364,
      515,
      393
    }, equipment: {
      AaciEquipment.aaRocketBritish: 1,
      AaciEquipment.aaGunPompom: 1
    }), // KongouKaiNi/KongouKaiNiC/HieiKaiNi/HieiKaiNiC/HarunaKaiNi/HarunaKaiNiB/HarunaKaiNiC/KirishimaKaiNi/Jervis/JervisKai/Janus/JanusKai/Javelin/JavelinKai/Nelson/NelsonKai/Rodney/RodneyKai/Warspite/WarspiteKai/ArkRoyal/ArkRoyalKai
    AntiAirCutInCondition(ships: {
      149,
      591,
      150,
      592,
      151,
      593,
      954,
      152,
      519,
      394,
      520,
      893,
      901,
      906,
      571,
      576,
      572,
      577,
      439,
      364,
      515,
      393
    }, equipment: {
      AaciEquipment.aaRocketBritish: 2
    }), // KongouKaiNi/KongouKaiNiC/HieiKaiNi/HieiKaiNiC/HarunaKaiNi/HarunaKaiNiB/HarunaKaiNiC/KirishimaKaiNi/Jervis/JervisKai/Janus/JanusKai/Javelin/JavelinKai/Nelson/NelsonKai/Rodney/RodneyKai/Warspite/WarspiteKai/ArkRoyal/ArkRoyalKai
  ]),
  AntiAirCutInKind(33, fixedBonus: 3, variableBonus: 1.35, rate: 0.415, conditions: [
    AntiAirCutInCondition(
        ships: {579, 630},
        equipment: {AaciEquipment.highAngle: 1, AaciEquipment.aaGun4Aa: 1}), // GotlandKai/Gotlandandra
  ]),
  AntiAirCutInKind(34, fixedBonus: 7, variableBonus: 1.6, rate: 0.594, conditions: [
    AntiAirCutInCondition(shipClasses: {91}, equipment: {AaciEquipment.highAngleAmericanGfcs: 2}), // FletcherClass
  ]),
  AntiAirCutInKind(35, fixedBonus: 6, variableBonus: 1.55, rate: 0.544, conditions: [
    AntiAirCutInCondition(
        shipClasses: {91},
        equipment: {AaciEquipment.highAngleAmerican: 1, AaciEquipment.highAngleAmericanGfcs: 1}), // FletcherClass
    AntiAirCutInCondition(
        shipClasses: {91},
        equipment: {AaciEquipment.highAngleAmericanKai: 1, AaciEquipment.highAngleAmericanGfcs: 1}), // FletcherClass
  ]),
  AntiAirCutInKind(36, fixedBonus: 6, variableBonus: 1.55, rate: 0.495, conditions: [
    AntiAirCutInCondition(
        shipClasses: {91},
        equipment: {AaciEquipment.highAngleAmerican: 2, AaciEquipment.radarGfcs: 1}), // FletcherClass
    AntiAirCutInCondition(shipClasses: {
      91
    }, equipment: {
      AaciEquipment.highAngleAmerican: 1,
      AaciEquipment.highAngleAmericanKai: 1,
      AaciEquipment.radarGfcs: 1
    }), // FletcherClass
    AntiAirCutInCondition(
        shipClasses: {91},
        equipment: {AaciEquipment.highAngleAmericanKai: 2, AaciEquipment.radarGfcs: 1}), // FletcherClass
  ]),
  AntiAirCutInKind(37, fixedBonus: 4, variableBonus: 1.45, rate: 0.396, conditions: [
    AntiAirCutInCondition(shipClasses: {91}, equipment: {AaciEquipment.highAngleAmericanKai: 2}), // FletcherClass
  ]),
  AntiAirCutInKind(38, fixedBonus: 10, variableBonus: 1.85, rate: 0.594, conditions: [
    AntiAirCutInCondition(shipClasses: {99}, equipment: {AaciEquipment.highAngleAtlantaGfcs: 2}), // AtlantaClass
  ]),
  AntiAirCutInKind(39, fixedBonus: 10, variableBonus: 1.7, rate: 0.55, conditions: [
    AntiAirCutInCondition(
        shipClasses: {99},
        equipment: {AaciEquipment.highAngleAtlanta: 1, AaciEquipment.highAngleAtlantaGfcs: 1}), // AtlantaClass
  ]),
  AntiAirCutInKind(40, fixedBonus: 10, variableBonus: 1.7, rate: 0.55, conditions: [
    AntiAirCutInCondition(
        shipClasses: {99}, equipment: {AaciEquipment.highAngleAtlanta: 2, AaciEquipment.radarGfcs: 1}), // AtlantaClass
    AntiAirCutInCondition(shipClasses: {
      99
    }, equipment: {
      AaciEquipment.highAngleAtlanta: 1,
      AaciEquipment.highAngleAtlantaGfcs: 1,
      AaciEquipment.radarGfcs: 1
    }), // AtlantaClass
    AntiAirCutInCondition(
        shipClasses: {99},
        equipment: {AaciEquipment.highAngleAtlantaGfcs: 2, AaciEquipment.radarGfcs: 1}), // AtlantaClass
  ]),
  AntiAirCutInKind(41, fixedBonus: 9, variableBonus: 1.65, rate: 0.594, conditions: [
    AntiAirCutInCondition(
        shipClasses: {99}, equipment: {AaciEquipment.highAngleAtlanta: 2, AaciEquipment.radarGfcs: 1}), // AtlantaClass
    AntiAirCutInCondition(
        shipClasses: {99},
        equipment: {AaciEquipment.highAngleAtlanta: 1, AaciEquipment.highAngleAtlantaGfcs: 1}), // AtlantaClass
    AntiAirCutInCondition(shipClasses: {99}, equipment: {AaciEquipment.highAngleAtlantaGfcs: 2}), // AtlantaClass
  ]),
  AntiAirCutInKind(42, fixedBonus: 10, variableBonus: 1.65, rate: 0.643, conditions: [
    AntiAirCutInCondition(ships: {
      911,
      916,
      546
    }, equipment: {
      AaciEquipment.highAngleConcentrated: 2,
      AaciEquipment.radarYamato: 1,
      AaciEquipment.aaGun6Aa: 1
    }), // YamatoKaiNi/YamatoKaiNiJuu/MusashiKaiNi
  ]),
  AntiAirCutInKind(43, fixedBonus: 8, variableBonus: 1.6, rate: 0.594, conditions: [
    AntiAirCutInCondition(ships: {
      911,
      916,
      546
    }, equipment: {
      AaciEquipment.highAngleConcentrated: 2,
      AaciEquipment.radarYamato: 1
    }), // YamatoKaiNi/YamatoKaiNiJuu/MusashiKaiNi
  ]),
  AntiAirCutInKind(44, fixedBonus: 6, variableBonus: 1.6, rate: 0.544, conditions: [
    AntiAirCutInCondition(ships: {
      911,
      916,
      546
    }, equipment: {
      AaciEquipment.highAngleConcentrated: 1,
      AaciEquipment.radarYamato: 1,
      AaciEquipment.aaGun6Aa: 1
    }), // YamatoKaiNi/YamatoKaiNiJuu/MusashiKaiNi
  ]),
  AntiAirCutInKind(45, fixedBonus: 5, variableBonus: 1.55, rate: 0.495, conditions: [
    AntiAirCutInCondition(ships: {
      911,
      916,
      546
    }, equipment: {
      AaciEquipment.highAngleConcentrated: 1,
      AaciEquipment.radarYamato: 1
    }), // YamatoKaiNi/YamatoKaiNiJuu/MusashiKaiNi
  ]),
  AntiAirCutInKind(46, fixedBonus: 8, variableBonus: 1.55, rate: 0.495, conditions: [
    AntiAirCutInCondition(ships: {
      593
    }, equipment: {
      AaciEquipment.harunaGun: 1,
      AaciEquipment.aaGunConcentrated: 1,
      AaciEquipment.antiAirRadar: 1
    }), // HarunaKaiNiB
  ]),
  AntiAirCutInKind(47, fixedBonus: 2, variableBonus: 1.3, rate: 0.7, conditions: [
    AntiAirCutInCondition(ships: {
      497,
      145,
      961,
      498,
      975
    }, equipment: {
      AaciEquipment.harusameGun: 2
    }), // ShiratsuyuKaiNi/ShigureKaiNi/ShigureKaiSan/MurasameKaiNi/HarusameKaiNi
    AntiAirCutInCondition(ships: {
      497,
      145,
      961,
      498,
      975
    }, equipment: {
      AaciEquipment.harusameGun: 1,
      AaciEquipment.aaGunShigure: 1
    }), // ShiratsuyuKaiNi/ShigureKaiNi/ShigureKaiSan/MurasameKaiNi/HarusameKaiNi
    AntiAirCutInCondition(ships: {
      497,
      145,
      961,
      498,
      975
    }, equipment: {
      AaciEquipment.harusameGun: 1,
      AaciEquipment.radar4AaOrMore: 1
    }), // ShiratsuyuKaiNi/ShigureKaiNi/ShigureKaiSan/MurasameKaiNi/HarusameKaiNi
  ]),
  AntiAirCutInKind(48, fixedBonus: 8, variableBonus: 1.75, rate: 0.643, conditions: [
    AntiAirCutInCondition(ships: {
      330,
      963,
      346,
      537,
      357,
      968,
      538
    }, equipment: {
      AaciEquipment.hatsuzukiGun: 2,
      AaciEquipment.radar4AaOrMore: 1
    }), // AkizukiKai/AkizukiKaiNi/TeruzukiKai/SuzutsukiKai/HatsuzukiKai/HatsuzukiKaiNi/FuyutsukiKai
  ]),
  AntiAirCutInKind(49, fixedBonus: 5, variableBonus: 1.5, rate: null, conditions: [
    AntiAirCutInCondition(ships: {
      426,
      986,
      981
    }, equipment: {
      AaciEquipment.highAngleDirector: 2,
      AaciEquipment.radar4AaOrMore: 1
    }), // FubukiKaiNi/ShirayukiKaiNi/FujinamiKaiNi
  ]),
  AntiAirCutInKind(50, fixedBonus: 7, variableBonus: 1.5, rate: null, conditions: [
    AntiAirCutInCondition(ships: {
      426,
      986,
      981
    }, shipClasses: {
      54
    }, equipment: {
      AaciEquipment.akizukiGunKai: 2,
      AaciEquipment.radar4AaOrMore: 1,
      AaciEquipment.aafd94: 1
    }), // FubukiKaiNi/ShirayukiKaiNi/FujinamiKaiNi AkizukiClass
  ]),
  AntiAirCutInKind(51, fixedBonus: 5, variableBonus: 1.35, rate: null, conditions: [
    AntiAirCutInCondition(ships: {
      426,
      986,
      981
    }, equipment: {
      AaciEquipment.akizukiGunKai: 1,
      AaciEquipment.radar4AaOrMore: 1,
      AaciEquipment.aaGun5Aa: 1
    }), // FubukiKaiNi/ShirayukiKaiNi/FujinamiKaiNi
  ]),
  AntiAirCutInKind(52, fixedBonus: 4, variableBonus: 1.4, rate: null, conditions: [
    AntiAirCutInCondition(ships: {
      426,
      986,
      981
    }, equipment: {
      AaciEquipment.akizukiPotatoGun: 2,
      AaciEquipment.aafd94: 1
    }), // FubukiKaiNi/ShirayukiKaiNi/FujinamiKaiNi
  ]),
];

/// 発動判定の優先順位 (AntiAirCutIn.ActivationPriorities)
const List<int> kAntiAirCutInPriorities = [
  38,
  39,
  40,
  42,
  41,
  10,
  43,
  46,
  11,
  25,
  48,
  1,
  34,
  44,
  26,
  4,
  2,
  35,
  36,
  27,
  45,
  50,
  49,
  51,
  52,
  19,
  21,
  29,
  16,
  14,
  3,
  5,
  6,
  28,
  37,
  33,
  30,
  8,
  13,
  15,
  7,
  20,
  24,
  32,
  12,
  31,
  47,
  17,
  18,
  22,
  9,
  23
];
