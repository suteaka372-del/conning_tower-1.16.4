// ダメージシミュレーター: 陸上型 (対地) への補正。
// 「艦これ攻略 Wiki*」の「対地攻撃」の表から、補正の値と計算の順番を読み取って書き直したもの (文章は写していない)。
//
// キャップ前: ((対地基本攻撃力 × 艦種補正 + 潜水艦の+30) × 一般対地乗算補正) に 11連隊・M4A1 などの
// 「×乗算 + 加算」を決まった順に重ね、最後に WG42・噴進砲・迫撃砲の加算を足す。
// キャップ後: 集積地棲姫 (集積地夏姫を除く) には集積地補正を掛ける。

import 'damage_attacks.dart';

/// 艦上偵察機 (空母の対地攻撃で爆装が数えられる)
const kDmgCarrierRecon = 9;

const kDmgWg42 = 126;

/// 四式20cm対地噴進砲 (無印・集中配備)
const kDmgGroundRockets = {348, 349};

/// 特大発系 (特大発動艇・III号戦車・III号戦車J型)
const kDmgTokuDaihatsu = {193, 482, 514};

/// 陸戦隊系 (陸戦隊・一式砲戦車・III号戦車・III号戦車J型)
const kDmgRikusen = {166, 449, 482, 514};
const kDmgRikusenOnly = 166;
const kDmgChiha = 494, kDmgChihaKai = 495;
const kDmgPanzer2 = 436;

/// M4A1 DD系 (M4A1 DD・特大発チハ改・III号戦車J型)
const kDmgM4Group = {355, 495, 514};
const kDmgM4 = 355;

/// 上陸支援舟艇 (武装大発・装甲艇(AB艇))
const kDmgArmedDaihatsu = 409, kDmgAbBoat = 408;
const kDmgToku4 = {525, 526};
const kDmgToku4Kai = 526;
const kDmgKami = 167;

/// 11連隊・一式砲戦車・III号戦車の補正 (×1.8 +25) を持つもの
const kDmgRegiment11 = {230, 449, 482, 514};
const kDmgType1Gun = 449;

/// 上陸支援舟艇シナジーの相手 (表の左の列・右の列)
const kDmgSupportSynergyA = {68, 193, 166, 449, 436, 525, 526};
const kDmgSupportSynergyB = {230, 482, 514, 494, 495, 167};

/// 加算補正 (1〜4積み)
const kDmgGroundAdds = {
  kDmgWg42: [75, 110, 140, 160],
  348: [55, 115, 160, 190],
  349: [80, 170, 230, 260],
  346: [30, 55, 75, 90],
  347: [60, 110, 150, 180],
};

/// 対地艦爆 (空母が砲撃戦で陸上型を攻撃できる艦爆)
const kDmgGroundBombers = {64, 148, 233, 277, 305, 306, 319, 320, 391, 392, 420, 421, 474, 550};

/// 陸上型の種類ごとの倍率。[1積み, 2積み以上] は数で変わるもの、Pair は2つ以上 (または混載) のときに追加で掛かる分
class _GroundTable {
  final double aaShell;
  final List<double> wg, rocket, mortar;
  final double landing, tokuDaihatsu, rikusen, rikusenPair, panzer2, panzer2Pair, m4, support, supportPair, toku4Kai;
  final List<double> kami;
  final double apShell, seaplane;
  final List<double> bomber;

  const _GroundTable({
    this.aaShell = 1,
    required this.wg,
    required this.rocket,
    required this.mortar,
    required this.landing,
    required this.tokuDaihatsu,
    required this.rikusen,
    required this.rikusenPair,
    required this.panzer2,
    required this.panzer2Pair,
    required this.m4,
    required this.support,
    required this.supportPair,
    required this.toku4Kai,
    required this.kami,
    this.apShell = 1,
    this.seaplane = 1,
    this.bomber = const [1, 1],
  });
}

