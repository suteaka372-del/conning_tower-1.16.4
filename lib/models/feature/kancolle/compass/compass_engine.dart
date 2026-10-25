// 羅針盤シミュレーター: 艦隊の編成から、各マスでどちらへ進むかを判定する。
//
// 分岐条件は「艦これ攻略 Wiki*」(https://wikiwiki.jp/kancolle/) の各海域ページの
// 「ルート分岐法則」を元に、条件の内容 (事実) を読んでこのアプリ用に書き直したもの (文章の転載はしない)。
// マスの番号とつながり (api_no → マスの記号) は KC3Kai/kancolle-replay の kcEDGES.js
// (MIT License, Copyright (c) 2016 fourinone41) を元にしている。

/// 判定に使う艦の情報
class CompassShip {
  /// 艦種 (api_stype)
  final int shipType;

  /// 速力 (api_soku。5 = 低速, 10 = 高速, 15 = 高速+, 20 = 最速)
  final int speed;

  /// ドラム缶 (輸送用) の数
  final int drums;

  /// 電探の数
  final int radars;
  final int shipId;

  const CompassShip({required this.shipType, this.speed = 10, this.drums = 0, this.radars = 0, this.shipId = 0});
}

// 艦種 (api_stype)
const kDE = 1, kDD = 2, kCL = 3, kCLT = 4, kCA = 5, kCAV = 6, kCVL = 7, kFBB = 8, kBB = 9, kBBV = 10, kCV = 11;
const kSS = 13, kSSV = 14, kAV = 16, kLHA = 17, kCVB = 18, kAR = 19, kAS = 20, kCT = 21, kAO = 22;

/// 判定に使う艦隊
class CompassFleet {
  final List<CompassShip> ships;

  /// 索敵スコア (判定式33)。引数は分岐点係数
  final double Function(double coefficient) losScore;

  CompassFleet(this.ships, {double Function(double coefficient)? losScore}) : losScore = losScore ?? ((_) => 0);

  int get n => ships.length;

  int count(Set<int> types) => ships.where((s) => types.contains(s.shipType)).length;

  int _t(int type) => ships.where((s) => s.shipType == type).length;

  int get de => _t(kDE);
  int get dd => _t(kDD);
  int get cl => _t(kCL);
  int get clt => _t(kCLT);
  int get ct => _t(kCT);
  int get ca => _t(kCA);
  int get cav => _t(kCAV);
  int get cvl => _t(kCVL);
  int get cv => _t(kCV);
  int get cvb => _t(kCVB);
  int get fbb => _t(kFBB);

  /// (低速)戦艦: 艦種が「戦艦」(高速戦艦ではない)。速力は関係ない
  int get bb => _t(kBB);
  int get bbv => _t(kBBV);
  int get av => _t(kAV);
  int get as => _t(kAS);
  int get ao => _t(kAO);
  int get ar => _t(kAR);
  int get lha => _t(kLHA);

  /// 潜水艦 (潜水空母を含む)
  int get subs => count({kSS, kSSV});

  /// 戦艦級 (高速戦艦 + 戦艦。航空戦艦は含まない)
  int get bbClass => fbb + bb;

  /// 空母系 (正規空母 + 装甲空母 + 軽空母)
  int get carriers => cv + cvb + cvl;

  /// 正規空母 (装甲空母を含む)
  int get standardCarriers => cv + cvb;

  /// 重巡級 (重巡 + 航巡)
  int get caClass => ca + cav;

  /// 駆逐 + 海防
  int get ddde => dd + de;

  /// 全艦が高速以上
  bool get allFast => ships.isNotEmpty && ships.every((s) => s.speed >= 10);

  /// 低速の艦を含む
  bool get anySlow => ships.any((s) => s.speed > 0 && s.speed < 10);

  /// ドラム缶を積んだ艦の数
  int get drumShips => ships.where((s) => s.drums > 0).length;

  /// 電探を積んだ艦の数
  int get radarShips => ships.where((s) => s.radars > 0).length;

  /// 全艦が [types] の艦種
  bool only(Set<int> types) => ships.isNotEmpty && ships.every((s) => types.contains(s.shipType));
}

/// 次に進むマスの候補
class RouteOption {
  final String node;
  final double probability;

  /// 確率がはっきりしていない (Wiki で割合が不明・推測) ので、このアプリで仮に決めた値
  final bool estimated;

  const RouteOption(this.node, this.probability, {this.estimated = false});
}

/// ある分岐点での判定結果
class BranchOutcome {
  final List<RouteOption> options;

  /// どの条件に当てはまったか
  final String reason;

  const BranchOutcome(this.options, this.reason);

  bool get fixed => options.length == 1;

  /// 割合や条件に推定を含む
  bool get estimated => options.any((o) => o.estimated && o.probability > 0);

  double probabilityOf(String node) =>
      options.where((o) => o.node == node).fold(0.0, (sum, o) => sum + o.probability);
}

