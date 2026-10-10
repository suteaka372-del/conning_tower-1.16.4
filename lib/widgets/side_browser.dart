import 'dart:developer';

import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 横並びモードの右側に出すブラウザ (DMMブックスの本棚など)。
/// ゲームの WebView とは別物で、ゲーム用の設定やスクリプトは入れない。
class SideBrowser extends StatefulWidget {
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
  State<SideBrowser> createState() => _SideBrowserState();
}

class _SideBrowserState extends State<SideBrowser> {
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
    final barColor = CupertinoColors.systemGroupedBackground.resolveFrom(context);
    return Column(
      children: [
        Expanded(
          child: Stack(
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
        ),
        ColoredBox(
          color: barColor,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _BarButton(
                    icon: CupertinoIcons.back,
                    label: repairText('戻る', 'Back'),
                    onPressed: _canGoBack ? () => _controller?.goBack() : null,
                  ),
                  _BarButton(
                    icon: CupertinoIcons.forward,
                    label: repairText('進む', 'Forward'),
                    onPressed: _canGoForward ? () => _controller?.goForward() : null,
                  ),
                  _BarButton(
                    icon: CupertinoIcons.refresh,
                    label: repairText('再読み込み', 'Reload'),
                    onPressed: () => _controller?.reload(),
                  ),
                  _BarButton(
                    icon: CupertinoIcons.book,
                    label: repairText('本棚', 'Shelf'),
                    onPressed: () => _controller?.loadUrl(
                        urlRequest: URLRequest(url: WebUri(SideBrowser.homeUrl))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
