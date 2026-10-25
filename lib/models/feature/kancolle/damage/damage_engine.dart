// ダメージシミュレーター: 1回の攻撃が当たったときのダメージの幅と、撃沈・大破・中破になる確率。
//
// 計算式は「艦これ攻略 Wiki*」(https://wikiwiki.jp/kancolle/) の「戦闘について」「夜戦」「対潜攻撃」「対地攻撃」
// 「改修工廠」「艦載機熟練度」の内容 (事実) を元に、このアプリ用に書き直したもの。
//
// 装甲の乱数 (装甲×0.7 + [[装甲]×乱数]×0.6) と割合ダメージ (カスダメ) の乱数は、どちらも
// 「0〜(値-1) の整数が同じ確率で出る」形なので、乱数を回さずに正確な確率を出す。

import 'dart:math';

/// 攻撃の段階 (キャップの値)
enum DamagePhase {
  shelling(220),
  torpedo(180),
  airstrike(170),
  asw(170),
  night(360);

  const DamagePhase(this.cap);

  final int cap;
}

/// キャップ処理: キャップ値 + √(キャップ前攻撃力 - キャップ値)
double damageSoftCap(double preCap, int cap) => preCap > cap ? cap + sqrt(preCap - cap) : preCap;

/// 損傷状態
enum DamageState {
  none('無傷', 'Undamaged'),
  light('小破', 'Light'),
  medium('中破', 'Moderate'),
  heavy('大破', 'Heavy'),
  sunk('撃沈', 'Sunk');

  const DamageState(this.ja, this.en);

  final String ja;
  final String en;
}

DamageState damageStateOf(int hp, int maxHp) {
  if (hp <= 0) return DamageState.sunk;
  if (hp * 4 <= maxHp) return DamageState.heavy;
  if (hp * 2 <= maxHp) return DamageState.medium;
  if (hp * 4 <= maxHp * 3) return DamageState.light;
  return DamageState.none;
}

/// 端数の誤差 (100×0.7 = 70.00000000000001 など) で切り捨てがずれないようにする
int damageFloor(double v) => (v + 1e-9).floor();

/// 1発のダメージ (耐久 [hp] の相手に、装甲の乱数ごと)。値 → 確率
Map<int, double> damageHitDistribution({
  required double attack,
  required double armor,
  required int hp,
  double ammo = 1,
  bool stopper = false,
}) {
  final result = <int, double>{};
  void add(int damage, double p) => result[damage] = (result[damage] ?? 0) + p;

  // 割合ダメージ (カスダメ): [現在HP×0.06 + [現在HP×乱数]×0.08]、轟沈ストッパー: [現在HP×0.5 + [現在HP×乱数]×0.3]
  // どちらも乱数部分は 0〜(現在HP-1) が同じ確率なので、まとめて数えておく
  var scratchShare = 0.0;
  var stopShare = 0.0;
  final a = max(0, armor.floor());
  final rolls = max(1, a);
  for (var k = 0; k < rolls; k++) {
    final defense = max(0.0, armor * 0.7 + (a == 0 ? 0 : k) * 0.6);
    final raw = damageFloor((attack - defense) * ammo);
    final p = 1 / rolls;
    if (raw <= 0) {
      scratchShare += p;
    } else if (stopper && raw >= hp) {
      stopShare += p;
    } else {
      add(raw, p);
    }
  }
  if (scratchShare > 0) {
    if (hp <= 0) {
      add(0, scratchShare);
    } else {
      for (var k = 0; k < hp; k++) {
        add(damageFloor(hp * 0.06 + k * 0.08), scratchShare / hp);
      }
    }
  }
  if (stopShare > 0) {
    for (var k = 0; k < hp; k++) {
      add(damageFloor(hp * 0.5 + k * 0.3), stopShare / hp);
    }
  }
  return result;
}

/// 1回の攻撃の結果 (撃沈・大破・中破になる確率と、1発あたりのダメージの幅)
class DamageOutcome {
  /// 1発あたりのダメージ (耐久で頭打ちにしない。装甲を抜けないときは null)
  final int? minDamage;
  final int? maxDamage;

  /// 装甲を抜けないことがある (割合ダメージになる)
  final bool canScratch;

  /// 何発当たるか
  final int hits;
  final double sink;
  final double heavy;
  final double medium;
  final double light;

