import 'dart:math';

import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// 長押しドラッグ・ダブルタップを受ける共通部分
class _ResizeGesture extends StatelessWidget {
  const _ResizeGesture({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onReset,
    required this.child,
  });

  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        onDragStart(details.globalPosition);
      },
      onLongPressMoveUpdate: (details) => onDragUpdate(details.globalPosition),
      onLongPressEnd: (_) => onDragEnd(),
      onLongPressCancel: onDragEnd,
      onDoubleTap: () {
        HapticFeedback.lightImpact();
        onReset();
      },
      child: child,
    );
  }
}

/// 横並びダッシュボードの境目の線 (線の上でも長押しドラッグできる)
class SideResizeHandle extends StatelessWidget {
  const SideResizeHandle({
    super.key,
    required this.width,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onReset,
  });

  static const double defaultWidth = 18;

  final double width;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: _ResizeGesture(
        onDragStart: onDragStart,
        onDragUpdate: onDragUpdate,
        onDragEnd: onDragEnd,
        onReset: onReset,
        child: Center(child: Container(width: 1, color: CupertinoColors.separator.resolveFrom(context))),
      ),
    );
  }
}

/// 境目の上部に重ねる大きなつまみと「幅を元に戻す」ボタン (ゲーム画面の上の余白に出る)
class SideResizeGrip extends StatelessWidget {
  const SideResizeGrip({
    super.key,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onReset,
    this.dragging = false,
  });

  /// 重ねる領域の幅 (境目の中心に合わせて置く)
  static const double width = 64;
  static const double gripHeight = 96;

  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final background = CupertinoColors.systemGrey5.resolveFrom(context).withOpacity(0.85);
    final pill = dragging ? CupertinoColors.activeBlue : CupertinoColors.systemGrey.resolveFrom(context);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ResizeGesture(
            onDragStart: onDragStart,
            onDragUpdate: onDragUpdate,
            onDragEnd: onDragEnd,
            onReset: onReset,
            child: SizedBox(
              width: width,
              height: gripHeight,
              child: Center(
                child: Container(
                  width: 36,
                  height: 84,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: pill, width: 1.5),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 4, height: 44, decoration: BoxDecoration(color: pill, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 5),
                        Container(width: 4, height: 44, decoration: BoxDecoration(color: pill, borderRadius: BorderRadius.circular(2))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Semantics(
            label: repairText('幅を元に戻す', 'Reset width'),
            button: true,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 48,
              onPressed: () {
                HapticFeedback.lightImpact();
                onReset();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: background, shape: BoxShape.circle),
                child: const Icon(CupertinoIcons.arrow_left_right_square, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 横並びモードの右側に出すもの
enum SidePanel { dashboard, browser }

/// 左メニューのダッシュボード / ブラウザボタンを押したときの開閉
class SidePanelState {
  final bool open;
  final SidePanel panel;

  const SidePanelState({required this.open, required this.panel});

  /// 表示中のものと同じボタン → 閉じる、それ以外 → そのパネルで開く
  SidePanelState tap(SidePanel tapped) {
    if (open && panel == tapped) return SidePanelState(open: false, panel: panel);
    return SidePanelState(open: true, panel: tapped);
  }

  bool isShowing(SidePanel target) => open && panel == target;
}

/// 横並びモードの寸法計算 (ゲーム画面は 5:3 を保つ)
class SideBySideLayout {
  static const double defaultRatio = 0.5;
  static const double minGameWidth = 300;
  static const double minDashboardWidth = 250;

  /// ダッシュボードの幅 / (全体の幅 - 境目)
  final double ratio;
  final double totalWidth;
  final double maxHeight;
  final double handleWidth;

  const SideBySideLayout({
    required this.ratio,
    required this.totalWidth,
    required this.maxHeight,
    this.handleWidth = SideResizeHandle.defaultWidth,
  });

  double get available => max(totalWidth - handleWidth, 0);

  double clampDashboard(double width) {
    if (available < minGameWidth + minDashboardWidth) {
      return available * defaultRatio;
    }
    return width.clamp(minDashboardWidth, available - minGameWidth);
  }

  double get dashboardWidth => clampDashboard(available * ratio);

  double get gameAreaWidth => available - dashboardWidth;

  Size get gameSize {
    var width = gameAreaWidth;
    var height = width * 3 / 5;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * 5 / 3;
    }
    return Size(width, height);
  }

  /// 境目を x (全体の左端からの位置) に動かしたときのダッシュボード幅
  /// gameFirst: 左からゲーム→境目→ダッシュボードの並びか
  double dashboardWidthAt(double x, {required bool gameFirst}) {
    final width = gameFirst ? totalWidth - x - handleWidth / 2 : x - handleWidth / 2;
    return clampDashboard(width);
  }

  /// ダッシュボード幅から境目の中心位置
  double handleCenterFor(double dashboardWidth, {required bool gameFirst}) =>
      gameFirst ? totalWidth - dashboardWidth - handleWidth / 2 : dashboardWidth + handleWidth / 2;

  double ratioFor(double dashboardWidth) => available == 0 ? defaultRatio : dashboardWidth / available;
}
