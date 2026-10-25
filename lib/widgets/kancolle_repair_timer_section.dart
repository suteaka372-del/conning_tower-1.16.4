import 'package:conning_tower/providers/dashboard_tab_provider.dart';
import 'dart:async';

import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/widgets/components/edge_insets_constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 泊地修理 / 給糧艦(野埼) のタイマー表示 (艦隊タブ)。
/// 工作艦・野埼の艦隊を編成記録で外している間は、第1艦隊のタブに表示を続ける。
/// 艦隊タブの中身は最初の build の変数を使い続けるので、ここで最新のデータを読む
class KancolleRepairTimerSection extends ConsumerStatefulWidget {
  const KancolleRepairTimerSection({super.key, required this.squadIndex});

  /// 0 = 第1艦隊
  final int squadIndex;

  @override
  ConsumerState<KancolleRepairTimerSection> createState() => _KancolleRepairTimerSectionState();
}

class _KancolleRepairTimerSectionState extends ConsumerState<KancolleRepairTimerSection> {
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

  Widget _dismissButton(VoidCallback onPressed) => CupertinoButton(
        padding: const EdgeInsets.only(left: 8),
        minSize: 28,
        onPressed: onPressed,
        child: Icon(CupertinoIcons.xmark_circle_fill,
            size: 20, color: CupertinoColors.tertiaryLabel.resolveFrom(context)),
      );

