import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/anti_air_cut_in.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/widgets/kancolle_anti_air_cut_in_section.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

int _id = 1;

Equipment eq({required int category, int icon = 0, int aa = 0, int itemId = 0}) =>
    Equipment(id: _id++, itemId: itemId, type: [0, 0, category, icon, 0], aa: aa, level: 0);

// よく使う装備
Equipment highAngleDirector() => eq(category: 1, icon: 16, aa: 10, itemId: 122); // 10cm連装高角砲+高射装置
Equipment highAngle() => eq(category: 4, icon: 16, aa: 7, itemId: 10); // 12.7cm連装高角砲
Equipment airRadar({int aa = 4}) => eq(category: 12, icon: 11, aa: aa, itemId: 27); // 13号対空電探改
Equipment surfaceRadar() => eq(category: 12, icon: 11, aa: 1, itemId: 28); // 22号対水上電探
Equipment concentratedAaGun() => eq(category: 21, icon: 15, aa: 9, itemId: 131); // 25mm三連装機銃 集中配備
Equipment aaGun({int aa = 6}) => eq(category: 21, icon: 15, aa: aa, itemId: 40); // 25mm三連装機銃
Equipment director() => eq(category: 36, icon: 30, aa: 6, itemId: 121); // 94式高射装置

Ship ship(int shipId, List<Equipment> equipment, {int shipType = 2}) => Ship(
      uid: _id++,
      shipId: shipId,
      level: 99,
      nowHP: 30,
      maxHP: 30,
      shipType: shipType,
      equipment: equipment,
    );

GetDataApiDataApiMstShipEntity master(int id, int ctype) => GetDataApiDataApiMstShipEntity(
      apiId: id,
      apiSortId: id,
      apiName: 'ship $id',
      apiYomi: '',
      apiStype: 2,
      apiCtype: ctype,
    );

void main() {
  setUp(() => Intl.defaultLocale = 'ja');

  test('the table covers every kind with a priority', () {
    expect(kAntiAirCutInKinds.length, 52);
    expect(kAntiAirCutInPriorities.length, 52);
    for (final kind in kAntiAirCutInKinds) {
      expect(kAntiAirCutInPriorities, contains(kind.id));
    }
    expect(kAntiAirCutInKinds.firstWhere((k) => k.id == 5).rate, 0.544);
    expect(kAntiAirCutInKinds.firstWhere((k) => k.id == 49).rate, isNull);
  });

  test('type 5 and 8 for a generic ship, sequential rates', () {
    final result = shipAntiAirCutIns(ship(1, [highAngleDirector(), highAngleDirector(), airRadar()]));
    // 優先順位: 5 → 8
    expect(result.chances.map((c) => c.kind.id), [5, 8]);
    expect(result.chances[0].effectiveRate, closeTo(0.544, 1e-9));
    expect(result.chances[1].effectiveRate, closeTo(0.456 * 0.495, 1e-9));
    expect(result.total, closeTo(1 - 0.456 * 0.505, 1e-9));
    expect(result.chances[0].condition.description, '高角砲(高射装置付)×2 + 対空電探');
  });

  test('Akizuki class cannot use types 5, 7, 8', () {
    final akizuki = ship(330, [highAngleDirector(), highAngleDirector(), airRadar()]);
    final result = shipAntiAirCutIns(akizuki, shipClass: 54);
    final ids = result.chances.map((c) => c.kind.id).toList();
    expect(ids, containsAll([1, 2, 3]));
    expect(ids.contains(5), isFalse);
    expect(ids.contains(8), isFalse);
    expect(ids.first, 1); // 1種が最優先
  });

  test('ship specific kinds and the Maya Kai Ni exception', () {
    final maya = ship(428, [highAngle(), concentratedAaGun(), airRadar()], shipType: 5);
    final ids = shipAntiAirCutIns(maya).chances.map((c) => c.kind.id).toList();
    expect(ids, containsAll([10, 11])); // 12種は機銃2つが必要
    expect(ids.contains(13), isFalse); // 摩耶改二は13種が出ない
    // 同じ装備でも摩耶改二でなければ 10, 11 はない
    final other = ship(1, [highAngle(), concentratedAaGun(), airRadar()]);
    final otherIds = shipAntiAirCutIns(other).chances.map((c) => c.kind.id).toList();
    expect(otherIds.contains(10), isFalse);
    expect(otherIds, contains(13));
  });

  test('radar thresholds and AA gun ranges', () {
    // 対空1の電探は対空電探ではない
    final noAirRadar = ship(1, [highAngleDirector(), highAngleDirector(), surfaceRadar()]);
    expect(shipAntiAirCutIns(noAirRadar).isEmpty, isTrue);
    // 12種: 集中機銃 + 機銃(対空3以上) + 対空電探
    final type12 = ship(1, [concentratedAaGun(), aaGun(aa: 3), airRadar(aa: 2)]);
    expect(shipAntiAirCutIns(type12).chances.map((c) => c.kind.id), [12]);
    final notType12 = ship(1, [concentratedAaGun(), aaGun(aa: 2), airRadar(aa: 2)]);
    expect(shipAntiAirCutIns(notType12).isEmpty, isTrue);
  });

  test('expansion slot equipment counts', () {
    final s = Ship(
      uid: _id++,
      shipId: 1,
      level: 99,
      nowHP: 30,
      maxHP: 30,
      equipment: [highAngle()],
      exEquipment: [director()],
    );
    expect(shipAntiAirCutIns(s).chances.map((c) => c.kind.id), [9]);
  });

  test('unknown rates make the total unknown', () {
    // 吹雪改二: 49種 (発動率不明)
    final fubuki = ship(426, [highAngleDirector(), highAngleDirector(), airRadar()]);
    final result = shipAntiAirCutIns(fubuki);
    expect(result.chances.first.kind.id, 49);
    expect(result.chances.first.rate, isNull);
    expect(result.total, isNull);
    expect(fleetAntiAirCutInRate([fubuki], null), isNull);
  });

  test('fleet rate combines ships', () {
    final a = ship(1, [highAngleDirector(), airRadar()]); // 8種 49.5%
    final b = ship(2, [highAngle(), director()]); // 9種 39.6%
    final none = ship(3, []);
    expect(fleetAntiAirCutInRate([a, b, none], null), closeTo(1 - 0.505 * 0.604, 1e-9));
    expect(fleetAntiAirCutInRate([none], null), 0);
    expect(fleetAntiAirCutInText([none], null), 'なし');
    expect(fleetAntiAirCutInText([a], {1: master(1, 1)}), '49.5%');
  });

  testWidgets('ship detail section lists the kinds', (tester) async {
    final akizuki = ship(330, [highAngleDirector(), highAngleDirector(), airRadar()]);
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(
        child: ListView(children: [
          KancolleAntiAirCutInSection(ship: akizuki, shipInfo: {330: master(330, 54)}),
        ]),
      ),
    ));
    expect(find.text('対空カットイン (推定)'), findsOneWidget);
    expect(find.text('第1種'), findsOneWidget);
    expect(find.text('64.3% / 64.3%'), findsOneWidget);
    expect(find.text('合計 (この艦)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 発動できない艦では何も出さない
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(
        child: ListView(children: [
          KancolleAntiAirCutInSection(ship: ship(1, []), shipInfo: null),
        ]),
      ),
    ));
    expect(find.text('対空カットイン (推定)'), findsNothing);
  });
}
