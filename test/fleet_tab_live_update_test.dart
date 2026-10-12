import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/quest_assistant.dart';
import 'package:conning_tower/models/feature/kancolle/quest_progress.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/pages/dashboard_pages/squad_info.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('fleet tab follows a new quest list', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    await S.load(const Locale('ja'));
    tester.view.physicalSize = const Size(393, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tracker = QuestProgressTracker();
    Ship ship(int uid, int type) => Ship(uid: uid, shipId: uid, name: 's$uid', level: 50, nowHP: 30, maxHP: 30,
        shipType: type, condition: 49, speed: 10, attack: [1, 1], antiAircraft: [1, 1], antiSubmarine: [1, 1],
        scout: [1, 1], exp: [0, 1], equipment: const []);
    final squads = [Squad(id: 1, name: '第1艦隊', ships: [ship(1, 3), ship(2, 2)])];
    KancolleData make(Ref ref, QuestAssistant? qa) => KancolleData(
          queue: OperationQueue(map: {}),
          squads: squads,
          seaForceBase: SeaForceBase(
            resource: const SeaForceBaseResource(fuel: 0, ammo: 0, steel: 0, bauxite: 0, instantCreateShip: 0,
                instantRepairs: 0, developmentMaterials: 0, improvementMaterials: 0),
            admiral: const Admiral(name: '', level: 1, rank: 10, maxShip: 0, maxItem: 0),
          ),
          fleet: Fleet(ships: [], equipment: {}),
          ref: ref,
          dataInfo: DataInfo(),
          battleInfo: BattleInfo(),
          questAssistant: qa,
          questProgress: tracker,
        );
    late WidgetRef widgetRef;
    await tester.pumpWidget(ProviderScope(
      overrides: [kancolleDataProvider.overrideWith((ref) => make(ref, null))],
      child: MaterialApp(
        localizationsDelegates: const [S.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        supportedLocales: S.delegate.supportedLocales,
        locale: const Locale('ja'),
        home: Consumer(builder: (context, ref, _) {
          widgetRef = ref;
          return const CupertinoPageScaffold(child: SquadInfo());
        }),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('受注中の任務の編成条件'), findsNothing);

    final notifier = widgetRef.read(kancolleDataProvider.notifier);
    notifier.state = make(notifier.state.ref, QuestAssistant(ready: [Quest(id: 257, state: 2, type: 3, title: '「水雷戦隊」南西へ！')], done: []));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('受注中の任務の編成条件'), findsOneWidget);
  });
}