  /// 泊地修理の行と、修理対象の艦の行
  void _addAnchorageRows(List<Widget> children, RepairTimerState repairTimer, Squad squad, DateTime now,
      {bool away = false}) {
    final info = repairTimer.anchorageRepairInfo(squad);
    final reason = repairTimer.anchorageRepairBlockedReason(squad);
    final anchorageTimer = repairTimer.anchorageRepairTimer;
    final elapsed = anchorageTimer == null ? null : now.difference(anchorageTimer);
    final ready = elapsed != null && elapsed >= kAnchorageRepairSpan;
    String subtitle;
    if (reason != null) {
      subtitle = reason;
    } else if (anchorageTimer == null) {
      subtitle = repairText('母港に戻ると計測を開始します', 'Starts when you return to port');
    } else if (away) {
      final flagship = squad.ships.first.name ?? '';
      subtitle = ready
          ? repairText('$flagshipの艦隊を編成記録で戻して母港に戻ると回復', 'Load the $flagship preset and return to port')
          : repairText('$flagshipの艦隊を編成記録で外しています', 'The $flagship fleet is stored in a preset');
    } else {
      subtitle = repairText(
          '対象 ${info!.bound}隻${info.is1st2ndRepairShip ? ' / 時間×0.85' : ''}',
          'Targets: ${info.bound}${info.is1st2ndRepairShip ? ' / time x0.85' : ''}');
    }
    final elapsedText = Text(
      elapsed == null ? '--:--' : '${repairText('経過', 'Elapsed')} ${_format(elapsed)}',
      style: ready && reason == null ? const TextStyle(color: CupertinoColors.activeGreen) : null,
    );
    children.add(CupertinoListTile(
      leading: const Icon(CupertinoIcons.wrench),
      title: Text(away ? repairText('泊地修理 (外し中)', 'Anchorage repair (stored)') : repairText('泊地修理', 'Anchorage repair')),
      subtitle: Text(subtitle, maxLines: 2),
      additionalInfo: elapsedText,
      trailing: away
          ? _dismissButton(() {
              repairTimer.anchorageAwayDismissed = true;
              ref.read(kancolleDataProvider).saveRepairTimer();
              setState(() {});
            })
          : null,
    ));
    if (info == null || anchorageTimer == null || elapsed == null) return;
    for (final target in info.targets) {
      final ship = target.ship;
      String detail;
      if (!target.eligible) {
        detail = repairText('中破以上のため対象外', 'Too damaged');
      } else if (target.dockingSeconds <= 0) {
        detail = '--';
      } else {
        final heal = ready
            ? RepairTimerState.healAmount(target.damage, target.dockingSeconds, elapsed, info.is1st2ndRepairShip)
            : 0;
        if (heal >= target.damage) {
          detail = repairText('+$heal 全快', '+$heal full');
        } else {
          final next = anchorageTimer.add(
              RepairTimerState.repairTime(target.damage, target.dockingSeconds, heal + 1, info.is1st2ndRepairShip));
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

  void _addConditionRow(List<Widget> children, RepairTimerState repairTimer, DateTime now,
      {String? reason, bool away = false}) {
    final conditionTimer = repairTimer.conditionRepairTimer;
    final elapsed = conditionTimer == null ? null : now.difference(conditionTimer);
    final ready = elapsed != null && elapsed >= kConditionRepairSpan;
    String subtitle;
    if (reason != null) {
      subtitle = reason;
    } else if (conditionTimer == null) {
      subtitle = repairText('母港に戻ると計測を開始します', 'Starts when you return to port');
    } else if (ready) {
      subtitle = away
          ? repairText('野埼の艦隊を編成記録で戻して母港に戻ると回復', 'Load the Nosaki preset and return to port')
          : repairText('母港に戻ると回復', 'Return to port to recover');
    } else {
      final remain = _format(conditionTimer.add(kConditionRepairSpan).difference(now));
      subtitle = away
          ? repairText('野埼の艦隊を編成記録で外しています (あと $remain)', 'Nosaki fleet stored in a preset ($remain)')
          : repairText('回復まで $remain', 'Recover in $remain');
    }
    children.add(CupertinoListTile(
      leading: const Icon(CupertinoIcons.cart),
      title: Text(away ? repairText('給糧艦(野埼) (外し中)', 'Nosaki (stored)') : repairText('給糧艦(野埼)', 'Nosaki')),
      subtitle: Text(subtitle, maxLines: 2),
      additionalInfo: Text(
        elapsed == null ? '--:--' : '${repairText('経過', 'Elapsed')} ${_format(elapsed)}',
        style: ready && reason == null ? const TextStyle(color: CupertinoColors.activeGreen) : null,
      ),
      trailing: away
          ? _dismissButton(() {
              repairTimer.conditionAwayDismissed = true;
              ref.read(kancolleDataProvider).saveRepairTimer();
              setState(() {});
            })
          : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final data = watchKancolleData(ref, context);
    final squads = data.squads;
    if (widget.squadIndex < 0 || widget.squadIndex >= squads.length) return const SizedBox.shrink();
    final squad = squads[widget.squadIndex];
    final repairTimer = data.repairTimer;
    final shipInfo = data.dataInfo.shipInfo;
    final now = DateTime.now();
    final children = <Widget>[];

    // 泊地修理: 旗艦が工作艦なら常に表示
    if (RepairTimerState.hasRepairShipFlagship(squad)) {
      _addAnchorageRows(children, repairTimer, squad, now);
    }

    // 給糧艦(野埼): 旗艦か2番艦にいれば常に表示
    if (RepairTimerState.hasNosaki(squad)) {
      _addConditionRow(children, repairTimer, now, reason: repairTimer.conditionRepairBlockedReason(squad, shipInfo));
    }

    // 編成記録で外している間は第1艦隊に表示する (タイマーはリセットされずに続く)
    if (widget.squadIndex == 0) {
      if (repairTimer.showAnchorageAway(squads)) {
        final remembered = repairTimer.rememberedAnchorageSquad(data.fleet.ships);
        if (remembered != null) _addAnchorageRows(children, repairTimer, remembered, now, away: true);
      }
      if (repairTimer.showConditionAway(squads)) {
        _addConditionRow(children, repairTimer, now, away: true);
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return CupertinoListSection.insetGrouped(
      margin: tabBottomListMargin,
      children: children,
    );
  }
}
