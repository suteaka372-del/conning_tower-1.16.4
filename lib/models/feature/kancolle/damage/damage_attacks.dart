// ダメージシミュレーター: 艦の装備から、できる攻撃と最終攻撃力を出す。
// 計算式は compass ・ air と同じく「艦これ攻略 Wiki*」の内容を元に書き直したもの (damage_engine.dart の説明を参照)。

import 'dart:math';

import 'damage_engine.dart';

export 'damage_engine.dart';

// 装備の種類 (api_type[2])
const kDmgSmallGun = 1, kDmgMediumGun = 2, kDmgLargeGun = 3, kDmgSecondary = 4, kDmgTorpedo = 5;
const kDmgFighter = 6, kDmgDiveBomber = 7, kDmgTorpedoBomber = 8, kDmgSeaplaneRecon = 10, kDmgSeaplaneBomber = 11;
const kDmgSmallRadar = 12, kDmgLargeRadar = 13, kDmgSonar = 14, kDmgDepthCharge = 15, kDmgAaShell = 18, kDmgApShell = 19;
const kDmgAaGun = 21, kDmgMidgetSub = 22, kDmgLandingCraft = 24, kDmgAutogyro = 25, kDmgAswPatrol = 26, kDmgSearchlight = 29;
const kDmgSubTorpedo = 32, kDmgCommand = 34, kDmgAaDirector = 36, kDmgGroundAttack = 37, kDmgLargeGun2 = 38;
const kDmgSurfaceCrew = 39, kDmgLargeSonar = 40, kDmgFlyingBoat = 41, kDmgLargeSearchlight = 42, kDmgSeaplaneFighter = 45;
const kDmgSpecialAmphibious = 46, kDmgSubRadar = 51, kDmgSmoke = 54, kDmgJetFighter = 56, kDmgJetFighterBomber = 57;
const kDmgJetAttacker = 58, kDmgLargeRadar2 = 93;

// 艦種 (api_stype)
const kDmgDE = 1, kDmgDD = 2, kDmgCL = 3, kDmgCLT = 4, kDmgCA = 5, kDmgCAV = 6, kDmgCVL = 7, kDmgFBB = 8, kDmgBB = 9;
const kDmgBBV = 10, kDmgCV = 11, kDmgSS = 13, kDmgSSV = 14, kDmgAV = 16, kDmgLHA = 17, kDmgCVB = 18, kDmgCT = 21, kDmgAO = 22;

/// 軽巡軽量砲 (単装・連装)
const kDmgLightSingleGuns = {4, 11};
const kDmgLightTwinGuns = {65, 119, 139, 303, 310, 359, 360, 361, 407, 518, 534, 535};

/// 副砲の改修効果が 0.3×★ のもの (15.5cm三連装副砲/改、15.2cm三連装砲)
const kDmgSecondaryC = {12, 234, 247};

/// 1つの装備
class DamageEquip {
  final int itemId;
  final String name;

  /// 種類 (api_type[2])
  final int category;

  /// アイコン (api_type[3]。16 = 高角砲、45 = 夜戦、46 = 夜攻、58 = 夜爆)
  final int icon;
  final int firepower;
  final int torpedo;
  final int bombing;
  final int asw;
  final int los;
  final int aa;
  final int armor;

  /// 改修値 (★)
  final int improvement;

  /// 艦載機熟練度 (0〜7)
  final int proficiency;

  /// 搭載数 (艦載機のスロットのみ)
  final int count;

  /// 何番目のスロットか (補強増設は -1)
  final int slot;

  const DamageEquip({
    this.itemId = 0,
    this.name = '',
    required this.category,
    this.icon = 0,
    this.firepower = 0,
    this.torpedo = 0,
    this.bombing = 0,
    this.asw = 0,
    this.los = 0,
    this.aa = 0,
    this.armor = 0,
    this.improvement = 0,
    this.proficiency = 0,
    this.count = 0,
    this.slot = 0,
  });

  bool get isMainGun => const {kDmgSmallGun, kDmgMediumGun, kDmgLargeGun, kDmgLargeGun2}.contains(category);
  bool get isSecondary => category == kDmgSecondary;
  bool get isTorpedo => category == kDmgTorpedo || category == kDmgSubTorpedo;
  bool get isRadar => const {kDmgSmallRadar, kDmgLargeRadar, kDmgLargeRadar2}.contains(category);
  bool get isSeaplaneSpotter => (category == kDmgSeaplaneRecon || category == kDmgSeaplaneBomber) && count > 0;

  /// 爆戦 (艦爆のうち対空の高いもの。カットインでは艦爆扱い、改修で砲撃・航空攻撃の攻撃力は上がらない)
  bool get isFighterBomber => category == kDmgDiveBomber && aa > 3;

  /// 昼砲撃・航空攻撃をする艦載機 (搭載数1以上)
  bool get isAttackPlane => const {kDmgDiveBomber, kDmgTorpedoBomber, kDmgJetFighterBomber}.contains(category) && count > 0;

  /// 熟練度クリティカル補正の対象 (艦攻・艦爆・噴式爆撃機・水爆・大型飛行艇)
  bool get hasProficiencyCritical =>
      const {kDmgDiveBomber, kDmgTorpedoBomber, kDmgJetFighterBomber, kDmgJetAttacker, kDmgSeaplaneBomber, kDmgFlyingBoat}.contains(category) &&
      proficiency > 0 &&
      count > 0;

