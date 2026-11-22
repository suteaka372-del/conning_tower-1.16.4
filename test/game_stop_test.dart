import 'package:conning_tower/models/perf_monitor.dart';
import 'package:conning_tower/pages/perf_page.dart';
import 'package:conning_tower/pages/webview.dart';
import 'package:conning_tower/providers/generatable/webview_provider.dart';
import 'package:conning_tower/utils/device_power.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:toastification/toastification.dart';

void main() {
  final t0 = DateTime(2026, 11, 21, 23, 5);
  setUp(() => intl.Intl.defaultLocale = 'ja');

  test('game volumes from the kcs_options cookie', () {
    // アプリのミュート / ミュート解除が書く値
    expect(parseKancolleVolumes('vol_bgm%3D0%3Bvol_se%3D0%3Bvol_voice%3D0%3Bv_be_left%3D1%3Bv_duty%3D1'),
        (bgm: 0, se: 0, voice: 0));
    expect(parseKancolleVolumes('vol_bgm%3D30%3Bvol_se%3D40%3Bvol_voice%3D60%3Bv_be_left%3D1%3Bv_duty%3D1'),
        (bgm: 30, se: 40, voice: 60));
    expect(parseKancolleVolumes('vol_bgm=0;vol_se=40;vol_voice=60'), (bgm: 0, se: 40, voice: 60));
    expect(parseKancolleVolumes(null), isNull);
    expect(parseKancolleVolumes('vol_bgm%3D10'), isNull);

    expect(GameStop(at: t0, volumes: (bgm: 0, se: 0, voice: 0)).soundOn, isFalse);
    expect(GameStop(at: t0, volumes: (bgm: 0, se: 40, voice: 0)).soundOn, isTrue);
    expect(GameStop(at: t0).soundOn, isNull);
    expect(gameStopText(GameStop(at: t0, volumes: (bgm: 30, se: 40, voice: 60))), '11/21 23:05 音あり BGM30・効果音40・ボイス60');
    expect(gameStopText(GameStop(at: t0, volumes: (bgm: 0, se: 0, voice: 0))), '11/21 23:05 ミュート');
    expect(gameStopText(GameStop(at: t0)), '11/21 23:05 音量不明');
  });

  test('stops are saved and only the latest are kept', () {
    String? saved;
    GameStopLog make() => GameStopLog(load: () => saved, save: (json) => saved = json);
    final log = make();
    log.add(GameStop(at: t0, volumes: (bgm: 30, se: 40, voice: 60)));
    log.add(GameStop(at: t0.add(const Duration(hours: 1))));
    final restored = make();
    expect(restored.stops.length, 2);
    expect(restored.stops.first.volumes, (bgm: 30, se: 40, voice: 60));
    expect(restored.stops.last.volumes, isNull);
    for (var i = 0; i < 40; i++) {
      restored.add(GameStop(at: t0.add(Duration(minutes: i))));
    }
    expect(restored.stops.length, GameStopLog.keep);
    restored.clear();
    expect(make().stops, isEmpty);
    expect(GameStopLog(load: () => 'broken').stops, isEmpty);
  });

  testWidgets('performance page measures the game page and lists stops', (tester) async {
    final m = PerfMonitor()..reset();
    final log = GameStopLog();
    log.add(GameStop(at: t0, volumes: (bgm: 30, se: 40, voice: 60)));
    m.gameFrameProbe = () async => 120;
    await tester.pumpWidget(CupertinoApp(home: PerfPage(monitor: m, stopLog: log)));
    expect(find.text('描画 (1秒あたり)'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    await tester.tap(find.text('測る'));
    await tester.pump();
    // 表示の更新は1秒に1回まで
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('120'), findsOneWidget);
    expect(m.gameFrameRate, 120);
    expect(find.text('止まった回数'), findsOneWidget);
    expect(find.text('11/21 23:05 音あり BGM30・効果音40・ボイス60'), findsOneWidget);
    expect(perfReportText(m, stops: log.stops, displayRate: 120), contains('ゲーム画面の描画 120回/秒 (画面の最大 120)'));
    expect(perfReportText(m, stops: log.stops), contains('ゲーム画面が止まった 1回: 11/21 23:05 音あり'));

    await tester.tap(find.text('消す'));
    await tester.pump(const Duration(seconds: 1));
    expect(log.stops, isEmpty);
    expect(find.text('消す'), findsNothing);
  });

  test('only big changes of the game page size are refitted', () {
    expect(contentSizeChangedMuch(const Size(800, 480), const Size(800, 480)), isFalse);
    expect(contentSizeChangedMuch(const Size(800, 480), const Size(805, 482)), isFalse);
    expect(contentSizeChangedMuch(const Size(800, 480), const Size(900, 480)), isTrue); // 横並びの幅を変えた
    expect(contentSizeChangedMuch(const Size(800, 480), const Size(480, 800)), isTrue); // 回転
    expect(contentSizeChangedMuch(Size.zero, const Size(800, 480)), isTrue); // 最初の表示
    expect(contentSizeChangedMuch(Size.zero, Size.zero), isFalse);
  });

  testWidgets('the page refreshes at most once a second', (tester) async {
    final notifier = ValueNotifier(0);
    var builds = 0;
    await tester.pumpWidget(ThrottledListenableBuilder(
      listenable: notifier,
      builder: (context) {
        builds++;
        return const SizedBox();
      },
    ));
    expect(builds, 1);
    for (var i = 0; i < 10; i++) {
      notifier.value++;
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(builds, 2, reason: '最初の変化ですぐ作り直し、そのあと1秒は待つ');
    await tester.pump(const Duration(milliseconds: 600));
    expect(builds, 3, reason: '待っている間に変わった分は1回にまとめる');
    await tester.pump(const Duration(seconds: 3));
    expect(builds, 3, reason: '変わらなければ作り直さない');
    notifier.value++;
    await tester.pump(const Duration(milliseconds: 1));
    expect(builds, 4, reason: '前の更新から1秒以上たっていれば、すぐ作り直す');
  });

  test('events during a battle are also counted separately', () {
    final m = PerfMonitor()..reset();
    m.countEvent('contentSize');
    m.measureApi('/api_req_sortie/battle', () {});
    m.countEvent('contentSize');
    m.measureApi('/api_req_sortie/battleresult', () {});
    m.countEvent('contentSize');
    expect(m.events, {'contentSize': 3, 'contentSize(戦闘中)': 1});
  });

  testWidgets('stopped game page shows a reload button and does nothing by itself', (tester) async {
    var reloads = 0;
    await tester.pumpWidget(CupertinoApp(
      home: SizedBox(width: 400, height: 240, child: GameStoppedOverlay(onReload: () => reloads++)),
    ));
    expect(find.text('ゲーム画面が止まりました'), findsOneWidget);
    expect(find.text('ゲームの最初の画面に戻ります'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(reloads, 0);
    await tester.tap(find.text('再読み込み'));
    expect(reloads, 1);
    expect(tester.takeException(), isNull);
  });

  test('stops remember low power mode and heat', () {
    const power = DevicePower(lowPower: true, thermal: 2);
    final stop = GameStop(at: t0, volumes: (bgm: 30, se: 40, voice: 60), power: power);
    expect(gameStopText(stop), '11/21 23:05 音あり BGM30・効果音40・ボイス60 低電力モード オン・本体の熱さ 熱い');
    final restored = GameStop.fromJson(stop.toJson())!;
    expect(restored.power, power);
    expect(GameStop.fromJson(GameStop(at: t0).toJson())!.power, isNull);
    // 前の版で保存した記録 (p がない) も読める
    expect(GameStop.fromJson({'t': t0.millisecondsSinceEpoch, 'v': [0, 0, 0]})!.power, isNull);
  });

  test('measuring the game page also notes low power mode and heat', () async {
    var now = DateTime(2026, 11, 22, 12);
    final m = PerfMonitor(now: () => now)..reset();
    m.gameFrameProbe = () async => 30;
    m.powerProbe = () async => const DevicePower(lowPower: true, thermal: 0);
    await m.measureGameFrameRate();
    expect(m.gameFrameRate, 30);
    expect(m.gameFramePower, const DevicePower(lowPower: true, thermal: 0));
    final report = perfReportText(m, displayRate: 120, powerNow: const DevicePower(lowPower: false, thermal: 2));
    expect(report, contains('コピーしたとき 低電力モード オフ・本体の熱さ 熱い'));
    expect(report, contains('ゲーム画面の描画 30回/秒 (画面の最大 120・測ったとき 低電力モード オン・本体の熱さ 普通)'));

    // 聞けないとき (iOS 以外) は今までどおり
    m.powerProbe = () async => null;
    await m.measureGameFrameRate();
    expect(perfReportText(m, displayRate: 120), contains('ゲーム画面の描画 30回/秒 (画面の最大 120)'));
    expect(perfReportText(m), isNot(contains('コピーしたとき')));
  });

  testWidgets('refits are listed with sizes, the frame size and battles', (tester) async {
    var now = DateTime(2026, 11, 22, 11, 4, 35);
    final m = PerfMonitor(now: () => now)..reset();
    m.gameViewSize = const Size(834, 500);
    m.recordRefit(const Size(1200, 720), const Size(1450, 870));
    m.measureApi('/api_req_sortie/battle', () {});
    now = now.add(const Duration(seconds: 30));
    m.gameViewSize = null;
    m.recordRefit(const Size(1450, 870), const Size(1200.4, 719.6));
    expect(m.events['refit'], 2);
    expect(m.events['refit(戦闘中)'], 1);
    expect(m.refits.map((r) => r.inBattle), [false, true]);
    expect(perfRefitText(m.refits.first), '11:04:35 1200×720→1450×870 枠 834×500');
    expect(perfRefitText(m.refits.last), '11:05:05 1450×870→1200×720 戦闘中');
    final report = perfReportText(m);
    expect(report, contains('[最近の合わせ直し] 中身の大きさ 前→後・ゲーム画面の枠\n11:05:05 1450×870→1200×720 戦闘中\n11:04:35 1200×720→1450×870 枠 834×500'));

    for (var i = 0; i < 15; i++) {
      m.recordRefit(Size.zero, const Size(100, 60));
    }
    expect(m.refits.length, PerfMonitor.keepRefits);
    m.reset();
    expect(m.refits, isEmpty);
    expect(perfReportText(m), isNot(contains('合わせ直し')));
    await tester.pump();
  });

  testWidgets('a burst of size changes is refitted once, from the first size to the last', (tester) async {
    final calls = <(Size, Size)>[];
    final refit = RefitDebouncer(onRefit: (from, to) => calls.add((from, to)));

    // 小さな変化は合わせ直さない
    refit.sizeChanged(const Size(800, 480), const Size(805, 482));
    await tester.pump(const Duration(seconds: 1));
    expect(calls, isEmpty);

    // 大きな変化が続いたら、最後の変化から 300ms 待って1回だけ
    refit.sizeChanged(const Size(800, 480), const Size(1000, 600));
    await tester.pump(const Duration(milliseconds: 200));
    refit.sizeChanged(const Size(1000, 600), const Size(1200, 720));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, isEmpty);
    expect(refit.pending, isTrue);
    // 待っている間の小さな変化も、最後の大きさになる
    refit.sizeChanged(const Size(1200, 720), const Size(1205, 723));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, [(const Size(800, 480), const Size(1205, 723))]);
    expect(refit.pending, isFalse);

    // 次の変化は新しい組
    refit.sizeChanged(const Size(1205, 723), const Size(800, 480));
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls.last, (const Size(1205, 723), const Size(800, 480)));

    refit.sizeChanged(const Size(800, 480), const Size(1200, 720));
    refit.cancel();
    await tester.pump(const Duration(seconds: 1));
    expect(calls.length, 2);
  });

  testWidgets('the page lists refits and copies the low power mode and heat', (tester) async {
    final m = PerfMonitor()..reset();
    m.gameViewSize = const Size(834, 500);
    m.recordRefit(const Size(1200, 720), const Size(1450, 870));
    m.gameFrameProbe = () async => 30;
    m.powerProbe = () async => const DevicePower(lowPower: true, thermal: 1);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(ToastificationWrapper(
      child: MaterialApp(home: CupertinoPageScaffold(child: PerfPage(monitor: m, stopLog: GameStopLog()))),
    ));
    expect(find.text('合わせ直し'), findsOneWidget);
    expect(find.textContaining('1200×720→1450×870 枠 834×500'), findsOneWidget);

    await tester.tap(find.text('測る'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('低電力モード オン・本体の熱さ 少し熱い'), findsOneWidget);

    await tester.tap(find.text('コピー'));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(copied, contains('コピーしたとき 低電力モード オン・本体の熱さ 少し熱い'));
    expect(copied, contains('測ったとき 低電力モード オン・本体の熱さ 少し熱い'));
    expect(copied, contains('[最近の合わせ直し]'));
    await tester.pumpAndSettle();
  });
}
