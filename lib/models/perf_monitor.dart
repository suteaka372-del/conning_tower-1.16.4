import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FramePhase, Size;

import 'package:conning_tower/utils/device_power.dart';
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

/// ゲーム画面の描画を測った1回
class GameFrameSample {
  const GameFrameSample({
    required this.at,
    required this.fps,
    this.power,
    this.inBattle = false,
    this.manual = false,
    this.shown,
  });

  final DateTime at;

  /// 1秒あたりの描画の回数
  final int fps;

  /// そのときの低電力モードと本体の熱さ (分からなければ null)
  final DevicePower? power;

  final bool inBattle;

  /// 「測る」を押した (false なら自動)
  final bool manual;

  /// ゲーム画面が見えていたか (分からなければ null)
  final bool? shown;
}

/// ゲーム画面の中で、全画面に合わせるスクリプト (kancolleFitIOS.js) が動いた回数 (ゲームのページを読み込んでから)
class GameFitStats {
  const GameFitStats({required this.minutes, required this.mutations, required this.applies});

  /// ページを読み込んでからの時間 (分)
  final double minutes;

  /// ページの中身が変わったと知らされた回数
  final int mutations;

  /// 実際に合わせ直した回数
  final int applies;

  /// ページの中のスクリプトが返した値から作る。形が違えば null
  static GameFitStats? fromJs(dynamic value) {
    if (value is! Map) return null;
    final minutes = value['minutes'], mutations = value['mutations'], applies = value['applies'];
    if (minutes is! num || mutations is! num || applies is! num) return null;
    return GameFitStats(minutes: minutes.toDouble(), mutations: mutations.toInt(), applies: applies.toInt());
  }
}

/// ゲーム画面の合わせ直し1回 (大きさが大きく変わったとき)
class PerfRefit {
  const PerfRefit({required this.at, required this.from, required this.to, this.view, this.inBattle = false});

  final DateTime at;

  /// ゲーム画面の中身の大きさ (変わる前 → 後)
  final Size from;
  final Size to;

  /// そのときのゲーム画面の枠 (アプリの中での大きさ)。枠が変わっていなければ、中身が自分で変わった
  final Size? view;

  final bool inBattle;
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

