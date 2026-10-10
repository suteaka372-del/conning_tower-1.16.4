import 'dart:math';

import 'equipment.dart';
import 'repair_timer.dart';
import 'ship.dart';

// Expedition success checks and great success rates.
// Ported from ElectronicObserver (MIT License,
// Original work Copyright (c) 2014 Andante, Translation work Copyright (c) 2015 Ryuu Kitsune)
// https://github.com/ElectronicObserverEN/ElectronicObserver
// ElectronicObserver/Data/MissionClearCondition.cs
// ElectronicObserver.Avalonia/ExpeditionCalculator/ExpeditionCalculatorData.cs, Extensions.cs
// ElectronicObserver.Core/Types/Extensions/ShipDataStatExtensions.cs (Expedition*Total)

// api_stype
const _de = 1; // 海防艦
const _dd = 2; // 駆逐艦
const _cl = 3; // 軽巡洋艦
const _ca = 5; // 重巡洋艦
const _cvl = 7; // 軽空母
const _bbv = 10; // 航空戦艦
const _cv = 11; // 正規空母
const _ss = 13; // 潜水艦
const _ssv = 14; // 潜水空母
const _av = 16; // 水上機母艦
const _cvb = 18; // 装甲空母
const _as = 20; // 潜水母艦
const _ct = 21; // 練習巡洋艦

// api_mst_slotitem api_type[2]
const _kDrum = 30; // ドラム缶(輸送用)
const Set<int> _kAircraftCategories = {
  6, 7, 8, 9, 10, 11, 25, 26, 41, 45, 47, 48, 49, 53, 56, 57, 58, 59, 94, //
};

/// 艦種の短い名前 (api_stype)
String expeditionShipTypeName(int shipType) => switch (shipType) {
      1 => repairText('海防', 'DE'),
      2 => repairText('駆逐', 'DD'),
      3 => repairText('軽巡', 'CL'),
      4 => repairText('雷巡', 'CLT'),
      5 => repairText('重巡', 'CA'),
      6 => repairText('航巡', 'CAV'),
      7 => repairText('軽空母', 'CVL'),
      8 => repairText('巡洋戦艦', 'FBB'),
      9 => repairText('戦艦', 'BB'),
      10 => repairText('航戦', 'BBV'),
      11 => repairText('正規空母', 'CV'),
      13 => repairText('潜水艦', 'SS'),
      14 => repairText('潜水空母', 'SSV'),
      16 => repairText('水母', 'AV'),
      17 => repairText('揚陸艦', 'LHA'),
      18 => repairText('装甲空母', 'CVB'),
      19 => repairText('工作艦', 'AR'),
      20 => repairText('潜水母艦', 'AS'),
      21 => repairText('練巡', 'CT'),
      22 => repairText('補給艦', 'AO'),
      _ => '?',
    };

/// 大成功のしくみ
enum ExpeditionGreatSuccessType {
  /// 全艦キラ付けが必要
  regular,

  /// ドラム缶を多めに積むと上がる
  drum,

  /// キラ付け隻数と旗艦レベルで上がる
  level;

  String get label => switch (this) {
        regular => repairText('通常型 (全艦キラ付けが必要)', 'Regular (all ships sparkled)'),
        drum => repairText('ドラム缶型 (キラ付けとドラム缶の追加で上がる)', 'Drum (sparkles and extra drums)'),
        level => repairText('旗艦Lv型 (キラ付け隻数と旗艦レベルで上がる)', 'Flagship level (sparkles and flagship level)'),
      };
}

/// 遠征ごとの報酬 (資源) と大成功のしくみ
class ExpeditionInfo {
  final int id;
  final ExpeditionGreatSuccessType greatSuccessType;
  final int fuel;
  final int ammo;
  final int steel;
  final int bauxite;
  final bool monthly;

  const ExpeditionInfo(
    this.id,
    this.greatSuccessType, {
    required this.fuel,
    required this.ammo,
    required this.steel,
    required this.bauxite,
    this.monthly = false,
  });

  List<int> get resources => [fuel, ammo, steel, bauxite];
}

