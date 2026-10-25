import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';
import 'package:conning_tower/models/feature/kancolle/damage/damage_attacks.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/perf_monitor.dart';
import 'package:conning_tower/pages/perf_page.dart';
import 'package:conning_tower/providers/dashboard_tab_provider.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/utils/memo.dart';
import 'package:conning_tower/widgets/dashboard_tab_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';

KancolleData _data(Ref ref) => KancolleData(
      queue: OperationQueue(map: {}),
      squads: [],
      seaForceBase: SeaForceBase(
        resource: const SeaForceBaseResource(
            fuel: 0,
            ammo: 0,
            steel: 0,
            bauxite: 0,
            instantCreateShip: 0,
            instantRepairs: 0,
            developmentMaterials: 0,
            improvementMaterials: 0),
        admiral: const Admiral(name: '', level: 1, rank: 10, maxShip: 0, maxItem: 0),
      ),
      fleet: Fleet(ships: [], equipment: {}),
      ref: ref,
      dataInfo: DataInfo(),
      battleInfo: BattleInfo(),
    );

/// 作り直した回数と、最後に見たデータを覚えるだけのウィジェット
class _Probe extends ConsumerWidget {
  const _Probe(this.name, this.builds, this.seen);

  final String name;
  final Map<String, int> builds;
  final Map<String, KancolleData> seen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    seen[name] = watchKancolleData(ref, context);
    builds[name] = (builds[name] ?? 0) + 1;
    return Text(name);
  }
}

