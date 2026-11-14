import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/feature/kancolle/senka.dart';
import 'package:conning_tower/widgets/kancolle_quest_detail_page.dart';
import 'package:flutter/cupertino.dart';

/// 戦果の表示 (小数2桁まで。12.50 → 12.5、3.00 → 3)
String senkaText(num value) => value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

String _two(int n) => n.toString().padLeft(2, '0');

/// 半日の見出し (11/14 02:00〜14:00)。端末の時刻で出す
String senkaSessionLabel(DateTime start, DateTime end) {
  final s = start.toLocal();
  final e = end.toLocal();
  return '${s.month}/${s.day} ${_two(s.hour)}:${_two(s.minute)}〜${_two(e.hour)}:${_two(e.minute)}';
}

/// 戦果の月の見出し (月の締めの翌日が属する月)
String senkaMonthLabel(DateTime monthStart) {
  final d = monthStart.toUtc().add(const Duration(days: 1));
  return repairText('${d.year}年${d.month}月', '${d.year}-${_two(d.month)}');
}

String _breakdown(double normal, int eo, int quest) => repairText(
    '通常 ${senkaText(normal)}・EO ${senkaText(eo)}・任務 ${senkaText(quest)}',
    'Normal ${senkaText(normal)}, EO ${senkaText(eo)}, quests ${senkaText(quest)}');

/// 戦果ビューア: 半日ごとの戦果 (通常・EO・任務) と、今日・月ごとの合計
class SenkaPage extends StatelessWidget {
  const SenkaPage({super.key, required this.admiralName, this.store, this.now});

  final String admiralName;
  final SenkaStore? store;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? senkaStore;
    final secondary = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(middle: Text(repairText('戦果', 'Ranking points'))),
      child: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<int>(
          valueListenable: store.revision,
          builder: (context, _, __) {
            final time = (now ?? DateTime.now)();
            final records = store.recordsOf(admiralName);
            final today = senkaTotal(records, from: senkaDayStart(time));
            final month = senkaTotal(records, from: senkaMonthStart(time));
            final currentStart = senkaSessionStart(time);
            // 月ごとにまとめる (新しい順)
            final months = <DateTime, List<SenkaRecord>>{};
            for (final r in records) {
              (months[senkaMonthStart(r.start)] ??= []).add(r);
            }
            return CupertinoScrollbar(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  QuestDetailSection(
                    title: repairText('合計', 'Totals'),
                    children: [
                      CupertinoListTile(
                        title: Text(repairText('今日 (2:00 から)', 'Today (from 2:00)'), style: const TextStyle(fontSize: 14)),
                        subtitle: Text(_breakdown(today.normal, today.eo, today.quest)),
                        additionalInfo: Text(senkaText(today.total)),
                      ),
                      CupertinoListTile(
                        title: Text(repairText('今月 (${senkaMonthLabel(senkaMonthStart(time))})', 'This month'),
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Text(_breakdown(month.normal, month.eo, month.quest)),
                        additionalInfo: Text(senkaText(month.total)),
                      ),
                    ],
                  ),
                  if (records.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Text(repairText('まだ記録がありません。母港に戻ると記録が始まります', 'No records yet. Recording starts at the port.'),
                          style: secondary),
                    ),
                  for (final MapEntry(key: monthStart, value: list) in months.entries)
                    () {
                      final total = senkaTotal(list);
                      return QuestDetailSection(
                        title: repairText('${senkaMonthLabel(monthStart)} 合計 ${senkaText(total.total)}',
                            '${senkaMonthLabel(monthStart)} total ${senkaText(total.total)}'),
                        footer: _breakdown(total.normal, total.eo, total.quest),
                        children: [
                          for (final r in list)
                            CupertinoListTile(
                              title: Text(
                                '${senkaSessionLabel(r.start, r.end)}${r.start == currentStart ? repairText(' (今)', ' (now)') : ''}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                '${_breakdown(r.normal, r.eo, r.quest)}\n'
                                '${repairText('提督経験値 +${r.expGain}', 'HQ exp +${r.expGain}')}',
                                maxLines: 2,
                              ),
                              additionalInfo: Text(senkaText(r.total)),
                            ),
                        ],
                      );
                    }(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      repairText(
                          '半日ごと (14:00 と 2:00 で区切り、月末は 22:00 で締め) の戦果です。通常の戦果は 提督経験値の増加 × 7 ÷ 10000。'
                              'このアプリで見た通信から記録するので、記録を始める前の分は出ません。'
                              'ほかの端末で遊んだ分は、通常の戦果だけ次に母港を開いた半日にまとめて入り、EO・任務の戦果は入りません。'
                              '前月からの引き継ぎ分は含みません。区切りと式は ElectronicObserver (MIT) の戦果ビューアに合わせています。',
                          'Ranking points per half day (cut at 14:00 and 2:00 JST, months end at 22:00 JST). '
                              'Normal points = HQ exp gained x 7 / 10000. Only what this app has seen is recorded. '
                              'Follows the ElectronicObserver (MIT) senka viewer.'),
                      style: secondary,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