/// ElectronicObserver.Avalonia/ExpeditionCalculator/ExpeditionCalculatorData.cs
final Map<int, ExpeditionInfo> kExpeditionInfo = {
  for (final info in const <ExpeditionInfo>[
    ExpeditionInfo(1, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 30, steel: 0, bauxite: 0), // 01
    ExpeditionInfo(2, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 100, steel: 30, bauxite: 0), // 02
    ExpeditionInfo(3, ExpeditionGreatSuccessType.regular, fuel: 30, ammo: 30, steel: 40, bauxite: 0), // 03
    ExpeditionInfo(4, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 70, steel: 0, bauxite: 0), // 04
    ExpeditionInfo(5, ExpeditionGreatSuccessType.regular, fuel: 200, ammo: 200, steel: 20, bauxite: 20), // 05
    ExpeditionInfo(6, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 0, steel: 0, bauxite: 80), // 06
    ExpeditionInfo(7, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 0, steel: 50, bauxite: 30), // 07
    ExpeditionInfo(8, ExpeditionGreatSuccessType.regular, fuel: 50, ammo: 100, steel: 50, bauxite: 50), // 08
    ExpeditionInfo(100, ExpeditionGreatSuccessType.regular, fuel: 45, ammo: 45, steel: 0, bauxite: 0), // A1
    ExpeditionInfo(101, ExpeditionGreatSuccessType.level, fuel: 70, ammo: 40, steel: 0, bauxite: 10), // A2
    ExpeditionInfo(102, ExpeditionGreatSuccessType.level, fuel: 120, ammo: 0, steel: 60, bauxite: 60), // A3
    ExpeditionInfo(103, ExpeditionGreatSuccessType.level, fuel: 80, ammo: 120, steel: 0, bauxite: 100, monthly: true), // A4
    ExpeditionInfo(104, ExpeditionGreatSuccessType.level, fuel: 0, ammo: 300, steel: 0, bauxite: 100, monthly: true), // A5
    ExpeditionInfo(105, ExpeditionGreatSuccessType.level, fuel: 100, ammo: 500, steel: 100, bauxite: 200, monthly: true), // A6
    ExpeditionInfo(9, ExpeditionGreatSuccessType.regular, fuel: 350, ammo: 0, steel: 0, bauxite: 0), // 09
    ExpeditionInfo(10, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 50, steel: 0, bauxite: 30), // 10
    ExpeditionInfo(11, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 0, steel: 0, bauxite: 250), // 11
    ExpeditionInfo(12, ExpeditionGreatSuccessType.regular, fuel: 50, ammo: 250, steel: 200, bauxite: 50), // 12
    ExpeditionInfo(13, ExpeditionGreatSuccessType.regular, fuel: 240, ammo: 300, steel: 0, bauxite: 0), // 13
    ExpeditionInfo(14, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 240, steel: 200, bauxite: 30), // 14
    ExpeditionInfo(15, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 0, steel: 300, bauxite: 400), // 15
    ExpeditionInfo(16, ExpeditionGreatSuccessType.regular, fuel: 500, ammo: 500, steel: 200, bauxite: 200), // 16
    ExpeditionInfo(110, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 0, steel: 10, bauxite: 30), // B1
    ExpeditionInfo(111, ExpeditionGreatSuccessType.regular, fuel: 300, ammo: 200, steel: 100, bauxite: 0, monthly: true), // B2
    ExpeditionInfo(112, ExpeditionGreatSuccessType.level, fuel: 0, ammo: 100, steel: 100, bauxite: 180, monthly: true), // B3
    ExpeditionInfo(113, ExpeditionGreatSuccessType.level, fuel: 0, ammo: 0, steel: 1200, bauxite: 650, monthly: true), // B4
    ExpeditionInfo(114, ExpeditionGreatSuccessType.level, fuel: 500, ammo: 500, steel: 1000, bauxite: 750, monthly: true), // B5
    ExpeditionInfo(115, ExpeditionGreatSuccessType.level, fuel: 600, ammo: 1000, steel: 600, bauxite: 600, monthly: true), // B6
    ExpeditionInfo(17, ExpeditionGreatSuccessType.regular, fuel: 70, ammo: 70, steel: 50, bauxite: 0), // 17
    ExpeditionInfo(18, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 0, steel: 300, bauxite: 100), // 18
    ExpeditionInfo(19, ExpeditionGreatSuccessType.regular, fuel: 400, ammo: 50, steel: 50, bauxite: 30), // 19
    ExpeditionInfo(20, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 0, steel: 150, bauxite: 0), // 20
    ExpeditionInfo(21, ExpeditionGreatSuccessType.drum, fuel: 320, ammo: 270, steel: 0, bauxite: 0), // 21
    ExpeditionInfo(22, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 10, steel: 0, bauxite: 0), // 22
    ExpeditionInfo(23, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 20, steel: 0, bauxite: 100), // 23
    ExpeditionInfo(24, ExpeditionGreatSuccessType.drum, fuel: 500, ammo: 0, steel: 0, bauxite: 150), // 24
    ExpeditionInfo(41, ExpeditionGreatSuccessType.level, fuel: 100, ammo: 0, steel: 0, bauxite: 20), // 41
    ExpeditionInfo(42, ExpeditionGreatSuccessType.regular, fuel: 800, ammo: 0, steel: 0, bauxite: 200, monthly: true), // 42
    ExpeditionInfo(43, ExpeditionGreatSuccessType.level, fuel: 2000, ammo: 0, steel: 0, bauxite: 400, monthly: true), // 43
    ExpeditionInfo(44, ExpeditionGreatSuccessType.drum, fuel: 0, ammo: 200, steel: 0, bauxite: 800, monthly: true), // 44
    ExpeditionInfo(45, ExpeditionGreatSuccessType.level, fuel: 40, ammo: 0, steel: 0, bauxite: 220), // 45
    ExpeditionInfo(46, ExpeditionGreatSuccessType.level, fuel: 300, ammo: 0, steel: 150, bauxite: 380, monthly: true), // 46
    ExpeditionInfo(25, ExpeditionGreatSuccessType.regular, fuel: 900, ammo: 0, steel: 500, bauxite: 0), // 25
    ExpeditionInfo(26, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 0, steel: 0, bauxite: 900), // 26
    ExpeditionInfo(27, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 0, steel: 800, bauxite: 0), // 27
    ExpeditionInfo(28, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 0, steel: 900, bauxite: 350), // 28
    ExpeditionInfo(29, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 50, steel: 0, bauxite: 100), // 29
    ExpeditionInfo(30, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 50, steel: 0, bauxite: 100), // 30
    ExpeditionInfo(31, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 30, steel: 0, bauxite: 0), // 31
    ExpeditionInfo(32, ExpeditionGreatSuccessType.level, fuel: 50, ammo: 50, steel: 50, bauxite: 50), // 32
    ExpeditionInfo(131, ExpeditionGreatSuccessType.level, fuel: 0, ammo: 20, steel: 20, bauxite: 100), // D1
    ExpeditionInfo(132, ExpeditionGreatSuccessType.level, fuel: 0, ammo: 0, steel: 400, bauxite: 800, monthly: true), // D2
    ExpeditionInfo(133, ExpeditionGreatSuccessType.level, fuel: 0, ammo: 800, steel: 500, bauxite: 400, monthly: true), // D3
    ExpeditionInfo(35, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 0, steel: 240, bauxite: 280), // 35
    ExpeditionInfo(36, ExpeditionGreatSuccessType.regular, fuel: 480, ammo: 0, steel: 200, bauxite: 200), // 36
    ExpeditionInfo(37, ExpeditionGreatSuccessType.drum, fuel: 0, ammo: 380, steel: 270, bauxite: 0), // 37
    ExpeditionInfo(38, ExpeditionGreatSuccessType.drum, fuel: 420, ammo: 0, steel: 200, bauxite: 0), // 38
    ExpeditionInfo(39, ExpeditionGreatSuccessType.regular, fuel: 0, ammo: 30, steel: 300, bauxite: 0), // 39
    ExpeditionInfo(40, ExpeditionGreatSuccessType.drum, fuel: 300, ammo: 300, steel: 100, bauxite: 0), // 40
    ExpeditionInfo(141, ExpeditionGreatSuccessType.level, fuel: 0, ammo: 600, steel: 600, bauxite: 1000, monthly: true), // E1
    ExpeditionInfo(142, ExpeditionGreatSuccessType.drum, fuel: 0, ammo: 480, steel: 0, bauxite: 0, monthly: true), // E2
  ])
    info.id: info
};