  /// 改修による攻撃力の上乗せ (昼砲撃)
  double get shellingImprovement {
    final s = sqrt(improvement);
    if (improvement <= 0) return 0;
    switch (category) {
      case kDmgSmallGun || kDmgMediumGun:
        return s;
      case kDmgLargeGun || kDmgLargeGun2:
        return 1.5 * s;
      case kDmgSecondary:
        if (kDmgSecondaryC.contains(itemId)) return 0.3 * improvement;
        return icon == 16 ? 0.2 * improvement : s;
      case kDmgSonar || kDmgLargeSonar:
        return 0.75 * s;
      case kDmgDepthCharge:
        return kDmgDepthCharges.contains(itemId) ? 0 : 0.75 * s;
      case kDmgSubTorpedo || kDmgAaShell || kDmgApShell || kDmgAaGun || kDmgAaDirector || kDmgLandingCraft:
      case kDmgSpecialAmphibious || kDmgGroundAttack || kDmgSearchlight || kDmgLargeSearchlight || kDmgSurfaceCrew:
      case kDmgCommand || kDmgSmoke:
        return s;
      case kDmgDiveBomber:
        return isFighterBomber ? 0 : 0.2 * improvement;
      case kDmgTorpedoBomber:
        return 0.2 * improvement;
      default:
        return 0;
    }
  }

  /// 改修による攻撃力の上乗せ (雷撃)
  double get torpedoImprovement {
    if (improvement <= 0) return 0;
    return switch (category) {
      kDmgTorpedo || kDmgAaGun => 1.2 * sqrt(improvement),
      kDmgSubTorpedo => 0.2 * improvement,
      _ => 0,
    };
  }

  /// 改修による攻撃力の上乗せ (夜戦)
  double get nightImprovement {
    final s = sqrt(improvement);
    if (improvement <= 0) return 0;
    switch (category) {
      case kDmgSmallGun || kDmgMediumGun || kDmgLargeGun || kDmgLargeGun2:
      case kDmgTorpedo || kDmgMidgetSub || kDmgAaShell || kDmgApShell || kDmgAaDirector || kDmgLandingCraft:
      case kDmgSpecialAmphibious || kDmgGroundAttack || kDmgSearchlight || kDmgLargeSearchlight || kDmgSurfaceCrew:
      case kDmgCommand || kDmgSmoke:
        return s;
      case kDmgSecondary:
        if (kDmgSecondaryC.contains(itemId)) return 0.3 * improvement;
        return icon == 16 ? 0.2 * improvement : s;
      case kDmgSubTorpedo:
        return 0.2 * improvement;
      default:
        return 0;
    }
  }

  /// 改修による攻撃力の上乗せ (対潜)
  double get aswImprovement {
    if (improvement <= 0) return 0;
    return switch (category) {
      kDmgSonar || kDmgLargeSonar || kDmgDepthCharge => sqrt(improvement),
      kDmgAutogyro => asw > 10 ? 0.3 * improvement : 0.2 * improvement,
      kDmgDiveBomber || kDmgTorpedoBomber => 0.2 * improvement,
      kDmgAswPatrol => itemId == 70 ? 0.2 * improvement : (itemId == 451 ? 0.3 * improvement : 0),
      _ => 0,
    };
  }
}

/// 爆雷 (爆雷投射機・迫撃砲ではないもの)
const kDmgDepthCharges = {226, 227, 488, 439, 378};

/// 爆雷投射機
const kDmgDepthChargeProjectors = {44, 45, 287, 288, 377, 472, 569};

/// 迫撃砲
const kDmgMortars = {346, 347};

/// 対潜攻撃で装備対潜として数えない装備 (水偵・水戦・艦戦・飛行艇・電探・小口径主砲)
const kDmgAswIgnored = {kDmgSeaplaneRecon, kDmgSeaplaneFighter, kDmgFighter, kDmgFlyingBoat, kDmgSmallRadar, kDmgLargeRadar, kDmgLargeRadar2, kDmgSmallGun};

/// 敵潜水艦の装甲を減らす対潜兵装
const kDmgArmorBreakers = {226, 227, 488, 439, 378, 377, 472};

/// 1隻 (味方・敵どちらも)
class DamageShip {
  final String name;
  final int shipId;

  /// 艦種 (api_stype)
  final int shipType;
  final int level;
  final int hp;
  final int maxHp;

  /// 装甲 (装備込み)
  final double armor;

  /// 火力・雷装・対潜 (装備・装備ボーナス込み)
  final int firepower;
  final int torpedo;
  final int asw;

  /// 素の雷装 (0 なら雷撃戦に出られない)
  final int nakedTorpedo;

  /// 素の対潜 (√ をとる部分。0 なら対潜攻撃できない艦がある)
  final int nakedAsw;
  final List<DamageEquip> equips;
  final bool enemy;

  /// 陸上型の種類 (0 = 水上艦、1 = ソフトスキン型、2 = 砲台小鬼、3 = 集積地型、4 = 離島棲姫、5 = 北端上陸姫、6 = 港湾夏姫)
  final int installType;

  /// 集積地補正 (キャップ後) を受ける
  final bool supplyDepot;

  /// PT小鬼群 (ダメージの式が特殊なので計算しない)
  final bool pt;

  /// 夜戦で攻撃できる空母 (敵)
  final bool nightCarrier;

  const DamageShip({
    required this.name,
    this.shipId = 0,
    required this.shipType,
    this.level = 99,
    required this.hp,
    required this.maxHp,
    required this.armor,
    required this.firepower,
    this.torpedo = 0,
    this.asw = 0,
    this.nakedTorpedo = 0,
    this.nakedAsw = 0,
    this.equips = const [],
    this.enemy = false,
    this.installType = 0,
    this.supplyDepot = false,
    this.pt = false,
    this.nightCarrier = false,
  });

  bool get submarine => shipType == kDmgSS || shipType == kDmgSSV;
  bool get carrier => shipType == kDmgCVL || shipType == kDmgCV || shipType == kDmgCVB;
  bool get installation => installType > 0;

