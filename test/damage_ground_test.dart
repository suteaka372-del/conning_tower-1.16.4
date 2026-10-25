import 'package:conning_tower/models/feature/kancolle/damage/damage_attacks.dart';
import 'package:flutter_test/flutter_test.dart';

DamageShip ship({
  String name = '艦',
  int type = kDmgDD,
  int fp = 50,
  int tp = 0,
  List<DamageEquip> equips = const [],
}) =>
    DamageShip(
      name: name,
      shipType: type,
      hp: 50,
      maxHp: 50,
      armor: 50,
      firepower: fp,
      torpedo: tp,
      nakedTorpedo: tp,
      equips: equips,
    );

DamageShip installation(int type, {bool depot = false, int hp = 400, double armor = 100}) => DamageShip(
      name: '陸上型',
      shipType: kDmgBBV,
      hp: hp,
      maxHp: hp,
      armor: armor,
      firepower: 100,
      enemy: true,
      installType: type,
      supplyDepot: depot,
    );

DamageEquip item(int id, int category, {int improvement = 0, int count = 0, int bombing = 0, int torpedo = 0}) =>
    DamageEquip(itemId: id, category: category, improvement: improvement, count: count, bombing: bombing, torpedo: torpedo);

final daihatsu = item(68, kDmgLandingCraft);
final rikusenMax = item(166, kDmgLandingCraft, improvement: 10);
final regiment11 = item(230, kDmgLandingCraft);
final tokudai = item(193, kDmgLandingCraft);
final armed = item(409, kDmgLandingCraft);
final abBoat = item(408, kDmgLandingCraft);
final panzer2 = item(436, kDmgLandingCraft);
final wg = item(126, kDmgGroundAttack);
final rocket = item(348, kDmgGroundAttack);
final aaShell = item(35, kDmgAaShell);
final apShell = item(116, kDmgApShell);
final kami = item(167, kDmgSpecialAmphibious);

final softSkin = installation(1);
final pillbox = installation(2);
final depot = installation(3, depot: true);
final island = installation(4);
final harbor = installation(6);

double first(DamageAttack a) => a.normal.first.$2.first;