/// ドラム缶型の大成功ボーナスが付くドラム缶の数 (Extensions.cs DrumBonus)
const Map<int, int> _kDrumBonusCount = {21: 4, 24: 2, 37: 5, 38: 10, 40: 4, 44: 8, 142: 6};

/// 遠征の判定に使う艦隊の値
class ExpeditionFleet {
  final List<Ship> ships;

  const ExpeditionFleet(this.ships);

  bool get isEmpty => ships.isEmpty;

  int get shipCount => ships.length;

  int get flagshipLevel => ships.isEmpty ? 0 : ships.first.level;

  int? get flagshipType => ships.isEmpty ? null : ships.first.shipType;

  int get levelSum => ships.fold(0, (sum, s) => sum + s.level);

  int countTypes(Set<int> types) => ships.where((s) => types.contains(s.shipType)).length;

  int get smallShipCount => countTypes({_dd, _de});

  int carrierCount({bool includeSeaplaneTender = true}) =>
      countTypes({_cvl, _cv, _cvb, if (includeSeaplaneTender) _av});

  int get submarineCount => countTypes({_ss, _ssv});

  static List<Equipment> _equipment(Ship ship) => [...?ship.equipment, ...?ship.exEquipment];

  static int _category(Equipment equipment) =>
      (equipment.type?.length ?? 0) > 2 ? equipment.type![2] : 0;

  /// その種類の装備を1つ以上積んでいる艦の数
  int equippedShipCount(int category) =>
      ships.where((s) => _equipment(s).any((e) => _category(e) == category)).length;

  /// その種類の装備の合計数
  int equipmentCount(int category) =>
      ships.fold(0, (sum, s) => sum + _equipment(s).where((e) => _category(e) == category).length);

  int get drumCount => equipmentCount(_kDrum);

  int get sparkleCount => ships.where((s) => (s.condition ?? 0) > 49).length;

  bool get allSparkled => ships.isNotEmpty && sparkleCount == ships.length;

  /// 素の対潜 (装備の分を除く)
  static int _baseAsw(Ship ship) =>
      (ship.antiSubmarine?[0] ?? 0) - _equipment(ship).fold(0, (sum, e) => sum + (e.asw ?? 0));

