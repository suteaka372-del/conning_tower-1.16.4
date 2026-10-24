import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 縦画面でブラウザ (漫画) を開いているとき、ゲームを小窓にして漫画を縦に広く表示するか。
/// アプリを起動し直したら元の大きさに戻す (ログインなどで小さいと困るため)
final miniGameProvider = StateProvider<bool>((ref) => false);

/// 縦画面の小窓モードを使う場面か (横画面では今までどおり)
bool useMiniGame({
  required bool portrait,
  required bool miniGame,
  required bool browserShowing,
  required bool dashboardInHome,
}) =>
    portrait && miniGame && browserShowing && dashboardInHome;

/// 小窓のゲームの大きさ。画面の横幅の 1/3 (ゲームの縦横比 5:3 のまま)
Size miniGameSize(double maxWidth) {
  final width = maxWidth / 3;
  return Size(width, width * 3 / 5);
}

/// ゲーム画面を置く欄。[mini] なら右下に寄せて、タップで戻す覆いを重ねる。
/// [mini] で変えるのは位置と大きさだけ。ゲーム画面 ([child]) を作り直すと再読み込みになるため、
/// [mini] が変わってもここから [child] までの組み方は変えない
class GameBox extends StatelessWidget {
  const GameBox({
    super.key,
    required this.areaWidth,
    required this.areaHeight,
    required this.gameSize,
    required this.mini,
    required this.onRestore,
    required this.child,
  });

  final double areaWidth;
  final double areaHeight;
  final Size gameSize;
  final bool mini;
  final VoidCallback onRestore;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: areaHeight,
      width: areaWidth,
      child: Align(
        alignment: mini ? Alignment.bottomRight : Alignment.center,
        child: SizedBox(
          height: gameSize.height,
          width: gameSize.width,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (mini) MiniGameOverlay(onRestore: onRestore),
            ],
          ),
        ),
      ),
    );
  }
}

/// 小窓のゲームの上に重ねる。ゲームを誤って操作しないよう、タップは「元の大きさに戻す」だけにする
/// (ゲーム画面は見えたまま動き続ける。完全に隠すと描画が止まるおそれがあるため隠さない)
class MiniGameOverlay extends StatelessWidget {
  const MiniGameOverlay({super.key, required this.onRestore});

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: repairText('ゲームを元の大きさに戻す', 'Restore the game size'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onRestore();
        },
        child: const Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.all(3),
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0x99000000), borderRadius: BorderRadius.all(Radius.circular(4))),
              child: Padding(
                padding: EdgeInsets.all(2),
                child: Icon(CupertinoIcons.arrow_up_left_arrow_down_right, size: 14, color: CupertinoColors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
