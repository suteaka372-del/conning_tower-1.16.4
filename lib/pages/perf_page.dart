import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/perf_monitor.dart';
import 'package:conning_tower/providers/game_stop_log.dart';
import 'package:conning_tower/utils/toast.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

String _ms(int micros) => (micros / 1000).toStringAsFixed(1);

String _time(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

/// 記録をテキストにする (コピーして貼り付けられるように)
String perfReportText(PerfMonitor m, {List<GameStop> stops = const [], double? displayRate}) {
  final lines = <String>[
    '計測開始 ${m.since == null ? '-' : _time(m.since!)}',
    if (m.gameFrameRate != null || displayRate != null)
      'ゲーム画面の描画 ${m.gameFrameRate ?? '-'}回/秒 (画面の最大 ${displayRate?.round() ?? '-'})',
    if (stops.isNotEmpty) 'ゲーム画面が止まった ${stops.length}回: ${[for (final s in stops.reversed.take(10)) gameStopText(s)].join('、')}',
    'フレーム ${m.frames} / 重いフレーム ${m.slowFrameCount}',
    '描き直し 平均 ${m.frameRate.toStringAsFixed(1)}回/秒',
    if (m.frameRates.isNotEmpty) '  タブ別 ${perfFrameRatesText(m)}',
    if (m.battleFrameRate != null) '  戦闘中 ${m.battleFrameRate!.toStringAsFixed(1)}回/秒 (${m.battleTime.inSeconds}秒)',
    if (m.events.isNotEmpty) 'ゲーム画面からの知らせ ${perfEventsText(m)}',
    '[重かった通信] 回数・読み込み 平均/最大・作り直し 平均/最大 (ms)',
    for (final s in m.slowestApis.take(15)) ...[
      '${s.path} ${s.count}回 読込 ${_ms(s.parseTotal ~/ s.count)}/${_ms(s.parseMax)} 作直 ${_ms(s.buildTotal ~/ s.count)}/${_ms(s.buildMax)}',
      if (perfStagesText(s).isNotEmpty) '  内訳 ${perfStagesText(s)}',
    ],
    '[最近の重いフレーム] 処理/描画 (ms)',
    for (final f in m.slowFrames.reversed)
      '${_time(f.at)} ${f.build.toStringAsFixed(1)}/${f.raster.toStringAsFixed(1)}'
          '${f.screen == null ? '' : ' 画面 ${f.screen}'}${f.lastPath == null ? '' : ' 直前 ${f.lastPath}'}',
  ];
  return lines.join('\n');
}

String _date(DateTime t) => '${t.month}/${t.day} ${_time(t).substring(0, 5)}';

/// 止まった1回 (11/21 23:05 音あり BGM30・効果音40・ボイス60)
String gameStopText(GameStop s) {
  final v = s.volumes;
  final sound = switch (s.soundOn) {
    true => repairText('音あり', 'sound on'),
    false => repairText('ミュート', 'muted'),
    null => repairText('音量不明', 'volume unknown'),
  };
  return '${_date(s.at)} $sound${v == null || s.soundOn == false ? '' : repairText(' BGM${v.bgm}・効果音${v.se}・ボイス${v.voice}', ' BGM ${v.bgm}, SE ${v.se}, voice ${v.voice}')}';
}

/// ゲーム画面からの知らせ (種類ごとの回数、多い順)
String perfEventsText(PerfMonitor m) =>
    ([...m.events.entries]..sort((a, b) => b.value.compareTo(a.value))).map((e) => '${e.key} ${e.value}').join('・');

/// タブ別の1秒あたりの描き直しの回数 (多い順)
String perfFrameRatesText(PerfMonitor m) =>
    [for (final (name, rate) in m.frameRates) '$name ${rate.toStringAsFixed(1)}'].join('・');

/// 読み込みの内訳 (0.5ms 以上の段階を平均の長い順に。平均/最大)
String perfStagesText(PerfApiStat s) => [
      for (final (name, average, max) in s.stages)
        if (max >= 500) '$name ${_ms(average)}/${_ms(max)}',
    ].join('・');

/// 設定 → 動作の重さ: ゲームのデータの処理と画面の作り直しにかかった時間
class PerfPage extends StatelessWidget {
  const PerfPage({super.key, this.monitor, this.stopLog});

  final PerfMonitor? monitor;
  final GameStopLog? stopLog;

  @override
  Widget build(BuildContext context) {
    final m = monitor ?? PerfMonitor.instance;
    final log = stopLog ?? gameStopLog;
    final displayRate = View.of(context).display.refreshRate;
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
              Clipboard.setData(ClipboardData(text: perfReportText(m, stops: log.stops, displayRate: displayRate)));
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
        child: ListenableBuilder(
          listenable: Listenable.merge([m.revision, log.revision]),
          builder: (context, _) {
            final apis = m.slowestApis.take(15).toList();
            final rate = m.frames == 0 ? 0 : m.slowFrameCount / m.frames * 100;
            final stops = log.stops;
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                CupertinoListSection.insetGrouped(
                  header: Text(repairText('ゲーム画面', 'Game page')),
                  footer: Text(
                    repairText(
                        'ゲーム画面 (ブラウザ) が1秒に何回描いているか。ゲームを表示したまま「測る」を押してください (1秒かかります)。'
                            'Safari はふつう 60 回までに抑えています。止まった記録は、iOS がゲーム画面を終了させた回数と、そのときの音量です (アプリを閉じても残ります)',
                        'How many times per second the game page draws (Safari usually caps pages at 60). '
                            'Stops are times iOS closed the game page, with the volume at that time.'),
                    style: secondary,
                  ),
                  children: [
                    CupertinoListTile(
                      title: Text(repairText('描画 (1秒あたり)', 'Draws per second')),
                      subtitle: Text(repairText('画面の最大 ${displayRate.round()}', 'Display max ${displayRate.round()}')),
                      additionalInfo: Text(m.measuringGame ? '…' : '${m.gameFrameRate ?? '-'}'),
                      trailing: CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minSize: 28,
                        onPressed: m.gameFrameProbe == null || m.measuringGame ? null : m.measureGameFrameRate,
                        child: Text(repairText('測る', 'Measure'), style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                    CupertinoListTile(
                      title: Text(repairText('止まった回数', 'Stopped')),
                      subtitle: stops.isEmpty
                          ? null
                          : Text([for (final s in stops.reversed.take(5)) gameStopText(s)].join('\n'), maxLines: 5),
                      additionalInfo: Text('${stops.length}'),
                      trailing: stops.isEmpty
                          ? null
                          : CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minSize: 28,
                              onPressed: log.clear,
                              child: Text(repairText('消す', 'Clear'), style: const TextStyle(fontSize: 14)),
                            ),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  header: Text(repairText('全体', 'Overview')),
                  footer: Text(
                    repairText(
                        '1フレームが ${PerfMonitor.slowFrameMs.round()}ms を超えると、カクついて見えます。「処理」はアプリの計算、「描画」は画面に描く時間です。「描き直し」は何も動いていなければ少ないほど良く、多いとゲームの動きを邪魔します。'
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
                    CupertinoListTile(
                      title: Text(repairText('描き直し (1秒あたり)', 'Redraws per second')),
                      subtitle: m.frameRates.isEmpty && m.battleFrameRate == null
                          ? null
                          : Text(
                              [
                                if (m.frameRates.isNotEmpty) perfFrameRatesText(m),
                                if (m.battleFrameRate != null)
                                  repairText('戦闘中 ${m.battleFrameRate!.toStringAsFixed(1)}', 'In battle ${m.battleFrameRate!.toStringAsFixed(1)}'),
                              ].join('\n'),
                              maxLines: 5),
                      additionalInfo: Text(m.frameRate.toStringAsFixed(1)),
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
                          [
                            repairText(
                                '読み込み ${_ms(s.parseTotal ~/ s.count)} / ${_ms(s.parseMax)}・作り直し ${_ms(s.buildTotal ~/ s.count)} / ${_ms(s.buildMax)}',
                                'Parse ${_ms(s.parseTotal ~/ s.count)} / ${_ms(s.parseMax)}, rebuild ${_ms(s.buildTotal ~/ s.count)} / ${_ms(s.buildMax)}'),
                            if (perfStagesText(s).isNotEmpty) repairText('内訳 ${perfStagesText(s)}', 'Stages ${perfStagesText(s)}'),
                          ].join('\n'),
                          maxLines: 4,
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
                        subtitle: f.lastPath == null && f.screen == null
                            ? null
                            : Text([
                                if (f.screen != null) repairText('画面 ${f.screen}', 'Tab ${f.screen}'),
                                if (f.lastPath != null) repairText('直前の通信 ${f.lastPath}', 'After ${f.lastPath}'),
                              ].join(repairText('・', ', '))),
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