  /// 徹甲弾補正の対象 (戦艦級・重巡級・正規空母・陸上型)
  bool get apShellTarget =>
      installation || const {kDmgCA, kDmgCAV, kDmgFBB, kDmgBB, kDmgBBV, kDmgCV, kDmgCVB}.contains(shipType);

  DamageState get state => damageStateOf(hp, maxHp);

  int countOf(bool Function(DamageEquip e) test) => equips.where(test).length;

  DamageShip copyWith({int? hp}) => DamageShip(
        name: name,
        shipId: shipId,
        shipType: shipType,
        level: level,
        hp: hp ?? this.hp,
        maxHp: maxHp,
        armor: armor,
        firepower: firepower,
        torpedo: torpedo,
        asw: asw,
        nakedTorpedo: nakedTorpedo,
        nakedAsw: nakedAsw,
        equips: equips,
        enemy: enemy,
        installType: installType,
        supplyDepot: supplyDepot,
        pt: pt,
        nightCarrier: nightCarrier,
      );
}

/// 交戦形態
enum DamageEngagement {
  parallel('同航戦', 'Parallel', 1.0),
  headOn('反航戦', 'Head-on', 0.8),
  crossingAdvantage('T字有利', 'Green T', 1.2),
  crossingDisadvantage('T字不利', 'Red T', 0.6);

  const DamageEngagement(this.ja, this.en, this.modifier);

  final String ja;
  final String en;
  final double modifier;
}

/// 陣形補正 (砲撃・雷撃・対潜)。1 単縦陣、2 複縦陣、3 輪形陣、4 梯形陣、5 単横陣
double damageFormationModifier(int formation, DamagePhase phase) => switch (phase) {
      DamagePhase.shelling => const {1: 1.0, 2: 0.8, 3: 0.7, 4: 0.75, 5: 0.6}[formation] ?? 1.0,
      DamagePhase.torpedo => const {1: 1.0, 2: 0.8, 3: 0.7, 4: 0.6, 5: 0.6}[formation] ?? 1.0,
      DamagePhase.asw => const {1: 0.6, 2: 0.8, 3: 1.2, 4: 1.1, 5: 1.3}[formation] ?? 1.0,
      _ => 1.0,
    };

/// 損傷補正 (中破・大破)
double damageStateModifier(DamageState state, DamagePhase phase) => switch ((state, phase)) {
      (DamageState.medium, DamagePhase.torpedo) => 0.8,
      (DamageState.heavy, DamagePhase.torpedo) => 0,
      (DamageState.medium, _) => 0.7,
      (DamageState.heavy, _) => 0.4,
      _ => 1.0,
    };

/// 戦闘の条件
class DamageConditions {
  final DamageEngagement engagement;

  /// 攻撃する側の陣形
  final int formation;

  /// 弾薬量補正 (残り50%以上 1.0、40% 0.8 など)
  final double ammo;

  /// 夜間触接の定数 (0 / 5 / 7 / 9)
  final int nightContact;

  /// イベントの特効などの倍率 (キャップ後)
  final double bonus;

  const DamageConditions({
    this.engagement = DamageEngagement.parallel,
    this.formation = 1,
    this.ammo = 1,
    this.nightContact = 0,
    this.bonus = 1,
  });
}

/// 攻撃の種類
enum DamageAttackKind { shelling, spotting, doubleAttack, carrier, carrierCutIn, torpedo, openingTorpedo, airstrike, night, nightCutIn, nightAir, asw }

/// 1種類の攻撃
class DamageAttack {
  final DamageAttackKind kind;
  final String ja;
  final String en;
  final DamagePhase phase;

  /// (確率, 1発ごとの最終攻撃力)。艦攻の航空攻撃は 0.8倍/1.5倍 が半々
  final List<(double, List<double>)> normal;

  /// クリティカルのとき
  final List<(double, List<double>)> critical;

  /// 相手の装甲を減らす量 (爆雷の装甲減少補正)
  final double armorReduction;

  const DamageAttack({
    required this.kind,
    required this.ja,
    required this.en,
    required this.phase,
    required this.normal,
    required this.critical,
    this.armorReduction = 0,
  });

  bool get night => phase == DamagePhase.night;
}

/// 熟練度クリティカル補正 (空母の砲撃・航空攻撃・艦載機の対潜)。[only] を指定するとそのスロットだけ
double damageProficiencyCritical(List<DamageEquip> equips, {DamageEquip? only}) {
  const internal = [0, 10, 25, 40, 55, 70, 85, 120];
  const constant = [0, 1, 2, 3, 4, 5, 7, 10];
  var bonus = 0.0;
  for (final e in only == null ? equips : [only]) {
    if (!e.hasProficiencyCritical) continue;
    final level = e.proficiency.clamp(0, 7);
    final value = (sqrt(internal[level]) + constant[level]).floor();
    bonus += value / (e.slot == 0 ? 100 : 200);
  }
  return 1 + bonus;
}

/// キャップ後の処理: [キャップ後] × 特殊攻撃 × 徹甲弾 → (徹甲弾対象なら切り捨て) × 集積地 × 特効 → クリティカル
(double, double) damagePostCap(
  double capped, {
  double special = 1,
  double apShell = 1,
  required bool apTarget,
  double depot = 1,
  double bonus = 1,
  double proficiency = 1,
}) {
  var a = capped.floor() * special * apShell;
  if (apTarget) a = damageFloor(a).toDouble();
  a = a * depot * bonus;
  final critical = damageFloor(a * 1.5 * proficiency).toDouble();
  return (a, critical);
}

