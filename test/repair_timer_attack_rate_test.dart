import 'package:conning_tower/models/feature/kancolle/attack_rate.dart';
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

      await tester.pumpWidget(CupertinoApp(
        home: CupertinoPageScaffold(
          child: ListView(children: [
            KancolleRepairTimerSection(squad: squad, repairTimer: state, shipInfo: null),
            KancolleAttackRateSection(ship: ships[1], squad: squad, shipInfo: null),
          ]),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('#2'), findsOneWidget);
      expect(find.textContaining('+4'), findsOneWidget); // 25 min -> floor(25*60/360) = 4
      expect(find.textContaining('#3'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
