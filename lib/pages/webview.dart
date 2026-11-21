import 'dart:collection';
import 'dart:developer';
import 'dart:io';

import 'package:conning_tower/constants.dart';
import 'package:conning_tower/helper.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/perf_monitor.dart';
import 'package:conning_tower/providers/game_stop_log.dart';
import 'package:conning_tower/providers/generatable/settings_provider.dart';
import 'package:conning_tower/providers/generatable/webview_provider.dart';
import 'package:conning_tower/providers/web_info_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppWebView extends ConsumerStatefulWidget {
  const AppWebView({super.key});
  @override
  AppWebViewState createState() => AppWebViewState();
}

class AppWebViewState extends ConsumerState<AppWebView> {
  // late String defaultUA;
  final GlobalKey webViewKey = GlobalKey();
  double progress = 0;

  /// iOS がゲーム画面 (ブラウザ) を終了させて、真っ暗になっている
  bool gameStopped = false;

  Future<void> _onGameStopped(WebController webController) async {
    PerfMonitor.instance.countEvent('stopped');
    if (mounted) setState(() => gameStopped = true);
    final volumes = await webController.kancolleVolumes();
    gameStopLog.add(GameStop(at: DateTime.now(), volumes: volumes));
  }

  static get defaultUA {
    if (Platform.isAndroid) {
      return kChromeUA;
    } else if (Platform.isIOS) {
      return kSafariUA;
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    String customUA = settings.customUA;

    InAppWebViewSettings webViewSetting = InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: customUA.isNotEmpty ? customUA : defaultUA,
        preferredContentMode: UserPreferredContentMode.DESKTOP,
        //Allow window.open JS
        javaScriptCanOpenWindowsAutomatically: true,
        //Android intercept kancolle API
        useShouldInterceptRequest: true,
        isElementFullscreenEnabled: false,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        supportZoom: deviceType != DeviceType.iPad,
        upgradeKnownHostsToHTTPS: false,
    );

    String homeUrl = getHomeUrl(settings.customHomeUrl, settings.enableAutoLoadHomeUrl);
    // final urlController = ref.watch(urlProvider);
    final webController = ref.watch(webControllerProvider);
    debugPrint("rebuild web");
    // final inAppWebViewControllerState = ref.watch(webViewControllerProvider);
    return AspectRatio(
      aspectRatio: 5 / 3,
      child: LayoutBuilder(builder: (context, constraints) {
        // debugPrint("rate: ${(constraints.maxWidth / constraints.maxHeight)/(5/3)}");
        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
            InAppWebView(
              key: webViewKey,
              initialSettings: webViewSetting,
              initialUrlRequest: URLRequest(url: WebUri(homeUrl), httpShouldHandleCookies: true),
              initialUserScripts: UnmodifiableListView([
                if (settings.useDMMCookieModify) dmmCookieScript,
                if (settings.useKancolleListener && settings.kancolleListenerType == 0) kancolleUserScript,
                alignUserScript,
                if (Platform.isIOS) kancolleFitUserScript,
              ]),
              onWebViewCreated: (InAppWebViewController controller) {
                webController.setController(controller);
                // ref.read(webViewControllerProvider.notifier).setController(controller);
                // urlController.setWebViewController(controller);
                webController.onWebviewCreate();
              },
              // iOS がメモリ不足などでブラウザを終了させると真っ暗になる。自動では読み込み直さず、知らせて選んでもらう
              onWebContentProcessDidTerminate: (controller) => _onGameStopped(webController),
              onLoadStart: (controller, uri) async {
                if (gameStopped) setState(() => gameStopped = false);
                print('Page started loading: $uri');
                // urlController.setCurrentUrl(uri.toString());
                // urlController.resetResponseUrls();
                await webController.onLoadStart(uri!, useHttpForKancolle: settings.useHttpForKancolle);
                // var uri = Uri.parse(uri);
              },
              onLoadStop: (controller, uri) {
                webController.onLoadStop(uri!);
              },
              onTitleChanged: (controller, title) {
                PerfMonitor.instance.countEvent('title');
                ref
                    .watch(webInfoProvider.notifier)
                    .update((state) => state.copyWith(title: title ?? ''));
              },
              // onZoomScaleChanged: (controller, oldScale, newScale) async {
              //   debugPrint("onZoomScaleChanged $oldScale, $newScale");
              // },
              onConsoleMessage: (controller, consoleMessage) {
                PerfMonitor.instance.countEvent('console');
                log(consoleMessage.message);
              },
              onNavigationResponse: (controller, response) async {
                PerfMonitor.instance.countEvent('navigation');
                await webController.onNavigationResponse(response);
                return NavigationResponseAction.ALLOW;
              },
              onContentSizeChanged:
                  (controller, oldContentSize, newContentSize) async {
                PerfMonitor.instance.countEvent('contentSize');
                debugPrint(
                    "onContentSizeChanged $oldContentSize, $newContentSize");
                await webController.onContentSizeChanged(oldContentSize, newContentSize);
              },
              shouldInterceptRequest: (
                controller,
                WebResourceRequest request,
              ) async {
                if (settings.kancolleListenerType == 1) {
                  return webController.onShouldInterceptRequest(request);
                }
                return null;
              },
              onProgressChanged: (controller, progress) {
                PerfMonitor.instance.countEvent('progress');
                setState(() {
                  this.progress = progress / 100;
                });
                webController.onProgressChanged(progress);
              },
              onReceivedHttpError: (controller, request, response) {
                // print("error");
                // print(request);
                // print(response);
              },
              onReceivedError: (controller, request, response) {
                // print("error");
                // print(request);
                // print(response);
              },
            ),
            progress < 1.0 && settings.webViewProgressBar
                ? LinearProgressIndicator(
                    value: progress,
                    color: CupertinoColors.systemBlue.resolveFrom(context),
                    backgroundColor: Colors.transparent,
                  )
                : Container(),
            if (gameStopped)
              Positioned.fill(
                child: GameStoppedOverlay(
                  onReload: () {
                    setState(() => gameStopped = false);
                    webController.controller.reload();
                  },
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// ゲーム画面が iOS に終了させられたときに重ねる表示 (押したときだけ読み込み直す)
class GameStoppedOverlay extends StatelessWidget {
  const GameStoppedOverlay({super.key, required this.onReload});

  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(color: CupertinoColors.white, fontSize: 15, fontWeight: FontWeight.w600);
    const grey = TextStyle(color: CupertinoColors.systemGrey2, fontSize: 12);
    return ColoredBox(
      color: const Color(0xEE000000),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(repairText('ゲーム画面が止まりました', 'The game page stopped'), style: white, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                repairText('iOS がゲーム画面 (ブラウザ) を終了させました。メモリ不足のことが多く、音を出していると起きやすくなります',
                    'iOS closed the game page, usually because of low memory (more likely with sound on)'),
                style: grey,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                minSize: 32,
                onPressed: onReload,
                child: Text(repairText('再読み込み', 'Reload'), style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(height: 6),
              Text(repairText('ゲームの最初の画面に戻ります', 'The game starts over from the title'), style: grey),
            ],
          ),
        ),
      ),
    );
  }
}
