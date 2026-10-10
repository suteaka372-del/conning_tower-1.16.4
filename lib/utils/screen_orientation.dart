import 'dart:io';

import 'package:flutter/services.dart';

/// 横画面でカメラ (ノッチ / Dynamic Island) がどちら側にあるか
enum CameraSide { left, right, unknown }

class ScreenOrientation {
  ScreenOrientation._();

  static const MethodChannel _channel = MethodChannel('conning_tower/orientation');

  /// iOS は横画面で左右に同じ安全領域を返すので、画面の向きをネイティブ側に問い合わせる
  /// (ios/Runner/AppDelegate.swift)
  static Future<CameraSide> cameraSide() async {
    if (!Platform.isIOS) return CameraSide.unknown;
    try {
      final orientation = await _channel.invokeMethod<String>('interfaceOrientation');
      return cameraSideOf(orientation);
    } catch (_) {
      return CameraSide.unknown;
    }
  }

  /// UIInterfaceOrientation.landscapeLeft はホームインジケータが左 = カメラが右
  static CameraSide cameraSideOf(String? interfaceOrientation) => switch (interfaceOrientation) {
        'landscapeLeft' => CameraSide.right,
        'landscapeRight' => CameraSide.left,
        _ => CameraSide.unknown,
      };
}
