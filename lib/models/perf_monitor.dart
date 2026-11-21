import 'dart:convert';

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
  String? get screen => _screen;
  String? _screen;
  DateTime? _screenSince;

  set screen(String? value) {
    if (value == _screen) return;
    _closeScreenTime();
    _screen = value;
  }

  /// タブごとの描き直しの回数と、表示していた時間 (1秒あたりの描き直しの回数を出す)
  final Map<String, int> framesByScreen = {};
  final Map<String, Duration> timeByScreen = {};

  void _closeScreenTime() {
    final now = _now();
    final since = _screenSince;
    final name = _screen;
    if (since != null && name != null) {
      timeByScreen[name] = (timeByScreen[name] ?? Duration.zero) + now.difference(since);
    }
    _screenSince = now;
  }

  /// タブごとの1秒あたりの描き直しの回数 (多い順)。表示していた時間が短いタブは除く
  List<(String, double)> get frameRates {
    _closeScreenTime();
    return [
      for (final e in timeByScreen.entries)
        if (e.value.inSeconds >= 10) (e.key, (framesByScreen[e.key] ?? 0) / e.value.inMilliseconds * 1000),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// ゲーム画面の描画の回数 (1秒あたり) を測る (ゲーム画面が用意する)。測れなければ null
  Future<int?> Function()? gameFrameProbe;

  /// 最後に測ったゲーム画面の描画の回数 (1秒あたり)
  int? gameFrameRate;
  DateTime? gameFrameAt;
  bool measuringGame = false;

  Future<void> measureGameFrameRate() async {
    final probe = gameFrameProbe;
    if (probe == null || measuringGame) return;
    measuringGame = true;
    revision.value++;
    try {
      gameFrameRate = await probe();
      gameFrameAt = _now();
    } catch (_) {
      gameFrameRate = null;
    } finally {
      measuringGame = false;
      revision.value++;
    }
  }

  /// ゲーム画面 (ブラウザ) からアプリに届いた知らせの回数 (種類 → 回数)
  final Map<String, int> events = {};

  void countEvent(String name) => events[name] = (events[name] ?? 0) + 1;

  /// 戦闘中 (戦闘開始の通信から戦闘結果まで) のアプリの描き直し
  int battleFrames = 0;
  Duration battleTime = Duration.zero;
  DateTime? _battleSince;

  static bool _battleStart(String path) =>
      !path.contains('result') &&
      (path.startsWith('/api_req_sortie/') ||
          path.startsWith('/api_req_battle_midnight/') ||
          path.startsWith('/api_req_combined_battle/') ||
          path.startsWith('/api_req_practice/battle') ||
          path.startsWith('/api_req_practice/midnight_battle'));

  static bool _battleEnd(String path) => path.contains('result') || path == '/api_port/port' || path.startsWith('/api_req_map/');

  void _trackBattle(String path) {
    final now = _now();
    if (_battleStart(path)) {
      _battleSince ??= now;
    } else if (_battleEnd(path)) {
      final since = _battleSince;
      if (since != null) battleTime += now.difference(since);
      _battleSince = null;
    }
  }

  /// 戦闘中の1秒あたりの描き直しの回数 (戦闘の記録がなければ null)
  double? get battleFrameRate => battleTime.inSeconds < 5 ? null : battleFrames / battleTime.inMilliseconds * 1000;

  /// 全体の1秒あたりの描き直しの回数
  double get frameRate {
    final start = since;
    if (start == null) return 0;
    final ms = _now().difference(start).inMilliseconds;
    return ms <= 0 ? 0 : frames / ms * 1000;
  }

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
    _screenSince = since;
    SchedulerBinding.instance.addTimingsCallback(recordFrames);
  }

  void reset() {
    api.clear();
    slowFrames.clear();
    frames = 0;
    slowFrameCount = 0;
    since = _now();
    framesByScreen.clear();
    timeByScreen.clear();
    _screenSince = since;
    events.clear();
    battleFrames = 0;
    battleTime = Duration.zero;
    _battleSince = null;
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
    final name = _screen;
    if (name != null) framesByScreen[name] = (framesByScreen[name] ?? 0) + 1;
    if (_battleSince != null) battleFrames++;
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
    _trackBattle(path);
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

/// ゲーム画面 (ブラウザ) が iOS に終了させられた1回
class GameStop {
  const GameStop({required this.at, this.volumes});

  final DateTime at;

  /// そのときのゲームの音量 (BGM・効果音・ボイス)。分からなければ null
  final ({int bgm, int se, int voice})? volumes;

  bool? get soundOn => volumes == null ? null : volumes!.bgm > 0 || volumes!.se > 0 || volumes!.voice > 0;

  Map<String, dynamic> toJson() => {
        't': at.millisecondsSinceEpoch,
        if (volumes != null) 'v': [volumes!.bgm, volumes!.se, volumes!.voice],
      };

  static GameStop? fromJson(dynamic json) {
    if (json is! Map || json['t'] is! int) return null;
    final v = json['v'];
    return GameStop(
      at: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
      volumes: v is List && v.length == 3 && v.every((e) => e is int)
          ? (bgm: v[0] as int, se: v[1] as int, voice: v[2] as int)
          : null,
    );
  }
}

/// ゲームの音量の設定 (cookie の kcs_options。例: vol_bgm%3D0%3Bvol_se%3D40%3Bvol_voice%3D60%3B...)
({int bgm, int se, int voice})? parseKancolleVolumes(String? kcsOptions) {
  if (kcsOptions == null || kcsOptions.isEmpty) return null;
  final text = Uri.decodeComponent(kcsOptions);
  final values = <String, int>{};
  for (final part in text.split(';')) {
    final kv = part.split('=');
    if (kv.length == 2 && int.tryParse(kv[1].trim()) != null) values[kv[0].trim()] = int.parse(kv[1].trim());
  }
  final bgm = values['vol_bgm'], se = values['vol_se'], voice = values['vol_voice'];
  if (bgm == null || se == null || voice == null) return null;
  return (bgm: bgm, se: se, voice: voice);
}

/// ゲーム画面が止まった記録 (端末に保存。直近の [keep] 件)
class GameStopLog {
  GameStopLog({this.load, this.save});

  static const keep = 30;

  final String? Function()? load;
  final void Function(String json)? save;

  List<GameStop>? _stops;

  /// 古い順
  List<GameStop> get stops => _stops ??= _read();

  final ValueNotifier<int> revision = ValueNotifier(0);

  List<GameStop> _read() {
    try {
      final text = load?.call();
      if (text == null || text.isEmpty) return [];
      return [for (final e in jsonDecode(text) as List) if (GameStop.fromJson(e) case final stop?) stop];
    } catch (_) {
      return [];
    }
  }

  void add(GameStop stop) {
    final list = stops..add(stop);
    if (list.length > keep) list.removeRange(0, list.length - keep);
    try {
      save?.call(jsonEncode([for (final s in list) s.toJson()]));
    } catch (_) {}
    revision.value++;
  }

  void clear() {
    stops.clear();
    try {
      save?.call('[]');
    } catch (_) {}
    revision.value++;
  }
}
