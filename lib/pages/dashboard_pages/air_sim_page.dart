import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/air/air_data.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/providers/air_data_provider.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
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
  static const _formations = [1, 2, 3, 6];

  late int _mapId;
  late int _phase;
  late int _fleetIndex;
  late int _formation;

  /// 選んでいるマス (null ならボス)
  String? _node;

  /// 選んでいる敵編成 (null なら制空値が一番高いもの)
  String? _compKey;

  @override
  void initState() {
    super.initState();
    int? map, phase, fleet, formation;
    try {
      map = localStorage.getInt(_mapKey);
      phase = localStorage.getInt(_phaseKey);
      fleet = localStorage.getInt(_fleetKey);
      formation = localStorage.getInt(_formationKey);
    } catch (_) {}
    _mapId = compassMapOf(map ?? 0)?.mapId ?? kCompassMaps.first.mapId;
    _phase = phase ?? 0;
    _fleetIndex = fleet ?? 0;
    _formation = _formations.contains(formation) ? formation! : 1;
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

  void _select({int? mapId, int? phase, int? fleetIndex, int? formation}) {
    setState(() {
      if (mapId != null && mapId != _mapId) {
        _mapId = mapId;
        _phase = 0;
        _node = null;
        _compKey = null;
      }
      if (phase != null && phase != _phase) {
        _phase = phase;
        _node = null;
        _compKey = null;
      }
      if (fleetIndex != null) _fleetIndex = fleetIndex;
      if (formation != null) _formation = formation;
    });
    try {
      localStorage.setInt(_mapKey, _mapId);
      localStorage.setInt(_phaseKey, _phase);
      localStorage.setInt(_fleetKey, _fleetIndex);
      localStorage.setInt(_formationKey, _formation);
    } catch (_) {}
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AirDataLoader.revision,
      builder: (context, _, __) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final data = ref.watch(kancolleDataProvider);
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
    final key = AirDataLoader.keyOf(map);
    final comps = AirDataLoader.comps[key];
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
        {for (final f in _formations) f: Text(repairText(airFormationName(f), airFormationName(f)), style: const TextStyle(fontSize: 12))},
        (f) => _select(formation: f),
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
      final byNode = enemyCompsByNode(comps);
      if (byNode.isEmpty) {
        children.add(_message(repairText('この海域の敵編成の報告がありません', 'No enemy compositions reported for this map'), secondary));
      } else {
        final nodes = byNode.keys.toList()..sort(_nodeOrder);
        final node = byNode.containsKey(_node) ? _node! : (byNode.containsKey(map.boss) ? map.boss : nodes.first);
        final nodeComps = byNode[node]!;
        final fleets = [
          for (final c in nodeComps) enemyAirFleet(c, abyssal: abyssal, slotItems: slotItems, shipInfo: shipInfo),
        ];
        final strongest = strongestEnemyComp(fleets);
        var selected = nodeComps.indexWhere((c) => c.key == _compKey);
        if (selected < 0) selected = strongest;
        final own = ownAirFleet(squads[fleetIndex], shipInfo: shipInfo, formation: _formation);
        final result = simulateAirBattles(own, [fleets[selected]], runs: kAirSimRuns, seed: 1).single;
        children
          ..add(_nodePicker(nodes, node, map, byNode))
          ..add(_patternSection(node, nodeComps, fleets, selected, strongest, secondary))
          ..addAll(_resultSections(context, own, fleets[selected], result, secondary));
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

  Widget _nodePicker(List<String> nodes, String selected, CompassMap map, Map<String, List<EnemyComp>> byNode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final n in nodes)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minSize: 30,
              color: n == selected ? CupertinoColors.activeBlue : CupertinoColors.tertiarySystemFill,
              borderRadius: BorderRadius.circular(15),
              onPressed: () => setState(() {
                _node = n;
                _compKey = null;
              }),
              child: Text(
                n == map.boss ? repairText('$n (ボス)', '$n (boss)') : n,
                style: TextStyle(
                    fontSize: 13, color: n == selected ? CupertinoColors.white : CupertinoColors.label.resolveFrom(context)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _patternSection(String node, List<EnemyComp> comps, List<AirFleet> fleets, int selected, int strongest, TextStyle secondary) {
    final total = comps.fold(0, (sum, c) => sum + c.count);
    final shown = [for (var i = 0; i < comps.length && i < 8; i++) i];
    if (!shown.contains(selected)) shown.add(selected);
    if (!shown.contains(strongest)) shown.add(strongest);
    return QuestDetailSection(
      title: repairText('$nodeマスの敵編成 (${comps.length}パターン)', 'Node $node (${comps.length} patterns)'),
      footer: repairText('最初は制空値が一番高い編成。タップで切り替え', 'The strongest air power is selected first. Tap to switch'),
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
            onTap: () => setState(() => _compKey = comps[i].key),
          ),
      ],
    );
  }

  List<Widget> _resultSections(BuildContext context, AirFleet own, AirFleet enemy, AirBattleResult result, TextStyle secondary) {
    final needed = airPowerNeeded(result.enemyPower);
    final ownHasAaci = own.ships.any((s) => s.aaci.isNotEmpty);
    return [
      QuestDetailSection(
        title: repairText('制空権', 'Air superiority'),
        children: [
          CupertinoListTile(
            title: Text(repairText('制空値', 'Air power')),
            additionalInfo: Text(repairText('自艦隊 ${result.ownPower.round()} / 敵 ${result.enemyPower}',
                'You ${result.ownPower.round()} / enemy ${result.enemyPower}')),
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
      QuestDetailSection(
        title: repairText('自艦隊の艦載機 (戦闘後の平均)', 'Your planes (average after the battle)'),
        footer: repairText('全滅 = そのスロットが0機になる確率。戦闘機は対空砲火では落ちません', 'Wiped = chance the slot ends at 0'),
        children: _slotRows(own, result.own, secondary, enemy: false),
      ),
      QuestDetailSection(
        title: repairText('敵艦隊の艦載機', 'Enemy planes'),
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

  static String _count(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