  /// 護衛空母 (対潜のある軽空母)
  static bool _isEscortCarrier(Ship ship) => ship.shipType == _cvl && _baseAsw(ship) > 0;

  int get escortCarrierCount => ships.where(_isEscortCarrier).length;

  static double _sqrtLevel(Equipment e) => sqrt(e.level ?? 0);

  static int _firepower(Ship ship) =>
      (ship.attack?[0] ?? 0) +
      _equipment(ship).fold(0.0, (sum, e) {
        return sum +
            switch (_category(e)) {
              1 => 0.5 * _sqrtLevel(e), // 小口径主砲
              2 => _sqrtLevel(e), // 中口径主砲
              4 => 0.15 * _sqrtLevel(e), // 副砲
              3 || 38 => 0.9 * _sqrtLevel(e), // 大口径主砲
              19 || 21 => 0.5 * _sqrtLevel(e), // 対艦強化弾・対空機銃
              _ => 0.0,
            };
      }).toInt();

  static int _asw(Ship ship) =>
      (ship.antiSubmarine?[0] ?? 0) +
      _equipment(ship).fold(0.0, (sum, e) {
        return sum +
            switch (_category(e)) {
              14 || 15 => _sqrtLevel(e), // ソナー・爆雷
              _ => 0.0,
            };
      }).toInt();

  static int _los(Ship ship) =>
      (ship.scout?[0] ?? 0) +
      _equipment(ship).fold(0.0, (sum, e) {
        return sum +
            switch (_category(e)) {
              12 || 13 || 93 => _sqrtLevel(e), // 電探
              _ => 0.0,
            };
      }).toInt();

  static int _aa(Ship ship) =>
      (ship.antiAircraft?[0] ?? 0) +
      _equipment(ship).fold(0.0, (sum, e) {
        final isHighAngleGun = (e.type?.length ?? 0) > 3 && e.type![3] == 16;
        return sum +
            (_category(e) == 21
                ? 0.9 * (e.level ?? 0) // 対空機銃
                : isHighAngleGun
                    ? 0.3 * (e.level ?? 0) // 高角砲
                    : 0.0);
      }).toInt();

  /// 遠征での火力の合計 (改修値込み)
  int get firepower => ships.fold(0, (sum, s) => sum + _firepower(s));

  /// 遠征での対空の合計 (改修値込み)
  int get antiAircraft => ships.fold(0, (sum, s) => sum + _aa(s));

  /// 遠征での対潜の合計 (改修値込み、水上偵察機・水上爆撃機・飛行艇の分は数えない)
  int get antiSubmarine => ships.fold(0, (sum, s) {
        final seaplaneAsw = _equipment(s)
            .where((e) => const {10, 11, 41}.contains(_category(e)))
            .fold(0, (sum, e) => sum + (e.asw ?? 0));
        return sum + _asw(s) - seaplaneAsw;
      });

  /// 遠征での索敵の合計 (改修値込み)
  int get lineOfSight => ships.fold(0, (sum, s) => sum + _los(s));

  /// 搭載数0の艦載機があるか
  bool get hasZeroSlotAircraft => ships.any((s) {
        final equipment = s.equipment ?? const <Equipment>[];
        final onSlot = s.onSlot ?? const <int>[];
        for (var i = 0; i < equipment.length && i < onSlot.length; i++) {
          if (_kAircraftCategories.contains(_category(equipment[i])) && onSlot[i] == 0) return true;
        }
        return false;
      });
}

enum ExpeditionParameter {
  firepower,
  antiAircraft,
  antiSubmarine,
  lineOfSight;

  String get label => switch (this) {
        firepower => repairText('火力合計', 'Firepower'),
        antiAircraft => repairText('対空合計', 'AA'),
        antiSubmarine => repairText('対潜合計', 'ASW'),
        lineOfSight => repairText('索敵合計', 'LoS'),
      };

  int valueOf(ExpeditionFleet fleet) => switch (this) {
        firepower => fleet.firepower,
        antiAircraft => fleet.antiAircraft,
        antiSubmarine => fleet.antiSubmarine,
        lineOfSight => fleet.lineOfSight,
      };
}

/// 遠征の条件1つ分
class ExpeditionRequirement {
  /// 条件の名前 (旗艦Lv、駆逐 など)
  final String label;

  /// 必要な値の表示
  final String requiredText;

  /// 数値の条件なら必要な値
  final int? required;

  /// 火力・対空・対潜・索敵の条件
  final ExpeditionParameter? parameter;

  final int Function(ExpeditionFleet fleet)? _value;
  final bool Function(ExpeditionFleet fleet) _isMet;

  ExpeditionRequirement._(
    this.label,
    this.requiredText,
    this._isMet, {
    this.required,
    this.parameter,
    int Function(ExpeditionFleet fleet)? value,
  }) : _value = value;

