import 'package:conning_tower/models/perf_monitor.dart';
import 'package:conning_tower/utils/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toastification/toastification.dart';

void main() {
  Future<void> showApp(WidgetTester tester) => tester.pumpWidget(
        const ToastificationWrapper(child: MaterialApp(home: Scaffold(body: SizedBox()))),
      );

  /// 通知は少し遅れて出てくる。1秒ぶん、少しずつ時間を進める
  Future<void> wait(WidgetTester tester, [int seconds = 1]) async {
    for (var i = 0; i < seconds * 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('notices have no progress bar, so the app does not redraw while one is shown', (tester) async {
    await showApp(tester);
    final before = PerfMonitor.instance.notices;
    Toast.show(title: '戦闘終了');
    await wait(tester); // 出る動きが終わる
    expect(find.text('戦闘終了'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse); // 出ている間は描き直さない
    expect(PerfMonitor.instance.notices, before + 1);

    // 時間がたてば今までどおり消える
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('戦闘終了'), findsNothing);
  });

  testWidgets('with the progress bar (the old way) the app redraws the whole time', (tester) async {
    await showApp(tester);
    toastification.show(
      title: const Text('戦闘終了'),
      style: ToastificationStyle.flat,
      autoCloseDuration: const Duration(seconds: 4),
    );
    await wait(tester);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('warnings keep their own display time', (tester) async {
    await showApp(tester);
    Toast.showWarning(title: '大破', description: '艦娘', autoCloseDuration: const Duration(seconds: 10));
    await wait(tester, 6);
    expect(find.text('大破'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('大破'), findsNothing);
  });
}
