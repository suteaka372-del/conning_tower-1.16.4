import 'package:conning_tower/models/perf_monitor.dart';
import 'package:conning_tower/pages/perf_page.dart';
import 'package:conning_tower/pages/webview.dart';
import 'package:conning_tower/providers/generatable/webview_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;

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
}

