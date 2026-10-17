import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/air_battle_record.dart';
import 'package:conning_tower/models/feature/kancolle/anti_air_cut_in.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/widgets/kancolle_air_battle_section.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _round({
  required List<int> s1,
  List<int>? s2,
  int? seiku,
  Map<String, dynamic>? airFire,
}) =>
    {
      'api_stage1': {
        'api_f_count': s1[0],
        'api_f_lostcount': s1[1],
        'api_e_count': s1[2],
        'api_e_lostcount': s1[3],
        if (seiku != null) 'api_disp_seiku': seiku,
      },
      if (s2 != null)
        'api_stage2': {
          'api_f_count': s2[0],
          'api_f_lostcount': s2[1],
          'api_e_count': s2[2],
          'api_e_lostcount': s2[3],
          if (airFire != null) 'api_air_fire': airFire,
        },
      'api_stage3': null,
    };

// 昼戦: 基地航空隊 (第1航空隊 2波、第2航空隊 1波)、噴式強襲、航空戦 (摩耶が第10種)
final _dayBattle = {
  'api_air_base_attack': [
    {'api_base_id': 1, ..._round(s1: [18, 2, 30, 12], s2: [16, 1, 0, 0])},
    {'api_base_id': 1, ..._round(s1: [18, 1, 18, 9])},
    {'api_base_id': 2, ..._round(s1: [18, 0, 9, 4])},
  ],
  'api_injection_kouku': _round(s1: [4, 0, 5, 3]),
  'api_kouku': _round(
    s1: [72, 5, 60, 41],
    s2: [40, 3, 19, 7],
    seiku: 2,
    airFire: {'api_idx': 1, 'api_kind': 10, 'api_use_items': [308, 307]},
  ),
  'api_kouku2': null,
};

Ship _ship(int uid, int shipId, String name) =>
    Ship(uid: uid, shipId: shipId, name: name, level: 99, nowHP: 50, maxHP: 50, shipType: 5, equipment: const []);

void main() {
  setUp(() => Intl.defaultLocale = 'ja');

  test('each air battle is read in order with the AA cut-in', () {
    final record = AirBattleRecord()
      ..addBattle('/api_req_sortie/battle', _dayBattle,
          shipAt: (index, {required friendly}) => index == 1 ? (2, '摩耶改二') : null);
    // ゲームと同じ順: 噴式強襲 → 基地航空隊 → 航空戦
    expect(record.phases.map((p) => p.label), [
      '噴式強襲',
      '第1基地航空隊 第1波',
      '第1基地航空隊 第2波',
      '第2基地航空隊 第1波',
      '航空戦',
    ]);
    final main = record.phases.last;
    expect(main.airSuperiority, 2);
    expect(main.stage1!.friendCount, 72);
    expect(main.stage1!.enemyLost, 41);
    expect(main.stage2!.friendLost, 3);
    expect(main.cutIn!.kind, 10);
    expect(main.cutIn!.shipName, '摩耶改二');
    expect(main.cutIn!.useItems, [308, 307]);
    expect(record.phases[1].stage2!.friendCount, 16);
    expect(record.phases[1].airSuperiority, isNull); // 制空は本隊の航空戦だけ

    // 航空戦 (2波) と空襲
    final airBattle = AirBattleRecord()
      ..addBattle('/api_req_sortie/airbattle', {
        'api_kouku': _round(s1: [50, 2, 40, 20]),
        'api_kouku2': _round(s1: [48, 1, 20, 10]),
      });
    expect(airBattle.phases.map((p) => p.label), ['航空戦 第1波', '航空戦 第2波']);
    final raid = AirBattleRecord()..addBattle('/api_req_sortie/ld_airbattle', {'api_kouku': _round(s1: [0, 0, 80, 0])});
    expect(raid.phases.single.label, '空襲');
    // 航空戦のない戦闘 (夜戦など) は何も足さない
    expect((AirBattleRecord()..addBattle('/api_req_battle_midnight/battle', {'api_hougeki': {}})).phases, isEmpty);
  });

  testWidgets('battle tab shows the air battles at the end and clears on the next node', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    await S.load(const Locale('ja'));
    tester.view.physicalSize = const Size(340, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late KancolleData data;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        kancolleDataProvider.overrideWith((ref) {
          data = KancolleData(
            queue: OperationQueue(map: {}),
            squads: [],
            seaForceBase: SeaForceBase(
              resource: const SeaForceBaseResource(fuel: 0, ammo: 0, steel: 0, bauxite: 0, instantCreateShip: 0,
                  instantRepairs: 0, developmentMaterials: 0, improvementMaterials: 0),
              admiral: const Admiral(name: '', level: 1, rank: 10, maxShip: 0, maxItem: 0),
            ),
            fleet: Fleet(ships: [], equipment: {}),
            ref: ref,
            dataInfo: DataInfo(),
            battleInfo: BattleInfo(inBattleSquads: [
              Squad(id: 1, name: '第1艦隊', ships: [_ship(1, 503, '鈴谷改二'), _ship(2, 428, '摩耶改二')]),
            ]),
            questProgress: null,
          );
          return data;
        }),
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
        home: CupertinoPageScaffold(
          child: Consumer(builder: (context, ref, _) {
            ref.watch(kancolleDataProvider);
            return ListView(children: const [KancolleAirBattleSection()]);
          }),
        ),
      ),
    ));
    expect(find.text('航空戦'), findsNothing); // 航空戦がなければ出さない

    data.recordAirBattle('/api_req_sortie/battle', {'api_result': 1, 'api_data': _dayBattle});
    data.recordAirBattle('/api_req_battle_midnight/battle', {'api_result': 1, 'api_data': {'api_hougeki': {}}});
    data.recordAirBattle('/api_req_sortie/battleresult', {'api_result': 1, 'api_data': {}});
    final container = ProviderScope.containerOf(tester.element(find.byType(ListView)));
    container.read(kancolleDataProvider.notifier).state = data.copyWith();
    await tester.pump();

    expect(find.text('航空戦'), findsWidgets);
    expect(find.text('第1基地航空隊 第2波'), findsOneWidget);
    expect(find.textContaining('味方 72機', findRichText: true), findsOneWidget);
    expect(find.textContaining('敵 60機', findRichText: true), findsOneWidget);
    expect(find.textContaining('摩耶改二: 第10種', findRichText: true), findsOneWidget);
    final kind10 = kAntiAirCutInKinds.firstWhere((k) => k.id == 10);
    expect(find.textContaining(kind10.conditions.first.description, findRichText: true), findsOneWidget);
    expect(find.text(S.current.KCAirBattleSuperiority), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 次のマスへ: 消える
    data.recordAirBattle('/api_req_map/next', {'api_result': 1, 'api_data': {}});
    container.read(kancolleDataProvider.notifier).state = data.copyWith();
    await tester.pump();
    expect(find.text('第1基地航空隊 第2波'), findsNothing);
  });
}