  /// 「必要数以上」の条件
  factory ExpeditionRequirement.atLeast(
          String label, int required, int Function(ExpeditionFleet fleet) value,
          {ExpeditionParameter? parameter}) =>
      ExpeditionRequirement._(label, '$required', (f) => value(f) >= required,
          required: required, parameter: parameter, value: value);

  bool isMet(ExpeditionFleet fleet) => _isMet(fleet);

  /// 艦隊の値 (数値でない条件は null)
  int? valueOf(ExpeditionFleet fleet) => _value?.call(fleet);

  /// 艦隊の値の表示
  String actualText(ExpeditionFleet fleet) {
    final value = valueOf(fleet);
    if (value != null) return '$value';
    return isMet(fleet) ? '○' : '×';
  }
}

// ---- 条件の定義用 (MissionClearCondition の Check* と同じ) ----
ExpeditionRequirement _flagshipLevel(int n) =>
    ExpeditionRequirement.atLeast(repairText('旗艦Lv', 'Flagship Lv'), n, (f) => f.flagshipLevel);

ExpeditionRequirement _levelSum(int n) =>
    ExpeditionRequirement.atLeast(repairText('Lv合計', 'Lv total'), n, (f) => f.levelSum);

ExpeditionRequirement _shipCount(int n) =>
    ExpeditionRequirement.atLeast(repairText('艦数', 'Ships'), n, (f) => f.shipCount);

ExpeditionRequirement _type(int shipType, int n) =>
    ExpeditionRequirement.atLeast(expeditionShipTypeName(shipType), n, (f) => f.countTypes({shipType}));

ExpeditionRequirement _smallShips(int n) =>
    ExpeditionRequirement.atLeast(repairText('駆逐+海防', 'DD+DE'), n, (f) => f.smallShipCount);

ExpeditionRequirement _carriers(int n, {bool includeSeaplaneTender = true}) =>
    ExpeditionRequirement.atLeast(
        includeSeaplaneTender
            ? repairText('空母系', 'Carriers')
            : repairText('空母系(水母除く)', 'Carriers (no AV)'),
        n,
        (f) => f.carrierCount(includeSeaplaneTender: includeSeaplaneTender));

ExpeditionRequirement _submarines(int n) =>
    ExpeditionRequirement.atLeast(repairText('潜水艦系', 'Submarines'), n, (f) => f.submarineCount);

ExpeditionRequirement _drumShips(int n) => ExpeditionRequirement.atLeast(
    repairText('ドラム缶搭載艦', 'Ships with drums'), n, (f) => f.equippedShipCount(_kDrum));

ExpeditionRequirement _drums(int n) =>
    ExpeditionRequirement.atLeast(repairText('ドラム缶', 'Drums'), n, (f) => f.drumCount);

ExpeditionRequirement _parameter(ExpeditionParameter parameter, int n) =>
    ExpeditionRequirement.atLeast(parameter.label, n, parameter.valueOf, parameter: parameter);

ExpeditionRequirement _firepower(int n) => _parameter(ExpeditionParameter.firepower, n);
ExpeditionRequirement _aa(int n) => _parameter(ExpeditionParameter.antiAircraft, n);
ExpeditionRequirement _asw(int n) => _parameter(ExpeditionParameter.antiSubmarine, n);
ExpeditionRequirement _los(int n) => _parameter(ExpeditionParameter.lineOfSight, n);

ExpeditionRequirement _flagshipType(int shipType) => ExpeditionRequirement._(
    repairText('旗艦', 'Flagship'), expeditionShipTypeName(shipType), (f) => f.flagshipType == shipType);

({int cl, int dd, int de, int ct, int escortCarrier}) _escortCounts(ExpeditionFleet f) => (
      cl: f.countTypes({_cl}),
      dd: f.countTypes({_dd}),
      de: f.countTypes({_de}),
      ct: f.countTypes({_ct}),
      escortCarrier: f.escortCarrierCount,
    );

bool _escortCommon(({int cl, int dd, int de, int ct, int escortCarrier}) c) =>
    (c.escortCarrier >= 1 && (c.dd >= 2 || c.de >= 2)) ||
    (c.dd >= 1 && c.de >= 3) ||
    (c.ct >= 1 && c.de >= 2);

/// 護衛隊 (軽巡+(駆逐+海防)2 / 護衛空母+(駆逐2 or 海防2) / 駆逐+海防3 / 練巡+海防2)
ExpeditionRequirement _escortFleet() => ExpeditionRequirement._(
      repairText('護衛隊', 'Escort'),
      repairText('軽巡1駆逐2など', 'CL+2 DD etc.'),
      (f) {
        final c = _escortCounts(f);
        return (c.cl >= 1 && (c.dd + c.de) >= 2) || _escortCommon(c);
      },
    );