/// ソフトスキン型 (集積地型・北端上陸姫のキャップ前もこれ)
const _softSkin = _GroundTable(
  aaShell: 2.5,
  wg: [1.3, 1.82],
  rocket: [1.25, 1.875],
  mortar: [1.2, 1.56],
  landing: 1.4,
  tokuDaihatsu: 1.15,
  rikusen: 1.5,
  rikusenPair: 1.3,
  panzer2: 1.5,
  panzer2Pair: 1.3,
  m4: 1.1,
  support: 1.1,
  supportPair: 1.1,
  toku4Kai: 1.2,
  kami: [1.5, 1.8],
  seaplane: 1.2,
);

/// トーチカ型 (砲台小鬼)
const _pillbox = _GroundTable(
  wg: [1.6, 2.72],
  rocket: [1.5, 2.7],
  mortar: [1.3, 1.95],
  landing: 1.8,
  tokuDaihatsu: 1.15,
  rikusen: 1.5,
  rikusenPair: 1.4,
  panzer2: 1.5,
  panzer2Pair: 1.4,
  m4: 2.0,
  support: 1.3,
  supportPair: 1.2,
  toku4Kai: 1.35,
  kami: [2.4, 3.24],
  apShell: 1.85,
  seaplane: 1.5,
  bomber: [1.5, 3.0],
);

/// ハードスキン型 (離島棲姫)
const _island = _GroundTable(
  aaShell: 1.75,
  wg: [1.4, 2.1],
  rocket: [1.3, 2.145],
  mortar: [1.2, 1.68],
  landing: 1.8,
  tokuDaihatsu: 1.15,
  rikusen: 1.2,
  rikusenPair: 1.4,
  panzer2: 1.2,
  panzer2Pair: 1.4,
  m4: 1.8,
  support: 1.3,
  supportPair: 1.1,
  toku4Kai: 1.35,
  kami: [2.4, 3.24],
  bomber: [1.4, 2.45],
);

/// 港湾夏姫
const _harborSummer = _GroundTable(
  aaShell: 1.75,
  wg: [1.4, 1.68],
  rocket: [1.25, 1.75],
  mortar: [1.1, 1.265],
  landing: 1.7,
  tokuDaihatsu: 1.2,
  rikusen: 1.6,
  rikusenPair: 1.5,
  panzer2: 1.6,
  panzer2Pair: 1.5,
  m4: 2.0,
  support: 1.5,
  supportPair: 1.1,
  toku4Kai: 1.5,
  kami: [2.8, 4.2],
  apShell: 1.3,
  seaplane: 1.3,
  bomber: [1.3, 1.3],
);

/// 集積地補正 (キャップ後)。II号戦車2つの値は分かっていないので1つと同じとする
const _supplyDepot = _GroundTable(
  wg: [1.25, 1.625],
  rocket: [1.2, 1.68],
  mortar: [1.15, 1.38],
  landing: 1.7,
  tokuDaihatsu: 1.2,
  rikusen: 1.3,
  rikusenPair: 1.6,
  panzer2: 1.3,
  panzer2Pair: 1.0,
  m4: 1.2,
  support: 1.5,
  supportPair: 1.1,
  toku4Kai: 1.5,
  kami: [1.7, 2.55],
);

_GroundTable _tableOf(int installType) => switch (installType) {
      2 => _pillbox,
      4 => _island,
      6 => _harborSummer,
      _ => _softSkin,
    };

/// 陸上型への補正。キャップ前は 対地基本攻撃力 × [multiplier] + [add]、キャップ後は × [depot]
class DamageGroundBonus {
  /// 艦種補正と、乗算補正すべての積
  final double multiplier;
  final double add;

  /// 集積地補正
  final double depot;

  const DamageGroundBonus({this.multiplier = 1, this.add = 0, this.depot = 1});

  static const none = DamageGroundBonus();

  double apply(double base) => base * multiplier + add;

  bool get isNone => multiplier == 1 && add == 0 && depot == 1;
}

double _pick(List<double> values, int count) => count <= 0 ? 1 : (count == 1 ? values[0] : values[1]);

double _average(Iterable<DamageEquip> equips) => equips.isEmpty ? 0 : equips.fold(0, (s, e) => s + e.improvement) / equips.length;

