// 制空権シミュレーター: 制空値・制空状態・制空戦と対空砲火による撃墜を、乱数で何千回も戦わせて数える。
//
// 計算式は「艦これ攻略 Wiki*」(https://wikiwiki.jp/kancolle/) の「航空戦」「対空砲火」「艦載機熟練度」「改修工廠」の
// 内容 (事実) を元に、このアプリ用に書き直したもの。

import 'dart:math';

/// 制空状態
enum AirState {
  supremacy('制空権確保', 'Air supremacy', 1),
  superiority('航空優勢', 'Air superiority', 3),
  parity('航空均衡', 'Air parity', 5),
  denial('航空劣勢', 'Air denial', 7),
  incapability('制空権喪失', 'Air incapability', 10),
  none('航空戦なし', 'No air battle', 0);

  const AirState(this.ja, this.en, this.constant);

  final String ja;
  final String en;

  /// 制空定数 (撃墜数の計算に使う)
  final int constant;
}

// 装備の種類 (api_mst_slotitem api_type[2])
const kAirFighter = 6, kAirDiveBomber = 7, kAirTorpedoBomber = 8, kAirCarrierRecon = 9, kAirSeaplaneRecon = 10;
const kAirSeaplaneBomber = 11, kAirAutogyro = 25, kAirAswPatrol = 26, kAirFlyingBoat = 41, kAirSeaplaneFighter = 45;
const kAirLandAttacker = 47, kAirLandFighter = 48, kAirLandRecon = 49, kAirHeavyLandAttacker = 53;
const kAirJetFighter = 56, kAirJetFighterBomber = 57, kAirJetAttacker = 58, kAirJetRecon = 59, kAirCarrierRecon2 = 94;

/// 艦載機 (航空機) の種類
const kAirPlaneCategories = {
  kAirFighter, kAirDiveBomber, kAirTorpedoBomber, kAirCarrierRecon, kAirSeaplaneRecon, kAirSeaplaneBomber, //
  kAirAutogyro, kAirAswPatrol, kAirFlyingBoat, kAirSeaplaneFighter, kAirLandAttacker, kAirLandFighter,
  kAirLandRecon, kAirHeavyLandAttacker, kAirJetFighter, kAirJetFighterBomber, kAirJetAttacker, kAirJetRecon,
  kAirCarrierRecon2,
};

/// 制空戦に参加する機種 (制空値に数え、制空戦で撃墜される。偵察機・飛行艇・回転翼機・対潜哨戒機は参加しない)
const kAirCombatCategories = {
  kAirFighter, kAirDiveBomber, kAirTorpedoBomber, kAirSeaplaneBomber, kAirSeaplaneFighter, kAirLandAttacker, //
  kAirLandFighter, kAirHeavyLandAttacker, kAirJetFighter, kAirJetFighterBomber, kAirJetAttacker,
};

/// 攻撃する機種 (対空砲火で撃墜される。戦闘機は撃墜されない)
const kAirAttackerCategories = {
  kAirDiveBomber, kAirTorpedoBomber, kAirSeaplaneBomber, kAirLandAttacker, kAirHeavyLandAttacker, //
  kAirJetFighterBomber, kAirJetAttacker,
};

/// 噴式機 (制空戦での撃墜が 0.6 倍)
const kAirJetCategories = {kAirJetFighter, kAirJetFighterBomber, kAirJetAttacker};

/// 艦載機熟練度 (0〜7) ごとの内部熟練度 (>> は最大の 120)
const kAirInternalProficiency = [0, 10, 25, 40, 55, 70, 85, 120];

/// 熟練度による固定の制空値ボーナス (艦戦・水戦・陸戦/局戦)
const kAirFighterProficiencyBonus = [0, 0, 2, 5, 9, 14, 14, 22];

/// 熟練度による固定の制空値ボーナス (水爆)
const kAirSeaplaneBomberProficiencyBonus = [0, 0, 1, 1, 1, 3, 3, 6];

/// 1スロットの艦載機
class AirPlane {
  final int itemId;
  final String name;

  /// 種類 (api_type[2])
  final int category;
  final int aa;

  /// 改修値 (★)
  final int improvement;

  /// 艦載機熟練度 (0〜7)
  final int proficiency;

  /// 迎撃 (局戦・陸戦の api_houk。基地航空隊の出撃で制空値に ×1.5 で加わる)
  final int interception;

