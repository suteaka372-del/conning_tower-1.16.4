import 'package:conning_tower/providers/dashboard_tab_provider.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_log.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';
import 'package:conning_tower/models/feature/kancolle/expedition_check.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/pages/dashboard_pages/air_sim_page.dart';
import 'package:conning_tower/pages/dashboard_pages/damage_sim_page.dart';
import 'package:conning_tower/widgets/components/edge_insets_constants.dart';
import 'package:conning_tower/widgets/kancolle_quest_detail_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「シミュ」タブ (羅針盤・制空権。ダメージはあとで足す)
class SimulatorPage extends ConsumerStatefulWidget {
  const SimulatorPage({super.key});

  @override
  ConsumerState createState() => _SimulatorPageState();
}

class _SimulatorPageState extends ConsumerState<SimulatorPage> with AutomaticKeepAliveClientMixin {
  static const _modeKey = 'sim_mode';

  /// 0 = 羅針盤、1 = 制空権、2 = ダメージ
  int _mode = 0;

  @override
  void initState() {
    super.initState();
    try {
      _mode = (localStorage.getInt(_modeKey) ?? 0).clamp(0, 2);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: tabContentMargin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10.0),
        child: ColoredBox(
          color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<int>(
                      groupValue: _mode,
                      children: {
                        0: Text(repairText('羅針盤', 'Compass')),
                        1: Text(repairText('制空権', 'Air power')),
                        2: Text(repairText('ダメージ', 'Damage')),
                      },
                      onValueChanged: (v) {
                        if (v == null) return;
                        setState(() => _mode = v);
                        try {
                          localStorage.setInt(_modeKey, v);
                        } catch (_) {}
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: switch (_mode) {
                    1 => const AirView(),
                    2 => const DamageView(),
                    _ => const CompassView(),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

/// 艦隊の艦種の内訳 (軽巡1 駆逐5 など)
String compassFleetSummary(CompassFleet fleet) {
  final counts = <int, int>{};
  for (final ship in fleet.ships) {
    counts[ship.shipType] = (counts[ship.shipType] ?? 0) + 1;
  }
  final parts = [for (final e in counts.entries) '${expeditionShipTypeName(e.key)}${e.value}'];
  final speed = fleet.allFast ? repairText('高速以上統一', 'all fast') : (fleet.anySlow ? repairText('低速あり', 'slow ship') : '');
  return [parts.join(' '), if (speed.isNotEmpty) speed].join(' / ');
}

String compassPercent(double p) {
  final v = p * 100;
  if (v > 0 && v < 1) return '<1%';
  return '${v.round()}%';
}

/// 羅針盤シミュレーター: 海域と艦隊を選ぶと、今の編成でどこへ進むかを出す
class CompassView extends ConsumerStatefulWidget {
  const CompassView({super.key});

  @override
  ConsumerState<CompassView> createState() => _CompassViewState();
}

class _CompassViewState extends ConsumerState<CompassView> {
  static const _mapKey = 'compass_map';
  static const _fleetKey = 'compass_fleet';
  static const _phaseKey = 'compass_phase';

  late int _mapId;
  late int _fleetIndex;

  /// ゲージが複数ある海域で、どのゲージを見ているか
  late int _phase;

  @override
  void initState() {
    super.initState();
    int? savedMap;
    int? savedFleet;
    int? savedPhase;
    try {
      savedMap = localStorage.getInt(_mapKey);
      savedFleet = localStorage.getInt(_fleetKey);
      savedPhase = localStorage.getInt(_phaseKey);
    } catch (_) {}
    _mapId = compassMapOf(savedMap ?? 0)?.mapId ?? kCompassMaps.first.mapId;
    _fleetIndex = savedFleet ?? 0;
    _phase = savedPhase ?? 0;
  }

  void _select({int? mapId, int? fleetIndex, int? phase}) {
    setState(() {
      if (mapId != null && mapId != _mapId) {
        _mapId = mapId;
        _phase = 0;
      }
      if (fleetIndex != null) _fleetIndex = fleetIndex;
      if (phase != null) _phase = phase;
    });
    try {
      localStorage.setInt(_mapKey, _mapId);
      localStorage.setInt(_fleetKey, _fleetIndex);
      localStorage.setInt(_phaseKey, _phase);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final data = watchKancolleData(ref, context);
    final phases = compassMapsOf(_mapId);
    final phase = _phase.clamp(0, phases.length - 1);
    final map = phases[phase];
    final areas = {for (final m in kCompassMaps) m.area}.toList()..sort();
    final mapsInArea = [
      for (final m in kCompassMaps)
        if (m.area == map.area && m.phase == compassMapOf(m.mapId)!.phase) m,
    ];
    final squads = data.squads;
    final fleetIndex = squads.isEmpty ? 0 : _fleetIndex.clamp(0, squads.length - 1);
    final fleet = squads.isEmpty || squads[fleetIndex].ships.isEmpty
        ? null
        : compassFleetOf(squads[fleetIndex], admiralLevel: data.seaForceBase.admiral.level);
    final result = fleet == null ? null : simulateCompassCached(map, fleet);
    final secondary = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));
    final logs = [for (final e in compassRecorder.entries) if (e.mapId == map.mapId) e].take(5).toList();

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

    return CupertinoScrollbar(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(repairText('羅針盤シミュレーター', 'Compass simulator'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          segmented<int>(
            map.area,
            {for (final a in areas) a: Text(repairText('$a-x', '$a-x'))},
            (area) => _select(mapId: kCompassMaps.firstWhere((m) => m.area == area).mapId),
          ),
          segmented<int>(
            map.mapId,
            {for (final m in mapsInArea) m.mapId: Text(m.name)},
            (mapId) => _select(mapId: mapId),
          ),
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
          if (fleet == null || result == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(repairText('ゲームを起動すると、今の艦隊で判定します', 'Start the game to check with your fleet'), style: secondary),
            )
          else ...[
            QuestDetailSection(
              title: '${map.name} ${map.title}',
              footer: [
                if (result.estimated) repairText('割合が分からない分岐を含むため、推定の値です', 'Includes branches with unknown shares (estimated)'),
                if (map.note != null) map.note!,
              ].join('\n'),
              children: [
                CupertinoListTile(
                  title: Text(repairText('ボス (${map.boss}マス) に着く確率', 'Reach the boss (${map.boss})')),
                  additionalInfo: Text(
                    '${result.estimated ? repairText('約', '~') : ''}${compassPercent(result.bossProbability)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                CupertinoListTile(
                  title: Text(repairText('第${fleetIndex + 1}艦隊 (${fleet.n}隻)', 'Fleet ${fleetIndex + 1} (${fleet.n})')),
                  subtitle: Text(compassFleetSummary(fleet), maxLines: 2),
                ),
                if (map.coefficient != null)
                  CupertinoListTile(
                    title: Text(repairText('索敵スコア (分岐点係数${map.coefficient!.toStringAsFixed(0)})',
                        'LoS score (coefficient ${map.coefficient!.toStringAsFixed(0)})')),
                    additionalInfo: Text(fleet.losScore(map.coefficient!).toStringAsFixed(2)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                  child: Text(
                    [
                      for (final MapEntry(key: node, value: p) in result.reach.entries)
                        if (node != 'Start' && p > 0) '$node ${compassPercent(p)}',
                    ].join(' · '),
                    style: secondary,
                  ),
                ),
              ],
            ),
            QuestDetailSection(
              title: repairText('分岐と理由', 'Branches'),
              children: [
                for (final step in result.steps)
                  if (map.ruleNodes.contains(step.node))
                    CupertinoListTile(
                      title: Text(repairText('${_nodeName(step.node)} (来る確率 ${compassPercent(step.reach)})',
                          '${_nodeName(step.node)} (${compassPercent(step.reach)})')),
                      subtitle: Text(
                        '→ ${[for (final o in step.outcome.options) if (o.probability > 0) '${o.node} ${compassPercent(o.probability)}'].join(' / ')}'
                        '${step.outcome.estimated ? repairText(' (推定)', ' (estimated)') : ''}\n'
                        '${step.outcome.reason}',
                        maxLines: 4,
                      ),
                    ),
              ],
            ),
          ],
          QuestDetailSection(
            title: repairText('答え合わせ (この海域の最近の出撃)', 'Recent sorties on this map'),
            footer: repairText('出撃したときの艦隊で予測し、実際に進んだマスと比べています', 'Compares the prediction for the sortie fleet with the actual route'),
            children: [
              if (logs.isEmpty) CupertinoListTile(title: Text(repairText('まだ記録がありません', 'No sorties yet'))),
              for (final log in logs)
                CupertinoListTile(
                  title: Text(log.route, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(_logText(log)),
                  additionalInfo: Text('${log.time.month}/${log.time.day} ${log.time.hour}:${log.time.minute.toString().padLeft(2, '0')}',
                      style: secondary),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              repairText(
                  '分岐条件は「艦これ攻略 Wiki*」(wikiwiki.jp/kancolle) 各海域の「ルート分岐法則」を元にしています。マスの番号は KC3Kai/kancolle-replay (MIT) を元にしています。ゲームの変更で条件が変わることがあります。',
                  'Branch rules are based on the "ルート分岐法則" sections of the KanColle wiki (wikiwiki.jp/kancolle). Node numbers are based on KC3Kai/kancolle-replay (MIT). Rules may change with game updates.'),
              style: secondary,
            ),
          ),
        ],
      ),
    );
  }

  static String _nodeName(String node) {
    if (node.startsWith('Start')) {
      final no = node.substring(5).trim();
      return repairText('出撃地点$no', node);
    }
    return repairText('$nodeマス', node);
  }

  static String _logText(CompassLogEntry log) {
    final miss = [for (final s in log.steps) if (s.mismatch) s];
    if (miss.isEmpty) return repairText('予測どおり', 'As predicted');
    return repairText('予測と違う: ${miss.map((s) => '${s.from}→${s.to}').join(', ')} (予測では0%)',
        'Differs: ${miss.map((s) => '${s.from}→${s.to}').join(', ')} (predicted 0%)');
  }
}