/// 徹甲弾補正 (主砲 + 徹甲弾、+副砲 1.15 / +電探 1.1 / それだけ 1.08)
double damageApShellModifier(DamageShip a) {
  if (a.countOf((e) => e.isMainGun) == 0 || a.countOf((e) => e.category == kDmgApShell) == 0) return 1;
  if (a.countOf((e) => e.isSecondary) > 0) return 1.15;
  if (a.countOf((e) => e.isRadar) > 0) return 1.10;
  return 1.08;
}

/// 軽巡軽量砲補正・伊重巡フィット砲補正 (昼砲撃と夜戦。キャップ前補正を受けず、キャップの直前に足す)
double damageFitGunBonus(DamageShip a) {
  var bonus = 0.0;
  if (const {kDmgCL, kDmgCLT, kDmgCT}.contains(a.shipType)) {
    bonus += sqrt(a.countOf((e) => kDmgLightSingleGuns.contains(e.itemId))) +
        2 * sqrt(a.countOf((e) => kDmgLightTwinGuns.contains(e.itemId)));
  }
  if (a.name.startsWith('Zara') || a.name.startsWith('Pola')) {
    bonus += sqrt(a.countOf((e) => e.itemId == 162));
  }
  return bonus;
}

/// 昼の特殊攻撃 (弾着観測射撃・空母カットイン) の候補: (種類, 名前, 倍率, 回数)
List<(DamageAttackKind, String, String, double, int)> damageDaySpecials(DamageShip a) {
  final specials = <(DamageAttackKind, String, String, double, int)>[];
  final main = a.countOf((e) => e.isMainGun);
  final secondary = a.countOf((e) => e.isSecondary);
  final ap = a.countOf((e) => e.category == kDmgApShell);
  final radar = a.countOf((e) => e.isRadar);
  if (!a.carrier && !a.submarine && a.equips.any((e) => e.isSeaplaneSpotter)) {
    if (main >= 2 && ap >= 1) specials.add((DamageAttackKind.spotting, '弾着 主主', 'Spotting MM', 1.5, 1));
    if (main >= 1 && secondary >= 1 && ap >= 1) specials.add((DamageAttackKind.spotting, '弾着 主徹', 'Spotting MAP', 1.3, 1));
    if (main >= 1 && secondary >= 1 && radar >= 1) specials.add((DamageAttackKind.spotting, '弾着 主電', 'Spotting MR', 1.2, 1));
    if (main >= 1 && secondary >= 1) specials.add((DamageAttackKind.spotting, '弾着 主副', 'Spotting MS', 1.1, 1));
    if (main >= 2) specials.add((DamageAttackKind.doubleAttack, '連撃', 'Double attack', 1.2, 2));
  }
  if (a.carrier) {
    final f = a.countOf((e) => e.category == kDmgFighter && e.count > 0);
    final b = a.countOf((e) => e.category == kDmgDiveBomber && e.count > 0);
    final t = a.countOf((e) => e.category == kDmgTorpedoBomber && e.count > 0);
    final jf = a.countOf((e) => e.category == kDmgJetFighter && e.count > 0);
    final jb = a.countOf((e) => e.category == kDmgJetFighterBomber && e.count > 0);
    if (jf >= 1 && jb >= 2) specials.add((DamageAttackKind.carrierCutIn, '噴式戦爆爆カットイン', 'jFjBjB cut-in', 1.35, 1));
    if (jf >= 1 && jb >= 1) specials.add((DamageAttackKind.carrierCutIn, '噴式戦爆カットイン', 'jFjB cut-in', 1.3, 1));
    if (jf >= 1 && b >= 1 && t >= 1) specials.add((DamageAttackKind.carrierCutIn, '噴式戦爆攻カットイン', 'jFBA cut-in', 1.27, 1));
    if (f >= 1 && b >= 1 && t >= 1) specials.add((DamageAttackKind.carrierCutIn, '戦爆攻カットイン', 'FBA cut-in', 1.25, 1));
    if (b >= 2 && t >= 1) specials.add((DamageAttackKind.carrierCutIn, '爆爆攻カットイン', 'BBA cut-in', 1.2, 1));
    if (b >= 1 && t >= 1) specials.add((DamageAttackKind.carrierCutIn, '爆攻カットイン', 'BA cut-in', 1.15, 1));
  }
  return specials;
}

/// 空母カットインの熟練度クリティカル補正 (熟練度最大で、隊長機 (1スロット目) が加わると 1.256、加わらないと 1.106 を熟練度で按分した推定)
double _carrierCutInProficiency(DamageShip a) {
  final planes = [for (final e in a.equips) if (e.count > 0 && (e.category == kDmgDiveBomber || e.category == kDmgTorpedoBomber)) e];
  if (planes.isEmpty) return 1;
  final average = planes.fold(0.0, (s, e) => s + e.proficiency.clamp(0, 7)) / planes.length / 7;
  final leader = a.equips.where((e) => e.slot == 0 && e.count > 0).firstOrNull;
  final leaderJoins = leader != null && const {kDmgFighter, kDmgDiveBomber, kDmgTorpedoBomber}.contains(leader.category);
  return 1 + 0.106 * average + (leaderJoins ? 0.15 * leader.proficiency.clamp(0, 7) / 7 : 0);
}

