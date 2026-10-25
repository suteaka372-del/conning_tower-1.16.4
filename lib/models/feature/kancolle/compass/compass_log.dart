import 'dart:convert';

import 'package:conning_tower/main.dart';

import 'compass_maps.dart';

/// 実際に進んだ1マスぶん (どこから → どこへ) と、そのときの予測
class CompassLogStep {
  final String from;
  final String to;

  /// 予測で [to] に進む確率 (判定できないときは null)
  final double? predicted;
  final String reason;

  const CompassLogStep({required this.from, required this.to, required this.predicted, required this.reason});

  /// 予測では行かないはずのマスに行った
  bool get mismatch => predicted != null && predicted! <= 0;

  Map<String, dynamic> toJson() => {'f': from, 't': to, 'p': predicted, 'r': reason};

  factory CompassLogStep.fromJson(Map<String, dynamic> json) => CompassLogStep(
        from: '${json['f']}',
        to: '${json['t']}',
        predicted: (json['p'] as num?)?.toDouble(),
        reason: '${json['r'] ?? ''}',
      );
}

/// 1回の出撃の記録
class CompassLogEntry {
  final int mapId;
  final DateTime time;
  final List<CompassLogStep> steps;

  CompassLogEntry({required this.mapId, required this.time, List<CompassLogStep>? steps}) : steps = steps ?? [];

  bool get mismatch => steps.any((s) => s.mismatch);

  /// Start→A→D のような道のり
  String get route => ['Start', ...steps.map((s) => s.to)].join('→');

  Map<String, dynamic> toJson() =>
      {'m': mapId, 't': time.millisecondsSinceEpoch, 's': [for (final s in steps) s.toJson()]};

  factory CompassLogEntry.fromJson(Map<String, dynamic> json) => CompassLogEntry(
        mapId: json['m'] as int,
        time: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
        steps: [for (final s in json['s'] as List) CompassLogStep.fromJson(Map<String, dynamic>.from(s as Map))],
      );
}

/// 出撃のたびに進んだマスと予測を記録して、予測が合っているか確かめられるようにする
class CompassRecorder {
  CompassRecorder({this.load, this.save, this.maxEntries = 30});

  /// 保存したもの (JSON) を読む / 保存する
  final String? Function()? load;
  final void Function(String json)? save;
  final int maxEntries;

  List<CompassLogEntry>? _entries;

  /// 出撃中の海域 (ゲージが複数ある海域は、ゲージごとの判定すべて)
  List<CompassMap> _maps = const [];
  CompassFleet? _fleet;
  String _last = 'Start';

  /// 出撃地点から [_last] の1つ前までに通ったマス
  final List<String> _path = [];
  CompassLogEntry? _current;

  /// 新しい順
  List<CompassLogEntry> get entries => _entries ??= _read();

  List<CompassLogEntry> _read() {
    try {
      final text = load?.call();
      if (text == null || text.isEmpty) return [];
      return [for (final e in jsonDecode(text) as List) CompassLogEntry.fromJson(Map<String, dynamic>.from(e as Map))];
    } catch (_) {
      return [];
    }
  }

  void _write() {
    try {
      save?.call(jsonEncode([for (final e in entries) e.toJson()]));
    } catch (_) {}
  }

  /// 出撃 (api_req_map/start) と進撃 (api_req_map/next) のたびに呼ぶ。[fleet] は出撃したときの艦隊
  void onMapPoint({required int mapId, required int? cell, required bool start, CompassFleet Function()? fleet}) {
    if (start) {
      _maps = compassMapsOf(mapId);
      _current = null;
      _last = 'Start';
      _path.clear();
      if (_maps.isEmpty) return; // まだ対応していない海域
      _fleet = fleet?.call();
      _current = CompassLogEntry(mapId: mapId, time: DateTime.now());
      entries.insert(0, _current!);
      if (entries.length > maxEntries) entries.removeRange(maxEntries, entries.length);
    }
    final current = _current;
    if (_maps.isEmpty || current == null || cell == null || _maps.first.mapId != mapId) return;
    // ゲージによってマスの数が違う海域があるので、どれかのゲージにあるマスなら使う
    final edge = [for (final map in _maps) map.edges[cell]].nonNulls.firstOrNull;
    if (edge == null) return;
    final (from, to) = edge;
    // 出撃地点が2つある海域などで、1つ手前のマスを飛ばして届くことがある
    if (from != _last && _maps.any((map) => map.nextOf(_last).contains(from))) _step(current, from);
    _step(current, to);
    _write();
  }

  void _step(CompassLogEntry current, String to) {
    final fleetNow = _fleet;
    double? predicted;
    var reason = '';
    if (fleetNow != null) {
      // ゲージごとの判定のうち、一番当てはまるもので比べる (今どのゲージかはわからないため)
      for (final map in _maps) {
        final outcome = map.decide(_last, fleetNow, path: _path);
        if (outcome == null) continue;
        final p = outcome.choice && outcome.options.any((o) => o.node == to) ? 1.0 : outcome.probabilityOf(to);
        if (predicted == null || p > predicted) {
          predicted = p;
          reason = outcome.reason;
        }
      }
    }
    current.steps.add(CompassLogStep(from: _last, to: to, predicted: predicted, reason: reason));
    _path.add(_last);
    _last = to;
  }
}

/// アプリ全体で使う記録 (端末に保存)
final CompassRecorder compassRecorder = CompassRecorder(
  load: () => localStorage.getString('compass_log'),
  save: (json) => localStorage.setString('compass_log', json),
);
