import 'dart:convert';

import 'repair_timer.dart';

// 任務ツリー (前提任務) と、まだ出現していない任務の推定。
// 前提任務: kcwiki の任務データ https://github.com/kcwikizh/kcQuests (quests-scn.json の pre)
// 任務名・説明: kcanotify-gamedata (MIT License, Copyright (c) 2021 antest1) files/quests-jp.json

const kKcQuestsUrl = 'https://kcwikizh.github.io/kcQuests/quests-scn.json';
const kKcanotifyQuestsUrl =
    'https://raw.githubusercontent.com/antest1/kcanotify-gamedata/master/files/quests-jp.json';

/// 種類 (任務コードの英字)
enum QuestTreeCategory {
  formation('A', '編成', 'Composition'),
  sortie('B', '出撃', 'Sortie'),
  exercise('C', '演習', 'Exercise'),
  expedition('D', '遠征', 'Expedition'),
  supply('E', '補給・入渠', 'Supply/Docking'),
  factory('F', '工廠', 'Factory'),
  remodel('G', '改装', 'Modernization');

  const QuestTreeCategory(this.letter, this.ja, this.en);

  final String letter;
  final String ja;
  final String en;

  String get label => repairText(ja, en);
}

/// 周期 (任務コードの小文字。先頭に年月があるものは期間限定)
enum QuestTreePeriod {
  once('単発', 'One-time'),
  daily('デイリー', 'Daily'),
  weekly('ウィークリー', 'Weekly'),
  monthly('マンスリー', 'Monthly'),
  quarterly('クォータリー', 'Quarterly'),
  yearly('イヤリー', 'Yearly'),
  limited('期間限定', 'Limited');

  const QuestTreePeriod(this.ja, this.en);

  final String ja;
  final String en;

  String get label => repairText(ja, en);
}

final RegExp _codePattern = RegExp(r'^L?(\d{4})?\s*[WS]?([A-G])([a-z]?)\d+$');

/// 任務コード (Bm1, By16, 2609 Cw1, WA01 など) から種類と周期を判別する
(QuestTreeCategory?, QuestTreePeriod) classifyQuestCode(String code) {
  final match = _codePattern.firstMatch(code.trim());
  if (match == null) return (null, QuestTreePeriod.once);
  final category = QuestTreeCategory.values.where((c) => c.letter == match.group(2)).firstOrNull;
  if (match.group(1) != null) return (category, QuestTreePeriod.limited);
  final period = switch (match.group(3)) {
    'd' => QuestTreePeriod.daily,
    'w' => QuestTreePeriod.weekly,
    'm' => QuestTreePeriod.monthly,
    'q' => QuestTreePeriod.quarterly,
    'y' || 's' => QuestTreePeriod.yearly, // s: 季節の大演習
    _ => QuestTreePeriod.once,
  };
  return (category, period);
}

/// 任務1件
class QuestTreeEntry {
  final int id;
  final String code;
  final String name;
  final String detail;

  /// 出現時期や注意 (kcanotify の memo)
  final String memo;

  /// 前提任務 (任務ID)
  final List<int> prerequisites;

  /// 任務IDが分からなかった前提任務のコード
  final List<String> unknownPrerequisites;

  /// 前提任務のデータがあるか (kcwiki にない任務は false)
  final bool hasPrerequisiteData;

  final QuestTreeCategory? category;
  final QuestTreePeriod period;

  const QuestTreeEntry({
    required this.id,
    required this.code,
    required this.name,
    this.detail = '',
    this.memo = '',
    this.prerequisites = const [],
    this.unknownPrerequisites = const [],
    this.hasPrerequisiteData = true,
    this.category,
    this.period = QuestTreePeriod.once,
  });
}

/// 任務ツリーのデータ
class QuestTreeData {
  final Map<int, QuestTreeEntry> quests;

  /// 任務ID -> その任務を前提にしている任務
  final Map<int, List<int>> successors;

  /// データを取得した時刻
  final DateTime? updatedAt;

  QuestTreeData(this.quests, {this.updatedAt})
      : successors = {
          for (final q in quests.values)
            for (final pre in q.prerequisites) pre: <int>[],
        } {
    for (final q in quests.values) {
      for (final pre in q.prerequisites) {
        successors[pre]!.add(q.id);
      }
    }
    for (final list in successors.values) {
      list.sort();
    }
  }