/// [a] が [t] に昼戦でできる攻撃 (砲撃・弾着観測射撃・空母カットイン・雷撃・航空攻撃)
List<DamageAttack> damageDayAttacks(DamageShip a, DamageShip t, DamageConditions c) {
  final attacks = <DamageAttack>[];
  if (a.pt || t.pt || t.submarine) return attacks;
  final state = a.state;
  final apMod = t.apShellTarget ? damageApShellModifier(a) : 1.0;
  final bonus = a.enemy ? 1.0 : c.bonus;

  // 砲撃
  final carrierStyle = a.carrier || (a.enemy && a.equips.any((e) => e.isAttackPlane));
  final canShell = !a.submarine &&
      (!carrierStyle ||
          (a.equips.any((e) => e.isAttackPlane) &&
              (a.shipType == kDmgCVB ? state.index < DamageState.heavy.index : state.index < DamageState.medium.index)));
  if (canShell && state != DamageState.sunk) {
    final improvement = a.equips.fold(0.0, (s, e) => s + e.shellingImprovement);
    final double base;
    if (carrierStyle) {
      final bombing = a.equips.fold(0, (s, e) => s + e.bombing);
      base = ((a.firepower + improvement + a.torpedo + (bombing * 1.3).floor()) * 1.5).floorToDouble() + 55;
    } else {
      base = a.firepower + improvement + 5;
    }
    final pre = base *
            c.engagement.modifier *
            damageFormationModifier(c.formation, DamagePhase.shelling) *
            damageStateModifier(state, DamagePhase.shelling) +
        damageFitGunBonus(a);
    final capped = damageSoftCap(pre, DamagePhase.shelling.cap);
    final proficiency = carrierStyle ? damageProficiencyCritical(a.equips) : 1.0;
    DamageAttack shell(DamageAttackKind kind, String ja, String en, double special, int hits, double prof) {
      final (normal, critical) =
          damagePostCap(capped, special: special, apShell: apMod, apTarget: t.apShellTarget, bonus: bonus, proficiency: prof);
      return DamageAttack(
        kind: kind,
        ja: ja,
        en: en,
        phase: DamagePhase.shelling,
        normal: [(1, List.filled(hits, normal))],
        critical: [(1, List.filled(hits, critical))],
      );
    }

    attacks.add(shell(carrierStyle ? DamageAttackKind.carrier : DamageAttackKind.shelling, '砲撃', 'Shelling', 1, 1, proficiency));
    if (state.index < DamageState.heavy.index) {
      for (final (kind, ja, en, special, hits) in damageDaySpecials(a)) {
        if (kind == DamageAttackKind.carrierCutIn && t.installation) continue;
        final prof = kind == DamageAttackKind.carrierCutIn ? _carrierCutInProficiency(a) : 1.0;
        attacks.add(shell(kind, '$ja ×$special${hits > 1 ? '×$hits' : ''}', '$en ×$special${hits > 1 ? '×$hits' : ''}', special, hits, prof));
      }
    }
  }

  // 雷撃 (潜水艦・陸上型には撃てない)
  if (!t.installation) {
    final improvement = a.equips.fold(0.0, (s, e) => s + e.torpedoImprovement);
    final pre = (a.torpedo + improvement + 5) *
        c.engagement.modifier *
        damageFormationModifier(c.formation, DamagePhase.torpedo) *
        damageStateModifier(state, DamagePhase.torpedo);
    final (normal, critical) = damagePostCap(damageSoftCap(pre, DamagePhase.torpedo.cap), apTarget: false, bonus: bonus);
    DamageAttack torpedo(DamageAttackKind kind, String ja, String en) => DamageAttack(
          kind: kind,
          ja: ja,
          en: en,
          phase: DamagePhase.torpedo,
          normal: [
            (1, [normal]),
          ],
          critical: [
            (1, [critical]),
          ],
        );
    final opening = a.equips.any((e) => e.category == kDmgMidgetSub) || (a.submarine && (a.enemy || a.level >= 10));
    if (opening) attacks.add(torpedo(DamageAttackKind.openingTorpedo, '開幕雷撃', 'Opening torpedo'));
    if (a.nakedTorpedo > 0 && state.index < DamageState.medium.index) {
      attacks.add(torpedo(DamageAttackKind.torpedo, '雷撃', 'Torpedo'));
    }
  }

  // 開幕航空攻撃 (スロットごと。艦攻は 0.8倍/1.5倍 が半々)
  for (final e in a.equips) {
    if (!const {kDmgDiveBomber, kDmgTorpedoBomber, kDmgSeaplaneBomber, kDmgJetFighterBomber}.contains(e.category) || e.count <= 0) continue;
    if (t.installation && e.category == kDmgTorpedoBomber) continue;
    final power = e.category == kDmgTorpedoBomber ? e.torpedo : e.bombing;
    if (power <= 0 && e.category != kDmgTorpedoBomber) continue;
    final improvement = (e.category == kDmgTorpedoBomber || (e.category == kDmgDiveBomber && !e.isFighterBomber) || e.category == kDmgSeaplaneBomber)
        ? 0.2 * e.improvement
        : 0.0;
    final base = (power + improvement) * sqrt(e.count) + 25;
    final types = switch (e.category) {
      kDmgTorpedoBomber => [(0.5, 0.8), (0.5, 1.5)],
      kDmgJetFighterBomber => [(1.0, 0.7071)],
      _ => [(1.0, 1.0)],
    };
    final proficiency = damageProficiencyCritical(a.equips, only: e);
    final normal = <(double, List<double>)>[];
    final critical = <(double, List<double>)>[];
    for (final (p, type) in types) {
      final (n, cr) = damagePostCap(damageSoftCap(base * type, DamagePhase.airstrike.cap),
          apTarget: false, bonus: bonus, proficiency: proficiency);
      normal.add((p, [n]));
      critical.add((p, [cr]));
    }
    attacks.add(DamageAttack(
      kind: DamageAttackKind.airstrike,
      ja: '航空攻撃 ${e.name} (${e.count}機)',
      en: 'Airstrike ${e.name} (${e.count})',
      phase: DamagePhase.airstrike,
      normal: normal,
      critical: critical,
    ));
  }
  return attacks;
}

