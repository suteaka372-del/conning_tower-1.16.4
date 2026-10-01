import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/ship_filter.dart';
import 'package:conning_tower/widgets/kancolle_ship_filter_editor.dart';
import 'package:flutter/cupertino.dart';
import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/widgets/kancolle_ship_viewer.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Ship _ship(int uid,
        {int shipType = 2, int asw = 60, int condition = 49, int level = 99, List<Equipment> equipment = const []}) =>
    Ship(
      uid: uid,
      shipId: 100 + uid,
      name: 'ship$uid',
      level: level,
      nowHP: 30,
      maxHP: 30,
      shipType: shipType,
      condition: condition,
      antiSubmarine: [asw, 99],
      equipment: [...equipment],
    );

final _sonar = Equipment(id: 1, itemId: 46, type: [1, 10, 14, 18, 0], asw: 10, name: '九三式水中聴音機');

void main() {
  group('ShipFilterPreset', () {
    test('base ASW excludes equipment', () {
      expect(ShipStat.baseAswOf(_ship(1, asw: 80, equipment: [_sonar, _sonar])), 60);
      expect(ShipStat.asw.valueOf(_ship(1, asw: 80, equipment: [_sonar])), 80);
    });

    test('default preset: destroyers with base ASW >= 50, condition descending', () {
      final preset = kDefaultShipFilterPresets.first;
      final ships = [
        _ship(1, asw: 70, condition: 40),
        _ship(2, asw: 70, condition: 85),
        _ship(3, asw: 55, condition: 60, equipment: [_sonar]), // base 45 -> excluded
        _ship(4, shipType: 3, asw: 90, condition: 99), // light cruiser -> excluded
        _ship(5, asw: 50, condition: 49),
      ];
      expect(preset.apply(ships).map((s) => s.uid), [2, 5, 1]);
    });

    test('second default preset uses base ASW 64', () {
      final preset = kDefaultShipFilterPresets[1];
      final ships = [_ship(1, asw: 63), _ship(2, asw: 64), _ship(3, asw: 80, equipment: [_sonar])];
      expect(preset.apply(ships).map((s) => s.uid), [2, 3]);
    });

    test('json round trip and decode fallback', () {
      final presets = [
        const ShipFilterPreset(
          name: 'test',
          shipTypes: [2, 3],
          conditions: [
            StatCondition(stat: ShipStat.baseAsw, op: CompareOp.gte, value: 64),
            StatCondition(stat: ShipStat.level, op: CompareOp.lte, value: 98),
          ],
          sortKeys: [SortKey(ShipStat.condition, descending: false), SortKey(ShipStat.level)],
        ),
      ];
      final decoded = ShipFilterStore.decode(ShipFilterStore.encode(presets));
      expect(decoded.length, 1);
      expect(decoded.first.name, 'test');
      expect(decoded.first.shipTypes, [2, 3]);
      expect(decoded.first.conditions.map((c) => c.text), presets.first.conditions.map((c) => c.text));
      expect(decoded.first.sortKeys.map((k) => k.stat), [ShipStat.condition, ShipStat.level]);
      expect(decoded.first.sortKeys.map((k) => k.descending), [false, true]);

      expect(ShipFilterStore.decode(null).length, kDefaultShipFilterPresets.length);
      expect(ShipFilterStore.decode('broken').length, kDefaultShipFilterPresets.length);
      expect(ShipFilterStore.decode('[]'), isEmpty); // all presets deleted
    });

    test('filters saved in the old format (one sort key) still load', () {
      final decoded = ShipFilterStore.decode(
          '[{"name":"old","shipTypes":[2],"conditions":[],"sortStat":"condition","descending":false}]');
      expect(decoded.single.sortKeys.single.stat, ShipStat.condition);
      expect(decoded.single.sortKeys.single.descending, isFalse);
    });

    test('multiple sort keys: condition desc, then level desc, then base ASW asc', () {
      const preset = ShipFilterPreset(name: 'multi', sortKeys: [
        SortKey(ShipStat.condition),
        SortKey(ShipStat.level),
        SortKey(ShipStat.baseAsw, descending: false),
      ]);
      final ships = [
        _ship(1, condition: 49, level: 90),
        _ship(2, condition: 49, level: 99, asw: 70),
        _ship(3, condition: 85, level: 50),
        _ship(4, condition: 49, level: 99, asw: 60),
        _ship(5, condition: 30, level: 175),
      ];
      expect(preset.apply(ships).map((s) => s.uid), [3, 4, 2, 1, 5]);
      expect(preset.displayStats, [ShipStat.condition, ShipStat.level, ShipStat.baseAsw]);
    });

    test('display stats are unique and start with the sort stat', () {
      expect(kDefaultShipFilterPresets.first.displayStats, [ShipStat.condition, ShipStat.baseAsw]);
    });
  });

  testWidgets('filter editor saves the edited preset', (tester) async {
    ShipFilterPreset? result;
    await tester.pumpWidget(CupertinoApp(
      home: Builder(
        builder: (context) => CupertinoButton(
          child: const Text('open'),
          onPressed: () async {
            result = await Navigator.of(context).push<ShipFilterPreset>(CupertinoPageRoute(
              builder: (_) => KancolleShipFilterEditor(
                initial: kDefaultShipFilterPresets.first,
                shipTypeOptions: const {'駆逐艦': [2], '軽巡洋艦': [3]},
              ),
            ));
          },
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // change the value 50 -> 64, add a 2nd sort key (Lv) and save
    await tester.enterText(find.byType(CupertinoTextField).last, '64');
    final addSortKey = find.byIcon(CupertinoIcons.add).last;
    await tester.ensureVisible(addSortKey);
    await tester.pumpAndSettle();
    await tester.tap(addSortKey);
    await tester.pumpAndSettle();
    final saveButton = find.descendant(of: find.byType(CupertinoNavigationBar), matching: find.byType(CupertinoButton));
    await tester.tap(saveButton.last);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.shipTypes, [2]);
    expect(result!.conditions.single.value, 64);
    expect(result!.conditions.single.stat, ShipStat.baseAsw);
    expect(result!.sortKeys.map((k) => k.stat), [ShipStat.condition, ShipStat.level]);
    expect(result!.sortKeys.every((k) => k.descending), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ship viewer shows presets and filters the list', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await S.load(const Locale('ja'));
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.resetPhysicalSize);

    final ships = [
      _ship(1, asw: 70, condition: 40),
      _ship(2, asw: 70, condition: 85),
      _ship(3, asw: 40, condition: 60),
      _ship(4, shipType: 3, asw: 90, condition: 99),
    ];
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
              fleet: Fleet(ships: ships, equipment: {}),
              ref: ref,
              dataInfo: DataInfo(),
              battleInfo: BattleInfo(),
            )),
      ],
      child: CupertinoApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        locale: const Locale('ja'),
        home: const KancolleShipViewer(),
      ),
    ));
    await tester.pumpAndSettle();

    // all 4 ships without filter
    expect(find.text('ship1'), findsOneWidget);
    expect(find.text('ship4'), findsOneWidget);

    await tester.tap(find.text(kDefaultShipFilterPresets.first.name));
    await tester.pumpAndSettle();

    expect(find.text('ship1'), findsOneWidget);
    expect(find.text('ship2'), findsOneWidget);
    expect(find.text('ship3'), findsNothing);
    expect(find.text('ship4'), findsNothing);
    // sorted by condition descending
    expect(tester.getTopLeft(find.text('ship2')).dy, lessThan(tester.getTopLeft(find.text('ship1')).dy));
    expect(tester.takeException(), isNull);
  });
}
