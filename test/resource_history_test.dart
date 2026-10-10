import 'package:conning_tower/models/feature/kancolle/resource_history.dart';
import 'package:conning_tower/models/feature/log/kancolle_log.dart';
import 'package:conning_tower/pages/dashboard_pages/port_info.dart';
import 'package:conning_tower/widgets/resource_history_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// JST の日時を作る
DateTime jst(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(const Duration(hours: 9));

KancolleResourceLogEntity log(DateTime time, String resource, int open, int close,
        {int? high, int? low}) =>
    KancolleResourceLogEntity(
      time: time,
      admiral: 'admiral',
      resource: resource,
      open: open,
      close: close,
      high: high ?? (open > close ? open : close),
      low: low ?? (open < close ? open : close),
    );

void main() {
  setUp(() => Intl.defaultLocale = 'ja');

  group('game day (5:00 JST)', () {
    test('4:59 belongs to the previous day, 5:00 to the new day', () {
      expect(gameDate(jst(2026, 10, 10, 4, 59)), DateTime.utc(2026, 10, 9));
      expect(gameDate(jst(2026, 10, 10, 5, 0)), DateTime.utc(2026, 10, 10));
      expect(gameDate(jst(2026, 10, 10, 23, 59)), DateTime.utc(2026, 10, 10));
      expect(gameDate(jst(2026, 11, 1, 3, 0)), DateTime.utc(2026, 10, 31));
    });

    test('day start is 5:00 JST', () {
      expect(gameDayStart(jst(2026, 10, 10, 14, 0)), jst(2026, 10, 10, 5, 0));
      expect(gameDayStart(jst(2026, 10, 10, 2, 0)), jst(2026, 10, 9, 5, 0));
      expect(gameDayStart(jst(2026, 1, 1, 4, 0)), jst(2025, 12, 31, 5, 0));
    });
  });

  group('groupResourceLogs', () {
    test('new records are grouped by game day and merged', () {
      final since = jst(2026, 10, 1).millisecondsSinceEpoch;
      final days = groupResourceLogs([
        log(jst(2026, 10, 10, 6, 0), 'fuel', 100, 150, high: 160, low: 90),
        // 翌日 2:00 はまだ 10/10 の続き
        log(jst(2026, 10, 11, 2, 0), 'fuel', 150, 170, high: 180, low: 140),
        log(jst(2026, 10, 11, 5, 30), 'fuel', 170, 200),
        log(jst(2026, 10, 10, 6, 0), 'ammo', 50, 40),
      ], gameDaySinceMs: since);

      expect(days.map((d) => d.date), [DateTime.utc(2026, 10, 10), DateTime.utc(2026, 10, 11)]);
      final fuel = days[0].values['fuel']!;
      expect(fuel.open, 100);
      expect(fuel.close, 170);
      expect(fuel.high, 180);
      expect(fuel.low, 90);
      expect(days[0].close('ammo'), 40);
      expect(days[1].close('fuel'), 200);
      expect(days[1].close('ammo'), isNull);
    });

    test('records before the switch keep their calendar date', () {
      final since = jst(2026, 10, 12, 12, 0).millisecondsSinceEpoch;
      final days = groupResourceLogs([
        // 0:00 区切りの頃の記録 (10/11 の 0:30 に作られた、10/11 1日分)
        log(jst(2026, 10, 10, 9, 0), 'fuel', 100, 110),
        log(jst(2026, 10, 11, 0, 30), 'fuel', 110, 130),
        // 切り替え後の記録
        log(jst(2026, 10, 12, 13, 0), 'fuel', 130, 140),
      ], gameDaySinceMs: since);

      expect(days.map((d) => d.date), [
        DateTime.utc(2026, 10, 10),
        DateTime.utc(2026, 10, 11),
        DateTime.utc(2026, 10, 12),
      ]);
    });

    test('without the switch time every record uses the calendar date', () {
      final days = groupResourceLogs([log(jst(2026, 10, 11, 0, 30), 'fuel', 1, 2)]);
      expect(days.single.date, DateTime.utc(2026, 10, 11));
    });
  });

  group('diffs', () {
    final days = [
      ResourceDay(date: DateTime.utc(2026, 10, 8), values: {
        'fuel': const ResourceDayValue(open: 90, close: 100, high: 100, low: 90),
      }),
      ResourceDay(date: DateTime.utc(2026, 10, 9), values: {
        'ammo': const ResourceDayValue(open: 10, close: 20, high: 20, low: 10),
      }),
      ResourceDay(date: DateTime.utc(2026, 10, 10), values: {
        'fuel': const ResourceDayValue(open: 100, close: 80, high: 120, low: 70),
        'ammo': const ResourceDayValue(open: 20, close: 25, high: 25, low: 20),
      }),
    ];

    test('diff against the previous recorded day', () {
      expect(diffFromPreviousDay(days, 0, 'fuel'), isNull);
      expect(diffFromPreviousDay(days, 2, 'fuel'), -20); // 10/8 と比べる
      expect(diffFromPreviousDay(days, 2, 'ammo'), 5);
      expect(diffFromPreviousDay(days, 1, 'fuel'), isNull); // その日の記録なし
    });

    test("today's diff uses the previous close, or today's open", () {
      final now = jst(2026, 10, 10, 20, 0);
      expect(todayResourceDiff(days, 'fuel', 130, now), 30);
      expect(todayResourceDiff(days, 'ammo', 30, now), 10);
      expect(todayResourceDiff(days.sublist(2), 'fuel', 130, now), 30); // 始値 100 と比べる
      expect(todayResourceDiff(const [], 'fuel', 130, now), isNull);
      // 5:00 前はまだ 10/10、5:00 を過ぎると 10/10 が前の日になる
      expect(todayResourceDiff(days, 'fuel', 130, jst(2026, 10, 11, 3, 0)), 30);
      expect(todayResourceDiff(days, 'fuel', 130, jst(2026, 10, 11, 6, 0)), 50);
    });

    test('period filter includes today', () {
      final now = jst(2026, 10, 10, 20, 0);
      expect(resourceDaysInPeriod(days, 2, now).map((d) => d.date.day), [9, 10]);
      expect(resourceDaysInPeriod(days, 0, now).length, 3);
    });

    test('formatting', () {
      expect(formatResourceDiff(1234), '+1,234');
      expect(formatResourceDiff(-560), '−560');
      expect(formatResourceDiff(0), '±0');
      expect(formatResourceValue(350000), '350,000');
      expect(formatResourceValue(12), '12');
    });
  });

  group('widgets', () {
    List<ResourceDay> sampleDays(int count) {
      final today = gameDate(DateTime.now());
      return [
        for (var i = count - 1; i >= 0; i--)
          ResourceDay(date: today.subtract(Duration(days: i)), values: {
            for (final (n, key) in [...kMainResourceKeys, ...kMaterialKeys].indexed)
              key: ResourceDayValue(
                  open: 100000 + n * 1000 + i,
                  close: 100500 + n * 1000 - i * 37,
                  high: 101000 + n * 1000,
                  low: 99000 + n * 1000),
          }),
      ];
    }

    Future<void> pumpPage(WidgetTester tester, List<ResourceDay> days, Size size,
        {bool materials = false}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ja'), Locale('en')],
        locale: const Locale('ja'),
        home: ResourceHistoryPage(admiralName: 'admiral', days: days, showMaterials: materials),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('history page shows chart and daily table without overflow', (tester) async {
      await pumpPage(tester, sampleDays(40), const Size(393, 420));
      expect(find.text('資源の推移'), findsOneWidget);
      expect(find.text('1ヶ月'), findsOneWidget);
      expect(find.text('日付'), findsOneWidget);
      expect(find.text('燃料'), findsWidgets);
      expect(tester.takeException(), isNull);

      // 資材に切り替え
      await tester.tap(find.text('資材'));
      await tester.pumpAndSettle();
      expect(find.text('開発資材'), findsWidgets);
      // 全期間
      await tester.tap(find.text('全期間'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('history page in a small landscape panel', (tester) async {
      await pumpPage(tester, sampleDays(10), const Size(300, 300), materials: true);
      expect(find.text('改修資材'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty history shows a message', (tester) async {
      await pumpPage(tester, const [], const Size(393, 420));
      expect(find.textContaining('記録がありません'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("resource box shows today's change", (tester) async {
      for (final width in [182.0, 120.0]) {
        await tester.pumpWidget(CupertinoApp(
          home: Center(
            child: SizedBox(
              width: width,
              height: width / 1.618,
              child: ResourceInfoBox(
                resource: 'fuel',
                color: const Color.fromRGBO(32, 89, 29, 1.0),
                admiralName: 'admiral',
                value: 250123,
                todayDiff: 1230,
              ),
            ),
          ),
        ));
        expect(find.text('250123'), findsOneWidget);
        expect(find.text('今日 +1,230'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(const CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 182,
            height: 112,
            child: ResourceInfoBox(
              resource: 'ammo',
              color: Color.fromRGBO(126, 102, 54, 1.0),
              admiralName: 'admiral',
              value: 100,
            ),
          ),
        ),
      ));
      expect(find.textContaining('今日'), findsNothing);
    });
  });
}
