import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/air/air_data.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';
import 'package:conning_tower/models/feature/kancolle/damage/damage_data.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/pages/dashboard_pages/air_sim_page.dart' show airPercent;
import 'package:conning_tower/providers/air_data_provider.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/widgets/kancolle_quest_detail_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kFormations = {1: '単縦陣', 2: '複縦陣', 3: '輪形陣', 4: '梯形陣', 5: '単横陣'};
final _kAmmo = <double, String>{1.0: '50%以上', 0.8: '40%', 0.6: '30%', 0.4: '20%'};

/// 結果の1行 (ダメージ 85〜131 → 撃沈 12%・大破 30%・中破 20%)
String damageOutcomeText(DamageOutcome o) {
  final range = o.maxDamage == null
      ? repairText('カスダメのみ', 'scratch only')
      : '${o.minDamage}〜${o.maxDamage}${o.canScratch ? repairText(' (カスダメあり)', ' (or scratch)') : ''}';
  final hits = o.hits > 1 ? '×${o.hits}' : '';
  final odds = [
    if (o.sink > 0) repairText('撃沈 ${airPercent(o.sink)}', 'sink ${airPercent(o.sink)}'),
    if (o.heavy > 0) repairText('大破 ${airPercent(o.heavy)}', 'heavy ${airPercent(o.heavy)}'),
    if (o.medium > 0) repairText('中破 ${airPercent(o.medium)}', 'moderate ${airPercent(o.medium)}'),
  ];
  return '$range$hits → ${odds.isEmpty ? repairText('中破未満', 'below moderate') : odds.join('・')}';
}