/// [attack] を [t] に当てたときの結果 (通常とクリティカル)。[stopper] は轟沈ストッパー
(DamageOutcome, DamageOutcome) damageAttackOutcome(DamageAttack attack, DamageShip t, DamageConditions c, {bool stopper = false}) {
  // 爆雷の装甲減少補正 (装甲は1未満にならない)
  final armor = attack.armorReduction > 0 ? max(1.0, t.armor - attack.armorReduction) : t.armor;
  DamageOutcome of(List<(double, List<double>)> variants) =>
      damageMixedOutcome(variants: variants, armor: armor, hp: t.hp, maxHp: t.maxHp, ammo: c.ammo, stopper: stopper);
  return (of(attack.normal), of(attack.critical));
}

// ---- 夜戦 ----

/// 後期型の潜水艦魚雷
const kDmgLateSubTorpedoes = {213, 214, 383, 441, 443, 457, 461, 512};

/// 熟練見張員・水雷戦隊 熟練見張員
const kDmgLookouts = {129, 412};
const kDmgTorpedoSquadronLookout = 412;
const kDmgDrum = 75;
const kDmgDGunKai2 = 267, kDmgDGunKai3 = 366;
const kDmgNightZuiun = 490;

/// 夜間作戦航空要員
const kDmgNightPersonnel = {258, 259};

/// 夜間飛行機のうち、夜戦・夜攻・夜爆以外 (光電管彗星・岩井爆戦・Swordfish系)
const kDmgPhotoSuisei = 320;
const kDmgOtherNightPlanes = {154, 242, 243, 244};

/// 夜間作戦航空要員なしでも夜戦で攻撃できる空母 (火力 + 雷装で攻撃する)
bool _carrierNightGunfire(DamageShip a) {
  final n = a.name;
  if (n.startsWith('Graf Zeppelin') || n.startsWith('Lexington') || n.startsWith('Wasp') || n == 'Saratoga') return true;
  if (const {'大鷹改二', '雲鷹改二', '神鷹改二', '加賀改二護'}.contains(n)) return true;
  return n.startsWith('Ark Royal') && a.equips.any((e) => const {242, 243, 244}.contains(e.itemId) && e.count > 0);
}

bool _isNightFighter(DamageEquip e) => e.icon == 45 && e.count > 0;
bool _isNightAttacker(DamageEquip e) => e.icon == 46 && e.count > 0;
bool _isNightBomber(DamageEquip e) => e.icon == 58 && e.count > 0;
bool _isNightPlane(DamageEquip e) =>
    e.count > 0 && (const {45, 46, 58}.contains(e.icon) || e.itemId == kDmgPhotoSuisei || kDmgOtherNightPlanes.contains(e.itemId));

/// 夜間航空攻撃ができる (夜間作戦航空要員か特定の艦 + 夜間飛行機)
bool damageCanNightAir(DamageShip a) =>
    a.carrier &&
    !a.enemy &&
    (a.equips.any((e) => kDmgNightPersonnel.contains(e.itemId)) || const {'Saratoga Mk.II', '赤城改二戊', '加賀改二戊', '龍鳳改二戊'}.contains(a.name)) &&
    a.equips.any((e) => _isNightFighter(e) || _isNightAttacker(e));

/// 夜戦の特殊攻撃の候補: (名前, 倍率, 1発ごとの倍率の並び。2回攻撃は2つ、1〜2回のものは null)
List<(String, String, double, int, bool)> damageNightSpecials(DamageShip a) {
  final specials = <(String, String, double, int, bool)>[];
  final main = a.countOf((e) => e.isMainGun);
  final secondary = a.countOf((e) => e.isSecondary);
  final torpedo = a.countOf((e) => e.isTorpedo);
  final surfaceRadar = a.countOf((e) => e.isRadar && e.los >= 5);
  // 駆逐艦専用カットイン (1回か2回当たる)。通常のカットインと両方判定される
  if (a.shipType == kDmgDD) {
    final d2 = a.countOf((e) => e.itemId == kDmgDGunKai2);
    final d3 = a.countOf((e) => e.itemId == kDmgDGunKai3);
    final dGun = (d2 + d3 >= 2 ? 1.4 : (d2 + d3 == 1 ? 1.25 : 1.0)) * (d3 >= 2 ? 1.1 : (d3 == 1 ? 1.05 : 1.0));
    final lookout = a.countOf((e) => kDmgLookouts.contains(e.itemId));
    final squadronLookout = a.countOf((e) => e.itemId == kDmgTorpedoSquadronLookout);
    if (main >= 1 && torpedo >= 1 && surfaceRadar >= 1) specials.add(('主魚電', 'GTR', 1.3 * dGun, 1, true));
    if (torpedo >= 1 && lookout >= 1 && surfaceRadar >= 1) specials.add(('魚見電', 'TLR', 1.2 * dGun, 1, true));
    if (torpedo >= 2 && squadronLookout >= 1) specials.add(('魚水魚', 'TsT', 1.5, 1, true));
    if (torpedo >= 1 && squadronLookout >= 1 && a.countOf((e) => e.itemId == kDmgDrum) >= 1) specials.add(('魚ド水', 'TDs', 1.3, 1, true));
  }
  // 夜間瑞雲カットイン (2回)
  final zuiun = a.countOf((e) => e.itemId == kDmgNightZuiun && e.count > 0);
  if (zuiun >= 1 && main >= 2 && const {kDmgCL, kDmgCAV, kDmgBBV, kDmgAV}.contains(a.shipType)) {
    final mod = (zuiun >= 2 ? 1.32 : 1.24) + (surfaceRadar >= 1 ? 0.04 : 0);
    specials.add(('夜間瑞雲', 'Night Zuiun', mod, 2, false));
  }
  // 通常のカットインは倍率の一番高いものだけ判定される (潜水艦は後期型魚雷のカットイン)
  final lateTorpedo = a.countOf((e) => kDmgLateSubTorpedoes.contains(e.itemId));
  final subRadar = a.countOf((e) => e.category == kDmgSubRadar);
  final generic = <(String, String, double, int, bool)>[
    if (main >= 3) ('主主主', 'MMM', 2.0, 1, false),
    if (a.submarine && lateTorpedo >= 1 && subRadar >= 1) ('後期魚雷+電探', 'Late torp+radar', 1.75, 2, false),
    if (main >= 2 && secondary >= 1) ('主主副', 'MMS', 1.75, 1, false),
    if (a.submarine && lateTorpedo >= 2) ('後期魚雷×2', 'Late torp×2', 1.6, 2, false),
    if (torpedo >= 2) ('魚雷カットイン', 'Torpedo CI', 1.5, 2, false),
    if (main >= 1 && torpedo >= 1) ('主魚', 'Gun-torp CI', 1.3, 2, false),
  ];
  if (generic.isNotEmpty) {
    specials.add(generic.first);
  } else if (main + secondary >= 2) {
    specials.add(('連撃', 'Double attack', 1.2, 2, false));
  }
  return specials;
}

