import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/models/feature/kancolle/air_battle_record.dart';
import 'package:conning_tower/models/feature/kancolle/anti_air_cut_in.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _airSuperiorityText(int? flag) => switch (flag) {
      0 => S.current.KCAirBattleParity,
      1 => S.current.KCAirBattleSupremacy,
      2 => S.current.KCAirBattleSuperiority,
      3 => S.current.KCAirBattleDenial,
      4 => S.current.KCAirBattleIncapability,
      _ => '',
    };

/// 戦闘情報タブの末尾の「航空戦」: 各航空戦の機数と撃墜された数、発動した対空カットイン。
/// 戦闘情報タブの中身は最初の build の変数を使い続けるので、ここで最新のデータを読む
class KancolleAirBattleSection extends ConsumerWidget {
  const KancolleAirBattleSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(kancolleDataProvider);
    final phases = data.airBattle.phases;
    if (phases.isEmpty) return const SizedBox.shrink();
    final battleInfo = data.battleInfo;
    final shipInfo = data.dataInfo.shipInfo;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final secondaryStyle = TextStyle(fontSize: 12, color: secondary);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final red = CupertinoColors.systemRed.resolveFrom(context);

    Ship? findShip(int? uid) {
      if (uid == null) return null;
      final ships = [
        for (final squad in [...?battleInfo.inBattleSquads, ...?battleInfo.friendSquads]) ...squad.ships,
      ];
      return ships.where((s) => s.uid == uid).firstOrNull;
    }

    String cutInText(AirBattleCutIn cutIn) {
      final kind = kAntiAirCutInKinds.where((k) => k.id == cutIn.kind).firstOrNull;
      final ship = findShip(cutIn.shipUid);
      final condition = kind == null
          ? null
          : (ship == null
                  ? null
                  : kind.matchingCondition(
                      ship.shipId, shipInfo?[ship.shipId]?.apiCtype, [...?ship.equipment])) ??
              kind.conditions.firstOrNull;
      final name = cutIn.shipName.isEmpty ? repairText('${cutIn.shipIndex + 1}番艦', 'Ship ${cutIn.shipIndex + 1}') : cutIn.shipName;
      final kindText = repairText('第${cutIn.kind}種', 'Type ${cutIn.kind}');
      final detail = [
        if (condition != null) condition.description,
        if (kind != null) repairText('固定撃墜+${kind.fixedBonus} / 割合×${kind.variableBonus}', 'fixed +${kind.fixedBonus}, x${kind.variableBonus}'),
      ].join('　');
      return detail.isEmpty ? '$name: $kindText' : '$name: $kindText\n$detail';
    }

    Widget stageLine(String title, AirBattleStage stage) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$title  ', style: secondaryStyle),
              TextSpan(text: repairText('味方 ${stage.friendCount}機 ', 'Ours ${stage.friendCount} ')),
              TextSpan(text: '−${stage.friendLost}', style: TextStyle(color: stage.friendLost > 0 ? red : null)),
              const TextSpan(text: '  /  '),
              TextSpan(text: repairText('敵 ${stage.enemyCount}機 ', 'Enemy ${stage.enemyCount} ')),
              TextSpan(text: '−${stage.enemyLost}', style: TextStyle(color: stage.enemyLost > 0 ? green : null)),
            ]),
            style: const TextStyle(fontSize: 13),
          ),
        );

    return CupertinoListSection.insetGrouped(
      header: Text(repairText('航空戦', 'Air battle')),
      footer: Text(
        repairText('機数は戦闘開始時、−は撃墜された数です。空対空 = 艦載機同士の戦闘、対空砲火 = 艦隊の対空射撃。',
            'Counts at the start; − = shot down. Stage 1 = air-to-air, stage 2 = anti-air fire.'),
        style: secondaryStyle,
      ),
      children: [
        for (final phase in phases)
          CupertinoListTile(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 12, 6),
            title: Text(phase.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            additionalInfo: phase.airSuperiority == null ? null : Text(_airSuperiorityText(phase.airSuperiority)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (phase.stage1 case final stage1?) stageLine(repairText('空対空', 'Air'), stage1),
                if (phase.stage2 case final stage2?) stageLine(repairText('対空砲火', 'AA fire'), stage2),
                if (phase.cutIn case final cutIn?)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: repairText('対空CI  ', 'AACI  '), style: secondaryStyle),
                        TextSpan(text: cutInText(cutIn)),
                      ]),
                      softWrap: true,
                      style: TextStyle(fontSize: 13, color: CupertinoColors.label.resolveFrom(context)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
