import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/attack_rate.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/widgets/components/edge_insets_constants.dart';
import 'package:flutter/cupertino.dart';

/// 昼戦・夜戦の攻撃種別と発動率 (艦娘の詳細画面)
class KancolleAttackRateSection extends StatelessWidget {
  const KancolleAttackRateSection({
    super.key,
    required this.ship,
    required this.squad,
    required this.shipInfo,
  });

  final Ship ship;
  final Squad squad;
  final Map<int, GetDataApiDataApiMstShipEntity>? shipInfo;

  static String _percent(double value) => '${value.toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final ShipAttackRates rates;
    try {
      rates = AttackRateCalculator.calculate(ship: ship, squad: squad, shipInfo: shipInfo);
    } catch (e) {
      return const SizedBox.shrink();
    }
    final secondaryStyle = TextStyle(
      fontSize: 13,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    );

    return Column(
      children: [
        CupertinoListSection.insetGrouped(
          margin: tabBottomListMargin,
          header: Text(repairText('昼戦 発動率', 'Day battle trigger rate')),
          footer: Text(
            repairText('左: 制空権確保 / 右: 航空優勢\n弾着観測射撃は制空権確保・優勢時のみ',
                'Left: air supremacy / Right: air superiority'),
            style: secondaryStyle,
          ),
          children: [
            if (rates.day.isEmpty)
              CupertinoListTile(title: Text(repairText('攻撃不能', 'Cannot attack'))),
            for (final rate in rates.day)
              CupertinoListTile(
                title: Text(rate.kind.label),
                additionalInfo: Text(rate.rateAS == null
                    ? _percent(rate.rate)
                    : '${_percent(rate.rate)} / ${_percent(rate.rateAS!)}'),
              ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          margin: tabBottomListMargin,
          header: Text(repairText('夜戦 発動率', 'Night battle trigger rate')),
          footer: Text(
            repairText('ElectronicObserver の計算式を移植した推定値です', 'Estimated with ElectronicObserver formulas'),
            style: secondaryStyle,
          ),
          children: [
            if (!rates.canAttackAtNight || rates.night.isEmpty)
              CupertinoListTile(title: Text(repairText('攻撃不能', 'Cannot attack'))),
            if (rates.canAttackAtNight)
              for (final rate in rates.night)
                CupertinoListTile(
                  title: Text(rate.kind.label),
                  additionalInfo: Text(_percent(rate.rate)),
                ),
          ],
        ),
      ],
    );
  }
}
