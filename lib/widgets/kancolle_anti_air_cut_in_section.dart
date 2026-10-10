import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/anti_air_cut_in.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/widgets/components/edge_insets_constants.dart';
import 'package:flutter/cupertino.dart';

String antiAirCutInRateText(double? rate) {
  if (rate == null) return repairText('不明', 'Unknown');
  return '${(rate * 100).toStringAsFixed(1)}%';
}

/// 艦隊タブの合計欄に出す「対空カットイン」の値
String fleetAntiAirCutInText(
    List<Ship> ships, Map<int, GetDataApiDataApiMstShipEntity>? shipInfo) {
  final hasAny = ships.any((s) =>
      !shipAntiAirCutIns(s, shipClass: shipInfo?[s.shipId]?.apiCtype).isEmpty);
  if (!hasAny) return repairText('なし', 'None');
  return antiAirCutInRateText(fleetAntiAirCutInRate(ships, shipInfo));
}

/// 対空カットインの種別と発動率 (艦娘の詳細画面)。発動できる種別がなければ何も出さない
class KancolleAntiAirCutInSection extends StatelessWidget {
  const KancolleAntiAirCutInSection({
    super.key,
    required this.ship,
    required this.shipInfo,
  });

  final Ship ship;
  final Map<int, GetDataApiDataApiMstShipEntity>? shipInfo;

  @override
  Widget build(BuildContext context) {
    final result = shipAntiAirCutIns(ship, shipClass: shipInfo?[ship.shipId]?.apiCtype);
    if (result.isEmpty) return const SizedBox.shrink();
    final secondaryStyle = TextStyle(
      fontSize: 12,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    );

    return CupertinoListSection.insetGrouped(
      margin: tabBottomListMargin,
      header: Text(repairText('対空カットイン (推定)', 'Anti-air cut-in (estimate)')),
      footer: Text(
        repairText(
            '左: 実際に出る確率 / 右: その種別だけの発動率\n優先順位の高い種別から判定し、出なかったら次の種別を判定するとした推定値です。1回の航空戦で発動するのは艦隊で1隻だけです。',
            'Left: chance to trigger / right: rate of the kind alone\nKinds are checked in priority order. Only one ship per fleet triggers per air battle.'),
        style: secondaryStyle,
      ),
      children: [
        for (final chance in result.chances)
          CupertinoListTile(
            title: Text(
              repairText('第${chance.kind.id}種', 'Type ${chance.kind.id}'),
              style: const TextStyle(fontSize: 15),
            ),
            subtitle: Text(
              '${chance.condition.description}\n${repairText('固定', 'Fixed')} +${chance.kind.fixedBonus} / ${repairText('変動', 'Variable')} ×${chance.kind.variableBonus}',
              maxLines: 3,
              style: secondaryStyle,
            ),
            additionalInfo: Text(
              '${antiAirCutInRateText(chance.effectiveRate)} / ${antiAirCutInRateText(chance.rate)}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        CupertinoListTile(
          title: Text(repairText('合計 (この艦)', 'Total (this ship)')),
          additionalInfo: Text(antiAirCutInRateText(result.total)),
        ),
      ],
    );
  }
}