  const AirPlane({
    required this.itemId,
    required this.name,
    required this.category,
    required this.aa,
    this.improvement = 0,
    this.proficiency = 0,
    this.interception = 0,
  });

  bool get isAirCombat => kAirCombatCategories.contains(category);
  bool get isAttacker => kAirAttackerCategories.contains(category);
  bool get isJet => kAirJetCategories.contains(category);

  /// 改修による対空値の上乗せ (艦戦・水戦・陸戦/局戦 ★×0.2、爆戦 ★×0.25)
  double get improvementAa {
    if (improvement <= 0) return 0;
    if (const {kAirFighter, kAirSeaplaneFighter, kAirLandFighter}.contains(category)) return 0.2 * improvement;
    if (category == kAirDiveBomber && aa > 3) return 0.25 * improvement;
    return 0;
  }

  /// 熟練度による制空値の上乗せ
  double get proficiencyBonus {
    final level = proficiency.clamp(0, 7);
    var bonus = sqrt(kAirInternalProficiency[level] / 10);
    if (const {kAirFighter, kAirSeaplaneFighter, kAirLandFighter}.contains(category)) {
      bonus += kAirFighterProficiencyBonus[level];
    } else if (category == kAirSeaplaneBomber) {
      bonus += kAirSeaplaneBomberProficiencyBonus[level];
    }
    return bonus;
  }
}

/// 艦の1スロット (何番目のスロットかと、出撃前の機数)
class AirSlot {
  final int index;
  final AirPlane plane;
  final int count;

  const AirSlot(this.index, this.plane, this.count);
}

/// 対空カットイン1種 (優先順位の高い順に判定する)
class AirAaci {
  final int kind;
  final int fixedBonus;
  final double variableBonus;
  final double rate;

  const AirAaci({required this.kind, required this.fixedBonus, required this.variableBonus, required this.rate});
}

/// 艦隊の1隻
class AirShip {
  final String name;
  final int shipType;
  final List<AirSlot> slots;

  /// 加重対空値 (味方・敵それぞれの式で計算済み)
  final int weightedAa;

  /// 艦隊対空ボーナス値 (端数切り捨て済み)
  final int fleetAaBonus;

  /// 発動できる対空カットイン (味方のみ)
  final List<AirAaci> aaci;
  final bool submarine;

  const AirShip({
    required this.name,
    required this.shipType,
    required this.slots,
    this.weightedAa = 0,
    this.fleetAaBonus = 0,
    this.aaci = const [],
    this.submarine = false,
  });

  bool get hasAttackers => slots.any((s) => s.plane.isAttacker && s.count > 0);
}

/// 陣形 (api の番号) → 艦隊防空の陣形補正
double airFormationModifier(int formation) => switch (formation) {
      2 => 1.2, // 複縦陣
      3 => 1.6, // 輪形陣
      6 => 1.1, // 警戒陣
      11 => 1.1, // 第一警戒航行序列 (敵連合艦隊)
      13 => 1.5, // 第三警戒航行序列 (敵連合艦隊)
      _ => 1.0, // 単縦陣・梯形陣・単横陣など
    };

String airFormationName(int formation) => switch (formation) {
      1 => '単縦陣',
      2 => '複縦陣',
      3 => '輪形陣',
      4 => '梯形陣',
      5 => '単横陣',
      6 => '警戒陣',
      11 => '第一警戒航行序列',
      12 => '第二警戒航行序列',
      13 => '第三警戒航行序列',
      14 => '第四警戒航行序列',
      _ => '陣形$formation',
    };

/// 艦隊 (味方か敵か、陣形)
class AirFleet {
  final List<AirShip> ships;
  final int formation;
  final bool enemy;

  const AirFleet(this.ships, {this.formation = 1, this.enemy = false});

  /// 艦隊防空値 (味方は ×2/1.3、敵は ×2)
  double get fleetAa {
    final total = ships.fold(0, (sum, s) => sum + s.fleetAaBonus);
    final base = (airFormationModifier(formation) * total).floor();
    return enemy ? base * 2.0 : base * 2 / 1.3;
  }

  /// 水上艦がいる (艦攻・艦爆の攻撃対象がある)
  bool get hasSurfaceShip => ships.any((s) => !s.submarine);
}

