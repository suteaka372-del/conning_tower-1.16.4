import 'dart:convert';
import 'dart:io';

import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/quest_tree.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// 任務ツリーのデータ (ネットから取得して端末に保存する。1日たったら取り直す)
final questTreeProvider =
    AsyncNotifierProvider<QuestTreeNotifier, QuestTreeData>(QuestTreeNotifier.new);

class QuestTreeNotifier extends AsyncNotifier<QuestTreeData> {
  static const _maxAge = Duration(hours: 24);
  static const _timeout = Duration(seconds: 15);

  File get _kcQuestsFile => File(pathUtil.localKcQuestsPath);

  File get _kcanotifyFile => File(pathUtil.localKcanotifyQuestsPath);

  @override
  Future<QuestTreeData> build() async {
    final cached = await _readCache();
    final updatedAt = cached?.updatedAt;
    if (cached != null && updatedAt != null && DateTime.now().difference(updatedAt) < _maxAge) {
      return cached;
    }
    try {
      return await _download();
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// ネットから取り直す。失敗したら今のデータのまま例外を投げる
  Future<void> refresh() async {
    final data = await _download();
    state = AsyncData(data);
  }

  Future<QuestTreeData?> _readCache() async {
    try {
      final file = _kcQuestsFile;
      if (!file.existsSync()) return null;
      final kcanotify = _kcanotifyFile.existsSync() ? await _kcanotifyFile.readAsString() : null;
      return QuestTreeData.parse(await file.readAsString(), kcanotify, updatedAt: file.lastModifiedSync());
    } catch (_) {
      return null;
    }
  }

  Future<QuestTreeData> _download() async {
    final kcQuests = await http.get(Uri.parse(kKcQuestsUrl)).timeout(_timeout);
    if (kcQuests.statusCode != 200) throw HttpException('kcQuests ${kcQuests.statusCode}');
    final kcQuestsText = utf8.decode(kcQuests.bodyBytes);

    String? kcanotifyText;
    try {
      final kcanotify = await http.get(Uri.parse(kKcanotifyQuestsUrl)).timeout(_timeout);
      if (kcanotify.statusCode == 200) kcanotifyText = utf8.decode(kcanotify.bodyBytes);
    } catch (_) {}
    if (kcanotifyText == null && _kcanotifyFile.existsSync()) {
      kcanotifyText = await _kcanotifyFile.readAsString();
    }

    // 壊れたデータを保存しないよう、先に読めるか確かめる
    final data = QuestTreeData.parse(kcQuestsText, kcanotifyText, updatedAt: DateTime.now());
    if (data.quests.isEmpty) throw const FormatException('empty quest data');

    final dir = _kcQuestsFile.parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await _kcQuestsFile.writeAsString(kcQuestsText);
    if (kcanotifyText != null) await _kcanotifyFile.writeAsString(kcanotifyText);
    return data;
  }
}

/// 任務一覧で見たことがある任務 (この端末の記録 + 今の任務一覧)
class QuestTreeSeen {
  final Set<int> seen;

  /// 達成 (api_state 3) を見た任務
  final Set<int> completed;

  /// 最後に「全て」タブで見た、いま受けられる任務 (まだ見ていなければ null)
  final Set<int>? available;
  final DateTime? availableAt;

  const QuestTreeSeen({this.seen = const {}, this.completed = const {}, this.available, this.availableAt});
}

final questTreeSeenProvider = Provider<QuestTreeSeen>((ref) {
  // 任務一覧を受け取るたびに読み直す
  final questAssistant = ref.watch(kancolleDataProvider.select((data) => data.questAssistant));
  final admiral = ref.watch(kancolleDataProvider.select((data) => data.seaForceBase.admiral.name));
  final tracker = ref.read(kancolleDataProvider).questProgress;

  final seen = <int>{};
  final completed = <int>{};
  try {
    for (final e in objectbox.questLogStates(admiral).entries) {
      seen.add(e.key);
      if (e.value == 3) completed.add(e.key);
    }
  } catch (_) {}
  for (final e in tracker.questStates.entries) {
    seen.add(e.key);
    if (e.value == 3) completed.add(e.key);
  }
  for (final quest in questAssistant?.ready ?? const []) {
    seen.add(quest.id);
    if (quest.state == 3) completed.add(quest.id);
  }
  return QuestTreeSeen(
    seen: seen,
    completed: completed,
    available: tracker.allTab.completeIds,
    availableAt: tracker.allTab.completedAt,
  );
});

/// 手動の指定 (true: クリア済みにした / false: 未クリアに戻した)。提督ごとに保存
final questTreeManualProvider =
    NotifierProvider<QuestTreeManualNotifier, Map<int, bool>>(QuestTreeManualNotifier.new);

class QuestTreeManualNotifier extends Notifier<Map<int, bool>> {
  String get _key {
    final admiral = ref.read(kancolleDataProvider).seaForceBase.admiral.name;
    return 'KC_QUEST_TREE_MANUAL_$admiral';
  }

  @override
  Map<int, bool> build() {
    ref.watch(kancolleDataProvider.select((data) => data.seaForceBase.admiral.name));
    try {
      final saved = localStorage.getString(_key);
      if (saved == null) return {};
      final json = jsonDecode(saved) as Map<String, dynamic>;
      return {
        for (final e in json.entries)
          if (int.tryParse(e.key) case final id? when e.value is bool) id: e.value as bool
      };
    } catch (_) {
      return {};
    }
  }

  /// [cleared] が null なら自動の判定に戻す
  void set(int id, bool? cleared) {
    final next = {...state};
    if (cleared == null) {
      next.remove(id);
    } else {
      next[id] = cleared;
    }
    state = next;
    try {
      localStorage.setString(_key, jsonEncode({for (final e in next.entries) '${e.key}': e.value}));
    } catch (_) {}
  }
}

/// 出現済み・クリア済みの推定 (データがまだなければ null)
final questTreeProgressProvider = Provider<QuestTreeProgress?>((ref) {
  final data = ref.watch(questTreeProvider).valueOrNull;
  if (data == null) return null;
  final seen = ref.watch(questTreeSeenProvider);
  final manual = ref.watch(questTreeManualProvider);
  return QuestTreeProgress.infer(
    data,
    seen: seen.seen,
    completed: seen.completed,
    manual: manual,
    available: seen.available,
  );
});
