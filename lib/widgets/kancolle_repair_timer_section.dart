import 'dart:async';

import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/widgets/components/edge_insets_constants.dart';
import 'package:flutter/cupertino.dart';

/// 泊地修理 / 給糧艦(野埼) のタイマー表示 (艦隊タブ)
class KancolleRepairTimerSection extends StatefulWidget {
  const KancolleRepairTimerSection({
    super.key,
    required this.squad,
    required this.repairTimer,
    required this.shipInfo,
  });

  final Squad squad;
  final RepairTimerState repairTimer;
  final Map<int, GetDataApiDataApiMstShipEntity>? shipInfo;

  @override
  State<KancolleRepairTimerSection> createState() => _KancolleRepairTimerSectionState();
}

class _KancolleRepairTimerSectionState extends State<KancolleRepairTimerSection> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _format(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final squad = widget.squad;
    final repairTimer = widget.repairTimer;
    final now = DateTime.now();
    final children = <Widget>[];

    final info = repairTimer.anchorageRepairInfo(squad);
    final anchorageTimer = repairTimer.anchorageRepairTimer;
    if (info != null && anchorageTimer != null) {
      final elapsed = now.difference(anchorageTimer);
      final ready = elapsed >= kAnchorageRepairSpan;
      children.add(CupertinoListTile(
        leading: const Icon(CupertinoIcons.wrench),
        title: Text(repairText('泊地修理', 'Anchorage repair')),
        subtitle: Text(repairText(
            '対象 ${info.bound}隻${info.is1st2ndRepairShip ? ' / 時間×0.85' : ''}',
            'Targets: ${info.bound}${info.is1st2ndRepairShip ? ' / time x0.85' : ''}')),
        additionalInfo: Text(
          '${repairText('経過', 'Elapsed')} ${_format(elapsed)}',
          style: ready ? const TextStyle(color: CupertinoColors.activeGreen) : null,
        ),
      ));
      if (info.targets.isEmpty) {
        children.add(CupertinoListTile(
          title: Text(repairText('修理が必要な対象艦なし', 'No ship needs repair')),
        ));
      }
      for (final target in info.targets) {
        final ship = target.ship;
        String detail;
        if (!target.eligible) {
          detail = repairText('中破以上のため対象外', 'Too damaged');
        } else if (target.dockingSeconds <= 0) {
          detail = '--';
        } else {
          final heal = ready
              ? RepairTimerState.healAmount(
                  target.damage, target.dockingSeconds, elapsed, info.is1st2ndRepairShip)
              : 0;
          if (heal >= target.damage) {
            detail = repairText('+$heal 全快', '+$heal full');
          } else {
            final next = anchorageTimer.add(RepairTimerState.repairTime(
                target.damage, target.dockingSeconds, heal + 1, info.is1st2ndRepairShip));
            detail = repairText('+$heal (+1まで ${_format(next.difference(now))})',
                '+$heal (+1 in ${_format(next.difference(now))})');
          }
        }
        children.add(CupertinoListTile(
          title: Text('#${target.index + 1} ${ship.name ?? ''}'),
          subtitle: Text('HP ${ship.nowHP}/${ship.maxHP}'),
          additionalInfo: Text(detail),
        ));
      }
    }

    final conditionTimer = repairTimer.conditionRepairTimer;
    if (conditionTimer != null && repairTimer.canConditionRepair(squad, widget.shipInfo)) {
      final elapsed = now.difference(conditionTimer);
      final ready = elapsed >= kConditionRepairSpan;
      children.add(CupertinoListTile(
        leading: const Icon(CupertinoIcons.cart),
        title: Text(repairText('給糧艦(野埼)', 'Nosaki')),
        subtitle: Text(ready
            ? repairText('母港に戻ると回復', 'Return to port to recover')
            : repairText('回復まで ${_format(conditionTimer.add(kConditionRepairSpan).difference(now))}',
                'Recover in ${_format(conditionTimer.add(kConditionRepairSpan).difference(now))}')),
        additionalInfo: Text(
          '${repairText('経過', 'Elapsed')} ${_format(elapsed)}',
          style: ready ? const TextStyle(color: CupertinoColors.activeGreen) : null,
        ),
      ));
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return CupertinoListSection.insetGrouped(
      margin: tabBottomListMargin,
      children: children,
    );
  }
}
