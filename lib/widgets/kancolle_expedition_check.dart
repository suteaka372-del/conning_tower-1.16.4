import 'package:conning_tower/helper.dart';
import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/expedition_check.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/widgets/components/edge_insets_constants.dart';
import 'package:conning_tower/widgets/scroll_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 遠征の一覧で判定する艦隊 (第2〜第4艦隊。第1艦隊は遠征に出せない)
const List<int> kExpeditionFleetNumbers = [2, 3, 4];

/// ゲームの遠征画面と同じ海域の並び (鎮守府, 南西諸島, 北方, 南西, 西方, 南方, ...)
const List<int> _kAreaOrder = [1, 2, 3, 7, 4, 5, 6];

int _areaRank(int areaId) {
  final index = _kAreaOrder.indexOf(areaId);
  return index < 0 ? 100 + areaId : index;
}

/// 遠征を海域の順に並べる
List<GetDataApiDataApiMstMissionEntity> sortedExpeditions(
        Iterable<GetDataApiDataApiMstMissionEntity> missions) =>
    missions.toList()
      ..sort((a, b) {
        final area = _areaRank(a.apiMapareaId).compareTo(_areaRank(b.apiMapareaId));
        return area != 0 ? area : a.apiId.compareTo(b.apiId);
      });

/// 艦隊番号 (2〜4) の艦娘。艦隊がなければ空
List<Ship> expeditionFleetShips(List<Squad> squads, int fleetNumber) =>
    fleetNumber - 1 < squads.length ? squads[fleetNumber - 1].ships : const [];

String _percent(double rate) => '${(rate * 100).floor()}%';

/// 一覧の1マス (第n艦隊の判定)
class ExpeditionResultCell extends StatelessWidget {
  const ExpeditionResultCell({super.key, required this.result, this.width = 52});

  final ExpeditionCheckResult result;
  final double width;

  @override
  Widget build(BuildContext context) {
    final String text;
    final Color color;
    Color? background;
    if (result.emptyFleet) {
      text = '-';
      color = CupertinoColors.tertiaryLabel.resolveFrom(context);
    } else if (!result.supported) {
      text = '?';
      color = CupertinoColors.secondaryLabel.resolveFrom(context);
    } else if (!result.success) {
      text = '×';
      color = CupertinoColors.systemRed.resolveFrom(context);
      background = CupertinoColors.systemRed.resolveFrom(context).withOpacity(0.14);
    } else {
      final rate = result.greatSuccessRate ?? 0;
      text = rate > 0 ? '○${_percent(rate)}' : '○';
      color = CupertinoColors.systemGreen.resolveFrom(context);
    }
    return Container(
      width: width,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// 遠征タブの「遠征チェック」 (CustomScrollView に入れる Sliver)
class ExpeditionCheckSliver extends ConsumerWidget {
  const ExpeditionCheckSliver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(kancolleDataProvider);
    final missionInfo = data.dataInfo.missionInfo;
    final secondaryStyle = TextStyle(
      fontSize: 12,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    );
    if (missionInfo == null || missionInfo.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            repairText('ゲームにログインすると遠征の一覧が表示されます', 'Log in to the game to see expeditions'),
            textAlign: TextAlign.center,
            style: secondaryStyle,
          ),
        ),
      );
    }

