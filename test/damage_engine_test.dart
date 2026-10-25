import 'package:conning_tower/models/feature/kancolle/damage/damage_attacks.dart';
import 'package:flutter_test/flutter_test.dart';

DamageShip ship({
  String name = '艦',
  int type = kDmgBB,
  int hp = 90,
  double armor = 90,
  int fp = 100,
  int tp = 0,
  int nakedTp = 0,
  List<DamageEquip> equips = const [],
  bool enemy = false,
  int install = 0,
}) =>
    DamageShip(
      name: name,
      shipType: type,
      hp: hp,
      maxHp: hp,
      armor: armor,
      firepower: fp,
      torpedo: tp,
      nakedTorpedo: nakedTp,
      equips: equips,
      enemy: enemy,
      installType: install,
    );

DamageAttack attackOf(List<DamageAttack> attacks, DamageAttackKind kind, [String? label]) =>
    attacks.firstWhere((a) => a.kind == kind && (label == null || a.ja.startsWith(label)));

double first(List<(double, List<double>)> variants) => variants.first.$2.first;

void main() {
  test('cap and damage formula', () {
    // キャップ前 230 の砲撃 → 220 + √10 = 223 (切り捨て)
    expect(damageSoftCap(230, DamagePhase.shelling.cap).floor(), 223);
    expect(damageSoftCap(150, DamagePhase.shelling.cap), 150);
    // 攻撃力155・装甲100: 防御力 70〜129.4 → 25〜85
    final hits = damageHitDistribution(attack: 155, armor: 100, hp: 500);
    expect(hits.keys.reduce((a, b) => a < b ? a : b), 25);
    expect(hits.keys.reduce((a, b) => a > b ? a : b), 85);
    expect(hits.values.fold(0.0, (s, p) => s + p), closeTo(1, 1e-9));
    // 弾薬量補正 (40% なら 0.8 倍)
    expect(damageHitDistribution(attack: 170, armor: 0, hp: 500, ammo: 0.8).keys.single, 136);
  });

  test('scratch damage when the armor is not pierced', () {
    // 現在HP100: [6 + [100×乱数]×0.08] = 6〜13
    final hits = damageHitDistribution(attack: 10, armor: 100, hp: 100);
    expect(hits.keys.toSet(), {6, 7, 8, 9, 10, 11, 12, 13});
    final outcome = damageOutcome(attacks: const [10], armor: 100, hp: 100, maxHp: 100);
    expect(outcome.canScratch, isTrue);
    expect(outcome.maxDamage, isNull);
    expect(outcome.sink, 0); // カスダメでは沈まない
  });

  test('sinking stopper follows the wiki table', () {
    // 耐久15/15 に大ダメージ → 7〜11 ダメージ (残り8〜4)、大破にはならない
    final hits = damageHitDistribution(attack: 999, armor: 0, hp: 15, stopper: true);
    expect(hits.keys.toSet(), {7, 8, 9, 10, 11});
    // 最大耐久12 (4n) の一撃大破率 16.7%、15 (4n+3) は 0%
    expect(damageOutcome(attacks: const [999], armor: 0, hp: 12, maxHp: 12, stopper: true).heavy, closeTo(2 / 12, 1e-9));
    expect(damageOutcome(attacks: const [999], armor: 0, hp: 15, maxHp: 15, stopper: true).heavyOrWorse, 0);
    expect(damageOutcome(attacks: const [999], armor: 0, hp: 15, maxHp: 15, stopper: true).sink, 0);
    // ストッパーが無ければ撃沈
    expect(damageOutcome(attacks: const [999], armor: 0, hp: 15, maxHp: 15).sink, 1);
  });

  test('two hits use the HP left after the first hit', () {
    // 攻撃力100・装甲0・耐久150: 1発では沈まず、2発で沈む
    expect(damageOutcome(attacks: const [100], armor: 0, hp: 150, maxHp: 150).sink, 0);
    final twice = damageOutcome(attacks: const [100, 100], armor: 0, hp: 150, maxHp: 150);
    expect(twice.sink, 1);
    expect(twice.hits, 2);
    // 状態の境目: 残り25%以下で大破、50%以下で中破
    expect(damageStateOf(25, 100), DamageState.heavy);
    expect(damageStateOf(26, 100), DamageState.medium);
    expect(damageStateOf(50, 100), DamageState.medium);
    expect(damageStateOf(75, 100), DamageState.light);
    expect(damageStateOf(76, 100), DamageState.none);
  });

  test('day shelling, spotting and AP shells', () {
    const gun = DamageEquip(category: kDmgLargeGun, firepower: 0);
    const ap = DamageEquip(category: kDmgApShell);
    const recon = DamageEquip(category: kDmgSeaplaneRecon, count: 3, slot: 2);
    final bb = ship(fp: 150, equips: const [gun, gun, recon, ap]);
    final target = ship(name: '戦艦', type: kDmgBB, enemy: true, armor: 100);
    final attacks = damageDayAttacks(bb, target, const DamageConditions());
    // 砲撃: 150 + 5 = 155、徹甲弾 (主砲+徹甲弾) 1.08 → [155×1.08] = 167
    expect(first(attackOf(attacks, DamageAttackKind.shelling).normal), 167);
    // 弾着 主主: [155] × 1.5 × 1.08 = 251.1 → 戦艦は徹甲弾対象なので切り捨て 251、クリティカル [251×1.5] = 376
    final spotting = attackOf(attacks, DamageAttackKind.spotting, '弾着 主主');
    expect(first(spotting.normal), 251);
    expect(first(spotting.critical), 376);
    // 連撃は 1.2 倍の2回
    expect(attackOf(attacks, DamageAttackKind.doubleAttack).normal.first.$2.length, 2);
    // 駆逐艦は徹甲弾の対象外
    final dd = ship(name: '駆逐', type: kDmgDD, enemy: true, armor: 10);
    expect(first(attackOf(damageDayAttacks(bb, dd, const DamageConditions()), DamageAttackKind.shelling).normal), 155);
    // 反航戦 0.8・複縦陣 0.8・中破 0.7
    final damaged = DamageShip(name: 'BB', shipType: kDmgBB, hp: 40, maxHp: 90, armor: 90, firepower: 150, equips: const [gun]);
    final weak = damageDayAttacks(damaged, dd, const DamageConditions(engagement: DamageEngagement.headOn, formation: 2));
    expect(first(attackOf(weak, DamageAttackKind.shelling).normal), 69); // [155 × 0.8 × 0.8 × 0.7] = [69.44]
  });

  test('carrier shelling, cut-ins and proficiency critical', () {
    DamageEquip plane(int category, int slot, {int tp = 0, int bk = 0, int prof = 7, int count = 20}) =>
        DamageEquip(category: category, torpedo: tp, bombing: bk, proficiency: prof, count: count, slot: slot);
    final cv = ship(type: kDmgCV, fp: 50, tp: 13, equips: [
      plane(kDmgTorpedoBomber, 0, tp: 13),
      plane(kDmgDiveBomber, 1, bk: 10),
      plane(kDmgDiveBomber, 2, bk: 10),
      plane(kDmgFighter, 3),
    ]);
    // 熟練度最大の艦攻・艦爆が1〜3スロット: 1 + 0.2 + 0.1 + 0.1 = 1.4 (Wiki の例)
    expect(damageProficiencyCritical(cv.equips), closeTo(1.4, 1e-9));
    final target = ship(type: kDmgDD, enemy: true, armor: 20);
    final attacks = damageDayAttacks(cv, target, const DamageConditions());
    // [(50 + 13 + [20×1.3]) × 1.5] + 55 = 188
    final shell = attackOf(attacks, DamageAttackKind.carrier);
    expect(first(shell.normal), 188);
    expect(first(shell.critical), (188 * 1.5 * 1.4).floor());
    expect(attacks.where((a) => a.kind == DamageAttackKind.carrierCutIn).map((a) => a.ja), [
      '戦爆攻カットイン ×1.25',
      '爆爆攻カットイン ×1.2',
      '爆攻カットイン ×1.15',
    ]);
    // 中破した正規空母は昼砲撃できない
    final damaged = DamageShip(name: 'CV', shipType: kDmgCV, hp: 30, maxHp: 90, armor: 70, firepower: 50, equips: cv.equips);
    expect(damageDayAttacks(damaged, target, const DamageConditions()).where((a) => a.kind == DamageAttackKind.carrier), isEmpty);
  });

  test('torpedo and airstrike', () {
    const torp = DamageEquip(category: kDmgTorpedo, torpedo: 15, improvement: 4);
    final dd = ship(type: kDmgDD, fp: 50, tp: 100, nakedTp: 70, equips: const [torp]);
    final target = ship(type: kDmgCA, enemy: true, armor: 60);
    final attacks = damageDayAttacks(dd, target, const DamageConditions());
    // 100 + 1.2×√4 + 5 = 107.4
    expect(first(attackOf(attacks, DamageAttackKind.torpedo).normal), 107);
    expect(attacks.any((a) => a.kind == DamageAttackKind.openingTorpedo), isFalse);
    // 潜水艦 (Lv10以上) と甲標的は開幕雷撃
    final ss = DamageShip(name: '伊58', shipType: kDmgSS, level: 50, hp: 20, maxHp: 20, armor: 10, firepower: 5, torpedo: 90, nakedTorpedo: 60);
    expect(damageDayAttacks(ss, target, const DamageConditions()).map((a) => a.kind),
        [DamageAttackKind.openingTorpedo, DamageAttackKind.torpedo]);
    // 陸上型・潜水艦には雷撃できない
    final airfield = ship(type: kDmgBBV, enemy: true, install: 1);
    expect(damageDayAttacks(dd, airfield, const DamageConditions()).where((a) => a.phase == DamagePhase.torpedo), isEmpty);
    final sub = ship(type: kDmgSS, enemy: true, armor: 10);
    expect(damageDayAttacks(dd, sub, const DamageConditions()), isEmpty);

    // 航空攻撃: 艦攻 (雷装13・18機) = 13×√18 + 25 → 0.8倍/1.5倍
    const tb = DamageEquip(category: kDmgTorpedoBomber, torpedo: 13, count: 18, slot: 1, name: '流星改');
    final cv = ship(type: kDmgCV, fp: 50, equips: const [tb]);
    final strike = attackOf(damageDayAttacks(cv, target, const DamageConditions()), DamageAttackKind.airstrike);
    final base = 13 * 4.242640687119285 + 25;
    // キャップのあとで端数を切り捨てる: [64.12] = 64、[120.23] = 120
    expect(strike.normal.map((v) => v.$2.single), [(base * 0.8).floorToDouble(), (base * 1.5).floorToDouble()]);
    expect(strike.normal.map((v) => v.$1), [0.5, 0.5]);
    // 艦攻は陸上型を攻撃しない
    expect(damageDayAttacks(cv, airfield, const DamageConditions()).where((a) => a.kind == DamageAttackKind.airstrike), isEmpty);
  });

  test('light cruiser fit guns and event bonus', () {
    const twin = DamageEquip(itemId: 139, category: kDmgMediumGun);
    const single = DamageEquip(itemId: 4, category: kDmgMediumGun);
    final cl = ship(type: kDmgCL, fp: 60, equips: const [twin, twin, single]);
    expect(damageFitGunBonus(cl), closeTo(1 + 2 * 1.4142135623730951, 1e-9));
    final target = ship(type: kDmgDD, enemy: true, armor: 10);
    // (60+5) + 3.83 = 68.83 → 68。特効 1.3 倍は自分 → 敵だけ
    expect(first(attackOf(damageDayAttacks(cl, target, const DamageConditions(bonus: 1.3)), DamageAttackKind.shelling).normal), 68 * 1.3);
    final enemyCl = ship(type: kDmgCL, fp: 60, enemy: true);
    expect(first(attackOf(damageDayAttacks(enemyCl, ship(type: kDmgDD, armor: 10), const DamageConditions(bonus: 1.3)), DamageAttackKind.shelling).normal), 65);
  });
}
