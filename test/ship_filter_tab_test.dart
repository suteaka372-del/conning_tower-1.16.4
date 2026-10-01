import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/ship_filter.dart';
import 'package:conning_tower/pages/dashboard.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/widgets/kancolle_ship_viewer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Ship _ship(int uid, {int shipType = 2, int asw = 60, int condition = 49}) => Ship(
      uid: uid,
      shipId: 100 + uid,
      name: 'ship$uid',
      level: 99,
      nowHP: 30,
      maxHP: 30,
      shipType: shipType,
      condition: condition,
      antiSubmarine: [asw, 99],
      equipment: [],
    );

final _ships = [
  _ship(1, asw: 70, condition: 40),
  _ship(2, asw: 70, condition: 85),
  _ship(3, asw: 40, condition: 60),
  _ship(4, shipType: 3, asw: 90, condition: 99),
];

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
      fleet: Fleet(ships: _ships, equipment: {}),
      ref: ref,
      dataInfo: DataInfo(),
      battleInfo: BattleInfo(),
    );

/// showFilterTab で「艦娘フィルター」タブと別のタブを切り替える
Widget _app({required ValueNotifier<bool> showFilterTab}) => ProviderScope(
      overrides: [kancolleDataProvider.overrideWith(_data)],
      child: CupertinoApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        locale: const Locale('ja'),
        home: ValueListenableBuilder<bool>(
          valueListenable: showFilterTab,
          builder: (context, show, _) => show ? const ShipFilterTab() : const Text('other tab'),
        ),
      ),
    );

void main() {
  setUp(() async {
    await S.load(const Locale('ja'));
  });

  testWidgets('selected filter survives tab switches and app restarts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.resetPhysicalSize);

    final showFilterTab = ValueNotifier(true);
    await tester.pumpWidget(_app(showFilterTab: showFilterTab));
    await tester.pumpAndSettle();
    expect(find.text('ship4'), findsOneWidget);

    await tester.tap(find.text(kDefaultShipFilterPresets.first.name));
    await tester.pumpAndSettle();
    expect(find.text('ship3'), findsNothing);
    expect(find.text('ship4'), findsNothing);

    // switch to another tab and back: filter still applied
    showFilterTab.value = false;
    await tester.pumpAndSettle();
    expect(find.text('other tab'), findsOneWidget);
    showFilterTab.value = true;
    await tester.pumpAndSettle();
    expect(find.text('ship2'), findsOneWidget);
    expect(find.text('ship3'), findsNothing);
    expect(find.text('ship4'), findsNothing);

    // app restart (new ProviderScope): restored from saved name
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(showFilterTab: ValueNotifier(true)));
    await tester.pumpAndSettle();
    expect(find.text('ship2'), findsOneWidget);
    expect(find.text('ship4'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('dashboard tab order: ship filter between operation and fleet', () {
    final dashboard = Dashboard.kancolle(notifyParent: () {});
    final titles = dashboard.titles;
    final operationIndex = titles.indexOf(S.current.KCDashboardOperation);
    expect(titles[operationIndex + 1], '艦娘フィルター');
    expect(titles[operationIndex + 2], S.current.KCDashboardFleet);
    expect(titles[kDashboardBattleReportIndex], S.current.KCDashboardBattleReport);
    expect(dashboard.children[operationIndex + 1], isA<ShipFilterTab>());

    final bottomTab = Dashboard.kancolleWithBottomTab(notifyParent: () {});
    expect(bottomTab.titles, titles);
    expect(bottomTab.children[kDashboardBattleReportIndex].runtimeType,
        dashboard.children[kDashboardBattleReportIndex].runtimeType);
  });
}
