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

  /// 大発動艇系 (分岐条件で数えるもの) の数
  final int daihatsu;
  final int shipId;

  /// 艦名 (祥鳳改 など。特定の艦で分岐する海域で使う)
  final String name;

  const CompassShip({
    required this.shipType,
    this.speed = 10,
    this.drums = 0,
    this.radars = 0,
    this.daihatsu = 0,
    this.shipId = 0,
    this.name = '',
  });
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

  /// 戦艦 (高速戦艦 + (低速)戦艦。航空戦艦は含まない)
  int get battleships => fbb + bb;

  /// 戦艦級 (高速戦艦 + (低速)戦艦 + 航空戦艦。公式の戦艦級タブと同じ)
  int get bbClass => fbb + bb + bbv;

  /// 空母系 (正規空母 + 装甲空母 + 軽空母)
  int get carriers => cv + cvb + cvl;

  /// 正規空母 (装甲空母を含む)
  int get standardCarriers => cv + cvb;

  /// 重巡級 (重巡 + 航巡)
  int get caClass => ca + cav;

  /// 駆逐 + 海防
  int get ddde => dd + de;

  /// 軽巡級 (軽巡 + 練巡 + 雷巡。公式の軽巡級タブと同じ)
  int get clClass => cl + ct + clt;

  /// 全艦が高速以上
  bool get allFast => ships.isNotEmpty && ships.every((s) => s.speed >= 10);

  /// 全艦が高速+以上
  bool get allFastPlus => ships.isNotEmpty && ships.every((s) => s.speed >= 15);

  /// 全艦が最速
  bool get allFastest => ships.isNotEmpty && ships.every((s) => s.speed >= 20);

  /// 低速の艦を含む
  bool get anySlow => ships.any((s) => s.speed > 0 && s.speed < 10);

  /// ドラム缶を積んだ艦の数
  int get drumShips => ships.where((s) => s.drums > 0).length;

  /// 電探を積んだ艦の数
  int get radarShips => ships.where((s) => s.radars > 0).length;

  /// 大発動艇系を積んだ艦の数
  int get daihatsuShips => ships.where((s) => s.daihatsu > 0).length;

  /// 旗艦の艦種
  int get flagshipType => ships.isEmpty ? 0 : ships.first.shipType;

  /// [name] (改造前の名前。改・改二なども含む) の艦の数
  int named(String name) => ships.where((s) => s.name.startsWith(name)).length;

  /// [name] (改造前の名前。改・改二なども含む) の艦を含む
  bool has(String name) => named(name) > 0;

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

  /// 能動分岐 (行き先を自分で選べる)
  final bool choice;

  const BranchOutcome(this.options, this.reason, {this.choice = false});

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

/// 能動分岐 (行き先を自分で選べる)。シミュレーターではボスへ着く確率が一番高い行き先を選んだとして計算する
BranchOutcome choose(List<String> nodes, [String reason = '能動分岐 (自分で選べる)']) => BranchOutcome(
      [for (final n in nodes) RouteOption(n, 1 / nodes.length)],
      reason,
      choice: true,
    );

/// 索敵スコアで分岐する。[low] 未満は [below]、[high] 以上は [above]、その間はランダム ([between] が無ければ片寄りなし)
BranchOutcome byLos(
  CompassFleet f,
  double coefficient, {
  required double low,
  required double high,
  required String below,
  required String above,
  BranchOutcome? between,
  bool guessed = false,
}) {
  final los = f.losScore(coefficient);
  final score = '索敵スコア${los.toStringAsFixed(1)}';
  final guess = guessed ? '。境目はWikiでも推測' : '';
  String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  if (los < low) return go(below, '$score (${fmt(low)}未満$guess)');
  if (los >= high) return go(above, '$score (${fmt(high)}以上$guess)');
  final mid = between ?? even([below, above], '割合不明', estimated: true);
  return BranchOutcome(mid.options, '$score (${fmt(low)}以上${fmt(high)}未満はランダム$guess。${mid.reason})');
}

typedef CompassRule = BranchOutcome Function(CompassFleet f);

/// 通ってきたマス ([path]。出撃地点から1つ前のマスまで) でも変わる判定
typedef CompassPathRule = BranchOutcome Function(CompassFleet f, List<String> path);

/// 1つの海域
class CompassMap {
  final int area;
  final int no;
  final String title;

  /// ボス (または到達目標) のマス
  final String boss;

  /// ゲージが複数ある海域で、どのゲージ (段階) の判定か (第1ゲージ など)
  final String? phase;

  /// api_no (マスの番号) → (どこから, どのマスへ)
  final Map<int, (String, String)> edges;

  /// 索敵スコアの分岐点係数 (索敵で分岐する海域のみ)
  final double? coefficient;

  /// 分岐点 → 判定 (行き先が1つのマスは書かない)
  final Map<String, CompassRule> rules;