  const DamageOutcome({
    required this.minDamage,
    required this.maxDamage,
    required this.canScratch,
    required this.hits,
    required this.sink,
    required this.heavy,
    required this.medium,
    required this.light,
  });

  /// 大破以上 (撃沈を含む)
  double get heavyOrWorse => sink + heavy;

  /// 中破以上
  double get mediumOrWorse => sink + heavy + medium;
}

/// [attacks] (1発ごとの最終攻撃力) が全部当たったときの結果。
/// [stopper] は轟沈ストッパー (味方の旗艦や、戦闘開始時に大破していない随伴艦が受ける攻撃)
DamageOutcome damageOutcome({
  required List<double> attacks,
  required double armor,
  required int hp,
  required int maxHp,
  double ammo = 1,
  bool stopper = false,
}) {
  var dist = <int, double>{hp: 1};
  int? minDamage, maxDamage;
  var canScratch = false;
  for (final attack in attacks) {
    // 1発あたりの幅 (耐久に関係しない部分)
    final a = max(0, armor.floor());
    final low = damageFloor((attack - max(0.0, armor * 0.7 + max(0, a - 1) * 0.6)) * ammo);
    final high = damageFloor((attack - armor * 0.7) * ammo);
    if (low <= 0) canScratch = true;
    if (high > 0) {
      minDamage = min(minDamage ?? 9999, max(1, low));
      maxDamage = max(maxDamage ?? 0, high);
    }
    final next = <int, double>{};
    for (final MapEntry(key: now, value: p) in dist.entries) {
      if (now <= 0) {
        next[now] = (next[now] ?? 0) + p;
        continue;
      }
      for (final MapEntry(key: damage, value: q) in damageHitDistribution(
        attack: attack,
        armor: armor,
        hp: now,
        ammo: ammo,
        stopper: stopper,
      ).entries) {
        final left = max(0, now - damage);
        next[left] = (next[left] ?? 0) + p * q;
      }
    }
    dist = next;
  }
  double sink = 0, heavy = 0, medium = 0, light = 0;
  for (final MapEntry(key: left, value: p) in dist.entries) {
    switch (damageStateOf(left, maxHp)) {
      case DamageState.sunk:
        sink += p;
      case DamageState.heavy:
        heavy += p;
      case DamageState.medium:
        medium += p;
      case DamageState.light:
        light += p;
      case DamageState.none:
        break;
    }
  }
  return DamageOutcome(
    minDamage: minDamage,
    maxDamage: maxDamage,
    canScratch: canScratch,
    hits: attacks.length,
    sink: sink,
    heavy: heavy,
    medium: medium,
    light: light,
  );
}

/// [variants] (確率, 1発ごとの最終攻撃力) を混ぜた結果 (艦攻の 0.8倍/1.5倍 など)
DamageOutcome damageMixedOutcome({
  required List<(double, List<double>)> variants,
  required double armor,
  required int hp,
  required int maxHp,
  double ammo = 1,
  bool stopper = false,
}) {
  if (variants.length == 1) {
    return damageOutcome(attacks: variants.single.$2, armor: armor, hp: hp, maxHp: maxHp, ammo: ammo, stopper: stopper);
  }
  final outcomes = [
    for (final (p, attacks) in variants)
      (p, damageOutcome(attacks: attacks, armor: armor, hp: hp, maxHp: maxHp, ammo: ammo, stopper: stopper)),
  ];
  double sum(double Function(DamageOutcome o) f) => outcomes.fold(0.0, (s, e) => s + e.$1 * f(e.$2));
  final mins = [for (final (_, o) in outcomes) if (o.minDamage != null) o.minDamage!];
  final maxs = [for (final (_, o) in outcomes) if (o.maxDamage != null) o.maxDamage!];
  return DamageOutcome(
    minDamage: mins.isEmpty ? null : mins.reduce(min),
    maxDamage: maxs.isEmpty ? null : maxs.reduce(max),
    canScratch: outcomes.any((e) => e.$2.canScratch),
    hits: outcomes.first.$2.hits,
    sink: sum((o) => o.sink),
    heavy: sum((o) => o.heavy),
    medium: sum((o) => o.medium),
    light: sum((o) => o.light),
  );
}
