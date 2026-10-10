import 'package:conning_tower/constants.dart';
import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/widgets/controls.dart';
import 'package:conning_tower/widgets/side_browser.dart';
import 'package:conning_tower/widgets/side_resize_handle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('side panel buttons: open / switch / close', () {
    var state = const SidePanelState(open: false, panel: SidePanel.dashboard);
    state = state.tap(SidePanel.browser); // closed -> browser
    expect(state.isShowing(SidePanel.browser), isTrue);
    state = state.tap(SidePanel.dashboard); // browser -> dashboard (stays open)
    expect(state.isShowing(SidePanel.dashboard), isTrue);
    state = state.tap(SidePanel.dashboard); // same button -> close
    expect(state.open, isFalse);
    expect(state.isShowing(SidePanel.dashboard), isFalse);
    state = state.tap(SidePanel.dashboard); // reopen
    expect(state.isShowing(SidePanel.dashboard), isTrue);
  });

  test('browser remembers the last page, starts at the DMM Books shelf', () async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    expect(SideBrowser.initialUrl(), 'https://book.dmm.com/shelf/');
    SideBrowser.saveLastUrl('https://book.dmm.com/library/?page=2');
    expect(SideBrowser.initialUrl(), 'https://book.dmm.com/library/?page=2');
    SideBrowser.saveLastUrl('about:blank'); // ignored
    expect(SideBrowser.initialUrl(), 'https://book.dmm.com/library/?page=2');
  });

  testWidgets('landscape menu: settings -> dashboard -> browser -> about', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    selectedIndex = 0;
    await S.load(const Locale('ja'));
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);

    final calls = <String>[];
    Widget rail({bool dashboard = false, bool browser = false}) => ProviderScope(
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
                  functionMap: {
                    FunctionName.toggleDashboard: () => calls.add('dashboard'),
                    FunctionName.toggleBrowser: () => calls.add('browser'),
                  },
                  dashboardOpen: dashboard,
                  browserOpen: browser,
                ),
              ]),
            ),
          ),
        );

    await tester.pumpWidget(rail());
    await tester.pumpAndSettle();
    double y(IconData icon) => tester.getCenter(find.byIcon(icon)).dy;
    expect(y(CupertinoIcons.settings), lessThan(y(CupertinoIcons.slider_horizontal_below_rectangle)));
    expect(y(CupertinoIcons.slider_horizontal_below_rectangle), lessThan(y(CupertinoIcons.book)));
    expect(y(CupertinoIcons.book), lessThan(y(CupertinoIcons.info)));

    await tester.tap(find.byIcon(CupertinoIcons.book));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.slider_horizontal_below_rectangle));
    await tester.pumpAndSettle();
    expect(calls, ['browser', 'dashboard']);

    // only the showing panel is blue
    await tester.pumpWidget(rail(browser: true));
    await tester.pumpAndSettle();
    expect(tester.widget<Icon>(find.byIcon(CupertinoIcons.book)).color, CupertinoColors.activeBlue);
    expect(tester.widget<Icon>(find.byIcon(CupertinoIcons.slider_horizontal_below_rectangle)).color, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('browser page uses the full height, buttons are on the right', (tester) async {
    await S.load(const Locale('ja'));
    final calls = <String>[];
    await tester.pumpWidget(CupertinoApp(
      home: MediaQuery(
        // landscape iPhone: home indicator inset at the bottom only
        data: const MediaQueryData(size: Size(874, 402), padding: EdgeInsets.only(bottom: 21)),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 380,
            child: SideBrowserLayout(
              content: const ColoredBox(key: ValueKey('page'), color: Color(0xFFFFFFFF)),
              bar: SideBrowserBar(
                onBack: null, // cannot go back yet
                onForward: () => calls.add('forward'),
                onReload: () => calls.add('reload'),
                onShelf: () => calls.add('shelf'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final page = tester.getRect(find.byKey(const ValueKey('page')));
    expect(page.top, 0);
    expect(page.height, 380); // no frame above or below
    expect(page.right, 400 - SideBrowserBar.width);

    final bar = tester.getRect(find.byType(SideBrowserBar));
    expect(bar.left, page.right);
    expect(bar.height, 380);

    double y(IconData icon) => tester.getCenter(find.byIcon(icon)).dy;
    // back / forward at the top, reload / shelf at the bottom, the middle (camera area) is empty
    expect(y(CupertinoIcons.back), lessThan(100));
    expect(y(CupertinoIcons.forward), lessThan(100));
    expect(y(CupertinoIcons.refresh), greaterThan(280));
    expect(tester.getRect(find.byIcon(CupertinoIcons.book)).bottom, lessThanOrEqualTo(380 - 21));
    for (final icon in [CupertinoIcons.back, CupertinoIcons.forward, CupertinoIcons.refresh, CupertinoIcons.book]) {
      expect((y(icon) - 190).abs(), greaterThan(63)); // keep the center 126pt free
    }

    await tester.tap(find.byIcon(CupertinoIcons.back)); // disabled
    await tester.tap(find.byIcon(CupertinoIcons.forward));
    await tester.tap(find.byIcon(CupertinoIcons.refresh));
    await tester.tap(find.byIcon(CupertinoIcons.book));
    expect(calls, ['forward', 'reload', 'shelf']);
    expect(tester.takeException(), isNull);
  });
}