  /// 通ってきたマスで変わる分岐点の判定 ([rules] より優先)
  final Map<String, CompassPathRule> pathRules;

  /// Wiki の「ルート分岐法則」の更新日など
  final String? note;

  const CompassMap({
    required this.area,
    required this.no,
    required this.title,
    required this.boss,
    required this.edges,
    required this.rules,
    this.pathRules = const {},
    this.phase,
    this.coefficient,
    this.note,
  });

  String get name => '$area-$no';

  int get mapId => area * 10 + no;

  /// [node] から進めるマス (同じマスへの線が2本あっても1つ)
  List<String> nextOf(String node) => {
        for (final (from, to) in edges.values)
          if (from == node) to,
      }.toList();

  /// マスの番号 (api_no) → 記号
  String? letterOf(int cell) => edges[cell]?.$2;

  /// 判定がある分岐点
  Set<String> get ruleNodes => {...rules.keys, ...pathRules.keys};

  /// [node] での判定。[path] は通ってきたマス
  BranchOutcome? decide(String node, CompassFleet fleet, {List<String> path = const []}) {
    final next = nextOf(node);
    if (next.isEmpty) return null;
    final pathRule = pathRules[node];
    if (pathRule != null) return pathRule(fleet, path);
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
///
/// 通ってきたマスで分岐が変わる海域があるので、道のりごとにたどる (同じマスには2回行かない)。
/// 能動分岐はボスへ着く確率が一番高い行き先を選んだとする。
CompassResult simulateCompass(CompassMap map, CompassFleet fleet) {
  final sim = _Simulation(map, fleet);
  sim.walk('Start', const [], 1);
  final nodes = sim.steps.keys.toList()..sort((a, b) => sim.steps[a]!.depth.compareTo(sim.steps[b]!.depth));
  return CompassResult(map, sim.reach, [
    for (final node in nodes) CompassStep(node, sim.reach[node] ?? 0, sim.steps[node]!.outcome()),
  ]);
}

/// 1つの分岐点に、いろいろな道のりから来たときの判定をまとめる
class _StepTotal {
  int depth;
  double weight = 0;
  final options = <String, double>{};
  final estimated = <String>{};
  final reasons = <String, double>{};

  _StepTotal(this.depth);

  void add(BranchOutcome outcome, double p) {
    weight += p;
    for (final o in outcome.options) {
      options[o.node] = (options[o.node] ?? 0) + p * o.probability;
      if (o.estimated && o.probability > 0) estimated.add(o.node);
    }
    reasons[outcome.reason] = (reasons[outcome.reason] ?? 0) + p;
  }

  BranchOutcome outcome() {
    final reason = (reasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key).join(' / ');
    return BranchOutcome([
      for (final MapEntry(key: node, value: p) in options.entries)
        RouteOption(node, weight > 0 ? p / weight : 0, estimated: estimated.contains(node)),
    ], reason);
  }
}

class _Simulation {
  final CompassMap map;
  final CompassFleet fleet;
  final reach = <String, double>{'Start': 1};
  final steps = <String, _StepTotal>{};

  _Simulation(this.map, this.fleet);

  static const _maxDepth = 40;

  /// 能動分岐を「ボスへ行きやすい方を選ぶ」に置き換えた判定
  BranchOutcome? _outcomeAt(String node, List<String> path) {
    final outcome = map.decide(node, fleet, path: path);
    if (outcome == null || !outcome.choice) return outcome;
    String? best;
    var bestP = -1.0;
    for (final o in outcome.options) {
      final p = _bossFrom(o.node, [...path, node]);
      if (p > bestP + 1e-9) {
        best = o.node;
        bestP = p;
      }
    }
    return go(best!, '${outcome.reason}。ボスへ行きやすい$bestマスを選んだとして計算');
  }

  /// [node] からボスに着く確率
  double _bossFrom(String node, List<String> path) {
    if (node == map.boss) return 1;
    if (path.length > _maxDepth) return 0;
    final outcome = _outcomeAt(node, path);
    if (outcome == null) return 0;
    var total = 0.0;
    for (final o in outcome.options) {
      if (o.probability <= 0 || o.node == node || path.contains(o.node)) continue;
      total += o.probability * _bossFrom(o.node, [...path, node]);
    }
    return total;
  }

  void walk(String node, List<String> path, double p) {
    if (path.length > _maxDepth) return;
    final outcome = _outcomeAt(node, path);
    if (outcome == null) return;
    (steps[node] ??= _StepTotal(path.length)).add(outcome, p);
    if (path.length < steps[node]!.depth) steps[node]!.depth = path.length;
    for (final o in outcome.options) {
      final q = p * o.probability;
      if (q < 1e-12 || o.node == node || path.contains(o.node)) continue;
      reach[o.node] = (reach[o.node] ?? 0) + q;
      walk(o.node, [...path, node], q);
    }
  }
}
