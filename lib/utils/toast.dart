import 'package:conning_tower/models/perf_monitor.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:toastification/toastification.dart';

import '../generated/l10n.dart';

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

  static battleResultNotify(List<String> damageShips) async {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    show(title: S.current.KCBattleFinish);
    if (damageShips.isEmpty) {
      return;
    }
    await Future.delayed(const Duration(milliseconds: 500));
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
