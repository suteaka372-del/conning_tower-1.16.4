import 'dart:io';

import 'package:conning_tower/constants.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/providers/generatable/settings_provider.dart';
import 'package:conning_tower/widgets/controls.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({
    super.key,
    required this.notifyParent,
    required this.cookieManager,
    required this.functionMap,
    this.dashboardOpen = false,
    this.browserOpen = false,
  });

  final Function() notifyParent;
  final CookieManager? cookieManager;
  final Map<FunctionName, Function> functionMap;
  final bool dashboardOpen;
  final bool browserOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Size size = MediaQuery.of(context).size;
    AppLayout appLayout = ref.watch(settingsProvider.select((value) => value.appLayout));

    if (appLayout == AppLayout.onlyJoystick ||
        appLayout == AppLayout.bothFABJoystick) {
      if (size.width >= 1024) {
        return SingleChildScrollView(
          controller: ScrollController(),
          scrollDirection: Axis.vertical,
          child: IntrinsicHeight(
              child: Controls(
            cookieManager,
            notifyParent: notifyParent,
            orientation: Orientation.landscape,
            functionMap: functionMap,
            isWideStyle: true,
            enableJoystick: Platform.isIOS,
            dashboardOpen: dashboardOpen,
            browserOpen: browserOpen,
          )));
      } else {
        return Center(
          child: Column(
            children: [
              Container(
                width: 52,
                margin: const EdgeInsets.only(
                  top: 40,
                  bottom: 10,
                ),
                child: Center(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: ScrollController(),
                  scrollDirection: Axis.vertical,
                  child: IntrinsicHeight(
                    child: Controls(
                      cookieManager,
                      notifyParent: notifyParent,
                      orientation: Orientation.landscape,
                      functionMap: functionMap,
                      dashboardOpen: dashboardOpen,
            browserOpen: browserOpen,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } else {
      return SingleChildScrollView(
          controller: ScrollController(),
          scrollDirection: Axis.vertical,
          child: IntrinsicHeight(
              child: Controls(
            cookieManager,
            notifyParent: notifyParent,
            orientation: Orientation.landscape,
            functionMap: functionMap,
            isWideStyle: size.width >= 1024,
            dashboardOpen: dashboardOpen,
            browserOpen: browserOpen,
          )));
    }
  }
}