/// 1スロットの制空値。敵は熟練度・改修なし
int airSlotPower(AirPlane plane, int count, {bool enemy = false}) {
  if (count <= 0 || !plane.isAirCombat) return 0;
  if (enemy) return (plane.aa * sqrt(count)).floor();
  return ((plane.aa + plane.improvementAa) * sqrt(count) + plane.proficiencyBonus).floor();
}

/// 艦隊の制空値 ([counts] は艦ごと・スロットごとの今の機数。無ければ出撃前の機数)
int airFleetPower(AirFleet fleet, {List<List<int>>? counts}) {
  var total = 0;
  for (final (i, ship) in fleet.ships.indexed) {
    for (final (j, slot) in ship.slots.indexed) {
      total += airSlotPower(slot.plane, counts?[i][j] ?? slot.count, enemy: fleet.enemy);
    }
  }
  return total;
}

/// 基地航空隊の出撃で制空値に数える偵察機
const kAirLbasReconCategories = {kAirCarrierRecon, kAirSeaplaneRecon, kAirFlyingBoat, kAirLandRecon, kAirJetRecon, kAirCarrierRecon2};

/// 基地航空隊1部隊 (出撃すると同じマスへ2回 (2波) 攻撃する)
class AirBase {
  final String name;
  final List<AirSlot> squadrons;

  /// 偵察機による制空値の倍率 (出撃時。陸偵 索敵9以上 1.18、それ以外の陸偵 1.15)
  final double reconMultiplier;

  const AirBase(this.name, this.squadrons, {this.reconMultiplier = 1});
}

/// 基地航空隊 (出撃) の1中隊の制空値: (対空 + 迎撃×1.5 + 改修) × √機数 + 熟練度。偵察機も数える
int airLbasSlotPower(AirPlane plane, int count) {
  if (count <= 0) return 0;
  if (!plane.isAirCombat && !kAirLbasReconCategories.contains(plane.category)) return 0;
  final interception = plane.category == kAirLandFighter ? 1.5 * plane.interception : 0;
  final improvement = plane.category == kAirLandAttacker ? 0.5 * sqrt(plane.improvement) : plane.improvementAa;
  return ((plane.aa + interception + improvement) * sqrt(count) + plane.proficiencyBonus).floor();
}

/// 基地航空隊の制空値 ([counts] は中隊ごとの今の機数)
int airBasePower(AirBase base, List<int> counts) {
  var total = 0;
  for (final (i, slot) in base.squadrons.indexed) {
    total += airLbasSlotPower(slot.plane, counts[i]);
  }
  return (total * base.reconMultiplier).floor();
}

/// 制空値から制空状態を決める。[battle] は航空戦が起きるか (どちらかに制空戦に出る機体がある)
AirState airStateOf(int own, int enemy, {bool battle = true}) {
  if (!battle) return AirState.none;
  if (enemy <= 0 || own >= 3 * enemy) return AirState.supremacy;
  if (2 * own >= 3 * enemy) return AirState.superiority;
  if (3 * own > 2 * enemy) return AirState.parity;
  if (3 * own > enemy) return AirState.denial;
  return AirState.incapability;
}

/// 敵の制空値に対して、それぞれの制空状態になるのに必要な制空値 (確保・優勢・均衡・劣勢)
Map<AirState, int> airPowerNeeded(int enemy) => {
      AirState.supremacy: 3 * enemy,
      AirState.superiority: (3 * enemy + 1) ~/ 2,
      AirState.parity: enemy * 2 ~/ 3 + 1,
      AirState.denial: enemy ~/ 3 + 1,
    };

/// 制空戦で撃墜される味方の機数: 機数 × (A + 制空定数/4) / 10 (A = 0〜制空定数の整数 / 3)。噴式機は 0.6 倍
int airOwnStage1Loss(int count, AirState state, {required bool jet, required Random random}) {
  final c = state.constant;
  if (count <= 0 || c == 0) return 0;
  final k = random.nextInt(c + 1);
  // A + c/4 = (4k + 3c) / 12 なので、/10 と合わせて /120 (整数で計算して端数のずれを防ぐ)
  final loss = jet ? count * (4 * k + 3 * c) * 3 ~/ 600 : count * (4 * k + 3 * c) ~/ 120;
  return min(count, loss);
}

/// 制空戦で撃墜される敵の機数: 機数 × (0.035×B1 + 0.065×B2) (B = 0〜(11 - 制空定数) の整数)
int airEnemyStage1Loss(int count, AirState state, {required Random random}) {
  final c = state.constant;
  if (count <= 0 || c == 0) return 0;
  final m = 11 - c;
  final loss = count * (35 * random.nextInt(m + 1) + 65 * random.nextInt(m + 1)) ~/ 1000;
  return min(count, loss);
}

