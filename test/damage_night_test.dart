import 'dart:math';

import 'package:conning_tower/models/feature/kancolle/damage/damage_attacks.dart';
import 'package:flutter_test/flutter_test.dart';

const gun = DamageEquip(category: kDmgMediumGun);
const sec = DamageEquip(category: kDmgSecondary);
const torp = DamageEquip(category: kDmgTorpedo);
const radar = DamageEquip(category: kDmgSmallRadar, los: 5);

DamageShip ship({
  String name = '艦',
  int type = kDmgCL,
  int hp = 50,
  double armor = 50,
  int fp = 100,
  int tp = 0,
  int nakedAsw = 0,
  List<DamageEquip> equips = const [],
  int level = 99,
  bool enemy = false,
}) =>
    DamageShip(
      name: name,
      shipType: type,
      level: level,
      hp: hp,
      maxHp: hp,
      armor: armor,
      firepower: fp,
      torpedo: tp,
      nakedTorpedo: tp,
      nakedAsw: nakedAsw,
      equips: equips,
      enemy: enemy,
    );

final target = ship(name: '敵', type: kDmgCA, hp: 80, armor: 60, enemy: true);

List<String> nightLabels(DamageShip a) => [for (final x in damageNightAttacks(a, target, const DamageConditions())) x.ja];

double first(DamageAttack a) => a.normal.first.$2.first;

