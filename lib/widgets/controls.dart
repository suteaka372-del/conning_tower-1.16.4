import 'dart:developer';

import 'package:conning_tower/constants.dart';
import 'package:conning_tower/generated/l10n.dart';
import 'package:conning_tower/helper.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/pages/about_page.dart';
import 'package:conning_tower/pages/settings_page.dart';
import 'package:conning_tower/pages/tools_page.dart';
import 'package:conning_tower/providers/generatable/navigator_provider.dart';
import 'package:conning_tower/providers/generatable/settings_provider.dart';
import 'package:conning_tower/providers/generatable/webview_provider.dart';
import 'package:conning_tower/widgets/dialog.dart';
import 'package:conning_tower/utils/local_navigator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:popover/popover.dart';

enum ConFunc {
  adjustWindow,
  loadHome,
  httpRedirect,
  bottomUp,
  scrollUp,
  scrollDown,
  goBack,
  goForward,
  refresh,
  clearCookies,
  clearCache,
  doRequest,
  navi2About,
  navi2Tool,
  navi2Settings,
  toggleDashboard,
}

class Controls extends ConsumerStatefulWidget {
  Controls(CookieManager? cookieManager,
      {super.key,
      required this.notifyParent,
      required this.orientation,
      required this.functionMap,
      this.isWideStyle = false,
      this.enableJoystick = false,
      this.dashboardOpen = false})
      : _cookieManager = cookieManager;
  final Function() notifyParent;
  final CookieManager? _cookieManager;

  /// 必要になったときに取得する (テストなど WebView のない環境でも Controls を作れるように)
  CookieManager get cookieManager => _cookieManager ?? CookieManager.instance();
  final Orientation orientation;
  final bool isWideStyle;
  final bool enableJoystick;

  /// 横画面でダッシュボードを横並びに表示しているか
  final bool dashboardOpen;
  final Map<FunctionName, Function> functionMap;

  @override
  ConsumerState<Controls> createState() => _ControlsState();
}

class _ControlsState extends ConsumerState<Controls> {
  int _selectedIndex = 0;
  bool _compact = true;
  bool _isInit = false;
  late String customHomeUrl;
  late bool enableAutoLoadHomeUrl;

  final Map funcMap = {
    0: ConFunc.loadHome,
    // 1: ConFunc.httpRedirect,
    1: ConFunc.navi2Tool,
    // 2: ConFunc.bottomUp,
    2: ConFunc.refresh,
    // 4: ConFunc.scrollUp,
    // 5: ConFunc.scrollDown,
    3: ConFunc.goBack,
    4: ConFunc.goForward,
    5: ConFunc.navi2Settings,
    6: ConFunc.navi2About,
    // 1: ConFunc.adjustWindow,
    // 8: ConFunc.clearCookies,
    // 9: ConFunc.clearCache
  };

  final Map naviItems = {
    0: 0, //loadHome
    1: 1, //navi2Tool
    2: 5, //navi2Settings
    3: 6, //navi2About
  };

  /// 横画面の左メニュー (設定と情報の間にダッシュボード)
  final Map landscapeFuncMap = {
    0: ConFunc.loadHome,
    1: ConFunc.navi2Tool,
    2: ConFunc.refresh,
    3: ConFunc.goBack,
    4: ConFunc.goForward,
    5: ConFunc.navi2Settings,
    6: ConFunc.toggleDashboard,
    7: ConFunc.navi2About,
  };

  final Map landscapeNaviItems = {
    0: 0, //loadHome
    1: 1, //navi2Tool
    2: 5, //navi2Settings
    3: 7, //navi2About
  };

