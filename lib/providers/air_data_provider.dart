import 'dart:convert';
import 'dart:io';

import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/air/air_data.dart';
import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 制空権シミュレーターのデータを取得して端末に保存する (1週間たったら取り直す)。
/// - 深海棲艦の素の対空値・搭載数: data ブランチの airsim/abyssal.json
/// - 敵編成: KCNav (tsunkit.net) の報告。アプリには同梱せず、開いた海域の分だけその場で取得する
class AirDataLoader {
  AirDataLoader._();

  static const _maxAge = Duration(days: 7);
  static const _timeout = Duration(seconds: 30);

  /// 敵編成は直近半年の報告を使う (少なすぎるときは2年)
  static const _recent = Duration(days: 180);
  static const _older = Duration(days: 730);

  static AbyssalTable? abyssal;
  static DateTime? abyssalAt;
  static String? abyssalError;

  /// 海域 (とゲージ) ごとの敵編成
  static final Map<String, List<EnemyComp>> comps = {};
  static final Map<String, DateTime> compsAt = {};
  static final Map<String, String> compsError = {};

  /// 読み込みの状態が変わったら増える (画面の作り直し用)
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<void>? _abyssalRunning;
  static final Map<String, Future<void>> _compsRunning = {};

  static File get _abyssalFile => File(pathUtil.localAirAbyssalPath);

  static String keyOf(CompassMap map) {
    final gauge = airGaugeOf(map);
    return gauge == null ? map.name : '${map.name}_g$gauge';
  }

  static File _compsFile(String key) => File('${pathUtil.localAirCompsDir}${Platform.pathSeparator}$key.json');

  static bool loadingComps(CompassMap map) => _compsRunning.containsKey(keyOf(map));

  static bool get loadingAbyssal => _abyssalRunning != null;

  /// 深海棲艦のデータ (端末に保存したものを読み、古ければ取り直す)
  static Future<void> loadAbyssal({bool force = false}) {
    final running = _abyssalRunning ??= _loadAbyssal(force).whenComplete(() {
      _abyssalRunning = null;
      revision.value++;
    });
    revision.value++;
    return running;
  }

  static Future<void> _loadAbyssal(bool force) async {
    DateTime? cachedAt;
    try {
      if (abyssal == null && _abyssalFile.existsSync()) {
        cachedAt = _abyssalFile.lastModifiedSync();
        abyssal = parseAbyssalTable(await _abyssalFile.readAsString());
        abyssalAt = cachedAt;
      }
    } catch (e) {
      abyssalError = '$e';
    }
    final last = abyssalAt ?? cachedAt;
    if (!force && abyssal != null && last != null && DateTime.now().difference(last) < _maxAge) return;
    try {
      final text = await _get(Uri.parse(kAirAbyssalUrl));
      final table = parseAbyssalTable(text);
      if (table.ships.isEmpty) throw const FormatException('empty data');
      abyssal = table;
      abyssalAt = DateTime.now();
      abyssalError = null;
      await _save(_abyssalFile, text);
    } catch (e) {
      abyssalError = '$e';
    }
  }

  /// [map] の敵編成 (端末に保存したものを読み、古ければ KCNav から取り直す)
  static Future<void> loadComps(CompassMap map, {bool force = false}) {
    final key = keyOf(map);
    final running = _compsRunning[key] ??= _loadComps(map, key, force).whenComplete(() {
      _compsRunning.remove(key);
      revision.value++;
    });
    revision.value++;
    return running;
  }

  static Future<void> _loadComps(CompassMap map, String key, bool force) async {
    try {
      if (!comps.containsKey(key)) {
        final file = _compsFile(key);
        if (file.existsSync()) {
          comps[key] = parseEnemyComps(await file.readAsString());
          compsAt[key] = file.lastModifiedSync();
        }
      }
    } catch (e) {
      compsError[key] = '$e';
    }
    final last = compsAt[key];
    if (!force && comps.containsKey(key) && last != null && DateTime.now().difference(last) < _maxAge) return;
    try {
      final file = _compsFile(key);
      final gauge = airGaugeOf(map);
      final now = DateTime.now();
      var text = await _get(kcnavEnemyCompsUrl(map, since: now.subtract(_recent), gauge: gauge));
      var parsed = parseEnemyComps(text);
      if (parsed.isEmpty) {
        text = await _get(kcnavEnemyCompsUrl(map, since: now.subtract(_older), gauge: gauge));
        parsed = parseEnemyComps(text);
      }
      comps[key] = parsed;
      compsAt[key] = now;
      compsError.remove(key);
      await _save(file, text);
    } catch (e) {
      compsError[key] = '$e';
    }
  }

  static Future<String> _get(Uri url) async {
    final response = await http.get(url).timeout(_timeout);
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
    return utf8.decode(response.bodyBytes);
  }

  static Future<void> _save(File file, String text) async {
    final dir = file.parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await file.writeAsString(text);
  }
}
