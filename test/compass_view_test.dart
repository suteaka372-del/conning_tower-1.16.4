import 'dart:convert';

import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/pages/dashboard_pages/simulator_page.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => Intl.defaultLocale = 'ja');

  testWidgets('compass view: boss chance, branch reasons, sortie check', (tester) async {
    // 1-5 で D→E に進んだ記録 (4隻の駆逐なら D→F のはず)
    final log = jsonEncode([
      {
        'm': 15,
        't': DateTime(2026, 10, 25, 9, 5).millisecondsSinceEpoch,
        's': [
          {'f': 'Start', 't': 'A', 'p': 1.0, 'r': '固定'},
          {'f': 'A', 't': 'D', 'p': 1.0, 'r': '固定'},
          {'f': 'D', 't': 'E', 'p': 0.0, 'r': 'それ以外'},
        ],
      },
    ]);
    SharedPreferences.setMockInitialValues({'compass_map': 15, 'compass_log': log});
    localStorage = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(402, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var uid = 1;
    Ship dd() => Ship(uid: uid++, shipId: 1, name: '吹雪', level: 50, nowHP: 30, maxHP: 30, shipType: kDD, speed: 10, scout: [10, 10]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        kancolleDataProvider.overrideWith((ref) => KancolleData(
              queue: OperationQueue(map: {}),
              squads: [
                Squad(id: 1, name: '第1艦隊', ships: [dd(), dd(), dd(), dd()]),
                Squad(id: 2, name: '第2艦隊', ships: []),
              ],
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
                admiral: const Admiral(name: '', level: 120, rank: 10, maxShip: 0, maxItem: 0),
              ),
              fleet: Fleet(ships: [], equipment: {}),
              ref: ref,
              dataInfo: DataInfo(),
              battleInfo: BattleInfo(),
            )),
      ],
      child: const CupertinoApp(home: CupertinoPageScaffold(child: CompassView())),
    ));
    await tester.pump();

    expect(find.text('1-5 鎮守府近海'), findsOneWidget);
    expect(find.text('ボス (Jマス) に着く確率'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('駆逐4 / 高速以上統一'), findsOneWidget);
    expect(find.textContaining('Dマス (来る確率 100%)'), findsOneWidget);
    expect(find.textContaining('→ F 100%\nそれ以外'), findsOneWidget);
    expect(find.text('Start→A→D→E'), findsOneWidget);
    expect(find.text('予測と違う: D→E (予測では0%)'), findsOneWidget);

    // 海域を切り替える (2-x → 2-5 は索敵スコアも出る)
    await tester.tap(find.text('2-x'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2-5'));
    await tester.pumpAndSettle();
    expect(find.text('2-5 沖ノ島沖'), findsOneWidget);
    expect(find.text('索敵スコア (分岐点係数1)'), findsOneWidget);
    expect(localStorage.getInt('compass_map'), 25);
    expect(tester.takeException(), isNull);
  });
}
