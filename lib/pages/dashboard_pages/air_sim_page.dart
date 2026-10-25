import 'package:conning_tower/providers/dashboard_tab_provider.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/air/air_base_store.dart';
import 'package:conning_tower/models/feature/kancolle/air/air_data.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/providers/air_data_provider.dart';
import 'package:conning_tower/utils/memo.dart';
import 'package:conning_tower/widgets/kancolle_quest_detail_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 試行回数
const kAirSimRuns = 5000;

String airPercent(double p) {
  final v = p * 100;
  if (v > 0 && v < 1) return '<1%';
  if (v < 100 && v > 99) return '>99%';
  return '${v.round()}%';
}

String airStateLabel(AirState s) => repairText(s.ja, s.en);

/// 制空状態の確率 (確保 80% / 優勢 20% など。出やすい順)
String airStatesText(Map<AirState, double> states) {
  final entries = states.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return entries.map((e) => '${airStateLabel(e.key).replaceAll('制空権', '').replaceAll('航空', '')} ${airPercent(e.value)}').join(' / ');
}

/// 熟練度の記号
const kAirProficiencyMarks = ['', '|', '||', '|||', '/', '//', '///', '>>'];

String airEquipmentLabel(Equipment e) {
  final level = e.level ?? 0;
  final prof = (e.proficiency ?? 0).clamp(0, 7);
  return [e.name ?? '', if (level > 0) '★$level', if (prof > 0) kAirProficiencyMarks[prof]].join(' ');
}

/// 制空権シミュレーター: 自分の艦隊と、各マスの敵編成 (KCNav の報告) を戦わせて、制空状態と撃墜を数える
class AirView extends ConsumerStatefulWidget {
  const AirView({super.key});

  @override
  ConsumerState<AirView> createState() => _AirViewState();
}

class _AirViewState extends ConsumerState<AirView> {
  static const _mapKey = 'air_map';
  static const _phaseKey = 'air_phase';
  static const _fleetKey = 'air_fleet';
  static const _formationKey = 'air_formation';
  static const _routeKey = 'air_route';
  static const _formations = [1, 2, 3, 6];

  late int _mapId;
  late int _phase;
  late int _fleetIndex;
  late int _formation;

  /// 計算結果の使い回し (ゲームのデータが届くたびに作り直すが、艦隊や敵が同じなら計算し直さない)
  final _byNode = Memo<Map<String, List<EnemyComp>>>();
  final _enemyFleets = Memo<Map<String, List<AirFleet>>>();
  final _battles = MemoCache<List<AirBattleResult>>(8);

  /// ルート (連戦) で計算する
  late bool _route;

  /// 選んでいるマス (null ならボス)
  String? _node;

  /// マス → 選んでいる敵編成 (無ければ制空値が一番高いもの)
  final Map<String, String> _compKeys = {};

  /// 艦の uid → (スロット番号 → 試しに積む装備。null なら外す)
  final Map<int, Map<int, Equipment?>> _overrides = {};

  bool _showSwap = false;

  /// 基地航空隊の番号 → 出撃させるか (無ければゲームで「出撃」になっているか)
  final Map<int, bool> _lbasOn = {};

  /// 基地航空隊の番号 → 攻撃するマス (ルートのとき。無ければ最後の戦闘マス)
  final Map<int, String> _lbasTarget = {};