/// 上陸用舟艇 (特四式内火艇を含む) のベース倍率 × 個別倍率 × 改修補正。上陸用舟艇がなければ 1
double _landingMultiplier(DamageShip a, _GroundTable t, {required bool support, int improvementPower = 1}) {
  int n(Set<int> ids) => a.countOf((e) => ids.contains(e.itemId));
  final landing = a.equips.where((e) => e.category == kDmgLandingCraft);
  final toku4 = a.equips.where((e) => kDmgToku4.contains(e.itemId));
  if (landing.isEmpty && toku4.isEmpty) return 1;
  var m = t.landing;
  if (n(kDmgTokuDaihatsu) > 0) m *= t.tokuDaihatsu;
  final rikusen = n(kDmgRikusen);
  final chiha = n({kDmgChiha});
  final chihaKai = n({kDmgChihaKai});
  if (rikusen > 0) m *= t.rikusen;
  // 陸戦隊系2つ以上、チハとチハ改、陸戦隊系とチハ (チハ改) で追加の補正
  if (rikusen >= 2 || (chiha > 0 && chihaKai > 0) || (rikusen > 0 && chiha + chihaKai > 0)) m *= t.rikusenPair;
  final panzer2 = n({kDmgPanzer2});
  if (panzer2 > 0) m *= t.panzer2;
  if (panzer2 >= 2) m *= t.panzer2Pair;
  if (n(kDmgM4Group) > 0) m *= t.m4;
  // 上陸支援舟艇の補正 (2つ目の分は特四式内火艇2つでも付く。重複はしない)
  if (support) {
    final boats = n({kDmgArmedDaihatsu, kDmgAbBoat});
    if (boats > 0) m *= t.support;
    if (boats >= 2 || toku4.length >= 2) m *= t.supportPair;
  }
  if (n({kDmgToku4Kai}) > 0) m *= t.toku4Kai;
  // 改修補正 (上陸用舟艇と特四式内火艇の★平均はそれぞれ別に計算する)
  final improvement = 1 + _average(landing) / 50 + _average(toku4) / 50;
  var power = 1.0;
  for (var i = 0; i < improvementPower; i++) {
    power *= improvement;
  }
  return m * power;
}

double _kamiMultiplier(DamageShip a, _GroundTable t) {
  final kami = a.equips.where((e) => e.itemId == kDmgKami);
  if (kami.isEmpty) return 1;
  return _pick(t.kami, kami.length) * (1 + _average(kami) / 30);
}

/// 一般対地乗算補正
double damageGroundGeneralMultiplier(DamageShip a, int installType, {required bool day, bool nightAir = false}) {
  final t = _tableOf(installType);
  int n(Set<int> ids) => a.countOf((e) => ids.contains(e.itemId));
  var m = a.countOf((e) => e.category == kDmgAaShell) > 0 ? t.aaShell : 1.0;
  m *= _pick(t.wg, n({kDmgWg42}));
  m *= _pick(t.rocket, n(kDmgGroundRockets));
  m *= _pick(t.mortar, n(kDmgMortars));
  m *= _landingMultiplier(a, t, support: day);
  m *= _kamiMultiplier(a, t);
  if (a.countOf((e) => e.category == kDmgApShell) > 0) m *= t.apShell;
  // 水戦・水爆、艦爆・噴式機は搭載数0でも補正が付く (艦爆は対地艦爆でないものも数える)
  if (a.countOf((e) => e.category == kDmgSeaplaneBomber || e.category == kDmgSeaplaneFighter) > 0) m *= t.seaplane;
  if (!nightAir) m *= _pick(t.bomber, a.countOf((e) => e.category == kDmgDiveBomber || e.category == kDmgJetFighterBomber));
  return m;
}

/// 集積地補正 (キャップ後。上陸支援舟艇の補正は昼夜どちらも付く)
double damageSupplyDepotMultiplier(DamageShip a) {
  const t = _supplyDepot;
  int n(Set<int> ids) => a.countOf((e) => ids.contains(e.itemId));
  // 陸戦隊・一式砲戦車・III号戦車があると改修補正が2乗、陸戦隊とII号戦車があると3乗
  final power = n({kDmgRikusenOnly}) > 0 && n({kDmgPanzer2}) > 0 ? 3 : (n(kDmgRikusen) > 0 ? 2 : 1);
  return _pick(t.wg, n({kDmgWg42})) *
      _pick(t.rocket, n(kDmgGroundRockets)) *
      _pick(t.mortar, n(kDmgMortars)) *
      _landingMultiplier(a, t, support: true, improvementPower: power) *
      _kamiMultiplier(a, t);
}

