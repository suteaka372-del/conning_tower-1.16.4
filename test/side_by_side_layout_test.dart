import 'package:conning_tower/utils/screen_orientation.dart';
import 'package:conning_tower/widgets/side_resize_handle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SideBySideLayout', () {
    // iPhone 17 Pro landscape: 874 x 402 pt, menu (56) + divider (1) -> main area 817
    const iphone17ProMain = 874.0 - 57;

    test('default is half and half and the game keeps 5:3', () {
      const layout = SideBySideLayout(ratio: 0.5, totalWidth: iphone17ProMain, maxHeight: 402);
      expect(layout.available, iphone17ProMain - SideResizeHandle.defaultWidth);
      expect(layout.dashboardWidth, closeTo(399.5, 0.01));
      expect(layout.gameAreaWidth, closeTo(399.5, 0.01));
      expect(layout.gameSize.width, closeTo(399.5, 0.01));
      expect(layout.gameSize.height, closeTo(239.7, 0.01));
      expect(layout.dashboardWidth + layout.gameAreaWidth + layout.handleWidth, closeTo(iphone17ProMain, 1e-9));
    });

    test('limits: game >= 300, dashboard >= 250', () {
      const wide = SideBySideLayout(ratio: 0.95, totalWidth: iphone17ProMain, maxHeight: 402);
      expect(wide.gameAreaWidth, closeTo(SideBySideLayout.minGameWidth, 1e-9));
      const narrow = SideBySideLayout(ratio: 0.05, totalWidth: iphone17ProMain, maxHeight: 402);
      expect(narrow.dashboardWidth, SideBySideLayout.minDashboardWidth);
      // game area wider than 5:3 of the height: height limited, width follows
      const tall = SideBySideLayout(ratio: 0.05, totalWidth: 1300, maxHeight: 402);
      expect(tall.gameSize.height, 402);
      expect(tall.gameSize.width, closeTo(670, 1e-9));
    });

    test('too small screen falls back to half', () {
      const small = SideBySideLayout(ratio: 0.9, totalWidth: 500, maxHeight: 300);
      expect(small.dashboardWidth, closeTo(small.available / 2, 1e-9));
    });

    test('dragging the divider (both orders)', () {
      const layout = SideBySideLayout(ratio: 0.5, totalWidth: 800, maxHeight: 402);
      // game | handle | dashboard: handle at x=309 -> dashboard 800 - 309 - 9 = 482
      final width = layout.dashboardWidthAt(309, gameFirst: true);
      expect(width, closeTo(482, 1e-9));
      expect(layout.handleCenterFor(width, gameFirst: true), closeTo(309, 1e-9));
      // dashboard | handle | game: handle at x=309 -> dashboard 300
      final mirrored = layout.dashboardWidthAt(309, gameFirst: false);
      expect(mirrored, closeTo(300, 1e-9));
      expect(layout.handleCenterFor(mirrored, gameFirst: false), closeTo(309, 1e-9));
      // ratio round trip
      final ratio = layout.ratioFor(width);
      expect(SideBySideLayout(ratio: ratio, totalWidth: 800, maxHeight: 402).dashboardWidth, closeTo(482, 1e-9));
      // clamped while dragging
      expect(layout.dashboardWidthAt(10, gameFirst: true), closeTo(layout.available - 300, 1e-9));
    });
  });

  test('camera side from iOS interface orientation', () {
    expect(ScreenOrientation.cameraSideOf('landscapeLeft'), CameraSide.right);
    expect(ScreenOrientation.cameraSideOf('landscapeRight'), CameraSide.left);
    expect(ScreenOrientation.cameraSideOf('portrait'), CameraSide.unknown);
    expect(ScreenOrientation.cameraSideOf(null), CameraSide.unknown);
  });

  testWidgets('divider: long press drag, double tap and reset button', (tester) async {
    final events = <String>[];
    Offset? last;
    await tester.pumpWidget(CupertinoApp(
      home: Center(
        child: SizedBox(
          height: 300,
          child: SideResizeHandle(
            width: SideResizeHandle.defaultWidth,
            onDragStart: (p) {
              events.add('start');
              last = p;
            },
            onDragUpdate: (p) {
              events.add('update');
              last = p;
            },
            onDragEnd: () => events.add('end'),
            onReset: () => events.add('reset'),
          ),
        ),
      ),
    ));

    final grip = tester.getCenter(find.byType(GestureDetector).first);
    final gesture = await tester.startGesture(grip);
    await tester.pump(const Duration(milliseconds: 600)); // long press
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(events.first, 'start');
    expect(events, contains('update'));
    expect(events.last, 'end');
    expect(last!.dx, closeTo(grip.dx - 80, 1));

    // a short drag without long press does nothing
    events.clear();
    await tester.dragFrom(grip, const Offset(-50, 0));
    await tester.pump(const Duration(milliseconds: 600));
    expect(events.where((e) => e != 'end'), isEmpty);

    events.clear();
    await tester.tap(find.byIcon(CupertinoIcons.arrow_left_right_square));
    await tester.pump();
    expect(events, ['reset']);

    events.clear();
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
    expect(events, contains('reset'));
  });
}