    final squads = data.squads;
    final fleets = {
      for (final number in kExpeditionFleetNumbers) number: expeditionFleetShips(squads, number)
    };
    final missions = sortedExpeditions(missionInfo.values);
    final areaNames = data.dataInfo.mapAreaInfo?.map((id, area) => MapEntry(id, area.name)) ??
        const <int, String>{};

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(repairText('遠征チェック', 'Expedition check'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            for (final number in kExpeditionFleetNumbers)
              SizedBox(
                width: 55,
                child: Text(
                  repairText('第$number', '#$number'),
                  textAlign: TextAlign.center,
                  style: secondaryStyle,
                ),
              ),
          ],
        ),
      ),
    ];

    int? currentArea;
    for (final mission in missions) {
      if (mission.apiMapareaId != currentArea) {
        currentArea = mission.apiMapareaId;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 2),
          child: Text(areaNames[currentArea] ?? repairText('海域 $currentArea', 'Area $currentArea'),
              style: secondaryStyle),
        ));
      }
      children.add(ExpeditionCheckRow(
        mission: mission,
        results: {
          for (final e in fleets.entries)
            e.key: checkExpedition(mission.apiId, e.value, missionName: mission.apiName)
        },
      ));
    }
    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: Text(
        repairText(
            '○: 成功 (数字は大成功率) / ×: 失敗 / -: 艦隊なし\n行をタップすると必要な条件を表示します。判定と大成功率は ElectronicObserver の式による推定です。',
            '○: success (great success rate) / ×: failure / -: no fleet\nTap a row for details. Estimated with ElectronicObserver formulas.'),
        style: secondaryStyle,
      ),
    ));

    return SliverList(delegate: SliverChildListDelegate(children));
  }
}

/// 遠征1件分の行
class ExpeditionCheckRow extends StatelessWidget {
  const ExpeditionCheckRow({super.key, required this.mission, required this.results});

  final GetDataApiDataApiMstMissionEntity mission;
  final Map<int, ExpeditionCheckResult> results;

  @override
  Widget build(BuildContext context) {
    final monthly = mission.apiResetType == 1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => navigatorToCupertino(context, ExpeditionDetailPage(missionId: mission.apiId)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 3, 10, 3),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: CupertinoColors.separator.resolveFrom(context), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                mission.apiDispNo,
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: mission.apiName),
                  if (monthly)
                    TextSpan(
                      text: repairText(' (月)', ' (M)'),
                      style: TextStyle(
                        fontSize: 11,
                        color: CupertinoColors.systemOrange.resolveFrom(context),
                      ),
                    ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            for (final number in kExpeditionFleetNumbers)
              ExpeditionResultCell(result: results[number]!),
          ],
        ),
      ),
    );
  }
}

/// 遠征の詳細 (必要な条件と艦隊ごとの値)
class ExpeditionDetailPage extends ConsumerWidget {
  const ExpeditionDetailPage({super.key, required this.missionId});

  final int missionId;

  static String _duration(int minutes) {
    if (minutes < 60) return repairText('$minutes分', '${minutes}m');
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return repairText('$hours時間', '${hours}h');
    return repairText('$hours時間$rest分', '${hours}h ${rest}m');
  }

  static List<String> get _resourceNames => [
        repairText('燃料', 'Fuel'),
        repairText('弾薬', 'Ammo'),
        repairText('鋼材', 'Steel'),
        repairText('ボーキ', 'Baux'),
      ];

  /// 編成例 (api_sample_fleet の艦種)
  static String sampleFleetText(List<int> sample) {
    final counts = <int, int>{};
    for (final type in sample) {
      if (type > 0) counts[type] = (counts[type] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => '${expeditionShipTypeName(e.key)}×${e.value}')
        .join(repairText('、', ', '));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(kancolleDataProvider);
    final mission = data.dataInfo.missionInfo?[missionId];
    final secondaryStyle = TextStyle(
      fontSize: 12,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    );
    if (mission == null) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(),
        child: SizedBox.shrink(),
      );
    }
    final info = kExpeditionInfo[missionId];
    final requirements = expeditionRequirements(missionId, missionName: mission.apiName);
    final fleets = {
      for (final number in kExpeditionFleetNumbers)
        number: expeditionFleetShips(data.squads, number)
    };
    final results = {
      for (final e in fleets.entries)
        e.key: checkExpedition(missionId, e.value, missionName: mission.apiName)
    };
    final areaName = data.dataInfo.mapAreaInfo?[mission.apiMapareaId]?.name ?? '';
    final items = [
      for (final item in [mission.apiWinItem1, mission.apiWinItem2])
        if (item.length >= 2 && item[0] > 0)
          '${data.dataInfo.itemInfo?[item[0]]?.apiName ?? 'ID ${item[0]}'} ×${item[1]}'
    ];
    final sample = sampleFleetText(mission.apiSampleFleet);

