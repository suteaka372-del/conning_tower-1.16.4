import 'dart:math';

import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// 横並びダッシュボードの境目。長押ししたまま左右に動かして幅を変える
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
    final separator = CupertinoColors.separator.resolveFrom(context);
    final grip = CupertinoColors.systemGrey.resolveFrom(context);
    return SizedBox(
      width: width,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(width: 1, color: separator),
                  Container(
                    width: 5,
                    height: 44,
                    decoration: BoxDecoration(color: grip, borderRadius: BorderRadius.circular(3)),
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            label: repairText('幅を元に戻す', 'Reset width'),
            button: true,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: width,
              onPressed: () {
                HapticFeedback.lightImpact();
                onReset();
              },
              child: Icon(CupertinoIcons.arrow_left_right_square, size: width),
            ),
          ),
        ],
      ),
    );
  }
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
