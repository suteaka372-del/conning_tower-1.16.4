import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/pages/dashboard.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('side dashboard with bottom tabs fits a 400x380 panel', (tester) async {
    // 艦娘フィルタータブ (4) を開いた状態にする
    SharedPreferences.setMockInitialValues({'dashboardIndex': 4});
    localStorage = await SharedPreferences.getInstance();
    selectedIndex = 0;
    await S.load(const Locale('ja'));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        kancolleDataProvider.overrideWith((ref) => KancolleData(
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
              fleet: Fleet(ships: [
                Ship(uid: 1, shipId: 1, name: 'ship1', level: 99, nowHP: 30, maxHP: 30, shipType: 2, condition: 49),
              ], equipment: {}),
              ref: ref,
              dataInfo: DataInfo(),
              battleInfo: BattleInfo(),
            )),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        locale: const Locale('ja'),
        home: Center(
          child: SizedBox(
            width: 400,
            height: 380,
            child: Dashboard.kancolleWithBottomTab(notifyParent: () {}),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // tabs are at the bottom, content above
    final tabBar = tester.getRect(find.byType(TabBar));
    expect(tabBar.bottom, closeTo(tester.getRect(find.byType(SizedBox).first).bottom, 1));
    expect(find.text('艦娘フィルター'), findsWidgets);
    expect(find.text('ship1'), findsOneWidget);
    expect(tester.getRect(find.text('ship1')).top, lessThan(tabBar.top));
    expect(tester.takeException(), isNull);
  });
}