    Widget infoRow(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
            ],
          ),
        );

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        middle: Text('${mission.apiDispNo} ${mission.apiName}'),
      ),
      child: SafeArea(
        bottom: false,
        child: ScrollViewWithCupertinoScrollbar(
          children: [
            CupertinoListSection.insetGrouped(
              margin: tabBottomListMargin,
              footer: mission.apiDetails.isEmpty
                  ? null
                  : Text(mission.apiDetails.replaceAll('<br>', ''), style: secondaryStyle),
              children: [
                infoRow(repairText('海域・時間', 'Area / time'),
                    '$areaName・${_duration(mission.apiTime)}${mission.apiResetType == 1 ? repairText('・マンスリー', ' / monthly') : ''}'),
                infoRow(repairText('消費', 'Cost'),
                    '${_resourceNames[0]} ${(mission.apiUseFuel * 100).round()}%  ${_resourceNames[1]} ${(mission.apiUseBull * 100).round()}%'),
                infoRow(
                  repairText('報酬', 'Reward'),
                  info == null
                      ? (mission.apiName.contains('支援任務')
                          ? repairText('なし (支援遠征)', 'None (support)')
                          : repairText('不明', 'Unknown'))
                      : [
                          for (final (i, amount) in info.resources.indexed)
                            if (amount > 0) '${_resourceNames[i]} $amount'
                        ].join('  '),
                ),
                if (items.isNotEmpty) infoRow(repairText('アイテム', 'Items'), items.join('  ')),
                if (info != null && mission.apiTime > 0)
                  infoRow(
                    repairText('時給 (成功時)', 'Per hour'),
                    [
                      for (final (i, amount) in info.resources.indexed)
                        if (amount > 0) '${_resourceNames[i]} ${(amount * 60 / mission.apiTime).round()}'
                    ].join('  '),
                  ),
                if (info != null)
                  infoRow(repairText('大成功のしくみ', 'Great success'), info.greatSuccessType.label),
                if (sample.isNotEmpty) infoRow(repairText('編成例', 'Sample fleet'), sample),
                if (mission.apiDamageType > 0)
                  infoRow(
                    repairText('戦闘', 'Combat'),
                    mission.apiDamageType == 2
                        ? repairText('あり (必要値の2.2倍以上で被害なし)', 'Yes (no damage at 220% of requirements)')
                        : repairText('あり (被害を受けることがある)', 'Yes (ships may be damaged)'),
                  ),
              ],
            ),
            if (requirements == null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  repairText('この遠征の条件データはまだありません', 'No condition data for this expedition'),
                  style: secondaryStyle,
                ),
              )
            else
              ExpeditionRequirementTable(
                requirements: requirements,
                fleets: fleets,
                results: results,
                showNoDamage: mission.apiDamageType == 2,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Text(
                repairText(
                    '対潜合計は水上偵察機・水上爆撃機・飛行艇の分を数えません。改修値の加算と大成功率は ElectronicObserver の式による推定です。大成功時の報酬は1.5倍です。',
                    'ASW excludes seaplanes and flying boats. Improvement bonuses and great success rates follow ElectronicObserver (estimates). Great success gives 1.5x rewards.'),
                style: secondaryStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 条件の表 (行: 条件, 列: 必要値と第2〜第4艦隊)
class ExpeditionRequirementTable extends StatelessWidget {
  const ExpeditionRequirementTable({
    super.key,
    required this.requirements,
    required this.fleets,
    required this.results,
    this.showNoDamage = false,
  });

  final List<ExpeditionRequirement> requirements;
  final Map<int, List<Ship>> fleets;
  final Map<int, ExpeditionCheckResult> results;
  final bool showNoDamage;

  static const double _valueWidth = 54;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, constraints) => _buildTable(context, narrow: constraints.maxWidth < 360));

  Widget _buildTable(BuildContext context, {required bool narrow}) {
    final valueWidth = narrow ? 44.0 : _valueWidth;
    final requiredWidth = narrow ? 50.0 : 64.0;
    final okColor = CupertinoColors.label.resolveFrom(context);
    final ngColor = CupertinoColors.systemRed.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final greenColor = CupertinoColors.systemGreen.resolveFrom(context);

    Widget cell(String text, {Color? color, FontWeight? weight, double? width}) =>
        SizedBox(
          width: width ?? valueWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(text, style: TextStyle(fontSize: 13, color: color, fontWeight: weight)),
          ),
        );

    Widget row(String label, String required, List<Widget> values, {bool bold = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: CupertinoColors.separator.resolveFrom(context), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : null),
                    overflow: TextOverflow.ellipsis),
              ),
              cell(required, color: secondary, width: requiredWidth),
              ...values,
            ],
          ),
        );

    final fleetNumbers = fleets.keys.toList();
    final views = {for (final e in fleets.entries) e.key: ExpeditionFleet(e.value)};

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(repairText('条件', 'Condition'),
                      style: TextStyle(fontSize: 12, color: secondary)),
                ),
                cell(repairText('必要', 'Need'), color: secondary, width: requiredWidth),
                for (final number in fleetNumbers)
                  cell(repairText('第$number', '#$number'), color: secondary),
              ],
            ),
          ),
          for (final requirement in requirements)
            row(requirement.label, requirement.requiredText, [
              for (final number in fleetNumbers)
                if (views[number]!.isEmpty)
                  cell('-', color: secondary)
                else
                  cell(
                    requirement.actualText(views[number]!),
                    color: requirement.isMet(views[number]!) ? okColor : ngColor,
                  ),
            ]),
          if (results.values.any((r) => r.zeroSlotAircraft))
            row(repairText('搭載数0の機体', 'Empty aircraft slot'), repairText('なし', 'None'), [
              for (final number in fleetNumbers)
                cell(results[number]!.zeroSlotAircraft ? repairText('あり', 'Yes') : '-',
                    color: results[number]!.zeroSlotAircraft ? ngColor : secondary),
            ]),
          row(repairText('判定', 'Result'), '', bold: true, [
            for (final number in fleetNumbers)
              cell(
                results[number]!.emptyFleet
                    ? '-'
                    : results[number]!.success
                        ? repairText('成功', 'OK')
                        : repairText('失敗', 'NG'),
                color: results[number]!.emptyFleet
                    ? secondary
                    : results[number]!.success
                        ? greenColor
                        : ngColor,
                weight: FontWeight.w600,
              ),
          ]),
          row(repairText('大成功率', 'Great success'), '', [
            for (final number in fleetNumbers)
              cell(
                results[number]!.greatSuccessRate == null
                    ? '-'
                    : '${(results[number]!.greatSuccessRate! * 100).toStringAsFixed(1)}%',
                color: results[number]!.greatSuccessRate == null ? secondary : greenColor,
              ),
          ]),
          row(repairText('キラ付け', 'Sparkled'), '', [
            for (final number in fleetNumbers)
              cell(
                views[number]!.isEmpty
                    ? '-'
                    : '${views[number]!.sparkleCount}/${views[number]!.shipCount}',
                color: secondary,
              ),
          ]),
          if (showNoDamage)
            row(repairText('被害なし (2.2倍)', 'No damage (220%)'), '', [
              for (final number in fleetNumbers)
                cell(
                  results[number]!.emptyFleet ? '-' : (results[number]!.noDamage ? '○' : '×'),
                  color: results[number]!.noDamage ? greenColor : secondary,
                ),
            ]),
        ],
      ),
    );
  }
}