/// 夜間航空攻撃の基本攻撃力 (素火力 + 夜間飛行機の火力・雷装・爆装 + 搭載数補正)
double damageNightAirBase(DamageShip a, int contact) {
  final naked = a.firepower - a.equips.fold(0, (s, e) => s + e.firepower);
  var base = naked.toDouble() + contact;
  for (final e in a.equips) {
    if (!_isNightPlane(e)) continue;
    final strong = const {45, 46, 58}.contains(e.icon);
    final (k1, k2) = strong ? (3.0, 0.45) : (0.0, 0.3);
    base += e.firepower + e.torpedo + e.bombing;
    base += k1 * e.count + k2 * (e.firepower + e.torpedo + e.bombing + e.asw) * sqrt(e.count) + sqrt(e.improvement);
  }
  return base;
}

/// [a] が [t] に夜戦でできる攻撃
List<DamageAttack> damageNightAttacks(DamageShip a, DamageShip t, DamageConditions c) {
  final attacks = <DamageAttack>[];
  final state = a.state;
  // 大破では攻撃できない。潜水艦への夜戦の対潜攻撃は必ずカスダメなので計算しない
  if (a.pt || t.pt || t.submarine || state.index >= DamageState.heavy.index) return attacks;
  final bonus = a.enemy ? 1.0 : c.bonus;
  final stateMod = damageStateModifier(state, DamagePhase.night);

  DamageAttack attack(DamageAttackKind kind, String ja, String en, double base, double special, int hits, {double prof = 1, double fit = 0}) {
    final pre = base * special * stateMod + fit;
    final (normal, critical) = damagePostCap(damageSoftCap(pre, DamagePhase.night.cap), apTarget: false, bonus: bonus, proficiency: prof);
    return DamageAttack(
      kind: kind,
      ja: '夜戦 $ja',
      en: 'Night $en',
      phase: DamagePhase.night,
      normal: [(1, List.filled(hits, normal))],
      critical: [(1, List.filled(hits, critical))],
    );
  }

  if (a.carrier) {
    if (damageCanNightAir(a) && (a.shipType == kDmgCVB ? state.index < DamageState.heavy.index : state.index < DamageState.medium.index)) {
      final base = damageNightAirBase(a, c.nightContact);
      final prof = damageProficiencyCritical([for (final e in a.equips) if (e.icon != 45) e]);
      attacks.add(attack(DamageAttackKind.nightAir, '航空攻撃', 'air attack', base, 1, 1, prof: prof));
      final fighters = a.countOf(_isNightFighter);
      final attackers = a.countOf(_isNightAttacker);
      final bombers = a.countOf(_isNightBomber);
      final photo = a.countOf((e) => e.itemId == kDmgPhotoSuisei && e.count > 0);
      final planes = a.countOf(_isNightPlane);
      final cutIns = <(String, String, double)>[
        if (fighters >= 2 && attackers >= 1) ('戦戦攻', 'FFA', 1.25),
        if (fighters >= 1 && attackers >= 1) ('戦攻', 'FA', 1.2),
        if ((fighters >= 1 && photo >= 1) || (attackers >= 1 && photo >= 1) || (fighters >= 1 && bombers >= 1) ||
            (attackers >= 1 && bombers >= 1) || (bombers >= 1 && photo >= 1))
          ('夜襲 (彗星・夜爆の組み合わせ)', 'Night CI', 1.2),
        if (fighters >= 1 && planes >= 3) ('戦他他', 'FOO', 1.18),
      ];
      for (final (ja, en, mod) in cutIns) {
        attacks.add(attack(DamageAttackKind.nightCutIn, '夜襲カットイン $ja ×$mod', 'night CI $en ×$mod', base, mod, 1, prof: prof));
      }
      return attacks;
    }
    if (!(a.enemy ? a.nightCarrier : _carrierNightGunfire(a))) return attacks;
  }

  // 火力 + 雷装 (陸上型への攻撃では雷装を数えない (3回目で対地補正と合わせて扱う))
  final improvement = a.equips.fold(0.0, (s, e) => s + e.nightImprovement);
  final torpedo = t.installation && a.equips.isNotEmpty ? 0 : a.torpedo;
  final base = (a.firepower + torpedo + improvement + c.nightContact).toDouble();
  final fit = damageFitGunBonus(a);
  attacks.add(attack(DamageAttackKind.night, '通常', 'normal', base, 1, 1, fit: fit));
  if (!a.carrier) {
    for (final (ja, en, mod, hits, oneOrTwo) in damageNightSpecials(a)) {
      if (oneOrTwo) {
        // 駆逐艦専用カットインは1回か2回 (割合は分からないので半々とする)
        final once = attack(DamageAttackKind.nightCutIn, '', '', base, mod, 1, fit: fit);
        attacks.add(DamageAttack(
          kind: DamageAttackKind.nightCutIn,
          ja: '夜戦 $ja ×${mod.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '')} (1〜2回。半々と仮定)',
          en: 'Night $en ×${mod.toStringAsFixed(3)} (1-2 hits, assumed half)',
          phase: DamagePhase.night,
          normal: [
            (0.5, once.normal.single.$2),
            (0.5, [...once.normal.single.$2, ...once.normal.single.$2]),
          ],
          critical: [
            (0.5, once.critical.single.$2),
            (0.5, [...once.critical.single.$2, ...once.critical.single.$2]),
          ],
        ));
      } else {
        attacks.add(attack(
          ja == '連撃' ? DamageAttackKind.night : DamageAttackKind.nightCutIn,
          '$ja ×$mod${hits > 1 ? '×$hits' : ''}',
          '$en ×$mod${hits > 1 ? '×$hits' : ''}',
          base,
          mod,
          hits,
          fit: fit,
        ));
      }
    }
  }
  return attacks;
}

