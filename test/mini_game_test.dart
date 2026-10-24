import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/utils/kancolle_origin.dart';
import 'package:conning_tower/utils/poll.dart';
import 'package:conning_tower/widgets/mini_game.dart';
import 'package:conning_tower/widgets/side_browser.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ゲーム画面の代わり。作り直されたら created が増える
class _FakeGame extends StatefulWidget {
  const _FakeGame();

  static int created = 0;

  @override
  State<_FakeGame> createState() => _FakeGameState();
}

class _FakeGameState extends State<_FakeGame> {
  @override
  void initState() {
    super.initState();
    _FakeGame.created++;
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(key: ValueKey('game'), color: Color(0xFF000000));
}

void main() {
  group('auto fullscreen', () {
    test('waits until the game frame appears', () async {
      var calls = 0;
      final found = await pollUntil(() async => ++calls >= 3, interval: const Duration(milliseconds: 1));
      expect(found, isTrue);
      expect(calls, 3);
    });

    test('gives up after the attempts, survives errors, stops when cancelled', () async {
      var calls = 0;
      expect(
          await pollUntil(() async {
            calls++;
            throw Exception('page is changing');
          }, interval: const Duration(milliseconds: 1), attempts: 4),
          isFalse);
      expect(calls, 4);

      // 別のページを読み込み始めたら待つのをやめる
      calls = 0;
      var cancelled = false;
      expect(
          await pollUntil(() async {
            calls++;
            cancelled = true;
            return false;
          }, interval: const Duration(milliseconds: 1), cancelled: () => cancelled),
          isFalse);
      expect(calls, 1);
    });

    test('only DMM pages are checked (play.games.dmm.com too)', () {
      expect(isDmmHost('play.games.dmm.com'), isTrue);
      expect(isDmmHost('www.dmm.com'), isTrue);
      expect(isDmmHost('osapi.dmm.com'), isTrue);
      expect(isDmmHost('dmm.com'), isTrue);
      expect(isDmmHost('book.dmm.com'), isTrue);
      expect(isDmmHost('evildmm.com'), isFalse);
      expect(isDmmHost('dmm.com.evil.example'), isFalse);
      expect(isDmmHost('localhost'), isFalse);
    });
  });

  group('mini game', () {
    test('only in portrait with the browser showing', () {
      bool use({bool portrait = true, bool mini = true, bool browser = true, bool dashboard = true}) =>
          useMiniGame(portrait: portrait, miniGame: mini, browserShowing: browser, dashboardInHome: dashboard);
      expect(use(), isTrue);
      expect(use(portrait: false), isFalse); // 横画面は今までどおり
      expect(use(mini: false), isFalse);
      expect(use(browser: false), isFalse); // ダッシュボードを見ているときは普通の大きさ
      expect(use(dashboard: false), isFalse);
    });

    test('a third of the width, 5:3', () {
      final size = miniGameSize(402);
      expect(size.width, closeTo(134, 0.01));
      expect(size.height, closeTo(80.4, 0.01));
    });

    testWidgets('shrinking moves the game to the bottom right without rebuilding it', (tester) async {
      await S.load(const Locale('ja'));
      _FakeGame.created = 0;
      var restored = 0;
      Widget box(bool mini) {
        final game = mini ? miniGameSize(402) : const Size(402, 241.2);
        return CupertinoApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: GameBox(
              areaWidth: 402,
              areaHeight: game.height,
              gameSize: game,
              mini: mini,
              onRestore: () => restored++,
              leading: const SizedBox.expand(key: ValueKey('buttons')),
              child: const _FakeGame(),
            ),
          ),
        );
      }

      await tester.pumpWidget(box(false));
      expect(tester.getRect(find.byKey(const ValueKey('game'))), const Rect.fromLTWH(0, 0, 402, 241.2));
      expect(find.byType(MiniGameOverlay), findsNothing);

      await tester.pumpWidget(box(true));
      final rect = tester.getRect(find.byKey(const ValueKey('game')));
      expect(rect.right, 402);
      expect(rect.width, closeTo(134, 0.01));
      expect(rect.height, closeTo(80.4, 0.01));
      expect(find.byType(MiniGameOverlay), findsOneWidget);
      // 小窓の左の空き地にブラウザのボタン
      final buttons = tester.getRect(find.byKey(const ValueKey('buttons')));
      expect(buttons.left, 0);
      expect(buttons.right, closeTo(rect.left, 0.01));
      expect(buttons.height, closeTo(80.4, 0.01));

      // 小窓をタップすると戻す (ゲームには触れない)
      await tester.tap(find.byType(MiniGameOverlay));
      expect(restored, 1);

      await tester.pumpWidget(box(false));
      expect(find.byType(MiniGameOverlay), findsNothing);
      expect(find.byKey(const ValueKey('buttons')), findsNothing);
      expect(_FakeGame.created, 1); // 一度も作り直していない (= 再読み込みにならない)
      expect(tester.takeException(), isNull);
    });

    testWidgets('browser bar: shrink button only when it is offered (portrait)', (tester) async {
      await S.load(const Locale('ja'));
      final calls = <String>[];
      Widget bar({VoidCallback? onMiniGame, bool mini = false}) => CupertinoApp(
            home: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                height: 500,
                child: SideBrowserBar(
                  onBack: null,
                  onForward: null,
                  onReload: () {},
                  onShelf: () {},
                  miniGame: mini,
                  onMiniGame: onMiniGame,
                ),
              ),
            ),
          );

      await tester.pumpWidget(bar());
      expect(find.byIcon(CupertinoIcons.arrow_down_right_arrow_up_left), findsNothing); // 横画面

      await tester.pumpWidget(bar(onMiniGame: () => calls.add('mini')));
      await tester.tap(find.byIcon(CupertinoIcons.arrow_down_right_arrow_up_left));
      expect(calls, ['mini']);
      // 押す場所はボタン列の下の方 (再読み込みの上)
      expect(tester.getCenter(find.byIcon(CupertinoIcons.arrow_down_right_arrow_up_left)).dy,
          lessThan(tester.getCenter(find.byIcon(CupertinoIcons.refresh)).dy));

      await tester.pumpWidget(bar(onMiniGame: () => calls.add('restore'), mini: true));
      await tester.tap(find.byIcon(CupertinoIcons.arrow_up_left_arrow_down_right));
      expect(calls, ['mini', 'restore']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mini mode: no right bar, the manga page gets the full width', (tester) async {
      await S.load(const Locale('ja'));
      Widget layout(bool showBar) => CupertinoApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 402,
                height: 600,
                child: SideBrowserLayout(
                  showBar: showBar,
                  content: const _FakeGame(),
                  bar: SideBrowserBar(onBack: null, onForward: null, onReload: () {}, onShelf: () {}),
                ),
              ),
            ),
          );
      _FakeGame.created = 0;
      await tester.pumpWidget(layout(true));
      expect(tester.getRect(find.byKey(const ValueKey('game'))).width, 402 - SideBrowserBar.width);
      await tester.pumpWidget(layout(false));
      expect(tester.getRect(find.byKey(const ValueKey('game'))).width, 402);
      expect(find.byType(SideBrowserBar), findsNothing);
      await tester.pumpWidget(layout(true));
      expect(_FakeGame.created, 1); // ボタン列を出し入れしてもページは作り直さない
      expect(tester.takeException(), isNull);
    });

    testWidgets('button row beside the mini game works the browser and restores the game', (tester) async {
      await S.load(const Locale('ja'));
      final calls = <String>[];
      final container = ProviderContainer(overrides: [
        sideBrowserNavProvider.overrideWith((ref) => SideBrowserNav(
              onBack: () => calls.add('back'),
              onForward: null, // まだ進めない
              onReload: () => calls.add('reload'),
              onShelf: () => calls.add('shelf'),
            )),
      ]);
      addTearDown(container.dispose);
      container.read(miniGameProvider.notifier).state = true;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const CupertinoApp(
          home: Align(alignment: Alignment.topLeft, child: SizedBox(width: 268, height: 80, child: SideBrowserRow())),
        ),
      ));

      double x(IconData icon) => tester.getCenter(find.byIcon(icon)).dx;
      // 左から 戻る・進む・再読み込み・本棚・元に戻す
      expect(x(CupertinoIcons.back), lessThan(x(CupertinoIcons.forward)));
      expect(x(CupertinoIcons.forward), lessThan(x(CupertinoIcons.refresh)));
      expect(x(CupertinoIcons.refresh), lessThan(x(CupertinoIcons.book)));
      expect(x(CupertinoIcons.book), lessThan(x(CupertinoIcons.arrow_up_left_arrow_down_right)));
      expect(tester.getRect(find.byIcon(CupertinoIcons.arrow_up_left_arrow_down_right)).right, lessThanOrEqualTo(268));

      for (final icon in [CupertinoIcons.back, CupertinoIcons.forward, CupertinoIcons.refresh, CupertinoIcons.book]) {
        await tester.tap(find.byIcon(icon));
      }
      expect(calls, ['back', 'reload', 'shelf']);
      await tester.tap(find.byIcon(CupertinoIcons.arrow_up_left_arrow_down_right));
      expect(container.read(miniGameProvider), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
