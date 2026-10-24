import 'dart:developer';

import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/widgets/mini_game.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 横並びモードの右側に出すブラウザ (DMMブックスの本棚など)。
/// ゲームの WebView とは別物で、ゲーム用の設定やスクリプトは入れない。
class SideBrowser extends ConsumerStatefulWidget {
  const SideBrowser({super.key});

  static const String homeUrl = 'https://book.dmm.com/shelf/';
  static const String _lastUrlKey = 'sideBrowserLastUrl';

  /// スマホ向けページで単ページ表示しやすいように iPhone の Safari を名乗る
  static const String mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';

  /// 前回開いていたページ (なければ本棚)
  static String initialUrl() {
    try {
      final url = localStorage.getString(_lastUrlKey);
      if (url != null && url.startsWith('https://')) return url;
    } catch (_) {}
    return homeUrl;
  }

  static void saveLastUrl(String url) {
    if (!url.startsWith('https://')) return;
    try {
      localStorage.setString(_lastUrlKey, url);
    } catch (_) {}
  }

  @override
  ConsumerState<SideBrowser> createState() => _SideBrowserState();
}

class _SideBrowserState extends ConsumerState<SideBrowser> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;

  Future<void> _updateNavigationState() async {
    final controller = _controller;
    if (controller == null) return;
    final back = await controller.canGoBack();
    final forward = await controller.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ゲームを小さくするボタンは縦画面だけ (横画面は境目のつまみで幅を変えられる)
    final portrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final miniGame = ref.watch(miniGameProvider);
    return SideBrowserLayout(
      content: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(SideBrowser.initialUrl())),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              userAgent: SideBrowser.mobileUserAgent,
              preferredContentMode: UserPreferredContentMode.MOBILE,
              javaScriptCanOpenWindowsAutomatically: true,
              supportZoom: true,
              allowsInlineMediaPlayback: true,
              isElementFullscreenEnabled: false,
              allowsBackForwardNavigationGestures: true,
            ),
            onWebViewCreated: (controller) => _controller = controller,
            onProgressChanged: (controller, progress) {
              if (mounted) setState(() => _progress = progress / 100);
            },
            onLoadStop: (controller, url) {
              if (url != null) SideBrowser.saveLastUrl(url.toString());
              _updateNavigationState();
            },
            onUpdateVisitedHistory: (controller, url, isReload) {
              if (url != null) SideBrowser.saveLastUrl(url.toString());
              _updateNavigationState();
            },
            // 新しいウインドウ (ビューアなど) は同じ画面で開く
            onCreateWindow: (controller, action) async {
              final url = action.request.url;
              if (url != null) {
                await controller.loadUrl(urlRequest: URLRequest(url: url));
              }
              return false;
            },
            onReceivedError: (controller, request, error) {
              log('side browser error: ${error.description}');
            },
          ),
          if (_progress < 1.0)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SizedBox(
                height: 2,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _progress.clamp(0.0, 1.0),
                  child: const ColoredBox(color: CupertinoColors.activeBlue),
                ),
              ),
            ),
        ],
      ),
      bar: SideBrowserBar(
        onBack: _canGoBack ? () => _controller?.goBack() : null,
        onForward: _canGoForward ? () => _controller?.goForward() : null,
        onReload: () => _controller?.reload(),
        onShelf: () => _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(SideBrowser.homeUrl))),
        miniGame: miniGame,
        onMiniGame: portrait ? () => ref.read(miniGameProvider.notifier).state = !miniGame : null,
      ),
    );
  }
}

/// ページを縦いっぱいに表示し、ボタンは右側に縦に並べる (縦長の漫画1ページのため上下に枠を取らない)
class SideBrowserLayout extends StatelessWidget {
  const SideBrowserLayout({super.key, required this.content, required this.bar});

  final Widget content;
  final Widget bar;

  @override
  Widget build(BuildContext context) {
    // 縦画面では上のステータスバー (時計など) の下から表示する。横並びでは上の余白は 0
    return SafeArea(
      left: false,
      right: false,
      bottom: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: content),
          bar,
        ],
      ),
    );
  }
}

/// 右側の縦のボタン列。上に「戻る・進む」、下に「再読み込み・本棚」。
/// 真ん中は空けておく (向きによってはカメラ (Dynamic Island) がここに来るため)
class SideBrowserBar extends StatelessWidget {
  const SideBrowserBar({
    super.key,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onShelf,
    this.miniGame = false,
    this.onMiniGame,
  });

  static const double width = 44;

  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onReload;
  final VoidCallback? onShelf;

  /// ゲームを小窓にしているか (ボタンの絵を切り替える)
  final bool miniGame;

  /// ゲームを小さく / 元に戻す。null ならボタンを出さない (横画面)
  final VoidCallback? onMiniGame;

  @override
  Widget build(BuildContext context) {
    // 下の端はホームバーのスワイプと重ならないように少し上げる
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
        border: Border(left: BorderSide(color: CupertinoColors.separator.resolveFrom(context), width: 0.5)),
      ),
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            const SizedBox(height: 4),
            _BarButton(icon: CupertinoIcons.back, label: repairText('戻る', 'Back'), onPressed: onBack),
            _BarButton(icon: CupertinoIcons.forward, label: repairText('進む', 'Forward'), onPressed: onForward),
            const Spacer(),
            if (onMiniGame != null)
              _BarButton(
                icon: miniGame ? CupertinoIcons.arrow_up_left_arrow_down_right : CupertinoIcons.arrow_down_right_arrow_up_left,
                label: miniGame
                    ? repairText('ゲームを元の大きさに戻す', 'Restore the game size')
                    : repairText('ゲームを小さくする', 'Shrink the game'),
                onPressed: onMiniGame,
              ),
            _BarButton(icon: CupertinoIcons.refresh, label: repairText('再読み込み', 'Reload'), onPressed: onReload),
            _BarButton(icon: CupertinoIcons.book, label: repairText('本棚', 'Shelf'), onPressed: onShelf),
            SizedBox(height: bottomInset > 0 ? bottomInset : 4),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 44,
        onPressed: onPressed == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onPressed!();
              },
        child: Icon(icon, size: 24),
      ),
    );
  }
}
