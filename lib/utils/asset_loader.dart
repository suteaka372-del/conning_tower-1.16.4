import 'package:flutter/services.dart';

class AssetLoader {

  static const KC_INJECT_PATH = 'assets/js/inject.js';

  static const KC_ALIGN_PATH = 'assets/js/align.js';

  static const KC_SCREENSHOT_PATH = 'assets/js/screenshot.js';

  static const KC_FIT_IOS_PATH = 'assets/js/kancolleFitIOS.js';

  static late String kcInjectJS;

  static late String kcAlignJS;

  static late String kcScreenshotJS;

  static late String kcFitIOSJS;

  static Future<void> init() async {
    kcInjectJS = await loadAsset(KC_INJECT_PATH);
    kcAlignJS = await loadAsset(KC_ALIGN_PATH);
    kcScreenshotJS = await loadAsset(KC_SCREENSHOT_PATH);
    kcFitIOSJS = await loadAsset(KC_FIT_IOS_PATH);
  }

  static Future<String> loadAsset(String path) async {
    return await rootBundle.loadString(path);
  }
}