/// 味方の対空砲火で敵の攻撃機が落とされたあとの機数 (割合撃墜・固定撃墜は 50% ずつ、最低1機 + 対空カットインの固定ボーナス)
int airOwnAaRemaining(int count, AirShip interceptor, double fleetAa, AirAaci? aaci, {required Random random}) {
  var n = count;
  if (n <= 0) return 0;
  if (random.nextBool()) n -= interceptor.weightedAa * n ~/ 400;
  if (random.nextBool()) n -= ((interceptor.weightedAa + fleetAa) * (aaci?.variableBonus ?? 1) / 10).floor();
  n -= 1 + (aaci?.fixedBonus ?? 0);
  return max(0, n);
}

/// 敵の対空砲火で味方の攻撃機が落とされたあとの機数 (割合撃墜・固定撃墜は 50% ずつ、最低保証なし)
int airEnemyAaRemaining(int count, AirShip interceptor, double fleetAa, {required Random random}) {
  var n = count;
  if (n <= 0) return 0;
  if (random.nextBool()) n -= interceptor.weightedAa * n ~/ 400;
  if (random.nextBool()) n -= ((interceptor.weightedAa + fleetAa) * 0.09375).floor();
  return max(0, n);
}

/// この戦闘で発動する対空カットイン (上の艦から順に、各艦は優先順位の高い順に判定)
AirAaci? airPickAaci(AirFleet fleet, Random random) {
  for (final ship in fleet.ships) {
    for (final aaci in ship.aaci) {
      if (random.nextDouble() < aaci.rate) return aaci;
    }
  }
  return null;
}

/// 1スロットの集計
class AirSlotResult {
  final AirSlot slot;

  /// 戦闘前の平均機数
  final double before;

  /// 制空戦のあとの平均機数
  final double afterAirCombat;

  /// 戦闘後 (対空砲火のあと) の平均機数
  final double after;

  /// 戦闘後に 0 機になっている確率 (戦闘前から 0 機だった回は除く)
  final double annihilation;

  const AirSlotResult(this.slot, this.before, this.afterAirCombat, this.after, this.annihilation);

  double get lost => before - after;
}

/// 基地航空隊の1波ぶんの集計
class AirWaveResult {
  final String baseName;

  /// 何波目か (1 か 2)
  final int wave;
  final Map<AirState, double> states;

  /// 基地の制空値 (平均)
  final double basePower;

  /// そのときの敵の制空値 (平均。前の波で減った分を反映)
  final double enemyPower;

  /// 中隊ごと (戦闘前 → 戦闘後)
  final List<AirSlotResult> squadrons;

  const AirWaveResult({
    required this.baseName,
    required this.wave,
    required this.states,
    required this.basePower,
    required this.enemyPower,
    required this.squadrons,
  });
}

/// 1戦ぶんの集計
class AirBattleResult {
  final int runs;

  /// 味方の制空値 (平均。連戦では前の戦闘で減った分を反映)
  final double ownPower;

  /// 敵の制空値 (出撃したときの機数で)
  final int enemyPower;

  /// 艦隊の航空戦のときの敵の制空値 (平均。基地航空隊で減った分を反映)
  final double enemyPowerAtFleet;

  /// 基地航空隊の波ごとの集計 (攻撃した順)
  final List<AirWaveResult> waves;

  /// 制空状態 → 確率
  final Map<AirState, double> states;

  /// 味方の艦ごと・スロットごと
  final List<List<AirSlotResult>> own;

  /// 敵の艦ごと・スロットごと
  final List<List<AirSlotResult>> enemy;

  /// 敵の艦ごとの「攻撃機が全滅する (棒立ちになる) 確率」(攻撃機を持たない艦は null)
  final List<double?> enemyGrounded;

  /// 敵の攻撃機がすべて落ちて、航空攻撃が来なくなる確率 (敵に攻撃機がなければ null)
  final double? enemyStrikeZero;

  /// 味方の対空カットインが出た割合
  final double aaciRate;