void main() {
  test('night: only the strongest normal cut-in is tried, double attack is last', () {
    expect(nightLabels(ship(equips: const [gun, gun, gun, sec])), ['夜戦 通常', '夜戦 主主主 ×2.0']);
    expect(nightLabels(ship(equips: const [gun, gun, sec])), ['夜戦 通常', '夜戦 主主副 ×1.75']);
    expect(nightLabels(ship(equips: const [torp, torp, gun])), ['夜戦 通常', '夜戦 魚雷カットイン ×1.5×2']);
    expect(nightLabels(ship(equips: const [gun, torp])), ['夜戦 通常', '夜戦 主魚 ×1.3×2']);
    expect(nightLabels(ship(equips: const [gun, sec])), ['夜戦 通常', '夜戦 連撃 ×1.2×2']);
    expect(nightLabels(ship(equips: const [sec, torp])), ['夜戦 通常']);
    // 吹雪改 (火力49 + 雷装79 = 128) の主主主は 256
    final fubuki = ship(type: kDmgDD, fp: 49, tp: 79, equips: const [gun, gun, gun]);
    final attacks = damageNightAttacks(fubuki, target, const DamageConditions());
    expect(first(attacks.first), 128);
    expect(first(attacks.last), 256);
    // 夜偵の触接 +5、中破 0.7、キャップ 360
    expect(first(damageNightAttacks(fubuki, target, const DamageConditions(nightContact: 5)).first), 133);
    final big = ship(fp: 250, tp: 150, equips: const [gun, gun, gun]);
    expect(first(damageNightAttacks(big, target, const DamageConditions()).first), (360 + sqrt(40)).floor());
    // 大破は攻撃できない。潜水艦は狙わない (夜戦の対潜は必ずカスダメ)
    final heavy = DamageShip(name: 'x', shipType: kDmgCL, hp: 10, maxHp: 50, armor: 40, firepower: 100, equips: const [gun]);
    expect(damageNightAttacks(heavy, target, const DamageConditions()), isEmpty);
    expect(damageNightAttacks(fubuki, ship(type: kDmgSS, enemy: true), const DamageConditions()), isEmpty);
  });

  test('destroyer cut-ins with D guns, submarine cut-ins, night Zuiun', () {
    const dGun = DamageEquip(itemId: kDmgDGunKai2, category: kDmgSmallGun);
    final dd = ship(type: kDmgDD, fp: 60, tp: 90, equips: const [dGun, torp, radar]);
    final labels = nightLabels(dd);
    expect(labels.any((l) => l.startsWith('夜戦 主魚電 ×1.625')), isTrue); // 1.3 × 1.25
    expect(labels.contains('夜戦 主魚 ×1.3×2'), isTrue); // 通常のカットインも判定される
    final gtr = damageNightAttacks(dd, target, const DamageConditions()).firstWhere((a) => a.ja.startsWith('夜戦 主魚電'));
    expect(gtr.normal.map((v) => (v.$1, v.$2.length)), [(0.5, 1), (0.5, 2)]); // 1〜2回を半々
    const lookout = DamageEquip(itemId: 412, category: kDmgSurfaceCrew);
    expect(nightLabels(ship(type: kDmgDD, equips: const [torp, torp, lookout])).any((l) => l.startsWith('夜戦 魚水魚 ×1.5')), isTrue);

    const late = DamageEquip(itemId: 383, category: kDmgSubTorpedo);
    const subRadar = DamageEquip(itemId: 384, category: kDmgSubRadar);
    expect(nightLabels(ship(type: kDmgSS, equips: const [late, late, subRadar])), ['夜戦 通常', '夜戦 後期魚雷+電探 ×1.75×2']);
    expect(nightLabels(ship(type: kDmgSS, equips: const [late, late])), ['夜戦 通常', '夜戦 後期魚雷×2 ×1.6×2']);

    const zuiun = DamageEquip(itemId: kDmgNightZuiun, category: kDmgSeaplaneBomber, count: 3);
    expect(nightLabels(ship(type: kDmgCAV, equips: const [gun, gun, zuiun, radar])), contains('夜戦 夜間瑞雲 ×1.28×2'));
  });

  test('night air attack (Saratoga Mk.II example)', () {
    // TBM-3D (火力2・雷装9・対潜8) 32機の搭載数補正 = 3×32 + 0.45×19×√32 ≒ 144.4
    const tbm = DamageEquip(itemId: 257, category: kDmgTorpedoBomber, icon: 46, firepower: 2, torpedo: 9, asw: 8, count: 32, slot: 0);
    const f6f = DamageEquip(itemId: 254, category: kDmgFighter, icon: 45, asw: 4, count: 24, slot: 1);
    const crew = DamageEquip(itemId: 258, category: 35, firepower: 1, slot: 2);
    final cv = DamageShip(
      name: 'Saratoga改', shipType: kDmgCV, hp: 90, maxHp: 90, armor: 80, firepower: 3, torpedo: 9, //
      equips: const [tbm, f6f, crew],
    );
    expect(damageCanNightAir(cv), isTrue);
    // 素火力 = 3 - (2 + 1) = 0
    final base = damageNightAirBase(cv, 0);
    expect(base, closeTo(0 + 11 + 96 + 0.45 * 19 * sqrt(32) + 0 + 72 + 0.45 * 4 * sqrt(24), 1e-9));
    final labels = [for (final a in damageNightAttacks(cv, target, const DamageConditions())) a.ja];
    expect(labels, ['夜戦 航空攻撃', '夜戦 夜襲カットイン 戦攻 ×1.2']);
    // 夜間作戦航空要員がなければ夜戦で攻撃しない
    expect(damageNightAttacks(DamageShip(name: '赤城', shipType: kDmgCV, hp: 90, maxHp: 90, armor: 80, firepower: 1, equips: const [tbm, f6f]), target,
            const DamageConditions()),
        isEmpty);
  });

  test('ASW: synergy, constants and depth charge armor reduction', () {
    const sonar = DamageEquip(itemId: 46, category: kDmgSonar, asw: 10);
    const projector = DamageEquip(itemId: 45, category: kDmgDepthCharge, asw: 8);
    const charge = DamageEquip(itemId: 227, category: kDmgDepthCharge, asw: 7);
    final de = ship(type: kDmgDE, nakedAsw: 60, equips: const [sonar, projector, charge]);
    final sub = ship(name: 'ヨ級', type: kDmgSS, hp: 40, armor: 30, enemy: true);
    final asw = damageAswAttacks(de, sub, const DamageConditions(formation: 5)).single;
    // (2√60 + 1.5×25 + 13) × 1.15 × 1.25 × 単横陣1.3
    final expected = ((2 * sqrt(60) + 37.5 + 13) * 1.4375 * 1.3).floor();
    expect(first(asw), expected);
    expect(asw.ja, '対潜 シナジー×1.4375');
    // 二式爆雷 (対潜7): √5 + 海防艦の+1
    expect(asw.armorReduction, closeTo(sqrt(5) + 1, 1e-9));
    // 艦載機の対潜は +8、潜水艦以外は狙わない、戦艦は対潜できない
    const tb = DamageEquip(category: kDmgTorpedoBomber, asw: 7, count: 18);
    expect(damageAswAttacks(ship(type: kDmgCVL, equips: const [tb]), sub, const DamageConditions()).single.ja, '対潜 (艦載機)');
    expect(damageAswAttacks(de, target, const DamageConditions()), isEmpty);
    expect(damageAswAttacks(ship(type: kDmgBB, nakedAsw: 0), sub, const DamageConditions()), isEmpty);
    // 結果は減らした装甲で計算する
    final (normal, _) = damageAttackOutcome(asw, sub, const DamageConditions(formation: 5));
    expect(normal.maxDamage, (expected - (30 - sqrt(5) - 1) * 0.7).floor());
  });
}