/// 必ず [node] へ
BranchOutcome go(String node, String reason) => BranchOutcome([RouteOption(node, 1)], reason);

/// 割合を決めたランダム ([shares] の合計で割る)
BranchOutcome split(Map<String, double> shares, String reason, {bool estimated = false}) {
  final total = shares.values.fold(0.0, (a, b) => a + b);
  return BranchOutcome(
    [for (final MapEntry(key: node, value: share) in shares.entries) RouteOption(node, share / total, estimated: estimated)],
    reason,
  );
}

/// 片寄りのないランダム
BranchOutcome even(List<String> nodes, String reason, {bool estimated = false}) =>
    split({for (final n in nodes) n: 1}, reason, estimated: estimated);

/// 割合が分からないときに「寄り」をこの割合とする
const kUnknownLean = 0.75;

/// [node] 寄りのランダム ([percent] が無ければ割合不明として [kUnknownLean])
BranchOutcome lean(String node, String other, String reason, [double? percent]) {
  final p = percent == null ? kUnknownLean : percent / 100;
  return BranchOutcome([
    RouteOption(node, p, estimated: percent == null),
    RouteOption(other, 1 - p, estimated: percent == null),
  ], reason);
}

typedef CompassRule = BranchOutcome Function(CompassFleet f);

/// 1つの海域
class CompassMap {
  final int area;
  final int no;
  final String title;

  /// ボス (または到達目標) のマス
  final String boss;

  /// api_no (マスの番号) → (どこから, どのマスへ)
  final Map<int, (String, String)> edges;

  /// 索敵スコアの分岐点係数 (索敵で分岐する海域のみ)
  final double? coefficient;

  /// 分岐点 → 判定 (行き先が1つのマスは書かない)
  final Map<String, CompassRule> rules;

  /// Wiki の「ルート分岐法則」の更新日など
  final String? note;

  const CompassMap({
    required this.area,
    required this.no,
    required this.title,
    required this.boss,
    required this.edges,
    required this.rules,
    this.coefficient,
    this.note,
  });

  String get name => '$area-$no';

  int get mapId => area * 10 + no;

  /// [node] から進めるマス
  List<String> nextOf(String node) => [
        for (final (from, to) in edges.values)
          if (from == node) to,
      ];

  /// マスの番号 (api_no) → 記号
  String? letterOf(int cell) => edges[cell]?.$2;

  /// [node] での判定
  BranchOutcome? decide(String node, CompassFleet fleet) {
    final next = nextOf(node);
    if (next.isEmpty) return null;
    final rule = rules[node];
    if (rule != null) return rule(fleet);
    if (next.length == 1) return go(next.first, '固定');
    return even(next, '条件不明', estimated: true);
  }
}

/// 分岐点1つぶんの結果
class CompassStep {
  final String node;

  /// このマスに来る確率
  final double reach;
  final BranchOutcome outcome;

  const CompassStep(this.node, this.reach, this.outcome);
}

class CompassResult {
  final CompassMap map;

  /// マス → 来る確率
  final Map<String, double> reach;

  /// 通る分岐点 (Start から近い順)
  final List<CompassStep> steps;

  const CompassResult(this.map, this.reach, this.steps);

  double get bossProbability => reach[map.boss] ?? 0;

  /// 通る分岐点に、割合を仮に決めたものがある
  bool get estimated => steps.any((s) => s.reach > 0 && s.outcome.estimated);
}

/// [fleet] で [map] に出撃したときに、各マスに来る確率
CompassResult simulateCompass(CompassMap map, CompassFleet fleet) {
  final reach = <String, double>{'Start': 1};
  final outcomes = <String, BranchOutcome>{};
  final order = <String>[];

  // 出撃地点からの深さの順に確率を流す (海域は一方通行なので、深さの順で足りる)
  final depth = <String, int>{'Start': 0};
  final queue = ['Start'];
  while (queue.isNotEmpty) {
    final node = queue.removeAt(0);
    for (final next in map.nextOf(node)) {
      final d = depth[node]! + 1;
      if ((depth[next] ?? -1) < d && d < 40) {
        depth[next] = d;
        queue.add(next);
      }
    }
  }
  final nodes = depth.keys.toList()..sort((a, b) => depth[a]!.compareTo(depth[b]!));
  for (final node in nodes) {
    final p = reach[node] ?? 0;
    if (p <= 0) continue;
    final outcome = map.decide(node, fleet);
    if (outcome == null) continue;
    outcomes[node] = outcome;
    order.add(node);
    for (final option in outcome.options) {
      if (option.probability <= 0) continue;
      reach[option.node] = (reach[option.node] ?? 0) + p * option.probability;
    }
  }
  return CompassResult(map, reach, [for (final node in order) CompassStep(node, reach[node]!, outcomes[node]!)]);
}
