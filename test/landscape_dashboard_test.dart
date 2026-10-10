import 'package:conning_tower/constants.dart';
import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/widgets/controls.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// initState が呼ばれた回数を数える (作り直されたかどうかの確認用)
class _CountingBox extends StatefulWidget {
  const _CountingBox();

  static int created = 0;

  @override
  State<_CountingBox> createState() => _CountingBoxState();
}

class _CountingBoxState extends State<_CountingBox> {
  @override
  void initState() {
    super.initState();
    _CountingBox.created++;
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFF00AA00));
}

/// home.dart と同じ組み方: 縦は [ダッシュボード, ゲーム]、横並びは [ゲーム, 区切り, ダッシュボード]
Widget _layout(bool sideBySide) => Directionality(
      textDirection: TextDirection.ltr,
      child: Flex(
        direction: sideBySide ? Axis.horizontal : Axis.vertical,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!sideBySide) const Expanded(key: ValueKey("dashboard"), child: Text('dashboard')),
          const Padding(
            key: ValueKey("game"),
            padding: EdgeInsets.zero,
            child: SizedBox(width: 300, height: 180, child: _CountingBox()),
          ),
          if (sideBySide) ...[
            const SizedBox(key: ValueKey("divider"), width: 1),
            const SizedBox(key: ValueKey("dashboard"), width: 300, height: 400, child: Text('dashboard')),
          ],
        ],
      ),
    );

void main() {
  testWidgets('game view is not recreated when switching portrait <-> side by side', (tester) async {
    _CountingBox.created = 0;
    await tester.pumpWidget(_layout(false));
    await tester.pumpWidget(_layout(true));
    await tester.pumpWidget(_layout(false));
    await tester.pumpWidget(_layout(true));
    expect(_CountingBox.created, 1);
    expect(find.text('dashboard'), findsOneWidget);
  });

  testWidgets('landscape rail: dashboard button between settings and about', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    selectedIndex = 0; // main() で設定されるグローバル値
    await S.load(const Locale('ja'));
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetPhysicalSize);

    var toggled = 0;
    Widget rail(bool open) => ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
            locale: const Locale('ja'),
            home: Scaffold(
              body: Row(children: [
                Controls(
                  null,
                  notifyParent: () {},
                  orientation: Orientation.landscape,
                  functionMap: {FunctionName.toggleDashboard: () => toggled++},
                  dashboardOpen: open,
                ),
              ]),
            ),
          ),
        );

    await tester.pumpWidget(rail(false));
    await tester.pumpAndSettle();

    final settings = tester.getCenter(find.byIcon(CupertinoIcons.settings)).dy;
    final dashboard = tester.getCenter(find.byIcon(CupertinoIcons.slider_horizontal_below_rectangle)).dy;
    final about = tester.getCenter(find.byIcon(CupertinoIcons.info)).dy;
    expect(settings < dashboard && dashboard < about, isTrue);

    await tester.tap(find.byIcon(CupertinoIcons.slider_horizontal_below_rectangle));
    await tester.pumpAndSettle();
    expect(toggled, 1);

    // open state is shown in blue
    await tester.pumpWidget(rail(true));
    await tester.pumpAndSettle();
    final icon = tester.widget<Icon>(find.byIcon(CupertinoIcons.slider_horizontal_below_rectangle));
    expect(icon.color, CupertinoColors.activeBlue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait bottom bar is unchanged (no dashboard button)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    selectedIndex = 0; // main() で設定されるグローバル値
    await S.load(const Locale('ja'));
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        locale: const Locale('ja'),
        home: Scaffold(
          bottomNavigationBar: Controls(
            null,
            notifyParent: () {},
            orientation: Orientation.portrait,
            functionMap: const {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.slider_horizontal_below_rectangle), findsNothing);
    expect(find.byIcon(CupertinoIcons.info), findsOneWidget);
  });
}
