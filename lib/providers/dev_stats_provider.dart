import 'dart:convert';
import 'dart:io';

import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/dev_stats.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 装備開発の統計をネットから取得して端末に保存する (1日たったら取り直す)。
/// 「開発」タブを開いたときに読み込む
class DevStatsLoader {
  DevStatsLoader._();

  static const _maxAge = Duration(hours: 24);
  static const _timeout = Duration(seconds: 30);

  /// 使っている統計 (まだなければ null)
  static DevStats? stats;

  /// 使っている統計を取得した時刻
  static DateTime? updatedAt;

  /// 最後に取得・読み込みに失敗した理由 (成功したら null)
  static String? lastError;

  /// 読み込みの状態が変わったら増える (画面の作り直し用)
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<void>? _running;

  static File get _file => File(pathUtil.localDevStatsPath);

  static bool get loading => _running != null;

  /// 端末に保存したデータを読み、古ければ ([force] なら必ず) ネットから取り直す
  static Future<void> load({bool force = false}) {
    final running = _running ??= _load(force).whenComplete(() {
      _running = null;
      revision.value++;
    });
    revision.value++;
    return running;
  }

  static Future<void> _load(bool force) async {
    DateTime? cachedAt;
    try {
      if (stats == null && _file.existsSync()) {
        cachedAt = _file.lastModifiedSync();
        _apply(await compute(parseDevStats, await _file.readAsString()), cachedAt);
      }
    } catch (e) {
      lastError = '$e';
    }
    final last = updatedAt ?? cachedAt;
    if (!force && last != null && DateTime.now().difference(last) < _maxAge) return;
    try {
      final response = await http.get(Uri.parse(kDevStatsUrl)).timeout(_timeout);
      if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
      final text = utf8.decode(response.bodyBytes);
      // 壊れたデータは保存しない
      if (!_apply(await compute(parseDevStats, text), DateTime.now())) throw const FormatException('empty data');
      final dir = _file.parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await _file.writeAsString(text);
    } catch (e) {
      lastError = '$e';
      if (force) rethrow;
    }
  }

  static bool _apply(DevStats parsed, DateTime time) {
    if (parsed.rows.isEmpty) return false;
    stats = parsed;
    updatedAt = time;
    lastError = null;
    return true;
  }

  /// 状態の表示 (poi の統計 2026-08〜2026-10・72万回 (10/24 取得) など)
  static String statusText({required String Function(String ja, String en) text}) {
    final data = stats;
    final time = updatedAt;
    if (data != null && time != null) {
      final t = time.toLocal();
      final months = data.months.isEmpty
          ? ''
          : data.months.length == 1
              ? data.months.first
              : '${data.months.first}〜${data.months.last}';
      final tries = data.totalTries >= 10000 ? '${(data.totalTries / 10000).toStringAsFixed(0)}万' : '${data.totalTries}';
      return text('poi の統計 $months・開発$tries回 (${t.month}/${t.day} 取得)',
          'poi stats $months, ${data.totalTries} developments (${t.month}/${t.day})');
    }
    if (_running != null) return text('開発の統計を取得中', 'Loading development stats');
    final error = lastError;
    return error == null
        ? text('開発の統計: 未取得', 'Development stats: not loaded')
        : text('開発の統計を取得できませんでした ($error)', 'Could not load development stats ($error)');
  }
}
