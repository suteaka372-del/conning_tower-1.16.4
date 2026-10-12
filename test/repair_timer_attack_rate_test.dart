import 'dart:convert';

import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/attack_rate.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/raw_data.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/widgets/kancolle_attack_rate_section.dart';
import 'package:conning_tower/widgets/kancolle_repair_timer_section.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

Equipment _equip(int itemId, int category, {int icon = 0, int los = 0, String name = ''}) =>
    Equipment(id: itemId * 10, itemId: itemId, type: [0, 0, category, icon, 0], los: los, name: name);

Ship _ship(
  int uid,
  int shipId, {
  int shipType = 2,
  int nowHP = 40,
  int maxHP = 40,
  int level = 99,
  int luck = 20,
  int condition = 49,
  int scout = 50,
  List<Equipment> equipment = const [],
}) =>
    Ship(
      uid: uid,
      shipId: shipId,
      name: 'ship$uid',
      level: level,
      nowHP: nowHP,
      maxHP: maxHP,
      shipType: shipType,
      luck: [luck, 99],
      scout: [scout, 99],
      condition: condition,
      fuel: 100,
      bull: 100,
      onSlot: [0, 0, 0, 0, 0],
      equipment: [...equipment],
    );

final _repairFacility = _equip(86, 31, name: '艦艇修理施設');

KancolleData _data(Ref ref, List<Squad> squads, List<Ship> allShips, RepairTimerState state) => KancolleData(
      queue: OperationQueue(map: {}),
      squads: squads,
      seaForceBase: SeaForceBase(
        resource: const SeaForceBaseResource(fuel: 0, ammo: 0, steel: 0, bauxite: 0, instantCreateShip: 0,
            instantRepairs: 0, developmentMaterials: 0, improvementMaterials: 0),
        admiral: const Admiral(name: '', level: 1, rank: 10, maxShip: 0, maxItem: 0),
      ),
      fleet: Fleet(ships: allShips, equipment: {}),
      ref: ref,
      dataInfo: DataInfo(),
      battleInfo: BattleInfo(),
      repairTimer: state,
    );

/// 艦隊タブと同じく、タイマーの表示は kancolleDataProvider から読む
Widget _host(List<Squad> squads, RepairTimerState state, List<Widget> children, {List<Ship>? allShips}) =>
    ProviderScope(
      overrides: [
        kancolleDataProvider.overrideWith(
            (ref) => _data(ref, squads, allShips ?? [for (final s in squads) ...s.ships], state)),
      ],
      child: CupertinoApp(home: CupertinoPageScaffold(child: ListView(children: children))),
    );

