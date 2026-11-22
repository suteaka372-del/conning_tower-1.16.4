import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/perf_monitor.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:toastification/toastification.dart';

import '../generated/l10n.dart';

/// 通知の設定 (端末に保存)
class NoticeSettings {
  static const battleEndKey = 'kcBattleEndNotice';

  /// 「戦闘終了」の通知を出すか。初期はオフ
  /// (戦闘結果の画面の上に毎回出て、出る・消える動きでアプリが描き直すため。終わったことは振動で分かる)
  static bool get battleEnd {
    try {
      return localStorage.getBool(battleEndKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setBattleEnd(bool value) async {
    try {
      await localStorage.setBool(battleEndKey, value);
    } catch (_) {}
  }
}

class Toast {
  /// 通知を出す。残り時間の横棒は出さない
  /// (横棒は出ている間ずっとアプリ全体を描き直し続け、ゲーム画面の上に重なるので戦闘結果の画面がカクつく)
  static ToastificationItem show(
      {required String title, String? description, Duration? autoCloseDuration, ToastificationType? type}) {
    final duration = autoCloseDuration ?? const Duration(seconds: 4);
    PerfMonitor.instance.countNotice(duration);
    return toastification.show(
      type: type ?? ToastificationType.info,
      style: ToastificationStyle.flat,
      title: Text(title),
      description: description != null ? Text(description) : null,
      alignment: Alignment.topCenter,
      autoCloseDuration: duration,
      showProgressBar: false,
    );
  }

  static showWarning({
    required String title,
    String? description,
    Duration? autoCloseDuration,
  }) =>
      show(
        type: ToastificationType.warning,
        title: title,
        description: description,
        autoCloseDuration: autoCloseDuration,
      );

  static showError({
    required String title,
    String? description,
    Duration? autoCloseDuration,
  }) =>
      show(
        type: ToastificationType.error,
        title: title,
        description: description,
        autoCloseDuration: autoCloseDuration,
      );

  static showSuccess({
    required String title,
    String? description,
    Duration? autoCloseDuration,
  }) =>
      show(
        type: ToastificationType.success,
        title: title,
        description: description,
        autoCloseDuration: autoCloseDuration,
      );

  /// 戦闘が終わった: 振動と音で知らせる。「戦闘終了」の通知は設定でオンのときだけ (初期はオフ)。
  /// 大破した艦がいれば、設定にかかわらず警告を出す
  static Future<void> battleResultNotify(List<String> damageShips) async {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    final finish = NoticeSettings.battleEnd;
    if (finish) show(title: S.current.KCBattleFinish);
    if (damageShips.isEmpty) {
      return;
    }
    if (finish) await Future.delayed(const Duration(milliseconds: 500));
    showWarning(
      title: S.current.TextLDamage,
      description: damageShips.join('\n'),
      autoCloseDuration: const Duration(seconds: 10),
    );
  }

  static kancolleUnlockNotify(String title, String description) {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    showSuccess(title: title, description: description, autoCloseDuration: const Duration(seconds: 15));
  }
}
