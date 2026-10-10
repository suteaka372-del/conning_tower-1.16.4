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
  const _CountingBox(this.name);

  final String name;
  static final Map<String, int> created = {};

  @override
  State<_CountingBox> createState() => _CountingBoxState();
}

class _CountingBoxState extends State<_CountingBox> {
  @override
  void initState() {
    super.initState();
    _CountingBox.created[widget.name] = (_CountingBox.created[widget.name] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFF00AA00));
}

enum _Mode { portrait, landscape, side }

/// home.dart と同じ組み方:
/// Row [メニュー?, 区切り?, Expanded(Stack > Flex)]
/// Flex: 縦は [ダッシュボード欄, ゲーム]、横並びは [ゲーム, 境目, ダッシュボード欄]
/// ダッシュボード欄: SizedBox > MediaQuery.removePadding > IndexedStack [ダッシュボード, ブラウザ]
Widget _layout(_Mode mode) {
  final side = mode == _Mode.side;
  final landscape = mode != _Mode.portrait;
  const rail = SizedBox(key: ValueKey("rail"), width: 56, child: Text('rail'));
  const railDivider = SizedBox(key: ValueKey("railDivider"), width: 1);
  Widget panel(double width, double height) => SizedBox(
        key: const ValueKey("dashboard"),
        width: width,
        height: height,
        child: Builder(
          builder: (context) => MediaQuery.removePadding(
            context: context,
            removeTop: side,
            removeLeft: side,
            removeRight: side,
            child: IndexedStack(index: 1, children: [
              Text(side ? 'dashboard (bottom tabs)' : 'dashboard'),
              const _CountingBox('browser'),
            ]),
          ),
        ),
      );
  final dash = [
    const SizedBox(key: ValueKey("divider"), width: 18),
    panel(300, 400),
  ];
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Row(children: [
      if (landscape) ...[rail, railDivider],
      Expanded(
        key: const ValueKey("main"),
        child: Stack(children: [
          Flex(
            direction: side ? Axis.horizontal : Axis.vertical,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (mode == _Mode.portrait) panel(300, 200), // 横画面 (横並びなし) では欄を出さない
              const Padding(
                key: ValueKey("game"),
                padding: EdgeInsets.zero,
                child: SizedBox(
                  width: 300,
                  height: 180,
                  child: Center(child: SizedBox(width: 300, height: 180, child: _CountingBox('game'))),
                ),
              ),
              if (side) ...dash,
            ],
          ),
        ]),
      ),
    ]),
  );
}

void main() {
  testWidgets('game and browser are not recreated when rotating (portrait <-> side by side)', (tester) async {
    _CountingBox.created.clear();
    for (final mode in [
      _Mode.portrait,
      _Mode.landscape,
      _Mode.side,
      _Mode.portrait,
      _Mode.side,
      _Mode.landscape,
      _Mode.side,
    ]) {
      await tester.pumpWidget(_layout(mode));
    }
    expect(_CountingBox.created['game'], 1);
    expect(find.text('dashboard (bottom tabs)', skipOffstage: false), findsOneWidget);

    // browser: kept between portrait and side by side (only the plain landscape view has no panel)
    _CountingBox.created.clear();
    for (final mode in [_Mode.landscape, _Mode.portrait, _Mode.side, _Mode.portrait, _Mode.side]) {
      await tester.pumpWidget(_layout(mode));
    }
    expect(_CountingBox.created['browser'], 1);
    expect(_CountingBox.created['game'], isNull); // still the first game view
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

  testWidgets('portrait bottom bar: browser button, no dashboard button', (tester) async {
    var browserToggled = 0;
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
            functionMap: {FunctionName.toggleBrowser: () => browserToggled++},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.slider_horizontal_below_rectangle), findsNothing);
    expect(find.byIcon(CupertinoIcons.info), findsOneWidget);
    // browser button between settings and about
    double x(IconData icon) => tester.getCenter(find.byIcon(icon)).dx;
    expect(x(CupertinoIcons.settings), lessThan(x(CupertinoIcons.book)));
    expect(x(CupertinoIcons.book), lessThan(x(CupertinoIcons.info)));
    await tester.tap(find.byIcon(CupertinoIcons.book));
    await tester.pumpAndSettle();
    expect(browserToggled, 1);
  });

  testWidgets('menu does not add its own camera margin when padding is removed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    selectedIndex = 0;
    await S.load(const Locale('ja'));
    tester.view.physicalSize = const Size(874 * 3, 402 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(left: 62 * 3, right: 62 * 3);
    addTearDown(tester.view.reset);

    Widget app({required bool removePadding}) {
      // Sidebar と同じくスクロールできるように包む
      final rail = SingleChildScrollView(
        child: IntrinsicHeight(
          child: Controls(
            null,
            notifyParent: () {},
            orientation: Orientation.landscape,
            functionMap: const {},
          ),
        ),
      );
      return ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          locale: const Locale('ja'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Row(children: [
                removePadding
                    ? MediaQuery.removePadding(context: context, removeLeft: true, removeRight: true, child: rail)
                    : rail,
              ]),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(app(removePadding: false));
    await tester.pumpAndSettle();
    final withMargin = tester.getSize(find.byType(NavigationRail)).width;

    await tester.pumpWidget(app(removePadding: true));
    await tester.pumpAndSettle();
    final withoutMargin = tester.getSize(find.byType(NavigationRail)).width;

    expect(withMargin, greaterThan(withoutMargin + 50)); // the rail adds the 62pt margin by itself
    expect(withoutMargin, lessThanOrEqualTo(72));
    expect(tester.getTopLeft(find.byType(NavigationRail)).dx, 0);
  });
}
