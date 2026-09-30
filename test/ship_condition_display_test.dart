import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/pages/dashboard_pages/squad_info.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

Ship _ship(int condition, {int fuel = 15, int bull = 20}) =>
    Ship(uid: 1, shipId: 1, level: 1, nowHP: 16, maxHP: 16, condition: condition, fuel: fuel, bull: bull);

void main() {
  testWidgets('condition number, color and supply status', (tester) async {
    Future<int?> colorOf(int condition) async {
      await tester.pumpWidget(CupertinoApp(
        home: Center(child: ShipConditionSupplyInfo(ship: _ship(condition), fuelMax: 15, bullMax: 20)),
      ));
      return tester.widget<Text>(find.text('$condition')).style?.color?.value;
    }

    expect(await colorOf(85), CupertinoColors.activeGreen.color.value);
    expect(await colorOf(50), CupertinoColors.activeGreen.color.value);
    expect(await colorOf(49), CupertinoColors.label.color.value);
    expect(await colorOf(30), CupertinoColors.label.color.value);
    expect(await colorOf(29), CupertinoColors.activeOrange.color.value);
    expect(await colorOf(20), CupertinoColors.activeOrange.color.value);
    expect(await colorOf(19), CupertinoColors.systemRed.color.value);
    expect(find.text('済'), findsOneWidget);

    await tester.pumpWidget(CupertinoApp(
      home: Center(child: ShipConditionSupplyInfo(ship: _ship(49, fuel: 10), fuelMax: 15, bullMax: 20)),
    ));
    expect(find.text('49'), findsOneWidget);
    expect(find.text('未'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
