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

  testWidgets('large grip: long press drag, double tap and reset button', (tester) async {
    final events = <String>[];
    Offset? last;
    await tester.pumpWidget(CupertinoApp(
      home: Align(
        alignment: Alignment.topCenter,
        child: SideResizeGrip(
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
    ));

    // touch area is large: 64 x 96 grip + 48pt reset button
    final gripRect = tester.getRect(find.byType(GestureDetector).first);
    expect(gripRect.width, greaterThanOrEqualTo(64));
    expect(gripRect.height, greaterThanOrEqualTo(96));

    // long press near the edge of the grip still works
    final start = gripRect.topLeft + const Offset(6, 10);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(events.first, 'start');
    expect(events, contains('update'));
    expect(events.last, 'end');
    expect(last!.dx, closeTo(start.dx - 80, 1));

    events.clear();
    final reset = tester.getRect(find.byType(CupertinoButton));
    expect(reset.width, greaterThanOrEqualTo(48));
    await tester.tapAt(reset.topLeft + const Offset(4, 4)); // edge of the button
    await tester.pump();
    expect(events, ['reset']);

    events.clear();
    await tester.tapAt(gripRect.center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(gripRect.center);
    await tester.pumpAndSettle();
    expect(events, contains('reset'));
  });

  testWidgets('thin divider line is also draggable', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(CupertinoApp(
      home: Center(
        child: SizedBox(
          height: 300,
          child: SideResizeHandle(
            width: SideResizeHandle.defaultWidth,
            onDragStart: (_) => events.add('start'),
            onDragUpdate: (_) => events.add('update'),
            onDragEnd: () => events.add('end'),
            onReset: () => events.add('reset'),
          ),
        ),
      ),
    ));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(SideResizeHandle)));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    expect(events.first, 'start');
    expect(events.last, 'end');
  });
}