/// 護衛隊 (軽巡+駆逐3 など)。[includeEscorts] なら軽巡+(駆逐+海防)3 でもよい
ExpeditionRequirement _escortFleetDD3(bool includeEscorts) => ExpeditionRequirement._(
      repairText('護衛隊', 'Escort'),
      repairText('軽巡1駆逐3など', 'CL+3 DD etc.'),
      (f) {
        final c = _escortCounts(f);
        final destroyers = includeEscorts ? c.dd + c.de : c.dd;
        return (destroyers >= 3 && c.cl >= 1) || (c.cl >= 1 && c.de >= 2) || _escortCommon(c);
      },
    );

/// 護衛隊 (軽巡+(駆逐+海防)4 など)
ExpeditionRequirement _escortFleetDD4() => ExpeditionRequirement._(
      repairText('護衛隊', 'Escort'),
      repairText('軽巡1駆逐4など', 'CL+4 DD etc.'),
      (f) {
        final c = _escortCounts(f);
        return (c.cl >= 1 && (c.dd + c.de) >= 4) || (c.cl >= 1 && c.de >= 2) || _escortCommon(c);
      },
    );

/// 遠征ごとの条件 (MissionClearCondition.CheckMissionCondition)
final Map<int, List<ExpeditionRequirement>> kExpeditionRequirements = {
  1: [_flagshipLevel(1), _shipCount(2)], // 練習航海
  2: [_flagshipLevel(2), _shipCount(4)], // 長距離練習航海
  3: [_flagshipLevel(3), _shipCount(3)], // 警備任務
  4: [_flagshipLevel(3), _escortFleet()], // 対潜警戒任務
  5: [_flagshipLevel(3), _shipCount(4), _escortFleet()], // 海上護衛任務
  6: [_flagshipLevel(4), _shipCount(4)], // 防空射撃演習
  7: [_flagshipLevel(5), _shipCount(6)], // 観艦式予行
  8: [_flagshipLevel(6), _shipCount(6)], // 観艦式
  100: [_flagshipLevel(5), _levelSum(10), _shipCount(4), _smallShips(3)], // 兵站強化任務
  101: [_flagshipLevel(20), _smallShips(4), _firepower(50), _aa(70), _asw(180)], // 海峡警備行動
  102: [_flagshipLevel(35), _levelSum(185), _shipCount(5), _escortFleetDD3(true), _aa(59), _asw(280), _los(60)], // 長時間対潜警戒
  103: [_flagshipLevel(40), _levelSum(200), _shipCount(5), _escortFleet(), _firepower(300), _aa(200), _asw(200), _los(120)], // 南西方面連絡線哨戒
  104: [_flagshipLevel(45), _levelSum(230), _shipCount(5), _escortFleetDD3(false), _firepower(280), _aa(220), _asw(240), _los(150)], // 小笠原沖哨戒線
  105: [_flagshipLevel(55), _levelSum(290), _shipCount(6), _escortFleetDD3(false), _firepower(330), _aa(300), _asw(270), _los(180)], // 小笠原沖戦闘哨戒
  9: [_flagshipLevel(3), _shipCount(4), _escortFleet()], // タンカー護衛任務
  10: [_flagshipLevel(3), _shipCount(3), _type(_cl, 2)], // 強行偵察任務
  11: [_flagshipLevel(6), _shipCount(4), _smallShips(2)], // ボーキサイト輸送任務
  12: [_flagshipLevel(4), _shipCount(4), _smallShips(2)], // 資源輸送任務
  13: [_flagshipLevel(5), _shipCount(6), _type(_cl, 1), _type(_dd, 4)], // 鼠輸送作戦
  14: [_flagshipLevel(6), _shipCount(6), _type(_cl, 1), _type(_dd, 3)], // 包囲陸戦隊撤収作戦
  15: [_flagshipLevel(8), _shipCount(6), _carriers(2), _type(_dd, 2)], // 囮機動部隊支援作戦
  16: [_flagshipLevel(10), _shipCount(6), _type(_cl, 1), _type(_dd, 2)], // 艦隊決戦援護作戦
  110: [_flagshipLevel(40), _levelSum(150), _shipCount(6), _type(_av, 1), _type(_cl, 1), _smallShips(2), _aa(200), _asw(200), _los(140)], // 南西方面航空偵察作戦
  111: [_flagshipLevel(45), _levelSum(220), _shipCount(6), _type(_ca, 1), _type(_cl, 1), _type(_dd, 3), _firepower(360), _aa(160), _asw(160), _los(140)], // 敵泊地強襲反撃作戦
  112: [_flagshipLevel(50), _levelSum(250), _type(_av, 1), _type(_cl, 1), _smallShips(4), _firepower(400), _aa(220), _asw(220), _los(190)], // 南西諸島離島哨戒作戦
  113: [_flagshipLevel(55), _levelSum(300), _type(_ca, 2), _type(_cl, 1), _type(_dd, 2), _submarines(1), _firepower(500), _aa(280), _asw(280), _los(170)], // 南西諸島離島防衛作戦
  114: [_flagshipLevel(60), _levelSum(330), _shipCount(6), _type(_av, 1), _type(_cl, 1), _type(_dd, 2), _firepower(510), _aa(400), _asw(285), _los(385)], // 南西諸島捜索撃滅戦
  115: [_flagshipLevel(75), _levelSum(400), _flagshipType(_cl), _type(_dd, 5), _firepower(410), _aa(390), _asw(410), _los(340)], // 精鋭水雷戦隊夜襲
  17: [_flagshipLevel(20), _shipCount(6), _type(_cl, 1), _type(_dd, 3)], // 敵地偵察作戦
  18: [_flagshipLevel(15), _shipCount(6), _carriers(3), _type(_dd, 2)], // 航空機輸送作戦
  19: [_flagshipLevel(20), _shipCount(6), _type(_bbv, 2), _type(_dd, 2)], // 北号作戦
  20: [_flagshipLevel(1), _submarines(1), _type(_cl, 1)], // 潜水艦哨戒任務
  21: [_flagshipLevel(15), _levelSum(30), _type(_cl, 1), _type(_dd, 4), _drumShips(3)], // 北方鼠輸送作戦
  22: [_flagshipLevel(30), _levelSum(45), _shipCount(6), _type(_ca, 1), _type(_cl, 1), _type(_dd, 2)], // 艦隊演習
  23: [_flagshipLevel(50), _levelSum(200), _shipCount(6), _type(_bbv, 2), _type(_dd, 2)], // 航空戦艦運用演習
  24: [_flagshipLevel(50), _levelSum(200), _shipCount(6), _flagshipType(_cl), _smallShips(4)], // 北方航路海上護衛
  25: [_flagshipLevel(25), _type(_ca, 2), _type(_dd, 2)], // 通商破壊作戦
  26: [_flagshipLevel(30), _carriers(1), _type(_cl, 1), _type(_dd, 2)], // 敵母港空襲作戦
  27: [_flagshipLevel(1), _submarines(2)], // 潜水艦通商破壊作戦
  28: [_flagshipLevel(30), _submarines(3)], // 西方海域封鎖作戦
  29: [_flagshipLevel(50), _submarines(3)], // 潜水艦派遣演習
  30: [_flagshipLevel(55), _submarines(4)], // 潜水艦派遣作戦
  31: [_flagshipLevel(60), _levelSum(200), _submarines(4)], // 海外艦との接触
  32: [_flagshipLevel(5), _flagshipType(_ct), _type(_dd, 2)], // 遠洋練習航海
  131: [_flagshipLevel(50), _levelSum(200), _shipCount(5), _flagshipType(_av), _type(_dd, 3), _aa(240), _asw(240), _los(300)], // 西方海域偵察作戦
  132: [_flagshipLevel(55), _levelSum(270), _shipCount(5), _flagshipType(_as), _submarines(3), _firepower(60), _aa(80), _asw(50)], // 西方潜水艦作戦
  133: [_flagshipLevel(65), _levelSum(350), _flagshipType(_as), _submarines(3), _shipCount(5), _firepower(115), _aa(90), _asw(70), _los(95)], // 欧州方面友軍との接触
  33: [_type(_dd, 2)], // 前衛支援任務
  34: [_type(_dd, 2)], // 艦隊決戦支援任務
  35: [_flagshipLevel(40), _shipCount(6), _carriers(2), _type(_ca, 1), _type(_dd, 1)], // MO作戦
  36: [_flagshipLevel(30), _shipCount(6), _type(_av, 2), _type(_cl, 1), _type(_dd, 1)], // 水上機基地建設
  37: [_flagshipLevel(50), _levelSum(200), _type(_cl, 1), _type(_dd, 5), _drumShips(3), _drums(4)], // 東京急行
  38: [_flagshipLevel(65), _levelSum(240), _shipCount(6), _type(_dd, 5), _drumShips(4), _drums(8)], // 東京急行(弐)
  39: [_flagshipLevel(3), _levelSum(180), _type(_as, 1), _submarines(4)], // 遠洋潜水艦作戦
  40: [_flagshipLevel(25), _levelSum(150), _shipCount(6), _flagshipType(_cl), _type(_av, 2), _type(_dd, 2)], // 水上機前線輸送
  141: [_flagshipLevel(55), _levelSum(290), _shipCount(6), _flagshipType(_ca), _type(_cl, 1), _type(_dd, 3), _firepower(450), _aa(350), _asw(330), _los(250)], // ラバウル方面艦隊進出
  142: [_flagshipLevel(70), _levelSum(320), _type(_dd, 5), _drumShips(3), _drums(4), _firepower(280), _aa(240), _asw(200), _los(160)], // 強行鼠輸送作戦
  41: [_flagshipLevel(30), _levelSum(100), _smallShips(3), _firepower(60), _aa(80), _asw(210)], // ブルネイ泊地沖哨戒
  42: [_flagshipLevel(45), _levelSum(200), _shipCount(4), _escortFleet()], // ミ船団護衛(一号船団)
  43: [_flagshipLevel(55), _levelSum(300), _shipCount(6), _flagshipType(_cvl), _escortFleetDD4(), _firepower(500), _aa(280), _asw(280), _los(170)], // ミ船団護衛(二号船団)
  44: [
    _flagshipLevel(35),
    _levelSum(210),
    _shipCount(6),
    ExpeditionRequirement._(
      repairText('水母・空母', 'AV/Carriers'),
      repairText('水母2 か 水母1+空母1', '2 AV or AV+carrier'),
      (f) =>
          f.countTypes({_av}) >= 2 ||
          (f.countTypes({_av}) >= 1 && f.carrierCount(includeSeaplaneTender: false) >= 1),
    ),
    _type(_cl, 1),
    _smallShips(2),
    _drumShips(3),
    _drums(6),
    _aa(200),
    _asw(200),
    _los(150),
  ], // 航空装備輸送任務
  45: [_flagshipLevel(50), _levelSum(240), _flagshipType(_cvl), _smallShips(4), _aa(240), _asw(300), _los(180)], // ボーキサイト船団護衛
  46: [_flagshipLevel(60), _levelSum(300), _shipCount(5), _type(_ca, 2), _type(_cl, 1), _type(_dd, 2), _firepower(350), _aa(250), _asw(220), _los(190)], // 南西海域戦闘哨戒
};