/// [a] が [t] を攻撃するときの対地補正。[day] は昼の砲撃 (上陸支援舟艇の個別補正は昼だけ)。
/// 夜間航空攻撃 ([nightAir]) は対地補正が付かない例があるので補正なしとする (集積地補正も分からないので付けない)。
/// 装備のない艦の夜戦は 火力 + 雷装 + 触接 だけなので補正なし
DamageGroundBonus damageGroundBonus(DamageShip a, DamageShip t, {required bool day, bool nightAir = false}) {
  if (a.enemy || nightAir || (!t.installation && !t.supplyDepot)) return DamageGroundBonus.none;
  if (!day && a.equips.isEmpty) return DamageGroundBonus.none;
  final depot = t.supplyDepot ? damageSupplyDepotMultiplier(a) : 1.0;
  // 浸水型 (集積地棲姫III バカンスmode) はキャップ後の集積地補正だけ
  if (!t.installation) return DamageGroundBonus(depot: depot);

  int n(Set<int> ids) => a.countOf((e) => ids.contains(e.itemId));
  // 艦種補正: 砲台小鬼には駆逐・軽巡 ×1.4、潜水艦はどの陸上型にも +30
  var multiplier = t.installType == 2 && (a.shipType == kDmgDD || a.shipType == kDmgCL) ? 1.4 : 1.0;
  var add = a.submarine ? 30.0 : 0.0;
  void step(double m, double plus) {
    multiplier *= m;
    add = add * m + plus;
  }

  step(damageGroundGeneralMultiplier(a, t.installType, day: day), 0);
  if (n(kDmgRegiment11) > 0) step(1.8, 25);
  if (n({kDmgM4}) > 0) step(1.4, 35);
  if (n({kDmgType1Gun}) > 0) step(1.3, 42);
  if (n({kDmgChiha}) > 0) step(1.4, 28);
  if (n({kDmgChihaKai}) > 0) step(1.5, 33);
  if (n(kDmgToku4) > 0) step(1.2, 42);
  if (n({kDmgToku4Kai}) > 0) step(1.1, 28);
  // 上陸支援舟艇シナジー (武装大発だけ・装甲艇だけ2つ以上では付かない)
  final armed = n({kDmgArmedDaihatsu});
  final ab = n({kDmgAbBoat});
  final groupA = n(kDmgSupportSynergyA);
  final groupB = n(kDmgSupportSynergyB);
  if (armed + ab == 1 && groupA + groupB >= 1) {
    step(1.2, 10);
  } else if (armed >= 1 && ab >= 1) {
    if (groupA + groupB >= 2) {
      step(1.5, 25);
    } else if (groupA == 1) {
      step(1.3, 15);
    } else if (groupB == 1) {
      step(1.4, 20);
    }
  }
  // WG42・噴進砲・迫撃砲の加算
  for (final MapEntry(key: id, value: adds) in kDmgGroundAdds.entries) {
    final count = n({id});
    if (count > 0) add += adds[count.clamp(1, 4) - 1];
  }
  return DamageGroundBonus(multiplier: multiplier, add: add, depot: depot);
}

/// 空母が砲撃戦で陸上型を攻撃できるか (対地艦爆があればできる。対地艦爆でない艦爆・噴式機があればできない。艦攻だけならできる)
bool damageCarrierCanHitInstallation(DamageShip a) {
  if (a.equips.any((e) => e.count > 0 && kDmgGroundBombers.contains(e.itemId))) return true;
  return !a.equips.any((e) => e.count > 0 && (e.category == kDmgDiveBomber || e.category == kDmgJetFighterBomber));
}

/// 空母の対地攻撃で数える爆装 (対地艦爆・艦攻・艦偵)
int damageCarrierGroundBombing(DamageShip a) => a.equips
    .where((e) => kDmgGroundBombers.contains(e.itemId) || e.category == kDmgTorpedoBomber || e.category == kDmgCarrierRecon)
    .fold(0, (s, e) => s + e.bombing);