  void _onItemTapped(int index, {bool landscape = false}) {
    setState(() {
      final keepSelection = landscape ? [2, 3, 4, 6] : [2, 3, 4];
      if (!keepSelection.contains(index)) {
        _selectedIndex = index;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _isInit = ref.watch(webControllerProvider.select((value) => value.isInit));
    late InAppWebViewController controller = ref.watch(webControllerProvider.select((value) => value.controller));
    final flnp = ref.watch(functionLayerNavigatorProvider);
    enableAutoLoadHomeUrl = ref.watch(settingsProvider.select((value) => value.enableAutoLoadHomeUrl));
    customHomeUrl = ref.watch(settingsProvider.select((value) => value.customHomeUrl));

    final isLandscape = widget.orientation != Orientation.portrait;
    _selectedIndex = (isLandscape ? landscapeNaviItems : naviItems)[flnp.index];
    if (selectedIndex == 0) _selectedIndex = 0;

    if (widget.orientation == Orientation.portrait) {
      return BottomNavigationBar(
        showSelectedLabels: false,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: false,
        currentIndex: _selectedIndex,
        onTap: ((value) async {
          HapticFeedback.mediumImpact();
          _onTap(value, context, controller, flnp);
        }),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.home),
            label: S.of(context).AppHome,
          ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.game_controller),
            label: S.of(context).ToolsButton,
          ),
          BottomNavigationBarItem(
            icon: const Icon(
              CupertinoIcons.refresh,
              color: CupertinoColors.destructiveRed,
            ),
            label: S.of(context).AppControlsReload,
          ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.back),
            label: S.of(context).AppBack,
          ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.forward),
            label: S.of(context).AppForward,
          ),
          BottomNavigationBarItem(
            icon: const Icon(
              CupertinoIcons.settings,
            ),
            label: S.of(context).SettingsButton,
          ),
          BottomNavigationBarItem(
            icon: const Icon(
              CupertinoIcons.info,
            ),
            label: S.of(context).AboutButton,
          ),
        ],
      );
    }
    return NavigationRail(
      minWidth: _compact ? 56 : 72,
      labelType:
          _compact ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      selectedIndex: widget.isWideStyle ? 0 : _selectedIndex,
      groupAlignment: 0,
      onDestinationSelected: (int index) async {
        HapticFeedback.mediumImpact();
        if (landscapeFuncMap[index] == ConFunc.toggleDashboard) {
          // ダッシュボードの開閉は WebView を使わないので先に処理する
          widget.functionMap[FunctionName.toggleDashboard]?.call();
          return;
        }
        if (widget.isWideStyle) {
          _onTapPopover(index, context, controller, landscape: true);
        } else {
          _onTap(index, context, controller, flnp, landscape: true);
        }
      },
      trailing: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _compact = !_compact;
          });
        },
        // onLongPress: () {
        //   HapticFeedback.mediumImpact();
        //   showPopoverPage(
        //       context,
        //       Dashboard(
        //         notifyParent: widget.notifyParent,
        //       )); //Canary Deployment
        // },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Icon(
            _compact
                ? CupertinoIcons.list_bullet_below_rectangle
                : CupertinoIcons.list_bullet,
            color: CupertinoColors.activeBlue,
          ),
        ),
      ),
      destinations: [
        NavigationRailDestination(
          icon: const Icon(CupertinoIcons.home),
          label: Text(
            S.of(context).AppHome,
          ),
        ),
        NavigationRailDestination(
          icon: const Icon(CupertinoIcons.game_controller),
          label: Text(S.of(context).ToolsButton),
        ),
        NavigationRailDestination(
          icon: const Icon(
            CupertinoIcons.refresh,
            color: CupertinoColors.destructiveRed,
          ),
          label: Text(S.of(context).AppControlsReload),
        ),
        NavigationRailDestination(
          icon: const Icon(CupertinoIcons.back),
          label: Text(S.of(context).AppBack),
        ),
        NavigationRailDestination(
          icon: const Icon(CupertinoIcons.forward),
          label: Text(S.of(context).AppForward),
        ),
        NavigationRailDestination(
          icon: const Icon(
            CupertinoIcons.settings,
          ),
          label: Text(S.of(context).SettingsButton),
        ),
        NavigationRailDestination(
          icon: Icon(
            CupertinoIcons.slider_horizontal_below_rectangle,
            color: widget.dashboardOpen ? CupertinoColors.activeBlue : null,
          ),
          label: Text(
            repairText('ダッシュボード', 'Dashboard'),
            textAlign: TextAlign.center,
          ),
        ),
        NavigationRailDestination(
          icon: const Icon(
            CupertinoIcons.info,
          ),
          label: Text(
            S.of(context).AboutButton,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  void _onTap(
    int value,
    BuildContext context,
    InAppWebViewController controller,
    FunctionLayerNavigator navigator, {
    bool landscape = false,
  }) {
    _onItemTapped(value, landscape: landscape);
    var func = (landscape ? landscapeFuncMap : funcMap)[value];
    switch (func) {
      case ConFunc.toggleDashboard:
        widget.functionMap[FunctionName.toggleDashboard]?.call();
        break;
      case ConFunc.navi2About:
        selectedIndex = 1;
        widget.notifyParent();
        navigator.changeIndex(3);
        break;
      case ConFunc.navi2Tool:
        selectedIndex = 1;
        widget.notifyParent();
        navigator.changeIndex(1);
        break;
      case ConFunc.navi2Settings:
        selectedIndex = 1;
        widget.notifyParent();
        navigator.changeIndex(2);
        break;
      case ConFunc.loadHome:
        if (selectedIndex != 0) {
          selectedIndex = 0;
          navigator.changeIndex(0);
          widget.notifyParent();
        } else {
          _onLoadHome(context, controller);
        }
        break;
      case ConFunc.scrollUp:
        if (!_isInit) return;
        controller.scrollBy(x: 1, y: 0);
        break;
      case ConFunc.scrollDown:
        if (!_isInit) return;
        controller.scrollBy(x: 0, y: 1);
        break;
      case ConFunc.goBack:
        _onGoBack(context, controller);
        break;
      case ConFunc.goForward:
        _onGoForward(context, controller);
        break;
      case ConFunc.refresh:
        _onReload(context, controller);
        break;
    }
  }

  void _onTapPopover(
    int value,
    BuildContext context,
    InAppWebViewController controller, {
    bool landscape = false,
  }) {
    _onItemTapped(value, landscape: landscape);
    var func = (landscape ? landscapeFuncMap : funcMap)[value];
    switch (func) {
      case ConFunc.toggleDashboard:
        widget.functionMap[FunctionName.toggleDashboard]?.call();
        break;
      case ConFunc.navi2About:
        showPopoverPage(context, const AboutPage());
        break;
      case ConFunc.navi2Tool:
        showPopoverPage(
            context,
            ToolsPage(
              widget.cookieManager,
              isWideStyle: true,
            ));
        break;
      case ConFunc.navi2Settings:
        showPopoverPage(
            context,
            const SettingsPage());
        break;
      case ConFunc.loadHome:
        _onLoadHome(context, controller);
        break;
      case ConFunc.scrollUp:
        if (!_isInit) return;
        controller.scrollBy(x: 1, y: 0);
        break;
      case ConFunc.scrollDown:
        if (!_isInit) return;
        controller.scrollBy(x: 0, y: 1);
        break;
      case ConFunc.goBack:
        _onGoBack(context, controller);
        break;
      case ConFunc.goForward:
        _onGoForward(context, controller);
        break;
      case ConFunc.refresh:
        _onReload(context, controller);
        break;
    }
  }

  void showPopoverPage(BuildContext context, Widget child) {
    showPopover(
      context: context,
      bodyBuilder: (context) => LocalNavigator(child: child),
      onPop: () => log('Popover was popped!'),
      direction: PopoverDirection.left,
      width: 500,
      height: double.infinity,
      arrowHeight: 0,
      arrowWidth: 0,
    );
  }

  Future<void> _onReload(
      BuildContext context, InAppWebViewController controller) async {
    if (!_isInit) return;
    safeNavi = false;
    bool? value = await showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return AdaptiveDialogWithBool(msg: S.current.AppControlsReload);
        });
    if (value ?? false) {
      await controller.reload();
    }
  }

  Future<bool> _confirm(BuildContext context, String msg) async {
    bool? value = await showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return AdaptiveDialogWithBool(msg: msg);
        });
    return value ?? false;
  }

  Future<void> _onGoBack(
      BuildContext context, InAppWebViewController controller) async {
    if (!_isInit) return;
    if (!await controller.canGoBack()) return;
    if (!context.mounted || !await _confirm(context, S.current.AppBack)) return;
    safeNavi = true;
    await controller.goBack();
  }

  Future<void> _onGoForward(
      BuildContext context, InAppWebViewController controller) async {
    if (!_isInit) return;
    if (!await controller.canGoForward()) return;
    if (!context.mounted || !await _confirm(context, S.current.AppForward)) return;
    safeNavi = true;
    await controller.goForward();
  }

  Future<void> _onLoadHome(
      BuildContext context, InAppWebViewController controller) async {
    bool? value = await showDialog(
        context: context,
        builder: (context) {
          return AdaptiveDialogWithBool(msg: S.current.AppHome);
        });
    if (value ?? false) {
      String homeUrl = getHomeUrl(customHomeUrl, enableAutoLoadHomeUrl);
      safeNavi = false;
      if (homeUrl == kLocalHomeUrl) {
        await ref.read(webControllerProvider.notifier).startLocalServer();
      }
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(homeUrl)));
    }
  }
}