  @override
  void initState() {
    super.initState();
    int? map, phase, fleet, formation;
    bool? route;
    try {
      map = localStorage.getInt(_mapKey);
      phase = localStorage.getInt(_phaseKey);
      fleet = localStorage.getInt(_fleetKey);
      formation = localStorage.getInt(_formationKey);
      route = localStorage.getBool(_routeKey);
    } catch (_) {}
    _mapId = compassMapOf(map ?? 0)?.mapId ?? kCompassMaps.first.mapId;
    _phase = phase ?? 0;
    _fleetIndex = fleet ?? 0;
    _formation = _formations.contains(formation) ? formation! : 1;
    _route = route ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  CompassMap get _map {
    final phases = compassMapsOf(_mapId);
    return phases[_phase.clamp(0, phases.length - 1)];
  }

  void _load({bool force = false}) {
    AirDataLoader.loadAbyssal(force: force);
    AirDataLoader.loadComps(_map, force: force);
  }

  void _select({int? mapId, int? phase, int? fleetIndex, int? formation, bool? route}) {
    setState(() {
      if (mapId != null && mapId != _mapId) {
        _mapId = mapId;
        _phase = 0;
        _node = null;
        _compKeys.clear();
      }
      if (phase != null && phase != _phase) {
        _phase = phase;
        _node = null;
        _compKeys.clear();
      }
      if (fleetIndex != null && fleetIndex != _fleetIndex) {
        _fleetIndex = fleetIndex;
        _overrides.clear();
      }
      if (formation != null) _formation = formation;
      if (route != null) _route = route;
    });
    try {
      localStorage.setInt(_mapKey, _mapId);
      localStorage.setInt(_phaseKey, _phase);
      localStorage.setInt(_fleetKey, _fleetIndex);
      localStorage.setInt(_formationKey, _formation);
      localStorage.setBool(_routeKey, _route);
    } catch (_) {}
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AirDataLoader.revision, airBaseStore.revision]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final data = watchKancolleData(ref, context);
    final map = _map;
    final phases = compassMapsOf(_mapId);
    final phase = _phase.clamp(0, phases.length - 1);
    final areas = {for (final m in kCompassMaps) m.area}.toList()..sort();
    final mapsInArea = [
      for (final m in kCompassMaps)
        if (m.area == map.area && m.phase == compassMapOf(m.mapId)!.phase) m,
    ];
    final squads = data.squads;
    final fleetIndex = squads.isEmpty ? 0 : _fleetIndex.clamp(0, squads.length - 1);
    final secondary = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));
    final slotItems = data.dataInfo.slotItemInfo;
    final shipInfo = data.dataInfo.shipInfo;
    final comps = AirDataLoader.comps[AirDataLoader.keyOf(map)];
    final abyssal = AirDataLoader.abyssal;

    Widget segmented<T extends Object>(T value, Map<T, Widget> children, ValueChanged<T> onChanged) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: CupertinoSlidingSegmentedControl<T>(
            groupValue: value,
            children: children,
            onValueChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        );

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Text(repairText('制空権シミュレーター', 'Air power simulator'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      segmented<int>(
        map.area,
        {for (final a in areas) a: Text('$a-x')},
        (area) => _select(mapId: kCompassMaps.firstWhere((m) => m.area == area).mapId),
      ),
      segmented<int>(map.mapId, {for (final m in mapsInArea) m.mapId: Text(m.name)}, (mapId) => _select(mapId: mapId)),
      if (phases.length > 1)
        segmented<int>(
          phase,
          {for (final (i, m) in phases.indexed) i: Text(m.phase ?? '${i + 1}', style: const TextStyle(fontSize: 12))},
          (index) => _select(phase: index),
        ),
      if (squads.length > 1)
        segmented<int>(
          fleetIndex,
          {for (var i = 0; i < squads.length; i++) i: Text(repairText('第${i + 1}艦隊', 'Fleet ${i + 1}'))},
          (index) => _select(fleetIndex: index),
        ),
      segmented<int>(
        _formation,
        {for (final f in _formations) f: Text(airFormationName(f), style: const TextStyle(fontSize: 12))},
        (f) => _select(formation: f),
      ),
      segmented<bool>(
        _route,
        {
          false: Text(repairText('1マス', 'One node')),
          true: Text(repairText('ルート (連戦)', 'Route')),
        },
        (v) => _select(route: v),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            Expanded(child: Text(_statusText(map), style: secondary)),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minSize: 28,
              onPressed: AirDataLoader.loadingComps(map) ? null : () => _load(force: true),
              child: Text(repairText('取り直す', 'Reload'), style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    ];

    if (squads.isEmpty || slotItems == null || slotItems.isEmpty) {
      children.add(_message(repairText('ゲームを起動すると、今の艦隊で計算します', 'Start the game to use your fleet'), secondary));
    } else if (comps == null || abyssal == null) {
      children.add(_message(
          AirDataLoader.loadingComps(map) || AirDataLoader.loadingAbyssal
              ? repairText('データを取得しています…', 'Loading data…')
              : repairText('データを取得できませんでした。「取り直す」を押してください', 'Could not load the data. Tap Reload.'),
          secondary));
    } else {
      final byNode = _byNode.of([comps], () => enemyCompsByNode(comps));
      final squad = squads[fleetIndex];
      final own = ownAirFleet(squad, shipInfo: shipInfo, formation: _formation, overrides: _overrides);
      final enemyFleetCache = _enemyFleets.of([byNode, abyssal, slotItems, shipInfo], () => <String, List<AirFleet>>{});
      List<AirFleet> fleetsOf(String node) => enemyFleetCache[node] ??= [
            for (final c in byNode[node]!) enemyAirFleet(c, abyssal: abyssal, slotItems: slotItems, shipInfo: shipInfo),
          ];
      int selectedOf(String node, List<AirFleet> fleets) {
        final index = byNode[node]!.indexWhere((c) => c.key == _compKeys[node]);
        return index >= 0 ? index : strongestEnemyComp(fleets);
      }

      // 計算するマス (1マスなら選んだマス、ルートなら羅針盤で一番通りやすい道のりの戦闘マス)
      final List<String> battleNodes;
      List<String> route = const [];
      if (_route) {
        final compass = simulateCompassCached(map, compassFleetOf(squad, admiralLevel: data.seaForceBase.admiral.level));
        route = compass.likelyRoute;
        battleNodes = [for (final n in route) if (byNode.containsKey(n)) n];
      } else {
        final nodes = byNode.keys.toList()..sort(_nodeOrder);
        battleNodes = nodes.isEmpty ? const [] : [byNode.containsKey(_node) ? _node! : (byNode.containsKey(map.boss) ? map.boss : nodes.first)];
      }

      if (byNode.isEmpty || battleNodes.isEmpty) {
        children.add(_message(
            _route
                ? repairText('羅針盤のルート上に敵編成の報告があるマスがありません', 'No reported battles on the likely route')
                : repairText('この海域の敵編成の報告がありません', 'No enemy compositions reported for this map'),
            secondary));
      } else {
        final enemyFleets = <String, List<AirFleet>>{for (final n in battleNodes) n: fleetsOf(n)};
        final chosen = [for (final n in battleNodes) enemyFleets[n]![selectedOf(n, enemyFleets[n]!)]];
        // 基地航空隊 (この海域の基地。それぞれ選んだマスへ2波)
        final areaBases = airBaseStore.basesIn(map.area);
        final airBases = {for (final b in areaBases) b.rid: airBaseOf(b, data.fleet.equipment)};
        bool baseOn(AirBaseData b) => _lbasOn[b.rid] ?? b.actionKind == 1;
        String targetOf(AirBaseData b) =>
            !_route ? battleNodes.single : (battleNodes.contains(_lbasTarget[b.rid]) ? _lbasTarget[b.rid]! : battleNodes.last);
        final basesByBattle = <int, List<AirBase>>{};
        for (final b in areaBases) {
          if (!baseOn(b) || airBases[b.rid]!.squadrons.isEmpty) continue;
          (basesByBattle[battleNodes.indexOf(targetOf(b))] ??= []).add(airBases[b.rid]!);
        }
        final battleKey = [
          own.key,
          for (final f in chosen) f.key,
          for (final e in basesByBattle.entries) '${e.key}:${e.value.map((b) => b.key).join('/')}',
        ].join('#');
        final results = _battles.get(
            battleKey, () => simulateAirBattles(own, chosen, runs: kAirSimRuns, seed: 1, bases: basesByBattle));
        final shown = _route && battleNodes.contains(_node) ? _node! : (_route ? battleNodes.last : battleNodes.single);
        final index = battleNodes.indexOf(shown);
        final fleets = enemyFleets[shown]!;
        if (_route) {
          children.add(_routeSection(route, battleNodes, results, shown, map, secondary));
        } else {
          final nodes = byNode.keys.toList()..sort(_nodeOrder);
          children.add(_nodePicker(nodes, shown, map));
        }
        children.add(_patternSection(shown, byNode[shown]!, fleets, selectedOf(shown, fleets), strongestEnemyComp(fleets), secondary));
        if (areaBases.isNotEmpty) {
          children.add(_lbasSection(areaBases, airBases, battleNodes, baseOn, targetOf, secondary));
        }
        children
          ..addAll(_resultSections(own, chosen[index], results[index], secondary,
              title: _route ? repairText('$shownマス (${index + 1}戦目)', 'Node $shown (battle ${index + 1})') : null))
          ..add(_swapSection(squad.ships, shipInfo?.map((k, v) => MapEntry(k, v.apiMaxeq)), data.fleet.equipment.values, secondary));
      }
    }

    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Text(
        repairText(
            '敵編成は KCNav (tsunkit.net) に報告されたもの (直近半年)。深海棲艦の搭載数は KC3Kai/kancolle-replay (MIT) のデータ。'
                '計算式は「艦これ攻略 Wiki*」の「航空戦」「対空砲火」を元にしています。$kAirSimRuns回戦わせた平均です。',
            'Enemy compositions are reports on KCNav (tsunkit.net, last 6 months). Abyssal plane counts come from '
                'KC3Kai/kancolle-replay (MIT). Formulas follow the KanColle wiki. Averages of $kAirSimRuns battles.'),
        style: secondary,
      ),
    ));

    return CupertinoScrollbar(child: ListView(padding: const EdgeInsets.only(bottom: 24), children: children));
  }

  Widget _message(String text, TextStyle style) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Text(text, style: style));

  String _statusText(CompassMap map) {
    final key = AirDataLoader.keyOf(map);
    final at = AirDataLoader.compsAt[key];
    final error = AirDataLoader.compsError[key] ?? AirDataLoader.abyssalError;
    if (AirDataLoader.loadingComps(map)) return repairText('KCNav から敵編成を取得中', 'Loading from KCNav');
    if (at != null) {
      final n = AirDataLoader.comps[key]?.length ?? 0;
      final t = at.toLocal();
      return repairText('敵編成 $n件 (${t.month}/${t.day} 取得)${error == null ? '' : '・更新失敗'}',
          '$n compositions (${t.month}/${t.day})${error == null ? '' : ', update failed'}');
    }
    return error == null ? '' : repairText('取得できませんでした ($error)', 'Could not load ($error)');
  }

  /// マスの並び (アルファベット順、1文字のマスを先に)
  static int _nodeOrder(String a, String b) {
    final byLength = a.length.compareTo(b.length);
    return byLength != 0 ? byLength : a.compareTo(b);
  }

  Widget _chip(String label, bool selected, VoidCallback onPressed) => CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minSize: 30,
        color: selected ? CupertinoColors.activeBlue : CupertinoColors.tertiarySystemFill,
        borderRadius: BorderRadius.circular(15),
        onPressed: onPressed,
        child: Text(label,
            style: TextStyle(fontSize: 13, color: selected ? CupertinoColors.white : CupertinoColors.label.resolveFrom(context))),
      );

  Widget _nodePicker(List<String> nodes, String selected, CompassMap map) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final n in nodes)
            _chip(n == map.boss ? repairText('$n (ボス)', '$n (boss)') : n, n == selected, () => setState(() => _node = n)),
        ],
      ),
    );
  }

  /// ルート: 戦闘マスごとの要約 (タップでそのマスの詳細)
  Widget _routeSection(List<String> route, List<String> nodes, List<AirBattleResult> results, String selected, CompassMap map,
      TextStyle secondary) {
    return QuestDetailSection(
      title: repairText('ルート ${route.join('→')}', 'Route ${route.join('→')}'),
      footer: repairText('羅針盤シミュレーターで一番通りやすい道のりのうち、敵編成の報告があるマス。艦載機は前の戦闘で減った分を持ち越します。タップで詳細',
          'Battles on the most likely route. Plane losses carry over. Tap for details'),
      children: [
        for (final (i, n) in nodes.indexed)
          () {
            final r = results[i];
            final before = r.own.expand((s) => s).fold(0.0, (sum, s) => sum + s.before);
            final after = r.own.expand((s) => s).fold(0.0, (sum, s) => sum + s.after);
            return CupertinoListTile(
              leading: Icon(n == selected ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle,
                  size: 20, color: n == selected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey),
              title: Text(
                repairText('${i + 1}戦目 $nマス${n == map.boss ? ' (ボス)' : ''}・制空値 ${r.ownPower.round()} / ${r.enemyPower}',
                    'Battle ${i + 1} $n${n == map.boss ? ' (boss)' : ''}, AP ${r.ownPower.round()} / ${r.enemyPower}'),
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                [
                  airStatesText(r.states),
                  repairText('艦載機 ${_count(before)} → ${_count(after)}機', 'Planes ${_count(before)} → ${_count(after)}'),
                  if (r.enemyStrikeZero != null)
                    repairText('敵の航空攻撃なし ${airPercent(r.enemyStrikeZero!)}', 'No enemy airstrike ${airPercent(r.enemyStrikeZero!)}'),
                ].join('\n'),
                maxLines: 3,
              ),
              onTap: () => setState(() => _node = n),
            );
          }(),
      ],
    );
  }

  Widget _patternSection(String node, List<EnemyComp> comps, List<AirFleet> fleets, int selected, int strongest, TextStyle secondary) {
    final total = comps.fold(0, (sum, c) => sum + c.count);
    final shown = [for (var i = 0; i < comps.length && i < 8; i++) i];
    if (!shown.contains(selected)) shown.add(selected);
    if (!shown.contains(strongest)) shown.add(strongest);
    return QuestDetailSection(
      title: repairText('$nodeマスの敵編成 (${comps.length}パターン)', 'Node $node (${comps.length} patterns)'),
      footer: repairText('最初は制空値が一番高い編成。タップで切り替え。右の%は報告の割合', 'The strongest air power is selected first. Tap to switch'),
      children: [
        for (final i in shown)
          CupertinoListTile(
            leading: Icon(i == selected ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle,
                size: 20, color: i == selected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey),
            title: Text(
              repairText('制空値 ${airFleetPower(fleets[i])}・${airFormationName(comps[i].formation)}${i == strongest ? '・最強' : ''}',
                  'AP ${airFleetPower(fleets[i])}, ${airFormationName(comps[i].formation)}${i == strongest ? ', strongest' : ''}'),
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(fleets[i].ships.map((s) => s.name).join('・'), maxLines: 2),
            additionalInfo: Text(total == 0 ? '' : airPercent(comps[i].count / total), style: secondary),
            onTap: () => setState(() => _compKeys[node] = comps[i].key),
          ),
      ],
    );
  }

/// 基地航空隊: この海域の基地を出撃させるかと、攻撃するマス
  Widget _lbasSection(List<AirBaseData> bases, Map<int, AirBase> airBases, List<String> battleNodes, bool Function(AirBaseData) baseOn,
      String Function(AirBaseData) targetOf, TextStyle secondary) {
    String actionName(int kind) => switch (kind) {
          1 => repairText('出撃', 'sortie'),
          2 => repairText('防空', 'air defense'),
          3 => repairText('退避', 'retreat'),
          4 => repairText('休息', 'rest'),
          _ => repairText('待機', 'standby'),
        };
    return QuestDetailSection(
      title: repairText('基地航空隊', 'Land-based air squadrons'),
      footer: repairText(
          '各基地は選んだマスへ2波攻撃し、艦隊の航空戦の前に敵機を減らします。補給したあと (満載) の機数で計算します。行動半径は確かめていません',
          'Each base attacks its node twice before the fleet air battle. Full plane counts. Range is not checked.'),
      children: [
        for (final b in bases)
          () {
            final base = airBases[b.rid]!;
            final on = baseOn(b);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CupertinoListTile(
                  title: Text('${base.name} (${actionName(b.actionKind)}・半径${b.distance})', style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    base.squadrons.isEmpty
                        ? repairText('配備なし', 'no squadrons')
                        : base.squadrons.map((s) => '${s.plane.name} ${s.count}').join('\n'),
                    maxLines: 4,
                  ),
                  trailing: CupertinoSwitch(
                    value: on && base.squadrons.isNotEmpty,
                    onChanged: base.squadrons.isEmpty ? null : (v) => setState(() => _lbasOn[b.rid] = v),
                  ),
                ),
                if (on && _route && battleNodes.length > 1 && base.squadrons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final n in battleNodes) _chip(n, n == targetOf(b), () => setState(() => _lbasTarget[b.rid] = n)),
                      ],
                    ),
                  ),
              ],
            );
          }(),
      ],
    );
  }

  List<Widget> _resultSections(AirFleet own, AirFleet enemy, AirBattleResult result, TextStyle secondary, {String? title}) {
    final needed = airPowerNeeded(result.enemyPowerAtFleet.round());
    final ownHasAaci = own.ships.any((s) => s.aaci.isNotEmpty);
    return [
      QuestDetailSection(
        title: title == null ? repairText('制空権', 'Air superiority') : repairText('制空権 ($title)', 'Air superiority ($title)'),
        children: [
          CupertinoListTile(
            title: Text(repairText('制空値', 'Air power')),
            additionalInfo: Text(repairText('自艦隊 ${result.ownPower.round()} / 敵 ${result.enemyPower}',
                'You ${result.ownPower.round()} / enemy ${result.enemyPower}')),
          ),
          if (result.waves.isNotEmpty)
            CupertinoListTile(
              title: Text(repairText('基地航空隊のあとの敵の制空値', 'Enemy AP after land-based attacks')),
              additionalInfo: Text(repairText('平均 ${result.enemyPowerAtFleet.toStringAsFixed(1)}', 'avg ${result.enemyPowerAtFleet.toStringAsFixed(1)}')),
            ),
          CupertinoListTile(
            title: Text(repairText('必要な制空値', 'Needed')),
            subtitle: Text(repairText(
                '確保 ${needed[AirState.supremacy]}・優勢 ${needed[AirState.superiority]}・均衡 ${needed[AirState.parity]}・劣勢 ${needed[AirState.denial]}',
                'AS+ ${needed[AirState.supremacy]}, AS ${needed[AirState.superiority]}, AP ${needed[AirState.parity]}, AD ${needed[AirState.denial]}')),
          ),
          CupertinoListTile(
            title: Text(repairText('制空状態', 'Air state')),
            subtitle: Text(airStatesText(result.states), maxLines: 2),
          ),
          if (ownHasAaci)
            CupertinoListTile(
              title: Text(repairText('対空カットイン', 'AACI')),
              additionalInfo: Text(airPercent(result.aaciRate)),
            ),
        ],
      ),
      if (result.waves.isNotEmpty)
        QuestDetailSection(
          title: repairText('基地航空隊の攻撃', 'Land-based attacks'),
          children: [
            for (final w in result.waves)
              CupertinoListTile(
                title: Text(
                  repairText('${w.baseName} ${w.wave}波・制空値 ${w.basePower.round()} / 敵 ${w.enemyPower.toStringAsFixed(1)}',
                      '${w.baseName} wave ${w.wave}, AP ${w.basePower.round()} / ${w.enemyPower.toStringAsFixed(1)}'),
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  [
                    airStatesText(w.states),
                    for (final s in w.squadrons)
                      '${s.slot.plane.name}: ${_count(s.before)} → ${_count(s.after)}'
                          '${s.annihilation > 0 ? repairText('・全滅 ${airPercent(s.annihilation)}', ', wiped ${airPercent(s.annihilation)}') : ''}',
                  ].join('\n'),
                  maxLines: 6,
                ),
              ),
          ],
        ),
      QuestDetailSection(
        title: repairText('自艦隊の艦載機 (戦闘前 → 戦闘後の平均)', 'Your planes (before → average after)'),
        footer: repairText('全滅 = そのスロットが0機になる確率。戦闘機は対空砲火では落ちません', 'Wiped = chance the slot ends at 0'),
        children: _slotRows(own, result.own, secondary, enemy: false),
      ),
      QuestDetailSection(
        title: repairText('敵艦隊の艦載機 (出撃 → 制空戦後 → 対空砲火後)', 'Enemy planes (start → after air combat → after AA)'),
        footer: [
          if (result.enemyStrikeZero != null)
            repairText('敵の航空攻撃が来なくなる (攻撃機が全部落ちる) 確率: ${airPercent(result.enemyStrikeZero!)}',
                'Chance all enemy attackers are shot down: ${airPercent(result.enemyStrikeZero!)}'),
          repairText('棒立ち = その艦の攻撃機が全部落ちて、航空攻撃も砲撃もできなくなる確率',
              'Grounded = chance that ship loses all its attackers'),
        ].join('\n'),
        children: _slotRows(enemy, result.enemy, secondary, enemy: true, grounded: result.enemyGrounded),
      ),
    ];
  }

  List<Widget> _slotRows(AirFleet fleet, List<List<AirSlotResult>> results, TextStyle secondary,
      {required bool enemy, List<double?>? grounded}) {
    final rows = <Widget>[];
    for (final (i, ship) in fleet.ships.indexed) {
      if (ship.slots.isEmpty) continue;
      final lines = [
        for (final r in results[i])
          if (r.slot.count > 0 || r.before > 0)
            '${r.slot.plane.name}: ${_count(r.before)} → '
                '${enemy && r.slot.plane.isAttacker ? '${_count(r.afterAirCombat)} → ' : ''}${_count(r.after)}'
                '${r.annihilation > 0 ? repairText('・全滅 ${airPercent(r.annihilation)}', ', wiped ${airPercent(r.annihilation)}') : ''}',
      ];
      if (lines.isEmpty) continue;
      final g = grounded?[i];
      rows.add(CupertinoListTile(
        title: Text(ship.name, style: const TextStyle(fontSize: 14)),
        subtitle: Text(lines.join('\n'), maxLines: 6),
        additionalInfo: g == null ? null : Text(repairText('棒立ち ${airPercent(g)}', 'grounded ${airPercent(g)}'), style: secondary),
      ));
    }
    if (rows.isEmpty) {
      rows.add(CupertinoListTile(title: Text(repairText('艦載機なし', 'No planes'), style: secondary)));
    }
    return rows;
  }

  /// 装備を試す: 艦載機を積める各スロットに、持っている艦載機を試しに積む (満載の機数で計算)
  Widget _swapSection(List<Ship> ships, Map<int, List<int>?>? maxeqs, Iterable<Equipment> owned, TextStyle secondary) {
    final changes = _overrides.values.fold(0, (sum, m) => sum + m.length);
    final rows = <Widget>[];
    if (_showSwap) {
      for (final ship in ships) {
        if (ship.escape == true) continue;
        final maxeq = maxeqs?[ship.shipId] ?? const <int>[];
        final equipment = ship.equipment ?? const <Equipment>[];
        for (var i = 0; i < maxeq.length; i++) {
          if (maxeq[i] <= 0) continue;
          final changed = _overrides[ship.uid]?.containsKey(i) ?? false;
          final current = changed ? _overrides[ship.uid]![i] : (i < equipment.length ? equipment[i] : null);
          rows.add(CupertinoListTile(
            title: Text('${ship.name ?? ''} ${i + 1}', style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              '${current == null ? repairText('(なし)', '(empty)') : airEquipmentLabel(current)}'
              '${changed ? repairText('・試し中 (${maxeq[i]}機)', ', trying (${maxeq[i]})') : ''}',
              style: changed ? const TextStyle(color: CupertinoColors.activeOrange) : null,
            ),
            trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
            onTap: () => _pickPlane(ship, i, owned),
          ));
        }
      }
      if (rows.isEmpty) rows.add(CupertinoListTile(title: Text(repairText('艦載機を積める艦がいません', 'No ship can carry planes'), style: secondary)));
    }
    return QuestDetailSection(
      title: repairText('装備を試す', 'Try other planes'),
      footer: _showSwap
          ? repairText('持っている艦載機から選びます (積めるかどうか・数は確かめていません)。試したスロットは満載で計算します',
              'Pick from your planes (equippability and stock are not checked). Swapped slots are full.')
          : null,
      children: [
        CupertinoListTile(
          title: Text(changes == 0
              ? repairText('艦載機を入れ替えて計算する', 'Swap planes and recalculate')
              : repairText('$changes か所を試しています', 'Trying $changes change(s)')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (changes > 0)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minSize: 28,
                onPressed: () => setState(_overrides.clear),
                child: Text(repairText('元に戻す', 'Reset'), style: const TextStyle(fontSize: 13)),
              ),
            Icon(_showSwap ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down, size: 16),
          ]),
          onTap: () => setState(() => _showSwap = !_showSwap),
        ),
        ...rows,
      ],
    );
  }

  void _pickPlane(Ship ship, int slot, Iterable<Equipment> owned) {
    final candidates = airSwapCandidates(owned).take(60).toList();
    void apply(Equipment? equipment, {bool reset = false}) {
      setState(() {
        final map = _overrides.putIfAbsent(ship.uid, () => {});
        if (reset) {
          map.remove(slot);
          if (map.isEmpty) _overrides.remove(ship.uid);
        } else {
          map[slot] = equipment;
        }
      });
      Navigator.of(context).pop();
    }

    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text('${ship.name ?? ''} ${slot + 1}'),
        actions: [
          CupertinoActionSheetAction(onPressed: () => apply(null, reset: true), child: Text(repairText('元の装備に戻す', 'Original'))),
          CupertinoActionSheetAction(onPressed: () => apply(null), child: Text(repairText('外す', 'Remove'))),
          for (final (e, n) in candidates)
            CupertinoActionSheetAction(
              onPressed: () => apply(e),
              child: Text('${airEquipmentLabel(e)}${n > 1 ? ' ×$n' : ''}', style: const TextStyle(fontSize: 15)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(repairText('キャンセル', 'Cancel')),
        ),
      ),
    );
  }

  static String _count(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
