import 'dart:convert';
import 'dart:io';

import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/quest_eo_tracker.dart';
import 'package:http/http.dart' as http;

/// ElectronicObserver EN の任務トラッカーをネットから取得して端末に保存する (1日たったら取り直す)。
/// 読み込めたら [kEoQuestDefinitions] に入り、組み込みの定義より優先して使われる
class EoQuestTrackerLoader {
  EoQuestTrackerLoader._();

  static const _maxAge = Duration(hours: 24);
  static const _timeout = Duration(seconds: 15);

  /// 取得に失敗したあと、もう一度試すまでの間隔
  static const _retryInterval = Duration(minutes: 5);

  /// 使っているデータを取得した時刻 (まだなければ null)
  static DateTime? updatedAt;

  /// 読み込めた任務の数
  static int count = 0;

  /// 最後に取得・読み込みに失敗した理由 (成功したら null)
  static String? lastError;

  static DateTime? _lastAttempt;

  /// 新しいデータを使い始めたときに呼ぶ (任務の進捗を定義に合わせ直す)
  static void Function()? onUpdated;

  static Future<void>? _running;

  static File get _trackersFile => File(pathUtil.localEoQuestTrackersPath);

  static File get _metadataFile => File(pathUtil.localEoQuestsMetadataPath);

  /// 端末に保存したデータを読み、古ければ ([force] なら必ず) ネットから取り直す
  static Future<void> load({bool force = false}) {
    return _running ??= _load(force).whenComplete(() => _running = null);
  }

  /// まだ読み込めていなければ取り直す (失敗していたら [_retryInterval] おき)。任務一覧を受け取ったときに呼ぶ
  static void retryIfMissing() {
    if (updatedAt != null || _running != null) return;
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < _retryInterval) return;
    load().catchError((_) {});
  }

  static Future<void> _load(bool force) async {
    _lastAttempt = DateTime.now();
    DateTime? cachedAt;
    try {
      if (updatedAt == null && _trackersFile.existsSync()) {
        cachedAt = _trackersFile.lastModifiedSync();
        final metadata = _metadataFile.existsSync() ? await _metadataFile.readAsString() : null;
        _apply(await _trackersFile.readAsString(), metadata, cachedAt);
      }
    } catch (e) {
      lastError = '$e';
    }
    final last = updatedAt ?? cachedAt;
    if (!force && last != null && DateTime.now().difference(last) < _maxAge) return;
    try {
      await _download();
      lastError = null;
    } catch (e) {
      lastError = '$e';
      if (force) rethrow;
    }
  }

  static Future<void> _download() async {
    final trackers = await http.get(Uri.parse(kEoQuestTrackersUrl)).timeout(_timeout);
    if (trackers.statusCode != 200) throw HttpException('QuestTrackers ${trackers.statusCode}');
    final trackersText = utf8.decode(trackers.bodyBytes);
    String? metadataText;
    try {
      final metadata = await http.get(Uri.parse(kEoQuestsMetadataUrl)).timeout(_timeout);
      if (metadata.statusCode == 200) metadataText = utf8.decode(metadata.bodyBytes);
    } catch (_) {}

    // 壊れたデータは保存しない
    if (!_apply(trackersText, metadataText, DateTime.now())) throw const FormatException('empty quest trackers');
    final dir = _trackersFile.parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await _trackersFile.writeAsString(trackersText);
    if (metadataText != null) await _metadataFile.writeAsString(metadataText);
  }

  /// 読めたら使い始めて true
  static bool _apply(String trackersJson, String? metadataJson, DateTime time) {
    final definitions = parseEoQuestTrackers(trackersJson);
    if (definitions.isEmpty) return false;
    Map<int, int> resetTypes = {};
    try {
      if (metadataJson != null) resetTypes = parseEoQuestsMetadata(metadataJson);
    } catch (_) {}
    applyEoQuestTrackers(definitions, resetTypes);
    updatedAt = time;
    count = definitions.length;
    lastError = null;
    try {
      onUpdated?.call();
    } catch (_) {}
    return true;
  }

  /// 状態の表示 (任務トラッカー 174件 10/18取得 / 未取得 など)
  static String statusText({required String Function(String ja, String en) text}) {
    final time = updatedAt;
    if (time != null) {
      final t = time.toLocal();
      return text('任務トラッカー $count件 (${t.month}/${t.day} 取得)', 'Quest trackers: $count (${t.month}/${t.day})');
    }
    if (_running != null) return text('任務トラッカーを取得中', 'Loading quest trackers');
    final error = lastError;
    return error == null
        ? text('任務トラッカー: 未取得', 'Quest trackers: not loaded')
        : text('任務トラッカーを取得できませんでした ($error)', 'Could not load quest trackers ($error)');
  }
}