  AirBattleResult({
    required this.runs,
    required this.ownPower,
    required this.enemyPower,
    double? enemyPowerAtFleet,
    this.waves = const [],
    required this.states,
    required this.own,
    required this.enemy,
    required this.enemyGrounded,
    required this.enemyStrikeZero,
    required this.aaciRate,
  }) : enemyPowerAtFleet = enemyPowerAtFleet ?? enemyPower.toDouble();

  /// いちばん起きやすい制空状態
  AirState get likelyState => states.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

class _SlotTotal {
  double before = 0, afterAirCombat = 0, after = 0;
  int zero = 0, had = 0;
}

/// [own] で [enemies] と順に戦ったときの、戦闘ごとの集計。味方の機数は次の戦闘に持ち越す (敵は毎回出撃前の機数)。
/// [bases] は戦闘の番号 → そのマスを攻撃する基地航空隊 (それぞれ2波。艦隊の航空戦の前に敵機を減らす)
List<AirBattleResult> simulateAirBattles(
  AirFleet own,
  List<AirFleet> enemies, {
  int runs = 5000,
  int? seed,
  Map<int, List<AirBase>> bases = const {},
}) {
  final random = Random(seed);
  final ownTotals = [
    for (final _ in enemies) [for (final ship in own.ships) [for (final _ in ship.slots) _SlotTotal()]],
  ];
  final enemyTotals = [
    for (final e in enemies) [for (final ship in e.ships) [for (final _ in ship.slots) _SlotTotal()]],
  ];
  final stateCounts = [for (final _ in enemies) <AirState, int>{}];
  final powerTotals = List.filled(enemies.length, 0.0);
  final groundedCounts = [for (final e in enemies) List.filled(e.ships.length, 0)];
  final strikeZeroCounts = List.filled(enemies.length, 0);
  final aaciCounts = List.filled(enemies.length, 0);
  final ownFleetAa = own.fleetAa;
  final enemyPowers = [for (final e in enemies) airFleetPower(e)];
  final enemyFleetAa = [for (final e in enemies) e.fleetAa];
  final enemyPowerAtFleet = List.filled(enemies.length, 0.0);
  // 基地航空隊: 戦闘ごと・波ごと (基地1の1波, 基地1の2波, 基地2の1波, ...)
  final waveBases = [for (var b = 0; b < enemies.length; b++) [for (final base in bases[b] ?? const <AirBase>[]) ...[base, base]]];
  final waveStates = [for (final list in waveBases) [for (final _ in list) <AirState, int>{}]];
  final waveBasePower = [for (final list in waveBases) List.filled(list.length, 0.0)];
  final waveEnemyPower = [for (final list in waveBases) List.filled(list.length, 0.0)];
  final waveSlots = [for (final list in waveBases) [for (final base in list) [for (final _ in base.squadrons) _SlotTotal()]]];

  for (var run = 0; run < runs; run++) {
    final counts = [for (final ship in own.ships) [for (final slot in ship.slots) slot.count]];
    for (final (b, enemy) in enemies.indexed) {
      final enemyCounts = [for (final ship in enemy.ships) [for (final slot in ship.slots) slot.count]];
      final start = [for (final row in counts) [...row]];
      for (final (i, ship) in enemy.ships.indexed) {
        for (var j = 0; j < ship.slots.length; j++) {
          enemyTotals[b][i][j].before += enemyCounts[i][j];
        }
      }

      // 基地航空隊 (同じ基地の1波と2波は機数を持ち越す)
      List<int>? baseCounts;
      for (final (k, base) in waveBases[b].indexed) {
        if (k.isEven) baseCounts = [for (final s in base.squadrons) s.count];
        final squadrons = baseCounts!;
        for (final (j, total) in waveSlots[b][k].indexed) {
          total.before += squadrons[j];
        }
        final basePower = airBasePower(base, squadrons);
        final enemyNow = airFleetPower(enemy, counts: enemyCounts);
        waveBasePower[b][k] += basePower;
        waveEnemyPower[b][k] += enemyNow;
        final baseFlies = base.squadrons.indexed.any((e) => squadrons[e.$1] > 0 && (e.$2.plane.isAirCombat || kAirLbasReconCategories.contains(e.$2.plane.category)));
        final waveState = airStateOf(basePower, enemyNow, battle: baseFlies);
        waveStates[b][k][waveState] = (waveStates[b][k][waveState] ?? 0) + 1;
        if (waveState != AirState.none) {
          for (final (j, slot) in base.squadrons.indexed) {
            if (!slot.plane.isAirCombat) continue;
            squadrons[j] -= airOwnStage1Loss(squadrons[j], waveState, jet: slot.plane.isJet, random: random);
          }
          for (final (i, ship) in enemy.ships.indexed) {
            for (final (j, slot) in ship.slots.indexed) {
              if (!slot.plane.isAirCombat) continue;
              enemyCounts[i][j] -= airEnemyStage1Loss(enemyCounts[i][j], waveState, random: random);
            }
          }
          // 攻撃機は敵の対空砲火を受ける (基地航空隊には敵の対空カットインは出ない)
          if (enemy.hasSurfaceShip) {
            for (final (j, slot) in base.squadrons.indexed) {
              if (!slot.plane.isAttacker || squadrons[j] <= 0) continue;
              final interceptor = enemy.ships[random.nextInt(enemy.ships.length)];
              squadrons[j] = airEnemyAaRemaining(squadrons[j], interceptor, enemyFleetAa[b], random: random);
            }
          }
        }
        for (final (j, total) in waveSlots[b][k].indexed) {
          total.after += squadrons[j];
          total.afterAirCombat += squadrons[j];
          if (base.squadrons[j].count > 0) {
            total.had++;
            if (squadrons[j] <= 0) total.zero++;
          }
        }
      }

      final ownPower = airFleetPower(own, counts: counts);
      powerTotals[b] += ownPower;
      final enemyPower = airFleetPower(enemy, counts: enemyCounts);
      enemyPowerAtFleet[b] += enemyPower;
      final battle = _hasAirCombat(own, counts) || _hasAirCombat(enemy, enemyCounts);
      final state = airStateOf(ownPower, enemyPower, battle: battle);
      stateCounts[b][state] = (stateCounts[b][state] ?? 0) + 1;

      // 戦闘前
      for (final (i, ship) in own.ships.indexed) {
        for (var j = 0; j < ship.slots.length; j++) {
          ownTotals[b][i][j].before += counts[i][j];
        }
      }

      // 制空戦
      if (state != AirState.none) {
        for (final (i, ship) in own.ships.indexed) {
          for (final (j, slot) in ship.slots.indexed) {
            if (!slot.plane.isAirCombat) continue;
            counts[i][j] -= airOwnStage1Loss(counts[i][j], state, jet: slot.plane.isJet, random: random);
          }
        }
        for (final (i, ship) in enemy.ships.indexed) {
          for (final (j, slot) in ship.slots.indexed) {
            if (!slot.plane.isAirCombat) continue;
            enemyCounts[i][j] -= airEnemyStage1Loss(enemyCounts[i][j], state, random: random);
          }
        }
      }
      for (final (i, ship) in own.ships.indexed) {
        for (var j = 0; j < ship.slots.length; j++) {
          ownTotals[b][i][j].afterAirCombat += counts[i][j];
        }
      }
      for (final (i, ship) in enemy.ships.indexed) {
        for (var j = 0; j < ship.slots.length; j++) {
          enemyTotals[b][i][j].afterAirCombat += enemyCounts[i][j];
        }
      }

      // 対空砲火
      if (state != AirState.none) {
        // 敵の攻撃機 ← 味方の対空砲火
        final enemyAttacks = _hasAttackers(enemy, enemyCounts) && own.ships.isNotEmpty;
        final aaci = enemyAttacks ? airPickAaci(own, random) : null;
        if (aaci != null) aaciCounts[b]++;
        if (enemyAttacks) {
          for (final (i, ship) in enemy.ships.indexed) {
            for (final (j, slot) in ship.slots.indexed) {
              if (!slot.plane.isAttacker || enemyCounts[i][j] <= 0) continue;
              final interceptor = own.ships[random.nextInt(own.ships.length)];
              enemyCounts[i][j] = airOwnAaRemaining(enemyCounts[i][j], interceptor, ownFleetAa, aaci, random: random);
            }
          }
        }
        // 味方の攻撃機 ← 敵の対空砲火 (攻撃できる水上艦がいるときだけ攻撃する)
        if (_hasAttackers(own, counts) && enemy.hasSurfaceShip) {
          for (final (i, ship) in own.ships.indexed) {
            for (final (j, slot) in ship.slots.indexed) {
              if (!slot.plane.isAttacker || counts[i][j] <= 0) continue;
              final interceptor = enemy.ships[random.nextInt(enemy.ships.length)];
              counts[i][j] = airEnemyAaRemaining(counts[i][j], interceptor, enemyFleetAa[b], random: random);
            }
          }
        }
      }

      // 戦闘後
      for (final (i, ship) in own.ships.indexed) {
        for (var j = 0; j < ship.slots.length; j++) {
          final total = ownTotals[b][i][j];
          total.after += counts[i][j];
          // 戦闘前から 0 機の回は全滅率に数えない
          if (start[i][j] > 0) {
            total.had++;
            if (counts[i][j] <= 0) total.zero++;
          }
        }
      }
      var anyEnemyAttacker = false;
      var allEnemyAttackersGone = true;
      for (final (i, ship) in enemy.ships.indexed) {
        var shipHasAttacker = false;
        var shipGrounded = true;
        for (final (j, slot) in ship.slots.indexed) {
          final total = enemyTotals[b][i][j];
          total.after += enemyCounts[i][j];
          if (slot.count > 0) {
            total.had++;
            if (enemyCounts[i][j] <= 0) total.zero++;
          }
          if (slot.plane.isAttacker && slot.count > 0) {
            shipHasAttacker = true;
            anyEnemyAttacker = true;
            if (enemyCounts[i][j] > 0) {
              shipGrounded = false;
              allEnemyAttackersGone = false;
            }
          }
        }
        if (shipHasAttacker && shipGrounded) groundedCounts[b][i]++;
      }
      if (anyEnemyAttacker && allEnemyAttackersGone) strikeZeroCounts[b]++;
    }
  }

  return [
    for (final (b, enemy) in enemies.indexed)
      AirBattleResult(
        runs: runs,
        ownPower: runs == 0 ? 0 : powerTotals[b] / runs,
        enemyPower: enemyPowers[b],
        enemyPowerAtFleet: runs == 0 ? enemyPowers[b].toDouble() : enemyPowerAtFleet[b] / runs,
        waves: [
          for (final (k, base) in waveBases[b].indexed)
            AirWaveResult(
              baseName: base.name,
              wave: k.isEven ? 1 : 2,
              states: {for (final s in AirState.values) if ((waveStates[b][k][s] ?? 0) > 0) s: waveStates[b][k][s]! / runs},
              basePower: runs == 0 ? 0 : waveBasePower[b][k] / runs,
              enemyPower: runs == 0 ? 0 : waveEnemyPower[b][k] / runs,
              squadrons: [for (final (j, slot) in base.squadrons.indexed) _slotResult(slot, waveSlots[b][k][j], runs)],
            ),
        ],
        states: {for (final s in AirState.values) if ((stateCounts[b][s] ?? 0) > 0) s: stateCounts[b][s]! / runs},
        own: [
          for (final (i, ship) in own.ships.indexed)
            [for (final (j, slot) in ship.slots.indexed) _slotResult(slot, ownTotals[b][i][j], runs)],
        ],
        enemy: [
          for (final (i, ship) in enemy.ships.indexed)
            [for (final (j, slot) in ship.slots.indexed) _slotResult(slot, enemyTotals[b][i][j], runs)],
        ],
        enemyGrounded: [
          for (final (i, ship) in enemy.ships.indexed) ship.hasAttackers ? groundedCounts[b][i] / runs : null,
        ],
        enemyStrikeZero: enemy.ships.any((s) => s.hasAttackers) ? strikeZeroCounts[b] / runs : null,
        aaciRate: runs == 0 ? 0 : aaciCounts[b] / runs,
      ),
  ];
}

AirSlotResult _slotResult(AirSlot slot, _SlotTotal t, int runs) => AirSlotResult(
      slot,
      runs == 0 ? 0 : t.before / runs,
      runs == 0 ? 0 : t.afterAirCombat / runs,
      runs == 0 ? 0 : t.after / runs,
      t.had == 0 ? 0 : t.zero / t.had,
    );

bool _hasAirCombat(AirFleet fleet, List<List<int>> counts) {
  for (final (i, ship) in fleet.ships.indexed) {
    for (final (j, slot) in ship.slots.indexed) {
      if (slot.plane.isAirCombat && counts[i][j] > 0) return true;
    }
  }
  return false;
}

bool _hasAttackers(AirFleet fleet, List<List<int>> counts) {
  for (final (i, ship) in fleet.ships.indexed) {
    for (final (j, slot) in ship.slots.indexed) {
      if (slot.plane.isAttacker && counts[i][j] > 0) return true;
    }
  }
  return false;
}
