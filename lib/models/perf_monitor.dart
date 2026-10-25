
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 通信1種類ぶんの処理時間 (マイクロ秒)
class PerfApiStat {
  PerfApiStat(this.path);

  final String path;
  int count = 0;

  /// データの読み込み (届いたデータを解析して覚えるまで)
  int parseTotal = 0;
  int parseMax = 0;

  /// その直後の画面の作り直し (ビルド・レイアウト・描画の準備。メインの処理だけ)
  int buildTotal = 0;
  int buildMax = 0;

  int get worst => parseMax + buildMax;
}

/// 重かった1フレーム
class PerfSlowFrame {
  const PerfSlowFrame({required this.at, required this.build, required this.raster, this.lastPath});

  final DateTime at;

  /// ミリ秒
  final double build;
  final double raster;

  /// 直前 (1秒以内) に届いた通信
  final String? lastPath;

  double get worst => build > raster ? build : raster;
}

/// 動作の重さを測る (設定の「動作の重さ」で見る。記録はアプリを閉じると消える)
class PerfMonitor {
  PerfMonitor({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final instance = PerfMonitor();

  /// 1フレームの目安 (これより長いとカクついて見える)
  static const slowFrameMs = 17.0;
  static const keepSlowFrames = 20;

  final DateTime Function() _now;
  final Map<String, PerfApiStat> api = {};
  final List<PerfSlowFrame> slowFrames = [];
  int frames = 0;
  int slowFrameCount = 0;
  DateTime? since;
  String? _lastPath;
  DateTime? _lastAt;

  /// 記録が増えたら番号が増える (画面の更新用)
  final ValueNotifier<int> revision = ValueNotifier(0);
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    since = _now();
    SchedulerBinding.instance.addTimingsCallback(recordFrames);
  }

  void reset() {
    api.clear();
    slowFrames.clear();
    frames = 0;
    slowFrameCount = 0;
    since = _now();
    revision.value++;
  }

  void recordApi(String path, {required int parseMicros, required int buildMicros}) {
    final stat = api[path] ??= PerfApiStat(path);
    stat.count++;
    stat.parseTotal += parseMicros;
    if (parseMicros > stat.parseMax) stat.parseMax = parseMicros;
    stat.buildTotal += buildMicros;
    if (buildMicros > stat.buildMax) stat.buildMax = buildMicros;
    _lastPath = path;
    _lastAt = _now();
    revision.value++;
  }

  void recordFrames(List<FrameTiming> timings) {
    var changed = false;
    for (final t in timings) {
      recordFrame(t.buildDuration.inMicroseconds / 1000, t.rasterDuration.inMicroseconds / 1000);
      changed = true;
    }
    if (changed) revision.value++;
  }

  void recordFrame(double buildMs, double rasterMs) {
    frames++;
    if (buildMs < slowFrameMs && rasterMs < slowFrameMs) return;
    slowFrameCount++;
    final now = _now();
    final recent = _lastAt != null && now.difference(_lastAt!) <= const Duration(seconds: 1);
    slowFrames.add(PerfSlowFrame(at: now, build: buildMs, raster: rasterMs, lastPath: recent ? _lastPath : null));
    if (slowFrames.length > keepSlowFrames) slowFrames.removeAt(0);
  }

  /// 通信を重い順に (1回の最大の合計)
  List<PerfApiStat> get slowestApis => api.values.toList()..sort((a, b) => b.worst.compareTo(a.worst));

  /// ゲームのデータを1つ処理する。読み込みの時間と、その直後のフレームでの作り直しの時間を記録する
  void measureApi(String path, void Function() parse) {
    final clock = Stopwatch()..start();
    parse();
    final parseMicros = clock.elapsedMicroseconds;
    int? frameStart;
    final binding = SchedulerBinding.instance;
    // フレームの始まり (作り直しの前) と終わりで測る。待ち時間 (次の描画までの間) は入らない
    binding.scheduleFrameCallback((_) => frameStart ??= clock.elapsedMicroseconds);
    binding.addPostFrameCallback((_) {
      final start = frameStart ?? clock.elapsedMicroseconds;
      recordApi(path, parseMicros: parseMicros, buildMicros: clock.elapsedMicroseconds - start);
    });
  }
}
