import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/perf_monitor.dart';
import 'package:conning_tower/utils/toast.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

String _ms(int micros) => (micros / 1000).toStringAsFixed(1);

String _time(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

/// 記録をテキストにする (コピーして貼り付けられるように)
String perfReportText(PerfMonitor m) {
  final lines = <String>[
    '計測開始 ${m.since == null ? '-' : _time(m.since!)}',
    'フレーム ${m.frames} / 重いフレーム ${m.slowFrameCount}',
    '[重かった通信] 回数・読み込み 平均/最大・作り直し 平均/最大 (ms)',
    for (final s in m.slowestApis.take(15))
      '${s.path} ${s.count}回 読込 ${_ms(s.parseTotal ~/ s.count)}/${_ms(s.parseMax)} 作直 ${_ms(s.buildTotal ~/ s.count)}/${_ms(s.buildMax)}',
    '[最近の重いフレーム] 処理/描画 (ms)',
    for (final f in m.slowFrames.reversed)
      '${_time(f.at)} ${f.build.toStringAsFixed(1)}/${f.raster.toStringAsFixed(1)}${f.lastPath == null ? '' : ' 直前 ${f.lastPath}'}',
  ];
  return lines.join('\n');
}

/// 設定 → 動作の重さ: ゲームのデータの処理と画面の作り直しにかかった時間
class PerfPage extends StatelessWidget {
  const PerfPage({super.key, this.monitor});

  final PerfMonitor? monitor;

  @override
  Widget build(BuildContext context) {
    final m = monitor ?? PerfMonitor.instance;
    final secondary = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        middle: Text(repairText('動作の重さ', 'Performance')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(repairText('コピー', 'Copy')),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: perfReportText(m)));
              Toast.showSuccess(title: repairText('コピーしました', 'Copied'));
            },
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: m.reset,
            child: Text(repairText('リセット', 'Reset')),
          ),
        ]),
      ),
      child: SafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: m.revision,
          builder: (context, _, __) {
            final apis = m.slowestApis.take(15).toList();
            final rate = m.frames == 0 ? 0 : m.slowFrameCount / m.frames * 100;
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                CupertinoListSection.insetGrouped(
                  header: Text(repairText('全体', 'Overview')),
                  footer: Text(
                    repairText(
                        '1フレームが ${PerfMonitor.slowFrameMs.round()}ms を超えると、カクついて見えます。「処理」はアプリの計算、「描画」は画面に描く時間です。'
                            'ゲーム画面そのもの (ブラウザの中) の重さは測れません。記録はアプリを閉じると消えます',
                        'Frames over ${PerfMonitor.slowFrameMs.round()} ms look janky. The game page itself cannot be measured.'),
                    style: secondary,
                  ),
                  children: [
                    CupertinoListTile(
                      title: Text(repairText('計測開始', 'Since')),
                      additionalInfo: Text(m.since == null ? '-' : _time(m.since!)),
                    ),
                    CupertinoListTile(
                      title: Text(repairText('重いフレーム', 'Slow frames')),
                      additionalInfo: Text('${m.slowFrameCount} / ${m.frames} (${rate.toStringAsFixed(1)}%)'),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  header: Text(repairText('重かった通信 (1回の最大の順)', 'Slowest game data')),
                  footer: Text(
                    repairText('読み込み = 届いたデータを読んで覚えるまで。作り直し = その直後に画面を作り直した時間。平均 / 最大 (ms)',
                        'Parse = reading the data. Rebuild = the next frame. Average / max (ms)'),
                    style: secondary,
                  ),
                  children: [
                    if (apis.isEmpty) CupertinoListTile(title: Text(repairText('まだ記録がありません', 'No records yet'), style: secondary)),
                    for (final s in apis)
                      CupertinoListTile(
                        title: Text(s.path, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                          repairText(
                              '読み込み ${_ms(s.parseTotal ~/ s.count)} / ${_ms(s.parseMax)}・作り直し ${_ms(s.buildTotal ~/ s.count)} / ${_ms(s.buildMax)}',
                              'Parse ${_ms(s.parseTotal ~/ s.count)} / ${_ms(s.parseMax)}, rebuild ${_ms(s.buildTotal ~/ s.count)} / ${_ms(s.buildMax)}'),
                        ),
                        additionalInfo: Text(repairText('${s.count}回', '${s.count}')),
                      ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  header: Text(repairText('最近の重いフレーム', 'Recent slow frames')),
                  children: [
                    if (m.slowFrames.isEmpty)
                      CupertinoListTile(title: Text(repairText('まだ記録がありません', 'No records yet'), style: secondary)),
                    for (final f in m.slowFrames.reversed)
                      CupertinoListTile(
                        title: Text(
                          repairText('処理 ${f.build.toStringAsFixed(1)}ms・描画 ${f.raster.toStringAsFixed(1)}ms',
                              'Build ${f.build.toStringAsFixed(1)} ms, raster ${f.raster.toStringAsFixed(1)} ms'),
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: f.lastPath == null ? null : Text(repairText('直前の通信 ${f.lastPath}', 'After ${f.lastPath}')),
                        additionalInfo: Text(_time(f.at)),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