// ---- 対潜 ----

/// [a] が潜水艦 [t] にできる昼の対潜攻撃 (夜戦の対潜は必ずカスダメ)
List<DamageAttack> damageAswAttacks(DamageShip a, DamageShip t, DamageConditions c) {
  if (!t.submarine || a.submarine || a.state.index >= DamageState.heavy.index) return const [];
  const aircraftTypes = {kDmgCVL, kDmgAV, kDmgCAV, kDmgBBV, kDmgLHA, kDmgCVB, kDmgCV};
  final aswPlanes = a.equips.where((e) =>
      e.count > 0 &&
      (a.shipType == kDmgCVL || a.shipType == kDmgCV || a.shipType == kDmgCVB
          ? const {kDmgDiveBomber, kDmgTorpedoBomber}.contains(e.category)
          : const {kDmgDiveBomber, kDmgTorpedoBomber, kDmgSeaplaneBomber, kDmgAutogyro, kDmgAswPatrol, kDmgFlyingBoat}.contains(e.category)));
  final bool aircraft;
  if (aircraftTypes.contains(a.shipType)) {
    if (aswPlanes.isEmpty) return const [];
    aircraft = true;
  } else if (const {kDmgDE, kDmgDD, kDmgCL, kDmgCLT, kDmgCT, kDmgAO}.contains(a.shipType) && a.nakedAsw > 0) {
    aircraft = a.shipType == kDmgAO && aswPlanes.isNotEmpty;
  } else {
    return const [];
  }
  final counted = a.equips.where((e) => !kDmgAswIgnored.contains(e.category));
  final equipAsw = counted.fold(0, (s, e) => s + e.asw);
  final improvement = a.equips.fold(0.0, (s, e) => s + e.aswImprovement);
  final base = 2 * sqrt(max(0, a.nakedAsw)) + 1.5 * equipAsw + improvement + (aircraft ? 8 : 13);
  // 対潜シナジー
  final smallSonar = a.countOf((e) => e.category == kDmgSonar) > 0;
  final largeSonar = a.countOf((e) => e.category == kDmgLargeSonar) > 0;
  final projector = a.countOf((e) => kDmgDepthChargeProjectors.contains(e.itemId)) > 0;
  final mortar = a.countOf((e) => kDmgMortars.contains(e.itemId)) > 0;
  final charge = a.countOf((e) => kDmgDepthCharges.contains(e.itemId)) > 0;
  final oldSynergy = (smallSonar || largeSonar) && (projector || mortar) ? 1.15 : 1.0;
  final newSynergy = 1 + (smallSonar && charge ? 0.15 : 0) + (projector && charge ? 0.1 : 0);
  final pre = base *
      oldSynergy *
      newSynergy *
      c.engagement.modifier *
      damageFormationModifier(c.formation, DamagePhase.asw) *
      damageStateModifier(a.state, DamagePhase.asw);
  final (normal, critical) = damagePostCap(damageSoftCap(pre, DamagePhase.asw.cap),
      apTarget: false, bonus: a.enemy ? 1.0 : c.bonus, proficiency: aircraft ? damageProficiencyCritical(a.equips) : 1.0);
  // 爆雷の装甲減少補正 (海防艦は1つにつき+1)
  final reduction = aircraft
      ? 0.0
      : a.equips
          .where((e) => kDmgArmorBreakers.contains(e.itemId))
          .fold(0.0, (s, e) => s + sqrt(max(0, e.asw - 2)) + (a.shipType == kDmgDE ? 1 : 0));
  final synergy = oldSynergy * newSynergy;
  return [
    DamageAttack(
      kind: DamageAttackKind.asw,
      ja: '対潜${aircraft ? ' (艦載機)' : ''}${synergy > 1 ? ' シナジー×${synergy.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '')}' : ''}',
      en: 'ASW${aircraft ? ' (aircraft)' : ''}${synergy > 1 ? ' synergy ×${synergy.toStringAsFixed(4)}' : ''}',
      phase: DamagePhase.asw,
      normal: [
        (1, [normal]),
      ],
      critical: [
        (1, [critical]),
      ],
      armorReduction: reduction,
    ),
  ];
}

/// [a] が [t] にできる攻撃すべて (昼・対潜・夜)
List<DamageAttack> damageAllAttacks(DamageShip a, DamageShip t, DamageConditions c) => [
      ...damageDayAttacks(a, t, c),
      ...damageAswAttacks(a, t, c),
      ...damageNightAttacks(a, t, c),
    ];