void main() {
  setUp(() => intl.Intl.defaultLocale = 'ja');

  test('Memo reuses the result while the inputs are equal', () {
    final memo = Memo<int>();
    var calls = 0;
    final list = [1, 2];
    expect(memo.of([list, 'a'], () => ++calls), 1);
    expect(memo.of([list, 'a'], () => ++calls), 1);
    // 中身が同じでも別のリストなら計算し直す (同じものかで比べる)
    expect(memo.of([[1, 2], 'a'], () => ++calls), 2);
    expect(memo.of([list, 'b'], () => ++calls), 3);
    memo.clear();
    expect(memo.of([list, 'b'], () => ++calls), 4);

    final cache = MemoCache<int>(2);
    expect(cache.get('x', () => 1), 1);
    expect(cache.get('y', () => 2), 2);
    expect(cache.get('x', () => 99), 1); // x を使ったので y が一番古い
    expect(cache.get('z', () => 3), 3);
    expect(cache.length, 2);
    expect(cache.get('y', () => 4), 4); // y は捨てられていた
    expect(cache.get('x', () => 5), 5); // z と y が残り、x は捨てられていた
  });

  test('keys change only when the contents change', () {
    const gun = DamageEquip(itemId: 2, category: kDmgSmallGun, firepower: 2);
    DamageShip ship({int hp = 30, List<DamageEquip> equips = const [gun]}) =>
        DamageShip(name: 'DD', shipType: kDmgDD, hp: hp, maxHp: 30, armor: 40, firepower: 50, equips: equips);
    expect(ship().key, ship().key);
    expect(ship(hp: 10).key, isNot(ship().key));
    expect(ship(equips: const [DamageEquip(itemId: 2, category: kDmgSmallGun, firepower: 2, improvement: 4)]).key,
        isNot(ship().key));
    expect(const DamageConditions(formation: 2).key, isNot(const DamageConditions().key));

    // 羅針盤: 同じ編成なら同じ結果を使い回し、編成が変われば計算し直す
    final map = compassMapOf(11)!;
    CompassFleet fleet(int type, {double los = 10}) =>
        CompassFleet([CompassShip(shipType: type), const CompassShip(shipType: kDD)], losScore: (c) => los * c);
    final first = simulateCompassCached(map, fleet(kCL));
    expect(identical(simulateCompassCached(map, fleet(kCL)), first), isTrue);
    expect(identical(simulateCompassCached(map, fleet(kCA)), first), isFalse);
    expect(identical(simulateCompassCached(map, fleet(kCL, los: 20)), first), isFalse);
    expect(simulateCompassCached(map, fleet(kCA)).likelyRoute, simulateCompass(map, fleet(kCA)).likelyRoute);
  });

  testWidgets('hidden dashboard tabs do not rebuild until they are shown', (tester) async {
    final container = ProviderContainer(overrides: [kancolleDataProvider.overrideWith(_data)]);
    addTearDown(container.dispose);
    final builds = <String, int>{};
    final seen = <String, KancolleData>{};
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [
          DashboardTabScope(index: 0, child: _Probe('tab0', builds, seen)),
          DashboardTabScope(index: 1, child: _Probe('tab1', builds, seen)),
          _Probe('outside', builds, seen),
        ]),
      ),
    ));
    expect(builds, {'tab0': 1, 'tab1': 1, 'outside': 1});

    container.read(visibleDashboardTabProvider.notifier).state = 0;
    await tester.pump();
    expect(builds, {'tab0': 1, 'tab1': 1, 'outside': 1}, reason: 'まだデータは変わっていない');

    // ゲームのデータが届く: 表示中のタブとタブの外だけ作り直す
    final controller = container.read(kancolleDataProvider.notifier);
    controller.state = controller.state.copyWith();
    await tester.pump();
    expect(builds, {'tab0': 2, 'tab1': 1, 'outside': 2});
    expect(identical(seen['tab0'], controller.state), isTrue);
    expect(identical(seen['tab1'], controller.state), isFalse);

    controller.state = controller.state.copyWith();
    await tester.pump();
    expect(builds, {'tab0': 3, 'tab1': 1, 'outside': 3});

    // タブ1を開くと、その時点の最新のデータで作り直す
    container.read(visibleDashboardTabProvider.notifier).state = 1;
    await tester.pump();
    expect(builds, {'tab0': 3, 'tab1': 2, 'outside': 3});
    expect(identical(seen['tab1'], controller.state), isTrue);

    // 表示中が分からなくなったら、すべて表示中として扱う
    container.read(visibleDashboardTabProvider.notifier).state = null;
    controller.state = controller.state.copyWith();
    await tester.pump();
    expect(builds, {'tab0': 4, 'tab1': 3, 'outside': 4});
  });

  testWidgets('the bottom tab view reports the tab on screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [kancolleDataProvider.overrideWith(_data)]);
    addTearDown(container.dispose);
    final builds = <String, int>{};
    final seen = <String, KancolleData>{};
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: DashboardTabView(
          initialIndex: 1,
          tabs: const [Tab(text: 'A'), Tab(text: 'B'), Tab(text: 'C')],
          contents: [_Probe('a', builds, seen), _Probe('b', builds, seen), _Probe('c', builds, seen)],
          colors: const [Colors.red, Colors.green, Colors.blue],
        ),
      ),
    ));
    await tester.pump();
    expect(container.read(visibleDashboardTabProvider), 1);

    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(container.read(visibleDashboardTabProvider), 2);
    final before = builds['c']!;
    final controller = container.read(kancolleDataProvider.notifier);
    controller.state = controller.state.copyWith();
    await tester.pump();
    expect(builds['c'], before + 1);
    expect(identical(seen['c'], controller.state), isTrue);
  });

  test('PerfMonitor keeps the slowest game data and slow frames', () {
    var now = DateTime(2026, 10, 25, 12);
    final m = PerfMonitor(now: () => now)..reset();
    m.recordApi('/api_port/port', parseMicros: 8000, buildMicros: 30000);
    m.recordApi('/api_port/port', parseMicros: 4000, buildMicros: 10000);
    m.recordApi('/api_get_member/questlist', parseMicros: 1000, buildMicros: 2000);
    final port = m.api['/api_port/port']!;
    expect(port.count, 2);
    expect(port.parseTotal ~/ port.count, 6000);
    expect(port.parseMax, 8000);
    expect(port.buildMax, 30000);
    expect(m.slowestApis.map((s) => s.path), ['/api_port/port', '/api_get_member/questlist']);

    // 重いフレーム: 直前 (1秒以内) の通信を添える
    m.recordFrame(5, 5);
    now = now.add(const Duration(milliseconds: 300));
    m.recordFrame(25, 4);
    now = now.add(const Duration(seconds: 3));
    m.recordFrame(3, 40);
    expect(m.frames, 3);
    expect(m.slowFrameCount, 2);
    expect(m.slowFrames.map((f) => f.lastPath), ['/api_get_member/questlist', null]);
    expect(m.slowFrames.last.worst, 40);

    for (var i = 0; i < 30; i++) {
      m.recordFrame(20, 0);
    }
    expect(m.slowFrames.length, PerfMonitor.keepSlowFrames);

    final text = perfReportText(m);
    expect(text, contains('/api_port/port 2回 読込 6.0/8.0 作直 20.0/30.0'));
    expect(text, contains('重いフレーム 32'));

    m.reset();
    expect(m.api, isEmpty);
    expect(m.frames, 0);
    expect(m.slowFrames, isEmpty);
  });

  testWidgets('PerfMonitor measures the parse and the next frame', (tester) async {
    final m = PerfMonitor();
    var parsed = false;
    m.measureApi('/api_port/port', () => parsed = true);
    expect(parsed, isTrue);
    expect(m.api, isEmpty, reason: '作り直しの時間はフレームの後で記録する');
    await tester.pump();
    expect(m.api['/api_port/port']!.count, 1);
  });

  testWidgets('performance page lists the records', (tester) async {
    final m = PerfMonitor()..reset();
    m.recordApi('/api_port/port', parseMicros: 12000, buildMicros: 3000);
    m.recordFrame(30, 2);
    await tester.pumpWidget(CupertinoApp(home: PerfPage(monitor: m)));
    expect(find.text('/api_port/port'), findsOneWidget);
    expect(find.text('読み込み 12.0 / 12.0・作り直し 3.0 / 3.0'), findsOneWidget);
    expect(find.text('処理 30.0ms・描画 2.0ms'), findsOneWidget);
    expect(find.text('直前の通信 /api_port/port'), findsOneWidget);

    await tester.tap(find.text('リセット'));
    await tester.pump();
    expect(find.text('/api_port/port'), findsNothing);
    expect(find.text('まだ記録がありません'), findsNWidgets(2));
  });

  test('quest progress is saved together after a short wait', () async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final data = container.read(Provider(_data));
    data.trackQuestProgress('/api_req_kousyou/remodel_slot', {'api_result': 1, 'api_data': {}}, null);
    expect(localStorage.getString('KC_QUEST_PROGRESS'), isNull, reason: 'すぐには書かない');
    KancolleData.flushQuestProgress();
    expect(localStorage.getString('KC_QUEST_PROGRESS'), isNotNull);

    await localStorage.remove('KC_QUEST_PROGRESS');
    data.trackQuestProgress('/api_req_kousyou/remodel_slot', {'api_result': 1, 'api_data': {}}, null);
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(localStorage.getString('KC_QUEST_PROGRESS'), isNotNull);
    // 書くものがなければ何もしない
    KancolleData.flushQuestProgress();
  });
}
