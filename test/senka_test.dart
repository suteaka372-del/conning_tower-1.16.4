import 'package:conning_tower/models/feature/kancolle/senka.dart';
import 'package:conning_tower/pages/dashboard_pages/port_info.dart';
import 'package:conning_tower/widgets/kancolle_senka_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;

/// 日本時間で指定する (UTC+9)
DateTime jst(int y, int m, int d, [int h = 0, int min = 0]) => DateTime.utc(y, m, d, h - 9, min);

void main() {
  setUp(() => intl.Intl.defaultLocale = 'ja');

  test('half days are cut at 14:00 and 2:00 JST, months end at 22:00 JST', () {
    // 11/14 10:00 → 2:00〜14:00
    expect(senkaSessionStart(jst(2026, 11, 14, 10)), jst(2026, 11, 14, 2));
    expect(senkaSessionEnd(jst(2026, 11, 14, 10)), jst(2026, 11, 14, 14));
    // 11/14 15:00 → 14:00〜翌 2:00
    expect(senkaSessionStart(jst(2026, 11, 14, 15)), jst(2026, 11, 14, 14));
    expect(senkaSessionEnd(jst(2026, 11, 14, 15)), jst(2026, 11, 15, 2));
    // 11/15 1:00 はまだ前日 14:00 からの半日
    expect(senkaSessionStart(jst(2026, 11, 15, 1)), jst(2026, 11, 14, 14));
    // ちょうど区切りの時刻は新しい半日
    expect(senkaSessionStart(jst(2026, 11, 14, 14)), jst(2026, 11, 14, 14));
    expect(senkaSessionEnd(jst(2026, 11, 14, 14)), jst(2026, 11, 15, 2));

    // 月末: 14:00〜22:00 で締め、22:00〜翌 2:00 は次の月
    expect(senkaSessionStart(jst(2026, 11, 30, 21)), jst(2026, 11, 30, 14));
    expect(senkaSessionEnd(jst(2026, 11, 30, 21)), jst(2026, 11, 30, 22));
    expect(senkaSessionStart(jst(2026, 11, 30, 23)), jst(2026, 11, 30, 22));
    expect(senkaSessionEnd(jst(2026, 11, 30, 23)), jst(2026, 12, 1, 2));
    expect(senkaSessionStart(jst(2026, 12, 1, 1)), jst(2026, 11, 30, 22));
    expect(senkaSessionStart(jst(2026, 12, 1, 3)), jst(2026, 12, 1, 2));

    // 月の始まり (前の月の締め)
    expect(senkaMonthStart(jst(2026, 11, 14, 10)), jst(2026, 10, 31, 22));
    expect(senkaMonthStart(jst(2026, 11, 30, 21, 59)), jst(2026, 10, 31, 22));
    expect(senkaMonthStart(jst(2026, 11, 30, 22)), jst(2026, 11, 30, 22));
    expect(senkaMonthStart(jst(2026, 12, 1, 5)), jst(2026, 11, 30, 22));
    expect(senkaMonthStart(jst(2027, 1, 1, 5)), jst(2026, 12, 31, 22));
    expect(senkaMonthStart(jst(2027, 3, 1, 5)), jst(2027, 2, 28, 22));
    expect(senkaMonthLabel(senkaMonthStart(jst(2026, 11, 14))), '2026年11月');
    expect(senkaMonthLabel(senkaMonthStart(jst(2027, 1, 1, 5))), '2027年1月');

    // 1日の始まりは 2:00。月の締めをまたがない
    expect(senkaDayStart(jst(2026, 11, 14, 10)), jst(2026, 11, 14, 2));
    expect(senkaDayStart(jst(2026, 11, 15, 1)), jst(2026, 11, 14, 2));
    expect(senkaDayStart(jst(2026, 11, 30, 23)), jst(2026, 11, 30, 22));
    expect(senkaDayStart(jst(2026, 12, 1, 3)), jst(2026, 12, 1, 2));

    // 半日を順にたどると、すき間も重なりもない
    var t = jst(2026, 11, 28, 2);
    final starts = <DateTime>[];
    while (t.isBefore(jst(2026, 12, 2, 2))) {
      starts.add(t);
      expect(senkaSessionStart(t), t);
      expect(senkaSessionStart(senkaSessionEnd(t).subtract(const Duration(seconds: 1))), t);
      t = senkaSessionEnd(t);
    }
    expect(starts.length, 9); // 4日 × 2 + 月末の 22:00
    expect(starts, contains(jst(2026, 11, 30, 22)));
  });

  test('store counts HQ exp, EO and quest points per half day', () {
    var now = jst(2026, 11, 14, 10);
    final saved = <String, String>{};
    SenkaStore make() =>
        SenkaStore(load: (a) => saved[a], save: (a, json) => saved[a] = json, now: () => now, saveDelay: Duration.zero);
    final store = make();
    Map<String, dynamic> api(Map<String, dynamic> data) => {'api_result': 1, 'api_data': data};

    // 母港: データの中の提督名を使う (起動直後はまだ名前を知らない)
    store.onApi('/api_port/port', api({'api_basic': {'api_nickname': '提督', 'api_experience': 1000000}}), '');
    store.onApi('/api_req_sortie/battleresult', api({'api_member_exp': 1002000, 'api_get_exmap_rate': '75'}), '提督');
    store.onApi('/api_req_map/next', api({'api_get_eo_rate': 100}), '提督');
    store.onApi('/api_req_map/next', api({'api_no': 5}), '提督');
    store.onApi('/api_req_quest/clearitemget', api({
      'api_bounus': [
        {'api_type': 1, 'api_count': 3},
        {'api_type': 18, 'api_count': 200},
      ],
    }), '提督');
    store.onApi('/api_req_mission/result', api({'api_member_exp': 1002500}), '提督');
    // 提督名が分からない間・関係ない通信は記録しない
    store.onApi('/api_req_practice/battle_result', api({'api_member_exp': 5}), '');
    store.onApi('/api_get_member/questlist', api({}), '提督');

    var records = store.recordsOf('提督');
    expect(records.length, 1);
    expect(records.single.start, jst(2026, 11, 14, 2));
    expect(records.single.end, jst(2026, 11, 14, 14));
    expect(records.single.expGain, 2500);
    expect(records.single.normal, closeTo(1.75, 1e-9));
    expect(records.single.eo, 175);
    expect(records.single.quest, 200);
    expect(records.single.total, closeTo(376.75, 1e-9));

    // 次の半日: ほかの端末で増えた分 (1002500 → 1010000) も、最初に見た半日に入る
    now = jst(2026, 11, 14, 20);
    store.onApi('/api_port/port', api({'api_basic': {'api_nickname': '提督', 'api_experience': 1010000}}), '提督');
    store.onApi('/api_req_combined_battle/battleresult', api({'api_member_exp': 1012500, 'api_get_exmap_rate': 0}), '提督');
    records = store.recordsOf('提督');
    expect(records.map((r) => r.expGain), [10000, 2500]); // 新しい順
    expect(records.first.normal, closeTo(7, 1e-9));

    // 合計: 今日 (2:00 から) と今月
    final today = senkaTotal(records, from: senkaDayStart(now));
    expect(today.normal, closeTo(8.75, 1e-9));
    expect(today.total, closeTo(383.75, 1e-9));
    now = jst(2026, 11, 15, 3);
    expect(senkaTotal(records, from: senkaDayStart(now)).total, 0);
    expect(senkaTotal(records, from: senkaMonthStart(now)).total, closeTo(383.75, 1e-9));

    // 保存したものを読み直しても同じ
    final restored = make();
    expect(restored.recordsOf('提督').map((r) => (r.start, r.expGain, r.eo, r.quest)),
        records.map((r) => (r.start, r.expGain, r.eo, r.quest)));
    expect(restored.recordsOf('別の提督'), isEmpty);

    // 古い記録は捨てる
    for (var i = 0; i < SenkaStore.keepSessions + 10; i++) {
      now = now.add(const Duration(hours: 12));
      store.recordExp('提督', 1020000 + i);
    }
    expect(store.sessionsOf('提督').length, SenkaStore.keepSessions);
  });

  testWidgets('saving waits a moment, flush writes at once', (tester) async {
    final saved = <String, String>{};
    final store = SenkaStore(load: (a) => saved[a], save: (a, json) => saved[a] = json, now: () => jst(2026, 11, 14, 10));
    store.recordExp('提督', 100);
    store.recordExp('提督', 200);
    expect(saved, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(saved.keys, ['提督']);
    saved.clear();
    store.recordExp('提督', 300);
    store.flush();
    expect(saved.keys, ['提督']);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('senka box and page show today, the month and each half day', (tester) async {
    var now = jst(2026, 11, 14, 10);
    final store = SenkaStore(now: () => now, saveDelay: Duration.zero);
    now = jst(2026, 10, 31, 20);
    store.recordExp('提督', 990000);
    store.recordExp('提督', 1000000); // 10月ぶん (22:00 の締めより前): 7
    now = jst(2026, 11, 13, 20);
    store.recordExp('提督', 1020000); // 14
    now = jst(2026, 11, 14, 10);
    store.recordExp('提督', 1025000); // 3.5
    store.addEo('提督', 75);
    store.addQuest('提督', 80);

    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(
        child: Center(child: SizedBox(width: 180, height: 110, child: SenkaInfoBox(admiralName: '提督', store: store, now: () => now))),
      ),
    ));
    expect(find.text('戦果 (今月)'), findsOneWidget);
    expect(find.text('172.5'), findsOneWidget); // 14 + 3.5 + 75 + 80
    expect(find.text('今日 +158.5'), findsOneWidget);

    await tester.tap(find.text('戦果 (今月)'));
    await tester.pumpAndSettle();
    expect(find.text('今日 (2:00 から)'), findsOneWidget);
    expect(find.text('今月 (2026年11月)'), findsOneWidget);
    expect(find.text('2026年11月 合計 172.5'), findsOneWidget);
    expect(find.text('2026年10月 合計 7'), findsOneWidget);
    final localStart = jst(2026, 11, 14, 2).toLocal();
    final localEnd = jst(2026, 11, 14, 14).toLocal();
    expect(find.text('${senkaSessionLabel(localStart, localEnd)} (今)'), findsOneWidget);
    expect(find.text('通常 3.5・EO 75・任務 80\n提督経験値 +5000'), findsOneWidget);

    // 記録が増えたら、開いたままでも更新される
    store.addEo('提督', 100);
    await tester.pump();
    expect(find.text('2026年11月 合計 272.5'), findsOneWidget);
  });
}
