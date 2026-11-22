import 'dart:async';

import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/perf_monitor.dart';
import 'package:conning_tower/providers/game_stop_log.dart';
import 'package:conning_tower/utils/device_power.dart';
import 'package:conning_tower/utils/toast.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

String _ms(int micros) => (micros / 1000).toStringAsFixed(1);

String _time(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

/// 記録をテキストにする (コピーして貼り付けられるように)
String perfReportText(PerfMonitor m, {List<GameStop> stops = const [], double? displayRate, DevicePower? powerNow}) {
  final lines = <String>[
    '計測開始 ${m.since == null ? '-' : _time(m.since!)}',
    if (powerNow != null) 'コピーしたとき ${powerNow.label}',
    if (m.gameFrameRate != null || displayRate != null)
      'ゲーム画面の描画 ${m.gameFrameRate ?? '-'}回/秒 (画面の最大 ${displayRate?.round() ?? '-'}'
          '${m.gameFramePower == null ? '' : '・測ったとき ${m.gameFramePower!.label}'}'
          '${m.gameFrameShown == false ? '・ゲーム画面は隠れていた' : ''})',
    if (m.gameFit != null) 'ページの中の合わせ直し ${gameFitText(m.gameFit!)}',
    if (stops.isNotEmpty) 'ゲーム画面が止まった ${stops.length}回: ${[for (final s in stops.reversed.take(10)) gameStopText(s)].join('、')}',
    'フレーム ${m.frames} / 重いフレーム ${m.slowFrameCount}',
    '描き直し 平均 ${m.frameRate.toStringAsFixed(1)}回/秒',
    if (m.frameRates.isNotEmpty) '  タブ別 ${perfFrameRatesText(m)}',
    if (m.battleFrameRate != null)
      '  戦闘中 ${m.battleFrameRate!.toStringAsFixed(1)}回/秒 (${m.battleTime.inSeconds}秒) ${perfBattleFramesText(m)}',
    if (m.notices > 0) perfNoticesText(m),
    if (m.browserTime.inSeconds > 0) perfBrowserText(m),
    if (m.events.isNotEmpty) 'ゲーム画面からの知らせ ${perfEventsText(m)}',
    if (m.browserEvents.isNotEmpty) '漫画のブラウザからの知らせ ${perfBrowserEventsText(m)}',
    if (m.gameSamples.isNotEmpty) ...[
      '[ゲームの描画の記録] ${PerfMonitor.gameSampleInterval.inMinutes}分おき (「測る」の分も) ${gameSamplesSummary(m)}',
      for (var i = 0; i < m.gameSamples.length; i += 4)
        m.gameSamples.skip(i).take(4).map(gameSampleText).join('・'),
    ],
    '[重かった通信] 回数・読み込み 平均/最大・作り直し 平均/最大 (ms)',
    for (final s in m.slowestApis.take(15)) ...[
      '${s.path} ${s.count}回 読込 ${_ms(s.parseTotal ~/ s.count)}/${_ms(s.parseMax)} 作直 ${_ms(s.buildTotal ~/ s.count)}/${_ms(s.buildMax)}',
      if (perfStagesText(s).isNotEmpty) '  内訳 ${perfStagesText(s)}',
    ],
    if (m.refits.isNotEmpty) ...[
      '[最近の合わせ直し] 中身の大きさ 前→後・ゲーム画面の枠',
      for (final r in m.refits.reversed) perfRefitText(r),
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
  return '${_date(s.at)} $sound${v == null || s.soundOn == false ? '' : repairText(' BGM${v.bgm}・効果音${v.se}・ボイス${v.voice}', ' BGM ${v.bgm}, SE ${v.se}, voice ${v.voice}')}'
      '${s.power == null ? '' : ' ${s.power!.label}'}';
}

String _size(Size s) => '${s.width.round()}×${s.height.round()}';

/// 合わせ直し1回 (11:04:35 1200×720→1450×870 枠 834×500 戦闘中)
String perfRefitText(PerfRefit r) =>
    '${_time(r.at)} ${_size(r.from)}→${_size(r.to)}${r.view == null ? '' : ' 枠 ${_size(r.view!)}'}${r.inBattle ? ' 戦闘中' : ''}';

/// ゲーム画面からの知らせ (種類ごとの回数、多い順)
String perfEventsText(PerfMonitor m) =>
    ([...m.events.entries]..sort((a, b) => b.value.compareTo(a.value))).map((e) => '${e.key} ${e.value}').join('・');

/// タブ別の1秒あたりの描き直しの回数と、開いていた時間 (多い順)
String perfFrameRatesText(PerfMonitor m) =>
    [for (final (name, rate, time) in m.frameRates) '$name ${rate.toStringAsFixed(1)} (${time.inSeconds}秒)'].join('・');

/// 戦闘中の描き直しの内訳 (通知が出ている間・通信の直後・それ以外)
String perfBattleFramesText(PerfMonitor m) =>
    'うち通知の表示中 ${m.battleFramesInNotice}・通信の直後 ${m.battleFramesAfterApi}・その他 '
    '${m.battleFrames - m.battleFramesInNotice - m.battleFramesAfterApi}';

/// アプリの通知 (「戦闘終了」など) の回数と、出ている間の描き直し
String perfNoticesText(PerfMonitor m) =>
    '通知 ${m.notices}回 (戦闘中 ${m.noticesInBattle}回)・表示中の描き直し ${m.noticeFrames}回';

String _hm(DateTime t) => _time(t).substring(0, 5);

/// ゲームの描画の記録1回 (00:18 60 普通 戦闘中)
String gameSampleText(GameFrameSample s) => [
      '${_hm(s.at)} ${s.fps}',
      s.power?.thermalLabel ?? '-',
      if (s.power?.lowPower == true) '低電力',
      if (s.inBattle) '戦闘中',
      if (s.shown == false) '隠れていた',
      if (s.manual) '手動',
    ].join(' ');

/// ゲームの描画の記録のまとめ (ゲーム画面が見えていた分だけ。隠れていると低く出るので)
String gameSamplesSummary(PerfMonitor m) {
  final shown = m.gameSamples.where((s) => s.shown != false).toList();
  if (shown.isEmpty) return '見えていたときの記録なし';
  final average = shown.fold(0, (sum, s) => sum + s.fps) / shown.length;
  final lowest = shown.reduce((a, b) => b.fps < a.fps ? b : a);
  return '平均 ${average.round()}・最低 ${lowest.fps} (${_hm(lowest.at)} ${lowest.power?.thermalLabel ?? '-'})・${shown.length}回';
}

/// 全画面に合わせるスクリプトが動いた回数
String gameFitText(GameFitStats f) {
  final perMinute = f.minutes <= 0 ? 0 : f.mutations / f.minutes;
  return 'ゲームを読み込んでから ${f.minutes.round()}分・ページの変化 ${f.mutations}回 '
      '(${perMinute.toStringAsFixed(1)}回/分)・合わせ ${f.applies}回';
}

/// 漫画のブラウザを開いていた時間と、その間の描き直し
String perfBrowserText(PerfMonitor m) {
  final seconds = m.browserTime.inMilliseconds / 1000;
  final rate = seconds <= 0 ? 0 : m.browserFrames / seconds;
  return '漫画のブラウザ 開いていた ${seconds.round()}秒・その間の描き直し ${rate.toStringAsFixed(1)}回/秒'
      ' (戦闘中に開いていた間 ${m.battleFramesWithBrowser}回)';
}

/// 漫画のブラウザからの知らせ (種類ごとの回数、多い順)
String perfBrowserEventsText(PerfMonitor m) =>
    ([...m.browserEvents.entries]..sort((a, b) => b.value.compareTo(a.value))).map((e) => '${e.key} ${e.value}').join('・');

/// 読み込みの内訳 (0.5ms 以上の段階を平均の長い順に。平均/最大)
String perfStagesText(PerfApiStat s) => [
      for (final (name, average, max) in s.stages)
        if (max >= 500) '$name ${_ms(average)}/${_ms(max)}',
    ].join('・');

/// [listenable] が変わったら作り直す。ただし [interval] に1回まで (続けて変わったら最後にまとめて1回)
class ThrottledListenableBuilder extends StatefulWidget {
  const ThrottledListenableBuilder(
      {super.key, required this.listenable, required this.builder, this.interval = const Duration(seconds: 1)});

  final Listenable listenable;
  final WidgetBuilder builder;
  final Duration interval;

  @override
  State<ThrottledListenableBuilder> createState() => _ThrottledListenableBuilderState();
}

class _ThrottledListenableBuilderState extends State<ThrottledListenableBuilder> {
  /// 作り直してから [ThrottledListenableBuilder.interval] の間は待つ
  Timer? _cooldown;

  /// 待っている間に変わった
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(ThrottledListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    _cooldown?.cancel();
    super.dispose();
  }

  void _changed() {
    if (_cooldown != null) {
      _pending = true;
      return;
    }
    // 画面を作っている最中に知らされても困らないよう、すぐ後で作り直す
    _cooldown = Timer(Duration.zero, _rebuild);
  }

  void _rebuild() {
    if (!mounted) return;
    _pending = false;
    setState(() {});
    _cooldown = Timer(widget.interval, () {
      _cooldown = null;
      if (_pending) _changed();
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

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
            onPressed: () async {
              final power = await (m.powerProbe?.call() ?? Future<DevicePower?>.value());
              await Clipboard.setData(
                  ClipboardData(text: perfReportText(m, stops: log.stops, displayRate: displayRate, powerNow: power)));
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
        // 記録は描き直すたびに増えるので、表示の更新は1秒に1回まで
        // (毎回更新すると、その描き直しがまた記録されて、開いている間ずっと描き直し続けていた)
        child: ThrottledListenableBuilder(
          listenable: Listenable.merge([m.revision, log.revision]),
          builder: (context) {
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
                            'Safari はふつう 60 回までに抑えています。低電力モードのときや本体が熱いときは 30 回に落ちることがあります (Safari でも同じ)。'
                            'ツールや歯車の設定の画面でゲームが隠れていると、低く出ます。'
                            '自動の記録は、ゲーム画面が見えているときだけ数分おきに1秒ずつ測ったものです。'
                            '合わせ直しは、ゲーム画面の大きさが大きく変わって合わせ直した記録です。'
                            'ページの中の合わせ直しは、ゲームのページの中で全画面に合わせる仕掛けが動いた回数です。'
                            '止まった記録は、iOS がゲーム画面を終了させた回数と、そのときの音量です (アプリを閉じても残ります)',
                        'How many times per second the game page draws (Safari usually caps pages at 60). '
                            'Stops are times iOS closed the game page, with the volume at that time.'),
                    style: secondary,
                  ),
                  children: [
                    CupertinoListTile(
                      title: Text(repairText('描画 (1秒あたり)', 'Draws per second')),
                      subtitle: Text([
                        repairText('画面の最大 ${displayRate.round()}', 'Display max ${displayRate.round()}'),
                        if (m.gameFramePower != null) m.gameFramePower!.label,
                        if (m.gameFrameShown == false)
                          repairText('ゲーム画面が隠れていたので低く出ています', 'The game page was hidden, so this is low'),
                      ].join('\n')),
                      additionalInfo: Text(m.measuringGame ? '…' : '${m.gameFrameRate ?? '-'}'),
                      trailing: CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minSize: 28,
                        onPressed: m.gameFrameProbe == null || m.measuringGame ? null : m.measureGameFrameRate,
                        child: Text(repairText('測る', 'Measure'), style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                    CupertinoListTile(
                      title: Text(repairText(
                          '自動の記録 (${PerfMonitor.gameSampleInterval.inMinutes}分おき)',
                          'Auto log (every ${PerfMonitor.gameSampleInterval.inMinutes} min)')),
                      subtitle: m.gameSamples.isEmpty
                          ? null
                          : Text(
                              [
                                gameSamplesSummary(m),
                                for (final s in m.gameSamples.reversed.take(5)) gameSampleText(s),
                              ].join('\n'),
                              maxLines: 6),
                      additionalInfo: Text('${m.gameSamples.length}'),
                    ),
                    if (m.gameFit != null)
                      CupertinoListTile(
                        title: Text(repairText('ページの中の合わせ直し', 'Fits inside the page')),
                        subtitle: Text(gameFitText(m.gameFit!), maxLines: 3),
                      ),
                    CupertinoListTile(
                      title: Text(repairText('合わせ直し', 'Refits')),
                      subtitle: m.refits.isEmpty
                          ? null
                          : Text([for (final r in m.refits.reversed.take(5)) perfRefitText(r)].join('\n'), maxLines: 5),
                      additionalInfo: Text('${m.events['refit'] ?? 0}'),
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
                                if (m.notices > 0) perfNoticesText(m),
                                if (m.browserTime.inSeconds > 0) perfBrowserText(m),
                              ].join('\n'),
                              maxLines: 10),
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