  /// kcwiki (quests-scn.json) と kcanotify (quests-jp.json) をまとめる
  factory QuestTreeData.parse(String kcQuestsJson, String? kcanotifyJson, {DateTime? updatedAt}) {
    final kcQuests = (jsonDecode(kcQuestsJson) as Map).cast<String, dynamic>();
    final kcanotify = kcanotifyJson == null
        ? const <String, dynamic>{}
        : (jsonDecode(kcanotifyJson) as Map).cast<String, dynamic>();

    String text(dynamic value) => value is String ? value.trim() : '';

    final codeToId = <String, int>{};
    void addCodes(Map<String, dynamic> source) {
      for (final e in source.entries) {
        final id = int.tryParse(e.key);
        final value = e.value;
        if (id == null || value is! Map) continue;
        final code = text(value['code']);
        if (code.isEmpty) continue;
        codeToId.putIfAbsent(code, () => id);
        // kcanotify の期間限定任務は先頭に L が付く (L2409B1 = kcwiki の 2409B1)
        if (code.startsWith('L')) codeToId.putIfAbsent(code.substring(1), () => id);
      }
    }

    addCodes(kcQuests);
    addCodes(kcanotify);

    final ids = <int>{
      for (final key in [...kcQuests.keys, ...kcanotify.keys])
        if (int.tryParse(key) case final id?) id,
    };
    final quests = <int, QuestTreeEntry>{};
    for (final id in ids) {
      final wiki = kcQuests['$id'];
      final jp = kcanotify['$id'];
      final wikiMap = wiki is Map ? wiki : null;
      final jpMap = jp is Map ? jp : null;
      final code = text(wikiMap?['code']).isNotEmpty ? text(wikiMap?['code']) : text(jpMap?['code']);
      final preCodes = [
        for (final c in (wikiMap?['pre'] is List ? wikiMap!['pre'] as List : const []))
          if (c is String && c.trim().isNotEmpty) c.trim()
      ];
      final (category, period) = classifyQuestCode(code);
      quests[id] = QuestTreeEntry(
        id: id,
        code: code,
        name: text(jpMap?['name']).isNotEmpty ? text(jpMap?['name']) : text(wikiMap?['name']),
        detail: text(jpMap?['desc']).isNotEmpty ? text(jpMap?['desc']) : text(wikiMap?['desc']),
        memo: text(jpMap?['memo']),
        prerequisites: [
          for (final c in preCodes)
            if (codeToId[c] != null && codeToId[c] != id) codeToId[c]!
        ],
        unknownPrerequisites: [
          for (final c in preCodes)
            if (codeToId[c] == null) c
        ],
        hasPrerequisiteData: wikiMap != null,
        category: category,
        period: period,
      );
    }
    return QuestTreeData(quests, updatedAt: updatedAt);
  }

  /// 前提任務をさかのぼったすべての任務 (自分は含まない)
  Set<int> ancestorsOf(int id) {
    final result = <int>{};
    final stack = [...?quests[id]?.prerequisites];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (current == id || !result.add(current)) continue;
      stack.addAll(quests[current]?.prerequisites ?? const []);
    }
    return result;
  }
}

enum QuestTreeStatus {
  /// クリア済み (推定)
  cleared,

  /// 出現したことがある (受注できる・遂行中・達成待ちなど)
  appeared,

  /// まだ出現していない
  notAppeared,
}

/// どの任務が出現済み・クリア済みかの推定
class QuestTreeProgress {
  final Set<int> cleared;
  final Set<int> appeared;

  /// 「全て」タブの一覧から推定したクリア済み (cleared に含まれる)
  final Set<int> estimated;

  /// いま受けられる任務 (「全て」タブ)。まだ見ていなければ null
  final Set<int>? available;

  /// 手動の指定 (true: クリア済みにした / false: 未クリアに戻した)
  final Map<int, bool> manual;

  const QuestTreeProgress({
    required this.cleared,
    required this.appeared,
    this.estimated = const {},
    this.available,
    this.manual = const {},
  });

  /// [seen]: 任務一覧で見たことがある任務、[completed]: 達成 (api_state 3) を見た任務、
  /// [available]: 「全て」タブで見えた、いま受けられる任務。
  /// 1. 出現した任務の前提任務は、さかのぼってすべてクリア済みとみなす
  /// 2. [available] があれば、そこにない単発任務のうち前提任務がすべてクリア済みのものもクリア済みとみなす
  ///    (単発任務は前提を満たすと出現し、クリアするまで一覧に残るため)
  factory QuestTreeProgress.infer(
    QuestTreeData data, {
    required Set<int> seen,
    Set<int> completed = const {},
    Map<int, bool> manual = const {},
    Set<int>? available,
  }) {
    final forcedCleared = {
      for (final e in manual.entries)
        if (e.value) e.key
    };
    final forcedNotCleared = {
      for (final e in manual.entries)
        if (!e.value) e.key
    };
    final cleared = <int>{...completed, ...forcedCleared};
    for (final id in {...seen, ...completed, ...forcedCleared, ...?available}) {
      cleared.addAll(data.ancestorsOf(id));
    }
    cleared.removeAll(forcedNotCleared);

    final estimated = <int>{};
    if (available != null) {
      var changed = true;
      while (changed) {
        changed = false;
        for (final q in data.quests.values) {
          if (q.period != QuestTreePeriod.once || !q.hasPrerequisiteData || q.unknownPrerequisites.isNotEmpty) {
            continue;
          }
          if (cleared.contains(q.id) || available.contains(q.id) || forcedNotCleared.contains(q.id)) continue;
          if (q.prerequisites.every(cleared.contains)) {
            cleared.add(q.id);
            estimated.add(q.id);
            changed = true;
          }
        }
      }
    }
    return QuestTreeProgress(
      cleared: cleared,
      appeared: {...seen, ...?available}.difference(cleared),
      estimated: estimated,
      available: available,
      manual: manual,
    );
  }