/// 遠征の条件 (イベント海域の支援遠征は名前で判断する)。対応していなければ null
List<ExpeditionRequirement>? expeditionRequirements(int missionId, {String? missionName}) {
  final requirements = kExpeditionRequirements[missionId];
  if (requirements != null) return requirements;
  if (missionName == '前衛支援任務' || missionName == '艦隊決戦支援任務') {
    return kExpeditionRequirements[33];
  }
  return null;
}

/// 1艦隊分の判定結果
class ExpeditionCheckResult {
  /// 条件のデータがあるか
  final bool supported;

  /// 艦隊が空か
  final bool emptyFleet;

  final bool success;

  /// 条件ごとの成否
  final List<(ExpeditionRequirement, bool)> requirements;

  /// 搭載数0の艦載機があって失敗する
  final bool zeroSlotAircraft;

  /// 大成功率 (成功するときだけ。分からなければ null)
  final double? greatSuccessRate;

  /// 火力などがすべて必要値の2.2倍以上 (戦闘のある遠征で被害なし)
  final bool noDamage;

  const ExpeditionCheckResult({
    required this.supported,
    required this.emptyFleet,
    required this.success,
    required this.requirements,
    this.zeroSlotAircraft = false,
    this.greatSuccessRate,
    this.noDamage = false,
  });

