import 'package:conning_tower/utils/device_power.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(devicePowerChannel, null));

  test('labels and saving', () {
    const power = DevicePower(lowPower: true, thermal: 2);
    expect(power.label, '低電力モード オン・本体の熱さ 熱い');
    expect(const DevicePower(lowPower: false, thermal: 0).label, '低電力モード オフ・本体の熱さ 普通');
    expect(const DevicePower(lowPower: false, thermal: 1).thermalLabel, '少し熱い');
    expect(const DevicePower(lowPower: false, thermal: 3).thermalLabel, 'とても熱い');
    expect(const DevicePower(lowPower: false, thermal: 9).thermalLabel, '不明');
    expect(DevicePower.fromJson(power.toJson()), power);
    expect(DevicePower.fromJson(null), isNull);
    expect(DevicePower.fromJson({'lp': 'yes', 'th': 1}), isNull);
  });

  test('asks iOS through the channel', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(devicePowerChannel, (call) async {
      calls.add(call.method);
      return {'lowPower': true, 'thermal': 1};
    });
    expect(await readDevicePower(), const DevicePower(lowPower: true, thermal: 1));
    expect(calls, ['get']);

    // 変な値なら分からないことにする
    messenger.setMockMethodCallHandler(devicePowerChannel, (call) async => {'lowPower': 1});
    expect(await readDevicePower(), isNull);
  });

  test('other platforms (no iOS side) give null', () async {
    expect(await readDevicePower(), isNull);
    messenger.setMockMethodCallHandler(devicePowerChannel, (call) async => throw PlatformException(code: 'x'));
    expect(await readDevicePower(), isNull);
  });
}