void main() {
  group('Anchorage repair', () {
    test('bound and availability for Akashi Kai', () {
      final squad = Squad(id: 1, name: 'fleet', ships: [
        _ship(1, 187, shipType: 19, equipment: [_repairFacility]),
        _ship(2, 100, nowHP: 30, maxHP: 40),
        _ship(3, 101),
        _ship(4, 102, nowHP: 35),
      ]);
      final state = RepairTimerState();
      expect(RepairTimerState.anchorageRepairBound(squad), 3);
      expect(state.canAnchorageRepair(squad), isTrue);

      state.ndockTime = {2: 3600 * 1000};
      final info = state.anchorageRepairInfo(squad)!;
      expect(info.targets.map((e) => e.ship.uid), [2]);
      expect(info.targets.first.eligible, isTrue);
    });

    test('not available when flagship is heavily damaged or ships are too damaged', () {
      final state = RepairTimerState();
      final damagedFlagship = Squad(id: 1, name: 'fleet', ships: [
        _ship(1, 187, shipType: 19, nowHP: 10, equipment: [_repairFacility]),
        _ship(2, 100, nowHP: 30),
      ]);
      expect(state.canAnchorageRepair(damagedFlagship), isFalse);

      final tooDamaged = Squad(id: 1, name: 'fleet', ships: [
        _ship(1, 187, shipType: 19, equipment: [_repairFacility]),
        _ship(2, 100, nowHP: 20),
      ]);
      expect(state.canAnchorageRepair(tooDamaged), isFalse);

      final onExpedition = Squad(id: 2, name: 'fleet', operation: 5, ships: [
        _ship(1, 187, shipType: 19, equipment: [_repairFacility]),
        _ship(2, 100, nowHP: 30),
      ]);
      expect(state.canAnchorageRepair(onExpedition), isFalse);
    });

    test('Asahi Kai needs repair facilities', () {
      final state = RepairTimerState();
      final noFacility = Squad(id: 1, name: 'fleet', ships: [
        _ship(1, 958, shipType: 19),
        _ship(2, 100, nowHP: 30),
      ]);
      expect(RepairTimerState.anchorageRepairBound(noFacility), 0);
      expect(state.canAnchorageRepair(noFacility), isFalse);

      final withFacility = Squad(id: 1, name: 'fleet', ships: [
        _ship(1, 958, shipType: 19, nowHP: 39, equipment: [_repairFacility, _repairFacility]),
        _ship(2, 100, nowHP: 30),
        _ship(3, 101, nowHP: 30),
      ]);
      expect(RepairTimerState.anchorageRepairBound(withFacility), 2);
      expect(state.canAnchorageRepair(withFacility), isTrue);
    });

    test('heal amount and repair time (EO Calculator)', () {
      // damage 10, docking 3600s -> 360s per HP
      expect(RepairTimerState.healAmount(10, 3600, const Duration(minutes: 20), false), 3);
      expect(RepairTimerState.healAmount(10, 3600, const Duration(minutes: 30), false), 5);
      expect(RepairTimerState.healAmount(10, 3600, const Duration(minutes: 90), false), 10);
      expect(RepairTimerState.repairTime(10, 3600, 1, false), const Duration(minutes: 20));
      expect(RepairTimerState.repairTime(10, 3600, 6, false), const Duration(minutes: 36));
      // Akashi + Akashi: time x0.85
      expect(RepairTimerState.healAmount(10, 3600, const Duration(minutes: 30), true), 5);
      expect(RepairTimerState.repairTime(10, 3600, 6, true), const Duration(minutes: 31));
    });

    test('timer starts on port and resets on healing / fleet change', () {
      final state = RepairTimerState();
      var ships = [
        _ship(1, 187, shipType: 19, equipment: [_repairFacility]),
        _ship(2, 100, nowHP: 30),
      ];
      var squad = Squad(id: 1, name: 'fleet', ships: ships);

      state.evacuate([squad], ships);
      state.onPort([squad], null);
      final first = state.anchorageRepairTimer!;

      // Port again without healing: timer is kept
      state.evacuate([squad], ships);
      state.onPort([squad], null);
      expect(state.anchorageRepairTimer, first);

      // Port after anchorage repair healed a ship: timer resets
      state.evacuate([squad], ships);
      final healed = [ships[0], ships[1].copyWith(nowHP: 33)];
      squad = Squad(id: 1, name: 'fleet', ships: healed);
      state.anchorageRepairTimer = first.subtract(const Duration(minutes: 5));
      state.onPort([squad], null);
      expect(state.anchorageRepairTimer!.isAfter(first), isTrue);

      // Fleet change with a repair ship flagship resets the timer
      state.anchorageRepairTimer = first.subtract(const Duration(minutes: 5));
      state.onHenseiChange(squad, 100);
      expect(state.anchorageRepairTimer!.isAfter(first), isTrue);

      // Removing all escorts (-2) does not reset
      final before = state.anchorageRepairTimer;
      state.onHenseiChange(squad, -2);
      expect(state.anchorageRepairTimer, before);
    });

    test('Nosaki condition repair', () {
      final state = RepairTimerState();
      final squad = Squad(id: 1, name: 'fleet', ships: [
        _ship(1, 100),
        _ship(2, 996, shipType: 22),
      ]);
      expect(RepairTimerState.hasNosaki(squad), isTrue);
      expect(state.canConditionRepair(squad, null), isTrue);

      final tired = Squad(id: 1, name: 'fleet', ships: [
        _ship(1, 100),
        _ship(2, 996, shipType: 22, condition: 20),
      ]);
      expect(state.canConditionRepair(tired, null), isFalse);
    });
  });

  group('Attack rate', () {
    final mainGun = _equip(7, 3, icon: 3, name: '35.6cm連装砲');
    final subGun = _equip(12, 4, icon: 4, name: '15.5cm三連装副砲');
    final apShell = _equip(36, 19, icon: 13, name: '九一式徹甲弾');
    final recon = _equip(25, 10, icon: 10, los: 5, name: '零式水上偵察機');
    final torpedo = _equip(15, 5, icon: 5, name: '61cm四連装(酸素)魚雷');
    final surfaceRadar = _equip(88, 12, icon: 11, los: 5, name: '22号対水上電探改四');

    test('battleship day cut-in list and rates sum to 100%', () {
      final battleship = _ship(1, 80, shipType: 9, luck: 30, equipment: [mainGun, mainGun, apShell, recon]);
      final squad = Squad(id: 1, name: 'fleet', ships: [battleship, _ship(2, 100)]);
      expect(AttackRateCalculator.dayAttackKinds(battleship),
          [DayAttackKind.cutinMainMain, DayAttackKind.doubleShelling, DayAttackKind.shelling]);

      final rates = AttackRateCalculator.calculate(ship: battleship, squad: squad, shipInfo: null);
      final totalAP = rates.day.fold<double>(0, (sum, r) => sum + r.rate);
      final totalAS = rates.day.fold<double>(0, (sum, r) => sum + r.rateAS!);
      expect(totalAP, closeTo(100, 0.001));
      expect(totalAS, closeTo(100, 0.001));
      // flagship bonus makes AP rate higher than AS rate
      expect(rates.day.first.rate, greaterThan(rates.day.first.rateAS!));
    });

    test('destroyer night cut-in', () {
      final destroyer = _ship(1, 100, shipType: 2, luck: 40, equipment: [mainGun, torpedo, surfaceRadar]);
      expect(AttackRateCalculator.nightAttackKinds(destroyer).first, NightAttackKind.cutinTorpedoRadar);

      final squad = Squad(id: 1, name: 'fleet', ships: [destroyer]);
      final rates = AttackRateCalculator.calculate(ship: destroyer, squad: squad, shipInfo: null);
      // no master data: firepower + torpedo unknown -> cannot judge night attack
      expect(rates.canAttackAtNight, isFalse);
    });

    test('night double attack and main-sub cut-in', () {
      final ship = _ship(1, 80, shipType: 9, equipment: [mainGun, mainGun, subGun]);
      expect(AttackRateCalculator.nightAttackKinds(ship),
          [NightAttackKind.cutinMainSub, NightAttackKind.normalAttack]);

      final ship2 = _ship(2, 80, shipType: 9, equipment: [mainGun, subGun]);
      expect(AttackRateCalculator.nightAttackKinds(ship2),
          [NightAttackKind.doubleShelling, NightAttackKind.normalAttack]);
    });
  });

  group('Widgets', () {
    testWidgets('repair timer and attack rate sections render', (tester) async {
      final ships = [
        _ship(1, 187, shipType: 19, equipment: [_repairFacility]),
        _ship(2, 100, nowHP: 30, maxHP: 40),
        _ship(3, 996, shipType: 22, nowHP: 10),
      ];
      final squad = Squad(id: 1, name: 'fleet', ships: ships);
      final state = RepairTimerState()
        ..ndockTime = {2: 3600 * 1000}
        ..anchorageRepairTimer = DateTime.now().subtract(const Duration(minutes: 25))
        ..conditionRepairTimer = DateTime.now().subtract(const Duration(minutes: 3));

      await tester.pumpWidget(_host([squad], state, [
        const KancolleRepairTimerSection(squadIndex: 0),
        KancolleAttackRateSection(ship: ships[1], squad: squad, shipInfo: null),
      ]));
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('#2'), findsOneWidget);
      expect(find.textContaining('+4'), findsOneWidget); // 25 min -> floor(25*60/360) = 4
      expect(find.textContaining('#3'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('repair ship flagship is always shown with the reason', (tester) async {
      final squad = Squad(id: 1, name: 'fleet', ships: [
        _ship(1, 958, shipType: 19, equipment: [_repairFacility]),
        _ship(2, 100),
      ]);
      final state = RepairTimerState();
      expect(state.anchorageRepairBlockedReason(squad), isNotNull);

      await tester.pumpWidget(_host([squad], state, [const KancolleRepairTimerSection(squadIndex: 0)]));
      expect(find.byIcon(CupertinoIcons.wrench), findsOneWidget);
      expect(find.text('--:--'), findsOneWidget);
      expect(find.text(state.anchorageRepairBlockedReason(squad)!), findsOneWidget);

      // Not a repair ship flagship: nothing is shown
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host([Squad(id: 1, name: 'fleet', ships: [_ship(2, 100)])], RepairTimerState(),
          [const KancolleRepairTimerSection(squadIndex: 0)]));
      expect(find.byIcon(CupertinoIcons.wrench), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });

  test('repair ship detected by ship id when ship type is missing', () {
    final squad = Squad(id: 1, name: 'fleet', ships: [
      Ship(uid: 1, shipId: 187, level: 1, nowHP: 40, maxHP: 40),
      _ship(2, 100, nowHP: 30),
    ]);
    expect(RepairTimerState.hasRepairShipFlagship(squad), isTrue);
    expect(RepairTimerState().canAnchorageRepair(squad), isTrue);
  });

  group('Repair fleet stored in a preset', () {
    setUp(() => Intl.defaultLocale = 'ja');

    final akashi = _ship(1, 187, shipType: 19, equipment: [_repairFacility]);
    final damaged = _ship(2, 100, nowHP: 30, maxHP: 40);
    final nosaki = _ship(3, 996, shipType: 22);
    final other = _ship(4, 101);
    final other2 = _ship(5, 102);

    test('the timer keeps going and the repair fleet is remembered', () {
      final state = RepairTimerState();
      final repairFleet = [Squad(id: 1, name: '第1艦隊', ships: [akashi, nosaki, damaged])];
      state.evacuate(repairFleet, [akashi, nosaki, damaged]);
      state.onPort(repairFleet, null);
      final started = state.anchorageRepairTimer;
      expect(state.anchorageFleetShipIds, [1, 3, 2]);
      expect(state.showAnchorageAway(repairFleet), isFalse);

      // 編成記録で別の艦隊に切り替え (preset_select): タイマーはそのまま
      final swapped = [Squad(id: 1, name: '第1艦隊', ships: [other, other2])];
      state.rememberFleets(swapped);
      expect(state.anchorageRepairTimer, started);
      expect(state.showAnchorageAway(swapped), isTrue);
      expect(state.showConditionAway(swapped), isTrue);
      final remembered = state.rememberedAnchorageSquad([akashi, damaged, nosaki, other, other2])!;
      expect(remembered.ships.map((s) => s.uid), [1, 3, 2]);
      state.ndockTime = {2: 3600 * 1000};
      expect(state.canAnchorageRepairAway(swapped, [akashi, damaged, nosaki, other, other2]), isTrue);

      // 外している間の母港 (20分未満) でもタイマーは続く
      state.evacuate(swapped, [other, other2]);
      state.onPort(swapped, null);
      expect(state.anchorageRepairTimer, started);
      expect(state.anchorageFleetShipIds, [1, 3, 2]);

      // ✕ で消す -> 工作艦の艦隊が戻ったら次はまた表示する
      state.anchorageAwayDismissed = true;
      state.conditionAwayDismissed = true;
      expect(state.showAnchorageAway(swapped), isFalse);
      expect(state.showConditionAway(swapped), isFalse);
      state.rememberFleets(repairFleet);
      expect(state.anchorageAwayDismissed, isFalse);
      expect(state.conditionAwayDismissed, isFalse);
      expect(state.showAnchorageAway(repairFleet), isFalse); // 戻っている間は通常の表示
    });

    test('saved and restored after a restart', () {
      final state = RepairTimerState()
        ..anchorageRepairTimer = DateTime(2026, 10, 12, 10, 0)
        ..conditionRepairTimer = DateTime(2026, 10, 12, 10, 5)
        ..anchorageFleetShipIds = [1, 2]
        ..conditionFleetSeen = true
        ..anchorageAwayDismissed = true;
      final restored = RepairTimerState.fromJson(jsonDecode(jsonEncode(state.toJson())));
      expect(restored.anchorageRepairTimer, DateTime(2026, 10, 12, 10, 0));
      expect(restored.conditionRepairTimer, DateTime(2026, 10, 12, 10, 5));
      expect(restored.anchorageFleetShipIds, [1, 2]);
      expect(restored.conditionFleetSeen, isTrue);
      expect(restored.anchorageAwayDismissed, isTrue);
      expect(restored.conditionAwayDismissed, isFalse);
      expect(RepairTimerState.fromJson(null).anchorageRepairTimer, isNull);
    });

    testWidgets('fleet data loads the saved timer and preset_select keeps it', (tester) async {
      final saved = RepairTimerState()
        ..anchorageRepairTimer = DateTime.now().subtract(const Duration(minutes: 7))
        ..anchorageFleetShipIds = [1, 2];
      SharedPreferences.setMockInitialValues({'KC_REPAIR_TIMER': jsonEncode(saved.toJson())});
      localStorage = await SharedPreferences.getInstance();

      late KancolleData data;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          kancolleDataProvider.overrideWith((ref) {
            data = KancolleData(
              queue: OperationQueue(map: {}),
              squads: [Squad(id: 1, name: '第1艦隊', ships: [akashi, damaged])],
              seaForceBase: SeaForceBase(
                resource: const SeaForceBaseResource(fuel: 0, ammo: 0, steel: 0, bauxite: 0, instantCreateShip: 0,
                    instantRepairs: 0, developmentMaterials: 0, improvementMaterials: 0),
                admiral: const Admiral(name: '', level: 1, rank: 10, maxShip: 0, maxItem: 0),
              ),
              fleet: Fleet(ships: [akashi, damaged, other, other2], equipment: {}),
              ref: ref,
              dataInfo: DataInfo(),
              battleInfo: BattleInfo(),
            );
            return data;
          }),
        ],
        child: Consumer(builder: (context, ref, _) {
          ref.watch(kancolleDataProvider);
          return const SizedBox();
        }),
      ));
      final started = saved.anchorageRepairTimer!;
      expect(data.repairTimer.anchorageRepairTimer!.difference(started).inSeconds.abs(), lessThan(1));

      data.parse(RawData(
        source: 'https://example/kcsapi/api_req_hensei/preset_select',
        timestamp: 0,
        params: const {},
        data: jsonEncode({
          'api_result': 1,
          'api_result_msg': '成功',
          'api_data': {
            'api_member_id': 1,
            'api_id': 1,
            'api_name': '第1艦隊',
            'api_name_id': '',
            'api_mission': [0, 0, 0, 0],
            'api_flagship': '0',
            'api_ship': [4, 5, -1, -1, -1, -1],
          },
        }),
      ));
      expect(data.squads.first.ships.map((s) => s.uid), [4, 5]);
      expect(data.repairTimer.anchorageRepairTimer!.difference(started).inSeconds.abs(), lessThan(1));
      expect(data.repairTimer.showAnchorageAway(data.squads), isTrue);
      final stored = RepairTimerState.fromJson(jsonDecode(localStorage.getString('KC_REPAIR_TIMER')!));
      expect(stored.anchorageFleetShipIds, [1, 2]);
    });

    testWidgets('fleet 1 keeps showing the stored repair fleet until dismissed', (tester) async {
      SharedPreferences.setMockInitialValues({});
      localStorage = await SharedPreferences.getInstance();
      final state = RepairTimerState()
        ..ndockTime = {2: 3600 * 1000}
        ..anchorageRepairTimer = DateTime.now().subtract(const Duration(minutes: 25))
        ..conditionRepairTimer = DateTime.now().subtract(const Duration(minutes: 3))
        ..anchorageFleetShipIds = [1, 2]
        ..conditionFleetSeen = true;
      final squads = [
        Squad(id: 1, name: '第1艦隊', ships: [other]),
        Squad(id: 2, name: '第2艦隊', ships: [other2]),
      ];
      await tester.pumpWidget(_host(
        squads,
        state,
        [const KancolleRepairTimerSection(squadIndex: 0), const KancolleRepairTimerSection(squadIndex: 1)],
        allShips: [akashi, damaged, nosaki, other, other2],
      ));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('泊地修理 (外し中)'), findsOneWidget); // 第1艦隊だけ
      expect(find.textContaining('編成記録で戻して母港に戻ると回復'), findsOneWidget);
      expect(find.textContaining('+4'), findsOneWidget); // 戻せば 25分 -> +4
      expect(find.text('給糧艦(野埼) (外し中)'), findsOneWidget);
      expect(find.textContaining('野埼の艦隊を編成記録で外しています (あと 1'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(CupertinoIcons.xmark_circle_fill).first);
      await tester.pump();
      expect(find.text('泊地修理 (外し中)'), findsNothing);
      expect(find.text('給糧艦(野埼) (外し中)'), findsOneWidget);
      expect(RepairTimerState.fromJson(jsonDecode(localStorage.getString('KC_REPAIR_TIMER')!)).anchorageAwayDismissed,
          isTrue);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