  /// 足りない条件の名前
  List<String> get failureLabels => [
        for (final (requirement, met) in requirements)
          if (!met) requirement.label,
        if (zeroSlotAircraft) repairText('搭載数0の機体', 'Empty aircraft slot'),
      ];
}

/// 大成功率 (Extensions.cs GreatSuccessRate)
double? expeditionGreatSuccessRate(int missionId, ExpeditionFleet fleet) {
  final info = kExpeditionInfo[missionId];
  if (info == null || fleet.isEmpty) return null;
  final sparkles = fleet.sparkleCount;
  final rate = switch (info.greatSuccessType) {
    ExpeditionGreatSuccessType.regular => fleet.allSparkled ? sparkles * 0.15 + 0.21 : 0.0,
    ExpeditionGreatSuccessType.drum =>
      sparkles * 0.15 + (fleet.drumCount >= (_kDrumBonusCount[missionId] ?? 1 << 30) ? 0.41 : 0.06),
    ExpeditionGreatSuccessType.level =>
      sparkles * 0.15 + 0.16 + sqrt(fleet.flagshipLevel) / 100 + fleet.flagshipLevel / 1000.0,
  };
  return rate.clamp(0.0, 1.0).toDouble();
}

/// 遠征に成功するかを判定する
ExpeditionCheckResult checkExpedition(int missionId, List<Ship> ships, {String? missionName}) {
  final requirements = expeditionRequirements(missionId, missionName: missionName);
  final fleet = ExpeditionFleet(ships);
  if (requirements == null) {
    return ExpeditionCheckResult(
        supported: false, emptyFleet: fleet.isEmpty, success: false, requirements: const []);
  }
  final results = [for (final r in requirements) (r, r.isMet(fleet))];
  final parameters = [
    for (final r in requirements)
      if (r.parameter != null && r.required != null) r
  ];
  final zeroSlot = parameters.isNotEmpty && fleet.hasZeroSlotAircraft;
  final success = !fleet.isEmpty && !zeroSlot && results.every((e) => e.$2);
  final noDamage = parameters.isNotEmpty &&
      parameters.every((r) => r.valueOf(fleet)! >= r.required! * 2.2);
  return ExpeditionCheckResult(
    supported: true,
    emptyFleet: fleet.isEmpty,
    success: success,
    requirements: results,
    zeroSlotAircraft: zeroSlot,
    greatSuccessRate: success ? expeditionGreatSuccessRate(missionId, fleet) : null,
    noDamage: noDamage,
  );
}
