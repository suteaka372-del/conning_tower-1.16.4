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

  /// 読み込みの内訳 (段階の名前 → 合計・最大)
  final Map<String, int> stageTotal = {};
  final Map<String, int> stageMax = {};

  int get worst => parseMax + buildMax;

  /// 内訳を平均の長い順に
  List<(String, int, int)> get stages => [
        for (final e in stageTotal.entries) (e.key, e.value ~/ count, stageMax[e.key] ?? 0),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
}

/// 重かった1フレーム
class PerfSlowFrame {
  const PerfSlowFrame({required this.at, required this.build, required this.raster, this.lastPath, this.screen});

  final DateTime at;

  /// ミリ秒
  final double build;
  final double raster;

  /// 直前 (1秒以内) に届いた通信
  final String? lastPath;

  /// そのとき表示していたダッシュボードのタブ
  final String? screen;

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

  /// 今表示しているダッシュボードのタブ (ダッシュボードが知らせる)
  String? screen;

  /// 処理中の通信の内訳 (段階ごとの時間)
  Map<String, int>? _stages;
  Stopwatch? _stageClock;
  int _stageMark = 0;

  /// 読み込みの1段階が終わった。前の区切りからの時間を [name] に足す (通信を処理していないときは何もしない)
  void lap(String name) {
    final stages = _stages;
    final clock = _stageClock;
    if (stages == null || clock == null) return;
    final now = clock.elapsedMicroseconds;
    stages[name] = (stages[name] ?? 0) + now - _stageMark;
    _stageMark = now;
  }

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

  void recordApi(String path, {required int parseMicros, required int buildMicros, Map<String, int> stages = const {}}) {
    final stat = api[path] ??= PerfApiStat(path);
    stat.count++;
    for (final MapEntry(:key, :value) in stages.entries) {
      stat.stageTotal[key] = (stat.stageTotal[key] ?? 0) + value;
      if (value > (stat.stageMax[key] ?? 0)) stat.stageMax[key] = value;
    }
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
    slowFrames.add(
        PerfSlowFrame(at: now, build: buildMs, raster: rasterMs, lastPath: recent ? _lastPath : null, screen: screen));
    if (slowFrames.length > keepSlowFrames) slowFrames.removeAt(0);
  }

  /// 通信を重い順に (1回の最大の合計)
  List<PerfApiStat> get slowestApis => api.values.toList()..sort((a, b) => b.worst.compareTo(a.worst));

  /// ゲームのデータを1つ処理する。読み込みの時間と、その直後のフレームでの作り直しの時間を記録する
  void measureApi(String path, void Function() parse) {
    final clock = Stopwatch()..start();
    final stages = <String, int>{};
    _stages = stages;
    _stageClock = clock;
    _stageMark = 0;
    try {
      parse();
      lap('画面へ知らせる');
    } finally {
      _stages = null;
      _stageClock = null;
    }
    final parseMicros = clock.elapsedMicroseconds;
    int? frameStart;
    final binding = SchedulerBinding.instance;
    // フレームの始まり (作り直しの前) と終わりで測る。待ち時間 (次の描画までの間) は入らない
    binding.scheduleFrameCallback((_) => frameStart ??= clock.elapsedMicroseconds);
    binding.addPostFrameCallback((_) {
      final start = frameStart ?? clock.elapsedMicroseconds;
      recordApi(path, parseMicros: parseMicros, buildMicros: clock.elapsedMicroseconds - start, stages: stages);
    });
  }
}