void main() {
  test('general multiplier: landing craft base, individual and improvement', () {
    // 陸戦隊★max + 11連隊 (ソフトスキン): 1.4 × 1.5 × (1 + 平均★5/50) = 2.31。そのあと 11連隊の ×1.8 +25
    final dd = ship(equips: [rikusenMax, regiment11]);
    expect(damageGroundGeneralMultiplier(dd, 1, day: true), closeTo(2.31, 1e-9));
    final bonus = damageGroundBonus(dd, softSkin, day: true);
    expect(bonus.multiplier, closeTo(2.31 * 1.8, 1e-9));
    expect(bonus.add, 25);
    expect(bonus.depot, 1);
    // WG42 + 20cm対地砲: 1.3 × 1.25 = 1.625、加算 75 + 55
    final wgRocket = damageGroundBonus(ship(equips: [wg, rocket]), softSkin, day: true);
    expect(wgRocket.multiplier, closeTo(1.625, 1e-9));
    expect(wgRocket.add, 130);
    // 陸上型の種類で倍率が変わる: 三式弾 + WG42 (離島 1.75 × 1.4)、港湾夏姫は徹甲弾 ×1.3 も
    expect(damageGroundGeneralMultiplier(ship(equips: [aaShell, wg, apShell]), 4, day: true), closeTo(1.75 * 1.4, 1e-9));
    expect(damageGroundGeneralMultiplier(ship(equips: [aaShell, wg, apShell]), 6, day: true), closeTo(1.75 * 1.4 * 1.3, 1e-9));
    // 陸戦隊 + II号戦車 (砲台): 1.8 × 1.5 × 1.5 × 改修 1.1
    expect(damageGroundGeneralMultiplier(ship(equips: [rikusenMax, panzer2]), 2, day: true), closeTo(1.8 * 1.5 * 1.5 * 1.1, 1e-9));
    // 特二式内火艇2つ (ソフトスキン 1.8)
    expect(damageGroundGeneralMultiplier(ship(type: kDmgSS, equips: [kami, kami]), 1, day: true), closeTo(1.8, 1e-9));
    // 対地装備がなければ補正なし。敵の攻撃・水上艦が相手なら計算しない
    expect(damageGroundBonus(ship(), softSkin, day: true).isNone, isTrue);
    expect(damageGroundBonus(ship(equips: [wg]), ship(name: '敵'), day: true).isNone, isTrue);
  });

  test('landing support craft: day-only individual bonus and the four synergy patterns', () {
    // 武装大発 + 大発: 昼は 1.4 × 1.1、シナジー① ×1.2 +10。夜は個別補正なし
    final one = ship(type: kDmgCL, equips: [armed, daihatsu]);
    final day = damageGroundBonus(one, softSkin, day: true);
    expect(day.multiplier, closeTo(1.4 * 1.1 * 1.2, 1e-9));
    expect(day.add, 10);
    expect(damageGroundBonus(one, softSkin, day: false).multiplier, closeTo(1.4 * 1.2, 1e-9));
    // 武装大発だけ2つではシナジーなし
    expect(damageGroundBonus(ship(type: kDmgCL, equips: [armed, armed, daihatsu]), softSkin, day: true).add, 0);
    // 両方 + 左の列1つ → ② +15、右の列1つ → ③ +20、合わせて2つ → ④ +25
    expect(damageGroundBonus(ship(type: kDmgCL, equips: [armed, abBoat, tokudai]), softSkin, day: true).add, 15);
    expect(damageGroundBonus(ship(type: kDmgCL, equips: [armed, abBoat, regiment11]), softSkin, day: true).add, 25 * 1.4 + 20);
    expect(damageGroundBonus(ship(type: kDmgCL, equips: [armed, abBoat, tokudai, daihatsu]), softSkin, day: true).add, 25);
  });

  test('pillbox: destroyer ×1.4, WG42 ×2 and the shelling attack', () {
    final dd = ship(fp: 50, equips: [wg, wg]);
    final bonus = damageGroundBonus(dd, pillbox, day: true);
    expect(bonus.multiplier, closeTo(1.4 * 2.72, 1e-9));
    expect(bonus.add, 110);
    // (50 + 5) × 3.808 + 110 = 319.44 → 220 + √99.44 = 229.97 → 229
    final shelling = damageDayAttacks(dd, pillbox, const DamageConditions()).first;
    expect(first(shelling), 229);
    // 重雷装巡洋艦には艦種補正がない
    expect(damageGroundBonus(ship(type: kDmgCLT, equips: [wg, wg]), pillbox, day: true).multiplier, closeTo(2.72, 1e-9));
  });

  test('supply depot: post-cap multiplier and squared improvement', () {
    // WG42 + 大発: キャップ前 1.3 × 1.4 = 1.82 +75、キャップ後 1.25 × 1.7 = 2.125
    final dd = ship(fp: 40, equips: [wg, daihatsu]);
    final bonus = damageGroundBonus(dd, depot, day: true);
    expect(bonus.multiplier, closeTo(1.82, 1e-9));
    expect(bonus.depot, closeTo(2.125, 1e-9));
    // 45 × 1.82 + 75 = 156.9 → 156 × 2.125 = 331.5、クリティカル [497.25] = 497
    final shelling = damageDayAttacks(dd, depot, const DamageConditions()).first;
    expect(first(shelling), 331.5);
    expect(shelling.critical.first.$2.first, 497);
    // 陸戦隊があると改修補正が2乗、陸戦隊 + II号戦車なら3乗
    expect(damageSupplyDepotMultiplier(ship(equips: [rikusenMax, daihatsu])), closeTo(1.7 * 1.3 * 1.1 * 1.1, 1e-9));
    expect(damageSupplyDepotMultiplier(ship(equips: [rikusenMax, panzer2])), closeTo(1.7 * 1.3 * 1.3 * 1.1 * 1.1 * 1.1, 1e-9));
    // 浸水型 (水上艦で集積地補正だけ): キャップ前の補正はなく、雷撃もできる (雷撃に集積地補正は付かない)
    final surface = DamageShip(name: '集積地III', shipType: kDmgBB, hp: 500, maxHp: 500, armor: 100, firepower: 100, enemy: true, supplyDepot: true);
    final surfaceBonus = damageGroundBonus(dd, surface, day: true);
    expect(surfaceBonus.multiplier, 1);
    expect(surfaceBonus.depot, closeTo(2.125, 1e-9));
  });

  test('carriers: ground dive bombers, torpedo counted as 0', () {
    final groundBomber = item(319, kDmgDiveBomber, count: 20, bombing: 12);
    final normalBomber = item(24, kDmgDiveBomber, count: 20, bombing: 10);
    final torpedoBomber = item(93, kDmgTorpedoBomber, count: 20, torpedo: 9);
    DamageShip cv(List<DamageEquip> equips) => ship(type: kDmgCV, fp: 50, tp: 9, equips: equips);
    expect(damageCarrierCanHitInstallation(cv([groundBomber, normalBomber])), isTrue);
    expect(damageCarrierCanHitInstallation(cv([normalBomber, torpedoBomber])), isFalse);
    expect(damageCarrierCanHitInstallation(cv([torpedoBomber])), isTrue);
    // [(50 + 5 + [12 × 1.3] + 15) × 1.5] + 25 = 152 (雷装 9 は数えない)
    final attacks = damageDayAttacks(cv([groundBomber, torpedoBomber]), softSkin, const DamageConditions());
    expect(first(attacks.firstWhere((a) => a.kind == DamageAttackKind.carrier)), 152);
    // 陸上型には空母カットインなし。対地艦爆でない艦爆があれば砲撃しない
    expect(attacks.any((a) => a.kind == DamageAttackKind.carrierCutIn), isFalse);
    expect(damageDayAttacks(cv([normalBomber, torpedoBomber]), softSkin, const DamageConditions()).any((a) => a.kind == DamageAttackKind.carrier),
        isFalse);
  });

  test('submarines with amphibious tanks shell installations', () {
    final ss = ship(type: kDmgSS, fp: 10, tp: 30, equips: [kami]);
    // (10 + 5) + 30 = 45、特二式 ×1.5 → 67.5 → 67
    final attacks = damageDayAttacks(ss, softSkin, const DamageConditions());
    expect(attacks.map((a) => a.ja), ['砲撃']);
    expect(first(attacks.single), 67);
    expect(damageDayAttacks(ship(type: kDmgSS, fp: 10, tp: 30), softSkin, const DamageConditions()), isEmpty);
  });

  test('night: torpedo ignored against installations, ground bonus applied', () {
    const gun = DamageEquip(category: kDmgMediumGun);
    const torp = DamageEquip(category: kDmgTorpedo, torpedo: 10);
    const radar = DamageEquip(category: kDmgSmallRadar, los: 5);
    const lookout = DamageEquip(itemId: 129, category: kDmgSurfaceCrew);
    // 主魚は魚雷なし扱いで連撃もない。火力 60 + 5 (雷装は数えない)
    final cl = ship(type: kDmgCL, fp: 60, tp: 40, equips: const [gun, torp]);
    final night = damageNightAttacks(cl, softSkin, const DamageConditions());
    expect(night.map((a) => a.ja), ['夜戦 通常']);
    expect(first(night.single), 65);
    // WG42: (60 + 5) × 1.3 + 75 = 159.5 → 159
    final withWg = ship(type: kDmgCL, fp: 60, tp: 40, equips: [gun, wg]);
    expect(first(damageNightAttacks(withWg, softSkin, const DamageConditions()).first), 159);
    // 駆逐艦専用カットインは主砲があれば判定される。主砲がなければ判定されない
    final dd = ship(fp: 50, tp: 80, equips: const [gun, torp, radar]);
    final labels = [for (final a in damageNightAttacks(dd, softSkin, const DamageConditions())) a.ja];
    expect(labels.any((l) => l.startsWith('夜戦 主魚電')), isTrue);
    expect(labels.contains('夜戦 主魚 ×1.3×2'), isFalse);
    final noGun = ship(fp: 50, tp: 80, equips: const [torp, lookout, radar]);
    expect(damageNightAttacks(noGun, softSkin, const DamageConditions()).map((a) => a.ja), ['夜戦 通常']);
    // 集積地補正は夜戦にも付く (上陸支援舟艇の個別補正も夜に付く)
    final boat = ship(type: kDmgCL, fp: 60, equips: [gun, armed]);
    expect(damageGroundBonus(boat, depot, day: false).depot, closeTo(1.7 * 1.5, 1e-9));
    // 装備のない艦は 火力 + 雷装 + 触接
    expect(first(damageNightAttacks(ship(type: kDmgCL, fp: 60, tp: 40), softSkin, const DamageConditions()).single), 100);
  });
}