  /// タブごとの1秒あたりの描き直しの回数と、表示していた時間 (多い順)。表示していた時間が短いタブは除く
  List<(String, double, Duration)> get frameRates {
    _closeScreenTime();
    return [
      for (final e in timeByScreen.entries)
        if (e.value.inSeconds >= 10) (e.key, (framesByScreen[e.key] ?? 0) / e.value.inMilliseconds * 1000, e.value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// ゲーム画面の描画の回数 (1秒あたり) を測る (ゲーム画面が用意する)。測れなければ null
  Future<int?> Function()? gameFrameProbe;

  /// 最後に測ったゲーム画面の描画の回数 (1秒あたり)
  int? gameFrameRate;
  DateTime? gameFrameAt;
  bool measuringGame = false;

  /// 低電力モードと本体の熱さを聞く (iOS 以外では null を返す)
  Future<DevicePower?> Function()? powerProbe;

  /// ゲーム画面の描画を測ったときの低電力モードと本体の熱さ
  DevicePower? gameFramePower;

  /// ゲーム画面が見えているか (アプリが表に出ていて、ツールや設定の画面に隠れていない)。分からなければ null
  bool Function()? gameShownProbe;

  /// 最後に測ったとき、ゲーム画面が見えていたか (隠れているとブラウザが描画を落とすので、数字が低く出る)
  bool? gameFrameShown;

  /// ゲーム画面の中の、全画面に合わせるスクリプトが動いた回数を聞く (ゲーム画面が用意する)
  Future<GameFitStats?> Function()? gameFitProbe;

  /// 最後に聞いた、全画面に合わせるスクリプトが動いた回数 (ゲームのページを読み込んでから)
  GameFitStats? gameFit;

  /// ゲーム画面の描画の記録 (自動で [gameSampleInterval] ごとに測った分と、「測る」を押した分。古い順)
  static const gameSampleInterval = Duration(minutes: 2);
  static const keepGameSamples = 60;
  final List<GameFrameSample> gameSamples = [];
  Timer? _sampleTimer;

  /// ゲーム画面の描画の回数を1秒かけて測る。[manual] は「測る」を押したとき
  Future<void> measureGameFrameRate({bool manual = true}) async {
    final probe = gameFrameProbe;
    if (probe == null || measuringGame) return;
    measuringGame = true;
    revision.value++;
    try {
      final shown = gameShownProbe?.call();
      final power = powerProbe?.call() ?? Future<DevicePower?>.value();
      gameFrameRate = await probe();
      gameFramePower = await power;
      gameFrameShown = shown;
      gameFrameAt = _now();
      final fps = gameFrameRate;
      if (fps != null) {
        gameSamples.add(GameFrameSample(
          at: gameFrameAt!,
          fps: fps,
          power: gameFramePower,
          inBattle: _battleSince != null,
          manual: manual,
          shown: shown,
        ));
        if (gameSamples.length > keepGameSamples) gameSamples.removeAt(0);
      }
      gameFit = await (gameFitProbe?.call() ?? Future<GameFitStats?>.value()) ?? gameFit;
    } catch (_) {
      gameFrameRate = null;
      gameFramePower = null;
    } finally {
      measuringGame = false;
      revision.value++;
    }
  }

  /// 自動の記録1回分。アプリが裏にあるときや、ゲーム画面が隠れているときは測らない (低く出るので)
  Future<void> sampleGame() async {
    if (gameShownProbe?.call() == false) return;
    await measureGameFrameRate(manual: false);
  }

  /// [gameSampleInterval] ごとに自動で測り始める (アプリの起動時に1回)
  void startGameSampling() {
    _sampleTimer ??= Timer.periodic(gameSampleInterval, (_) => sampleGame());
  }

  /// ゲーム画面 (ブラウザ) からアプリに届いた知らせの回数 (種類 → 回数)
  final Map<String, int> events = {};

  /// 戦闘中に届いた知らせは「(戦闘中)」を付けて別にも数える (カクつきとの関係を見るため)
  void countEvent(String name) {
    events[name] = (events[name] ?? 0) + 1;
    if (_battleSince != null) {
      final battle = '$name(戦闘中)';
      events[battle] = (events[battle] ?? 0) + 1;
    }
  }

  /// 漫画のブラウザからアプリに届いた知らせの回数 (種類 → 回数。戦闘中は「(戦闘中)」付きでも数える)
  final Map<String, int> browserEvents = {};

  void countBrowserEvent(String name) {
    browserEvents[name] = (browserEvents[name] ?? 0) + 1;
    if (_battleSince != null) {
      final battle = '$name(戦闘中)';
      browserEvents[battle] = (browserEvents[battle] ?? 0) + 1;
    }
  }

  /// 漫画のブラウザを表示している間の時間と描き直し (戦闘中の分も別に数える)
  bool _browserShown = false;
  DateTime? _browserSince;
  Duration _browserTime = Duration.zero;
  int browserFrames = 0;
  int battleFramesWithBrowser = 0;

  bool get browserShown => _browserShown;

  /// 漫画のブラウザを表示している (画面が知らせる)
  set browserShown(bool value) {
    if (value == _browserShown) return;
    final now = _now();
    if (_browserShown && _browserSince != null) _browserTime += now.difference(_browserSince!);
    _browserShown = value;
    _browserSince = value ? now : null;
  }

  /// 漫画のブラウザを表示していた時間 (今表示していればその分も)
  Duration get browserTime {
    final since = _browserSince;
    return _browserShown && since != null ? _browserTime + _now().difference(since) : _browserTime;
  }

  /// ゲーム画面の枠の大きさ (ゲーム画面が作られるたびに知らせる)
  Size? gameViewSize;

  /// 最近の合わせ直し (古い順、[keepRefits] 件まで)
  static const keepRefits = 10;
  final List<PerfRefit> refits = [];

  /// ゲーム画面を合わせ直した (中身の大きさ [from] → [to])
  void recordRefit(Size from, Size to) {
    countEvent('refit');
    refits.add(PerfRefit(at: _now(), from: from, to: to, view: gameViewSize, inBattle: _battleSince != null));
    if (refits.length > keepRefits) refits.removeAt(0);
    revision.value++;
  }

  /// アプリの通知 (「戦闘終了」など) を出した回数と、通知が出ている間の描き直しの回数
  int notices = 0;
  int noticesInBattle = 0;
  int noticeFrames = 0;
  DateTime? _noticeFrom;
  DateTime? _noticeUntil;

  /// 通知を出した。[shown] は表示する時間 (出る・消える動きのぶん少し長めに見る)
  void countNotice(Duration shown) {
    notices++;
    if (_battleSince != null) noticesInBattle++;
    final now = _now();
    final until = now.add(shown + const Duration(seconds: 1));
    final current = _noticeUntil;
    if (current == null || now.isAfter(current)) {
      _noticeFrom = now;
      _noticeUntil = until;
    } else if (until.isAfter(current)) {
      _noticeUntil = until;
    }
  }

  /// [at] に通知が出ていたか
  bool _inNotice(DateTime at) {
    final from = _noticeFrom;
    final until = _noticeUntil;
    return from != null && until != null && !at.isBefore(from) && !at.isAfter(until);
  }

  /// [at] が通信を処理した直後 (1秒以内) か
  bool _afterApi(DateTime at) {
    final last = _lastAt;
    if (last == null) return false;
    final d = at.difference(last);
    return d > const Duration(milliseconds: -100) && d <= const Duration(seconds: 1);
  }

  /// 戦闘中 (戦闘開始の通信から戦闘結果まで) のアプリの描き直し
  int battleFrames = 0;

  /// 戦闘中の描き直しの内訳: 通知が出ている間・通信の直後 (1秒以内)・それ以外
  int battleFramesInNotice = 0;
  int battleFramesAfterApi = 0;
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
    powerProbe ??= readDevicePower;
    startGameSampling();
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
    refits.clear();
    gameSamples.clear();
    browserEvents.clear();
    _browserTime = Duration.zero;
    _browserSince = _browserShown ? since : null;
    browserFrames = 0;
    battleFramesWithBrowser = 0;
    notices = 0;
    noticesInBattle = 0;
    noticeFrames = 0;
    _noticeFrom = null;
    _noticeUntil = null;
    battleFrames = 0;
    battleFramesInNotice = 0;
    battleFramesAfterApi = 0;
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
    final now = _now();
    for (final t in timings) {
      recordFrame(t.buildDuration.inMicroseconds / 1000, t.rasterDuration.inMicroseconds / 1000, at: frameTime(t, now));
      changed = true;
    }
    if (changed) revision.value++;
  }

  /// フレームを描き終えた時刻。リリース版ではフレームの記録が約1秒ごとにまとめて届くので、届いた時刻ではなくこちらを使う
  static DateTime frameTime(FrameTiming t, DateTime now) {
    final micros = t.timestampInMicroseconds(FramePhase.rasterFinishWallTime);
    if (micros <= 0) return now;
    final at = DateTime.fromMicrosecondsSinceEpoch(micros);
    // 時計がずれていそうなら届いた時刻にする
    return at.difference(now).abs() > const Duration(seconds: 10) ? now : at;
  }

  void recordFrame(double buildMs, double rasterMs, {DateTime? at}) {
    frames++;
    final name = _screen;
    if (name != null) framesByScreen[name] = (framesByScreen[name] ?? 0) + 1;
    final now = at ?? _now();
    final inNotice = _inNotice(now);
    if (inNotice) noticeFrames++;
    if (_browserShown) browserFrames++;
    if (_battleSince != null) {
      battleFrames++;
      if (_browserShown) battleFramesWithBrowser++;
      if (inNotice) {
        battleFramesInNotice++;
      } else if (_afterApi(now)) {
        battleFramesAfterApi++;
      }
    }
    if (buildMs < slowFrameMs && rasterMs < slowFrameMs) return;
    slowFrameCount++;
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
  const GameStop({required this.at, this.volumes, this.power});

  final DateTime at;

  /// そのときのゲームの音量 (BGM・効果音・ボイス)。分からなければ null
  final ({int bgm, int se, int voice})? volumes;

  /// そのときの低電力モードと本体の熱さ。分からなければ null
  final DevicePower? power;

  bool? get soundOn => volumes == null ? null : volumes!.bgm > 0 || volumes!.se > 0 || volumes!.voice > 0;

  Map<String, dynamic> toJson() => {
        't': at.millisecondsSinceEpoch,
        if (volumes != null) 'v': [volumes!.bgm, volumes!.se, volumes!.voice],
        if (power != null) 'p': power!.toJson(),
      };

  static GameStop? fromJson(dynamic json) {
    if (json is! Map || json['t'] is! int) return null;
    final v = json['v'];
    return GameStop(
      at: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
      volumes: v is List && v.length == 3 && v.every((e) => e is int)
          ? (bgm: v[0] as int, se: v[1] as int, voice: v[2] as int)
          : null,
      power: DevicePower.fromJson(json['p']),
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
