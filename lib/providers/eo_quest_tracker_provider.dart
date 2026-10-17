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

  /// 使っているデータを取得した時刻 (まだなければ null)
  static DateTime? updatedAt;

  /// 読み込めた任務の数
  static int count = 0;

  /// 新しいデータを使い始めたときに呼ぶ (任務の進捗を定義に合わせ直す)
  static void Function()? onUpdated;

  static Future<void>? _running;

  static File get _trackersFile => File(pathUtil.localEoQuestTrackersPath);

  static File get _metadataFile => File(pathUtil.localEoQuestsMetadataPath);

  /// 端末に保存したデータを読み、古ければ ([force] なら必ず) ネットから取り直す
  static Future<void> load({bool force = false}) {
    return _running ??= _load(force).whenComplete(() => _running = null);
  }

  static Future<void> _load(bool force) async {
    DateTime? cachedAt;
    try {
      if (updatedAt == null && _trackersFile.existsSync()) {
        cachedAt = _trackersFile.lastModifiedSync();
        final metadata = _metadataFile.existsSync() ? await _metadataFile.readAsString() : null;
        _apply(await _trackersFile.readAsString(), metadata, cachedAt);
      }
    } catch (_) {}
    final last = updatedAt ?? cachedAt;
    if (!force && last != null && DateTime.now().difference(last) < _maxAge) return;
    try {
      await _download();
    } catch (_) {
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
    onUpdated?.call();
    return true;
  }
}