String _number(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

/// 対地補正の1行 (×2.31 +25・集積地 ×2.125)
String damageGroundText(DamageGroundBonus b) {
  final parts = [
    if (b.multiplier != 1 || b.add != 0) '×${_number(b.multiplier)}${b.add != 0 ? ' +${_number(b.add)}' : ''}',
    if (b.depot != 1) repairText('集積地 ×${_number(b.depot)}', 'depot ×${_number(b.depot)}'),
  ];
  return parts.isEmpty ? repairText('なし', 'none') : parts.join(repairText('・', ', '));
}

/// ダメージシミュレーター: 海域から敵編成を1つ選び、自分の艦隊の攻撃が当たったときにどうなるかを並べる
class DamageView extends ConsumerStatefulWidget {
  const DamageView({super.key});

  @override
  ConsumerState<DamageView> createState() => _DamageViewState();
}

class _DamageViewState extends ConsumerState<DamageView> {
  static const _prefix = 'dmg_';

  late int _mapId;
  late int _phase;
  late int _fleetIndex;
  late int _formation;
  late DamageEngagement _engagement;
  late double _ammo;

  /// 選んでいるマス (null ならボス) と、マスごとの敵編成
  String? _node;
  final Map<String, String> _compKeys = {};

  /// 狙う艦 (自分 → 敵なら敵編成の何番目、敵 → 自分なら自分の艦隊の何番目)
  int _target = 0;

  /// 敵 → 自分 を見る
  bool _reverse = false;

  /// 今の耐久 (と損傷) で計算する (しなければ満タン・無傷)
  bool _current = false;

  /// 夜間触接の定数 (0 / 5 / 7 / 9)
  int _contact = 0;

  /// イベントの特効などの倍率 (自分 → 敵)
  double _bonus = 1.0;
  late final TextEditingController _bonusController;

  /// 計算結果の使い回し
  final Map<String, (DamageOutcome, DamageOutcome)> _cache = {};

  @override
  void initState() {
    super.initState();
    int? map, phase, fleet, formation, engagement;
    double? ammo;
    try {
      map = localStorage.getInt('${_prefix}map');
      phase = localStorage.getInt('${_prefix}phase');
      fleet = localStorage.getInt('${_prefix}fleet');
      formation = localStorage.getInt('${_prefix}formation');
      engagement = localStorage.getInt('${_prefix}engagement');
      ammo = localStorage.getDouble('${_prefix}ammo');
    } catch (_) {}
    _mapId = compassMapOf(map ?? 0)?.mapId ?? kCompassMaps.first.mapId;
    _phase = phase ?? 0;
    _fleetIndex = fleet ?? 0;
    _formation = _kFormations.containsKey(formation) ? formation! : 1;
    _engagement = DamageEngagement.values[(engagement ?? 0).clamp(0, DamageEngagement.values.length - 1)];
    _ammo = _kAmmo.containsKey(ammo) ? ammo! : 1.0;
    try {
      _reverse = localStorage.getBool('${_prefix}reverse') ?? false;
      _current = localStorage.getBool('${_prefix}current') ?? false;
      _contact = localStorage.getInt('${_prefix}contact') ?? 0;
      _bonus = localStorage.getDouble('${_prefix}bonus') ?? 1.0;
    } catch (_) {}
    if (!const [0, 5, 7, 9].contains(_contact)) _contact = 0;
    _bonusController = TextEditingController(text: _bonus == 1 ? '' : '$_bonus');
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

  void _select({int? mapId, int? phase, int? fleetIndex, int? formation, DamageEngagement? engagement, double? ammo}) {
    setState(() {
      if (mapId != null && mapId != _mapId) {
        _mapId = mapId;
        _phase = 0;
        _node = null;
        _compKeys.clear();
        _target = 0;
      }
      if (phase != null && phase != _phase) {
        _phase = phase;
        _node = null;
        _compKeys.clear();
        _target = 0;
      }
      if (fleetIndex != null) _fleetIndex = fleetIndex;
      if (formation != null) _formation = formation;
      if (engagement != null) _engagement = engagement;
      if (ammo != null) _ammo = ammo;
    });
    try {
      localStorage.setInt('${_prefix}map', _mapId);
      localStorage.setInt('${_prefix}phase', _phase);
      localStorage.setInt('${_prefix}fleet', _fleetIndex);
      localStorage.setInt('${_prefix}formation', _formation);
      localStorage.setInt('${_prefix}engagement', _engagement.index);
      localStorage.setDouble('${_prefix}ammo', _ammo);
    } catch (_) {}
    _load();
  }

  @override
  void dispose() {
    _bonusController.dispose();
    super.dispose();
  }

  void _save() {
    try {
      localStorage.setBool('${_prefix}reverse', _reverse);
      localStorage.setBool('${_prefix}current', _current);
      localStorage.setInt('${_prefix}contact', _contact);
      localStorage.setDouble('${_prefix}bonus', _bonus);
    } catch (_) {}
  }

  /// 轟沈ストッパー: 旗艦か、戦闘開始時に大破していない艦は沈まない
  bool _stopper(List<DamageShip> own, int index) => index == 0 || own[index].state != DamageState.heavy;

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
    Text small(String text) => Text(text, style: const TextStyle(fontSize: 12));

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Text(repairText('ダメージシミュレーター', 'Damage simulator'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      segmented<int>(map.area, {for (final a in areas) a: Text('$a-x')},
          (area) => _select(mapId: kCompassMaps.firstWhere((m) => m.area == area).mapId)),
      segmented<int>(map.mapId, {for (final m in mapsInArea) m.mapId: Text(m.name)}, (mapId) => _select(mapId: mapId)),
      if (phases.length > 1)
        segmented<int>(phase, {for (final (i, m) in phases.indexed) i: small(m.phase ?? '${i + 1}')}, (index) => _select(phase: index)),
      if (squads.length > 1)
        segmented<int>(fleetIndex, {for (var i = 0; i < squads.length; i++) i: Text(repairText('第${i + 1}艦隊', 'Fleet ${i + 1}'))},
            (index) => _select(fleetIndex: index)),
      segmented<int>(_formation, {for (final MapEntry(:key, :value) in _kFormations.entries) key: small(value)},
          (f) => _select(formation: f)),
      segmented<DamageEngagement>(_engagement, {for (final e in DamageEngagement.values) e: small(repairText(e.ja, e.en))},
          (e) => _select(engagement: e)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(repairText('弾薬の残り', 'Ammo left'), style: secondary),
      ),
      segmented<double>(_ammo, {for (final MapEntry(:key, :value) in _kAmmo.entries) key: small(value)}, (a) => _select(ammo: a)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(repairText('夜偵の触接 (夜戦の攻撃力に足す)', 'Night contact'), style: secondary),
      ),
      segmented<int>(_contact, {0: small(repairText('なし', 'none')), 5: small('+5'), 7: small('+7'), 9: small('+9')}, (v) {
        setState(() => _contact = v);
        _save();
      }),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Expanded(child: Text(repairText('今の耐久・損傷で計算', 'Use current HP'), style: const TextStyle(fontSize: 14))),
          CupertinoSwitch(
            value: _current,
            onChanged: (v) {
              setState(() => _current = v);
              _save();
            },
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Expanded(child: Text(repairText('特効の倍率 (自分 → 敵)', 'Bonus multiplier (you → enemy)'), style: const TextStyle(fontSize: 14))),
          SizedBox(
            width: 90,
            child: CupertinoTextField(
              controller: _bonusController,
              placeholder: '1.0',
              prefix: const Padding(padding: EdgeInsets.only(left: 6), child: Text('×')),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (text) {
                final v = double.tryParse(text.trim());
                setState(() => _bonus = v == null || v <= 0 ? 1.0 : v);
                _save();
              },
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Expanded(child: Text(_statusText(map, abyssal), style: secondary)),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minSize: 28,
            onPressed: AirDataLoader.loadingComps(map) ? null : () => _load(force: true),
            child: Text(repairText('取り直す', 'Reload'), style: const TextStyle(fontSize: 13)),
          ),
        ]),
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
    } else if (abyssal.stats.isEmpty) {
      children.add(_message(
          repairText('深海棲艦のデータが古い形のままです。GitHub の Actions で「Development stats」を実行してから「取り直す」を押してください',
              'The abyssal data is old. Run "Development stats" on GitHub Actions, then tap Reload.'),
          secondary));
    } else {
      final byNode = enemyCompsByNode(comps);
      final nodes = byNode.keys.toList()..sort((a, b) => a.length != b.length ? a.length.compareTo(b.length) : a.compareTo(b));
      if (nodes.isEmpty) {
        children.add(_message(repairText('この海域の敵編成の報告がありません', 'No enemy compositions reported for this map'), secondary));
      } else {
        final node = byNode.containsKey(_node) ? _node! : (byNode.containsKey(map.boss) ? map.boss : nodes.first);
        final nodeComps = byNode[node]!;
        final airFleets = [for (final c in nodeComps) enemyAirFleet(c, abyssal: abyssal, slotItems: slotItems, shipInfo: shipInfo)];
        var selected = nodeComps.indexWhere((c) => c.key == _compKeys[node]);
        if (selected < 0) selected = strongestEnemyComp(airFleets);
        final comp = nodeComps[selected];
        final enemies = damageEnemyFleetOf(comp, abyssal: abyssal, slotItems: slotItems, shipInfo: shipInfo);
        final own = damageFleetOf(squads[fleetIndex], full: !_current);
        final conditions = DamageConditions(engagement: _engagement, formation: _formation, ammo: _ammo, nightContact: _contact, bonus: _bonus);
        // 敵の攻撃: 陣形は敵編成のもの (連合艦隊の陣形は補正1.0)、弾薬は満タン、特効なし
        final enemyConditions = DamageConditions(engagement: _engagement, formation: comp.formation);
        children
          ..add(_nodePicker(nodes, node, map))
          ..add(_patternSection(node, nodeComps, airFleets, selected, secondary));
        if (comp.formation >= 11) {
          children.add(_message(
              repairText('この編成は敵の連合艦隊です。連合艦隊どうしの補正は入れず、通常艦隊の式で計算しています',
                  'This is an enemy combined fleet. Combined-fleet modifiers are not applied.'),
              secondary));
        }
        if (enemies.isEmpty) {
          children.add(_message(repairText('この編成の深海棲艦のデータがありません', 'No data for these abyssal ships'), secondary));
        } else {
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: CupertinoSlidingSegmentedControl<bool>(
              groupValue: _reverse,
              children: {
                false: Text(repairText('自分 → 敵', 'You → enemy')),
                true: Text(repairText('敵 → 自分', 'Enemy → you')),
              },
              onValueChanged: (v) {
                if (v == null) return;
                setState(() {
                  _reverse = v;
                  _target = 0;
                });
                _save();
              },
            ),
          ));
          if (!_reverse) {
            final target = _target.clamp(0, enemies.length - 1);
            children
              ..add(_targetPicker([for (final e in enemies) '${e.name} (${e.hp}${e.installation ? repairText('・陸上', ', land') : ''})'], target))
              ..add(_summarySection(own, enemies, conditions, secondary))
              ..addAll([for (final ship in own) _shipSection(ship, enemies[target], conditions, secondary)]);
          } else if (own.isNotEmpty) {
            final target = _target.clamp(0, own.length - 1);
            children
              ..add(_targetPicker([for (final s in own) '${s.name} (${s.hp}/${s.maxHp})'], target))
              ..add(_reverseSummarySection(own, enemies, enemyConditions, secondary))
              ..addAll([
                for (final enemy in enemies) _shipSection(enemy, own[target], enemyConditions, secondary, stopper: _stopper(own, target)),
              ]);
          }
        }
      }
    }

    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Text(
        repairText(
            '攻撃が当たったときの結果です (命中率・誰を狙うかは含みません)。耐久は満タン・無傷として計算します。'
                '敵編成は KCNav (tsunkit.net) の報告、深海棲艦の能力は KC3Kai/kancolle-replay (MIT) のデータ。'
                '計算式は「艦これ攻略 Wiki*」の「戦闘について」などを元にしています。',
            'Results when an attack hits (accuracy and targeting are not included). Ships are at full HP. '
                'Enemy compositions from KCNav, abyssal stats from KC3Kai/kancolle-replay (MIT), formulas from the KanColle wiki.'),
        style: secondary,
      ),
    ));
    return CupertinoScrollbar(child: ListView(padding: const EdgeInsets.only(bottom: 24), children: children));
  }

  Widget _message(String text, TextStyle style) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Text(text, style: style));

  String _statusText(CompassMap map, AbyssalTable? abyssal) {
    final key = AirDataLoader.keyOf(map);
    final at = AirDataLoader.compsAt[key];
    if (AirDataLoader.loadingComps(map)) return repairText('KCNav から敵編成を取得中', 'Loading from KCNav');
    if (at == null) {
      final error = AirDataLoader.compsError[key] ?? AirDataLoader.abyssalError;
      return error == null ? '' : repairText('取得できませんでした ($error)', 'Could not load ($error)');
    }
    final t = at.toLocal();
    return repairText('敵編成 ${AirDataLoader.comps[key]?.length ?? 0}件 (${t.month}/${t.day} 取得)',
        '${AirDataLoader.comps[key]?.length ?? 0} compositions (${t.month}/${t.day})');
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

  Widget _nodePicker(List<String> nodes, String selected, CompassMap map) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in nodes)
            _chip(n == map.boss ? repairText('$n (ボス)', '$n (boss)') : n, n == selected, () => setState(() {
                  _node = n;
                  _target = 0;
                })),
        ]),
      );

  Widget _patternSection(String node, List<EnemyComp> comps, List<AirFleet> fleets, int selected, TextStyle secondary) {
    final total = comps.fold(0, (sum, c) => sum + c.count);
    final shown = [for (var i = 0; i < comps.length && i < 6; i++) i];
    if (!shown.contains(selected)) shown.add(selected);
    return QuestDetailSection(
      title: repairText('$nodeマスの敵編成 (${comps.length}パターン)', 'Node $node (${comps.length} patterns)'),
      footer: repairText('最初は制空値が一番高い編成。右の%は報告の割合。陣形はその編成のもの', 'Strongest first. Formation as reported'),
      children: [
        for (final i in shown)
          CupertinoListTile(
            leading: Icon(i == selected ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle,
                size: 20, color: i == selected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey),
            title: Text('${airFormationName(comps[i].formation)}・${fleets[i].ships.first.name}', style: const TextStyle(fontSize: 14)),
            subtitle: Text(fleets[i].ships.map((s) => s.name).join('・'), maxLines: 2),
            additionalInfo: Text(total == 0 ? '' : airPercent(comps[i].count / total), style: secondary),
            onTap: () => setState(() {
              _compKeys[node] = comps[i].key;
              _target = 0;
            }),
          ),
      ],
    );
  }

  Widget _targetPicker(List<String> labels, int target) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (i, label) in labels.indexed) _chip('${i + 1} $label', i == target, () => setState(() => _target = i)),
        ]),
      );

  (DamageOutcome, DamageOutcome) _outcome(DamageAttack attack, DamageShip target, DamageConditions c, {bool stopper = false}) {
    final key = '${attack.normal}|${attack.critical}|${attack.armorReduction}|${target.hp}|${target.maxHp}|${target.armor}|${c.ammo}|$stopper';
    if (_cache.length > 4000) _cache.clear();
    return _cache[key] ??= damageAttackOutcome(attack, target, c, stopper: stopper);
  }

  /// [attackers] の攻撃のうち、[target] を一番撃沈・大破させやすいもの (通常の命中)
  ((double, String), (double, String)) _best(List<DamageShip> attackers, DamageShip target, DamageConditions c, {bool stopper = false}) {
    var bestSink = (0.0, '');
    var bestHeavy = (0.0, '');
    for (final ship in attackers) {
      for (final attack in damageAllAttacks(ship, target, c)) {
        final (normal, _) = _outcome(attack, target, c, stopper: stopper);
        final label = '${ship.name} ${repairText(attack.ja, attack.en)}';
        if (normal.sink > bestSink.$1) bestSink = (normal.sink, label);
        if (normal.heavyOrWorse > bestHeavy.$1) bestHeavy = (normal.heavyOrWorse, label);
      }
    }
    return (bestSink, bestHeavy);
  }

  /// 要約: 敵艦ごとに、1回 (通常の命中) で撃沈・大破できる一番よい攻撃
  Widget _summarySection(List<DamageShip> own, List<DamageShip> enemies, DamageConditions c, TextStyle secondary) {
    return QuestDetailSection(
      title: repairText('1回の攻撃で撃沈・大破できるか (通常の命中)', 'Can one hit sink it? (normal hit)'),
      footer: repairText('昼戦・対潜・夜戦の攻撃すべてから選んでいます。タップでその敵の詳細。クリティカルは各艦の欄を見てください', 'Tap for details'),
      children: [
        for (final (i, enemy) in enemies.indexed)
          () {
            final (sink, heavy) = _best(own, enemy, c);
            final lines = [
              sink.$1 > 0
                  ? repairText('撃沈 最大 ${airPercent(sink.$1)} (${sink.$2})', 'Sink up to ${airPercent(sink.$1)} (${sink.$2})')
                  : repairText('1回では撃沈できない', 'Cannot sink with one hit'),
              if (heavy.$1 > 0)
                repairText('大破以上 最大 ${airPercent(heavy.$1)} (${heavy.$2})', 'Heavy+ up to ${airPercent(heavy.$1)} (${heavy.$2})'),
            ];
            return CupertinoListTile(
              title: Text('${i + 1} ${enemy.name}', style: const TextStyle(fontSize: 14)),
              subtitle: Text(lines.join('\n'), maxLines: 3),
              additionalInfo: Text(repairText('耐久${enemy.hp}・装甲${enemy.armor.round()}', 'HP ${enemy.hp}, armor ${enemy.armor.round()}'), style: secondary),
              onTap: () => setState(() => _target = i),
            );
          }(),
      ],
    );
  }

  /// 要約 (敵 → 自分): 自分の艦ごとに、敵の攻撃1回 (通常の命中) で大破・撃沈しうるか
  Widget _reverseSummarySection(List<DamageShip> own, List<DamageShip> enemies, DamageConditions c, TextStyle secondary) {
    return QuestDetailSection(
      title: repairText('敵の攻撃1回で大破するか (通常の命中)', 'Can one enemy hit cause heavy damage?'),
      footer: repairText(
          '旗艦と、戦闘開始時に大破していない艦は沈みません (轟沈ストッパー)。今の耐久で計算する場合は、大破している随伴艦が撃沈されうるかも出ます。タップでその艦の詳細',
          'Flagship and ships not heavily damaged at the start cannot sink. Tap for details'),
      children: [
        for (final (i, ship) in own.indexed)
          () {
            final (sink, heavy) = _best(enemies, ship, c, stopper: _stopper(own, i));
            final lines = [
              if (sink.$1 > 0) repairText('撃沈 最大 ${airPercent(sink.$1)} (${sink.$2})', 'Sink up to ${airPercent(sink.$1)} (${sink.$2})'),
              heavy.$1 > 0
                  ? repairText('大破以上 最大 ${airPercent(heavy.$1)} (${heavy.$2})', 'Heavy+ up to ${airPercent(heavy.$1)} (${heavy.$2})')
                  : repairText('1回では大破しない', 'No heavy damage from one hit'),
            ];
            return CupertinoListTile(
              title: Text('${i + 1} ${ship.name}', style: const TextStyle(fontSize: 14)),
              subtitle: Text(lines.join('\n'), maxLines: 3),
              additionalInfo: Text(repairText('耐久${ship.hp}/${ship.maxHp}・装甲${ship.armor.round()}', 'HP ${ship.hp}/${ship.maxHp}, armor ${ship.armor.round()}'),
                  style: secondary),
              onTap: () => setState(() => _target = i),
            );
          }(),
      ],
    );
  }

  /// 1隻の攻撃と、狙う艦に当たったときの結果
  Widget _shipSection(DamageShip ship, DamageShip target, DamageConditions c, TextStyle secondary, {bool stopper = false}) {
    final attacks = damageAllAttacks(ship, target, c);
    final ground = !ship.enemy && (target.installation || target.supplyDepot);
    return QuestDetailSection(
      title: repairText('${ship.name} → ${target.name}', '${ship.name} → ${target.name}'),
      footer: ground && target.installation
          ? repairText('陸上型には雷撃できません。艦攻の航空攻撃は雷装0扱い。航空攻撃・夜間航空攻撃の対地補正は分かっていないので付けていません',
              'No torpedoes against installations. Installation bonuses for air attacks are unknown and not applied')
          : null,
      children: [
        if (ground)
          CupertinoListTile(
            title: Text(repairText('陸上型への補正 (対地装備)', 'Installation bonus'), style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              '${repairText('昼', 'Day')} ${damageGroundText(damageGroundBonus(ship, target, day: true))}\n'
              '${repairText('夜', 'Night')} ${damageGroundText(damageGroundBonus(ship, target, day: false))}',
              maxLines: 2,
            ),
          ),
        if (target.pt || ship.pt)
          CupertinoListTile(title: Text(repairText('PT小鬼群はダメージの式が特殊なため計算しません', 'PT Imps are not supported'), style: secondary)),
        if (attacks.isEmpty && !target.pt && !ship.pt)
          CupertinoListTile(
            title: Text(
              target.submarine
                  ? repairText('潜水艦を攻撃できません (対潜できる艦・装備がない)', 'Cannot attack submarines')
                  : repairText('この相手にできる攻撃がありません', 'No attack against this target'),
              style: secondary,
            ),
          ),
        for (final attack in attacks)
          () {
            final (normal, critical) = _outcome(attack, target, c, stopper: stopper);
            return CupertinoListTile(
              title: Text(repairText(attack.ja, attack.en), style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                '${damageOutcomeText(normal)}\n${repairText('クリティカル', 'Critical')} ${damageOutcomeText(critical)}',
                maxLines: 3,
              ),
            );
          }(),
      ],
    );
  }
}
