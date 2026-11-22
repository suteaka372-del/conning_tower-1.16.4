import 'package:flutter/services.dart';

/// iPhone の低電力モードと本体の熱さ (iOS が教えてくれる値)。
/// どちらの場合も、iPhone のブラウザはゲームの動きを1秒に30回に落とすことがある (Safari でも同じ)
class DevicePower {
  const DevicePower({required this.lowPower, required this.thermal});

  final bool lowPower;

  /// 本体の熱さ。0 普通・1 少し熱い・2 熱い・3 とても熱い (iOS の ProcessInfo.ThermalState)
  final int thermal;

  static const thermalLabels = ['普通', '少し熱い', '熱い', 'とても熱い'];

  String get thermalLabel => thermal >= 0 && thermal < thermalLabels.length ? thermalLabels[thermal] : '不明';

  /// 低電力モード オフ・本体の熱さ 普通
  String get label => '低電力モード ${lowPower ? 'オン' : 'オフ'}・本体の熱さ $thermalLabel';

  Map<String, dynamic> toJson() => {'lp': lowPower, 'th': thermal};

  static DevicePower? fromJson(dynamic json) {
    if (json is! Map || json['lp'] is! bool || json['th'] is! int) return null;
    return DevicePower(lowPower: json['lp'] as bool, thermal: json['th'] as int);
  }

  @override
  bool operator ==(Object other) => other is DevicePower && other.lowPower == lowPower && other.thermal == thermal;

  @override
  int get hashCode => Object.hash(lowPower, thermal);
}

/// iOS 側 (AppDelegate.swift) と同じ名前
const devicePowerChannel = MethodChannel('conning_tower/device_power');

/// 今の低電力モードと本体の熱さを iOS に聞く。iOS 以外や、聞けなかったときは null
Future<DevicePower?> readDevicePower() async {
  try {
    final result = await devicePowerChannel.invokeMapMethod<String, dynamic>('get');
    if (result == null || result['lowPower'] is! bool || result['thermal'] is! num) return null;
    return DevicePower(lowPower: result['lowPower'] as bool, thermal: (result['thermal'] as num).toInt());
  } catch (_) {
    return null;
  }
}