  QuestTreeStatus statusOf(int id) {
    if (cleared.contains(id)) return QuestTreeStatus.cleared;
    if (appeared.contains(id)) return QuestTreeStatus.appeared;
    return QuestTreeStatus.notAppeared;
  }

  bool isNotAppeared(int id) => statusOf(id) == QuestTreeStatus.notAppeared;

  /// いま受けられる (「全て」タブにある)
  bool isAvailable(int id) => available?.contains(id) ?? false;

  /// まだクリアしていない前提任務 (さかのぼったもの全部)
  Set<int> remainingPrerequisites(QuestTreeData data, int id) =>
      data.ancestorsOf(id).where((a) => !cleared.contains(a)).toSet();
}

/// 前提任務の流れの1行
class QuestTreeNode {
  final int id;
  final int depth;
  final QuestTreeStatus status;

  /// 上にすでに出ている任務 (前提はそこで表示済み)
  final bool repeated;

  const QuestTreeNode({required this.id, required this.depth, required this.status, this.repeated = false});
}

/// [id] の前提任務を木の形で並べる。クリア済みの任務より先はさかのぼらない
List<QuestTreeNode> prerequisiteTree(QuestTreeData data, QuestTreeProgress progress, int id) {
  final nodes = <QuestTreeNode>[];
  final expanded = <int>{id};
  void visit(int questId, int depth) {
    for (final pre in data.quests[questId]?.prerequisites ?? const <int>[]) {
      final status = progress.statusOf(pre);
      final repeated = expanded.contains(pre);
      nodes.add(QuestTreeNode(id: pre, depth: depth, status: status, repeated: repeated));
      if (repeated || status == QuestTreeStatus.cleared) continue;
      expanded.add(pre);
      visit(pre, depth + 1);
    }
  }

  visit(id, 0);
  return nodes;
}

/// 未出現の任務 (種類・周期で絞り込む)。周期が null のときは期間限定を除く
List<QuestTreeEntry> notAppearedQuests(
  QuestTreeData data,
  QuestTreeProgress progress, {
  QuestTreeCategory? category,
  QuestTreePeriod? period,
}) {
  final list = [
    for (final q in data.quests.values)
      if (progress.isNotAppeared(q.id) &&
          (category == null || q.category == category) &&
          (period == null ? q.period != QuestTreePeriod.limited : q.period == period))
        q
  ];
  list.sort((a, b) {
    final c = (a.category?.index ?? 99).compareTo(b.category?.index ?? 99);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return list;
}

/// ゲームの任務画面「全て」タブ (api_tab_id 0) で見えた任務 = いま受けられる任務の一覧。
/// 1回の応答で全件が来る (api_count == api_list の件数) が、ページ分けされた場合も集められるようにしておく
class QuestListSnapshot {
  /// 集めている途中の一覧
  int count = 0;
  final Set<int> ids = {};
  DateTime? updatedAt;

  /// 最後に全件そろった一覧
  Set<int>? completeIds;
  DateTime? completedAt;

  /// これより間が空いたら集め直す
  static const _sessionGap = Duration(minutes: 10);

  void onPage({required int count, required Iterable<int> ids, required DateTime now}) {
    final last = updatedAt;
    if (count != this.count || last == null || now.difference(last) > _sessionGap) {
      this.ids.clear();
      this.count = count;
    }
    this.ids.addAll(ids);
    updatedAt = now;
    if (this.ids.length >= this.count) {
      completeIds = {...this.ids};
      completedAt = now;
    }
  }

  /// 報酬を受け取った任務は一覧から消える
  void onCleared(int id) {
    if (ids.remove(id) && count > 0) count--;
    completeIds?.remove(id);
  }

  Map<String, dynamic> toJson() => {
        'count': count,
        'ids': ids.toList(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
        'completeIds': completeIds?.toList(),
        'completedAt': completedAt?.toUtc().toIso8601String(),
      };

  static QuestListSnapshot fromJson(dynamic json) {
    final snapshot = QuestListSnapshot();
    if (json is! Map) return snapshot;
    snapshot.count = json['count'] is int ? json['count'] as int : 0;
    snapshot.ids.addAll((json['ids'] as List? ?? const []).whereType<int>());
    snapshot.updatedAt = DateTime.tryParse('${json['updatedAt'] ?? ''}');
    final complete = json['completeIds'];
    if (complete is List) snapshot.completeIds = complete.whereType<int>().toSet();
    snapshot.completedAt = DateTime.tryParse('${json['completedAt'] ?? ''}');
    return snapshot;
  }
}
