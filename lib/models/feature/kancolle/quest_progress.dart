import 'dart:convert';
import 'dart:math';
import 'dart:math' as math;

import 'repair_timer.dart';

// Quest progress tracking (x/y).
// Ported from ElectronicObserver (MIT License, Copyright (c) 2014 Andante)
// https://github.com/dais-k/ElectronicObserver
// Data/Quest/QuestProgressManager.cs, ProgressData.cs, Progress*.cs, Data/QuestManager.cs

enum QuestCounterKind {
  battle,
  slaughter,
  sortie,
  practice,
  expedition,
  docking,
  supply,
  development,
  construction,
  destruction,
  discard,
  improvement,
  modernization,
}

/// 勝利ランク (EO Constants.GetWinRank)
int winRankValue(String? rank) => switch ((rank ?? '').toUpperCase()) {
      'E' => 1,
      'D' => 2,
      'C' => 3,
      'B' => 4,
      'A' => 5,
      'S' => 6,
      'SS' => 7,
      _ => 0,
    };

String _rankLabel(int rank) => switch (rank) {
      1 => 'E',
      2 => 'D',
      3 => 'C',
      4 => 'B',
      5 => 'A',
      6 => 'S',
      7 => 'SS',
      _ => '',
    };

/// 装備の廃棄判定に使う情報
class DiscardedEquipment {
  final int itemId;
  final int category; // api_type[2]
  final int icon; // api_type[3]

  const DiscardedEquipment({required this.itemId, required this.category, required this.icon});
}

/// 任務の条件1つ分のカウンタ
class QuestCounter {
  final QuestCounterKind kind;
  final int max;

  /// battle / practice: 条件を満たす最低ランク
  final int minRank;

  /// battle: 対象海域 (エリア*10+番号)、expedition: 遠征ID。null なら全て
  final Set<int>? areas;
  final bool bossOnly;

  /// slaughter: 艦種、discard: 装備分類
  final Set<int>? targets;

  /// discard: true=個数, false=回数
  final bool countsAmount;

  /// discard: -1=装備ID, 2=カテゴリ(api_type[2]), 3=アイコン(api_type[3])
  final int categoryIndex;

  /// 表示用の短い説明 (複数条件の任務で使う)
  final String label;

  int progress = 0;

  QuestCounter(
    this.kind,
    this.max, {
    this.minRank = 0,
    this.areas,
    this.bossOnly = false,
    this.targets,
    this.countsAmount = false,
    this.categoryIndex = 2,
    this.label = '',
  });

  bool get isCleared => progress >= max;

  void add([int amount = 1]) => progress = min(progress + amount, max);

  bool matchesBattle(int rank, int areaId, bool isBoss) {
    if (areas != null && !areas!.contains(areaId)) return false;
    if (rank < minRank) return false;
    if (bossOnly && !isBoss) return false;
    return true;
  }

  int discardAmount(List<DiscardedEquipment> equipments) {
    if (!countsAmount) return 1;
    if (targets == null) return equipments.length;
    return equipments.where((eq) {
      final value = switch (categoryIndex) {
        -1 => eq.itemId,
        3 => eq.icon,
        _ => eq.category,
      };
      return targets!.contains(value);
    }).length;
  }
}

typedef QuestCounterFactory = List<QuestCounter> Function();

class QuestDefinition {
  final int id;
  final QuestCounterFactory counters;

  /// 共有カウンタのずれ (EO SharedCounterShift)
  final int shift;

  /// あ号作戦のように、条件ごとに 25% ずつ評価する
  final bool weightedEqually;

  const QuestDefinition(this.id, this.counters, {this.shift = 0, this.weightedEqually = false});
}

// ---- 定義用ヘルパー ----
QuestCounter _battle(int max, String rank, {List<int>? areas, bool boss = false, String label = ''}) =>
    QuestCounter(QuestCounterKind.battle, max,
        minRank: winRankValue(rank), areas: areas?.toSet(), bossOnly: boss, label: label);

QuestCounter _slaughter(int max, List<int> shipTypes) =>
    QuestCounter(QuestCounterKind.slaughter, max, targets: shipTypes.toSet());

QuestCounter _practice(int max, {String rank = ''}) =>
    QuestCounter(QuestCounterKind.practice, max, minRank: winRankValue(rank));

QuestCounter _expedition(int max, [List<int>? missions, String label = '']) =>
    QuestCounter(QuestCounterKind.expedition, max, areas: missions?.toSet(), label: label);

QuestCounter _discard(int max, {bool amount = true, List<int>? categories, int index = 2, String label = ''}) =>
    QuestCounter(QuestCounterKind.discard, max,
        countsAmount: amount, targets: categories?.toSet(), categoryIndex: index, label: label);

QuestCounter _simple(QuestCounterKind kind, int max) => QuestCounter(kind, max);

const _carrier = [7, 11]; // 軽空母, 正規空母
const _transport = [15]; // 補給艦
const _submarine = [13]; // 潜水艦

/// 第1段階で対応する任務 (デイリー・ウィークリーと、よく使うもの)
final Map<int, QuestDefinition> kQuestDefinitions = {
  for (final def in <QuestDefinition>[
    // ---- 出撃 ----
    QuestDefinition(201, () => [_battle(1, 'B')]), // 敵艦隊を撃破せよ！
    QuestDefinition(216, () => [_battle(1, 'E')]), // 敵艦隊主力を撃滅せよ！
    QuestDefinition(210, () => [_battle(10, 'E')]), // 敵艦隊を10回邀撃せよ！
    QuestDefinition(211, () => [_slaughter(3, _carrier)]), // 敵空母を3隻撃沈せよ！
    QuestDefinition(212, () => [_slaughter(5, _transport)]), // 敵輸送船団を叩け！
    QuestDefinition(213, () => [_slaughter(20, _transport)]), // 海上通商破壊作戦
    QuestDefinition(
        214,
        () => [
              QuestCounter(QuestCounterKind.sortie, 36, label: '出撃'),
              _battle(6, 'S', label: 'S勝利'),
              _battle(24, 'E', boss: true, label: 'ボス'),
              _battle(12, 'B', boss: true, label: 'ボス勝利'),
            ],
        weightedEqually: true), // あ号作戦
    QuestDefinition(218, () => [_slaughter(3, _transport)]), // 敵補給艦を3隻撃沈せよ！
    QuestDefinition(220, () => [_slaughter(20, _carrier)]), // い号作戦
    QuestDefinition(221, () => [_slaughter(50, _transport)]), // ろ号作戦
    QuestDefinition(226, () => [_battle(5, 'B', areas: [21, 22, 23, 24, 25], boss: true)]), // 南西諸島海域の制海権を握れ！
    QuestDefinition(228, () => [_slaughter(15, _submarine)]), // 海上護衛戦
    QuestDefinition(229, () => [_battle(12, 'B', areas: [41, 42, 43, 44, 45], boss: true)]), // 敵東方艦隊を撃滅せよ！
    QuestDefinition(230, () => [_slaughter(6, _submarine)]), // 敵潜水艦を制圧せよ！
    QuestDefinition(241, () => [_battle(5, 'B', areas: [33, 34, 35], boss: true)]), // 敵北方艦隊主力を撃滅せよ！
    QuestDefinition(242, () => [_battle(1, 'B', areas: [44], boss: true)]), // 敵東方中枢艦隊を撃破せよ！
    QuestDefinition(243, () => [_battle(2, 'S', areas: [52], boss: true)]), // 南方海域珊瑚諸島沖の制空権を握れ！
    QuestDefinition(256, () => [_battle(3, 'S', areas: [61], boss: true)]), // 「潜水艦隊」出撃せよ！
    QuestDefinition(261, () => [_battle(3, 'A', areas: [15], boss: true)]), // 海上輸送路の安全確保に努めよ！
    QuestDefinition(265, () => [_battle(10, 'A', areas: [15], boss: true)]), // 海上護衛強化月間
    QuestDefinition(822, () => [_battle(2, 'S', areas: [24], boss: true)]), // 沖ノ島海域迎撃戦
    // ---- 演習 ----
    QuestDefinition(303, () => [_practice(3)]), // 「演習」で練度向上！
    QuestDefinition(304, () => [_practice(5, rank: 'B')]), // 「演習」で他提督を圧倒せよ！
    QuestDefinition(302, () => [_practice(20, rank: 'B')]), // 大規模演習
    QuestDefinition(311, () => [_practice(7, rank: 'B')]), // 精鋭艦隊演習
    QuestDefinition(313, () => [_practice(8, rank: 'B')]), // 秋季大演習
    QuestDefinition(314, () => [_practice(8, rank: 'B')]), // 冬季大演習
    QuestDefinition(315, () => [_practice(8, rank: 'B')]), // 春季大演習
    QuestDefinition(326, () => [_practice(8, rank: 'B')]), // 夏季大演習
    // ---- 遠征 ----
    QuestDefinition(402, () => [_expedition(3)]), // 「遠征」を3回成功させよう！
    QuestDefinition(403, () => [_expedition(10)]), // 「遠征」を10回成功させよう！
    QuestDefinition(404, () => [_expedition(30)]), // 大規模遠征作戦、発令！
    QuestDefinition(410, () => [_expedition(1, [37, 38])]), // 南方への輸送作戦を成功させよ！
    QuestDefinition(411, () => [_expedition(6, [37, 38])], shift: 1), // 南方への鼠輸送を継続実施せよ！
    QuestDefinition(424, () => [_expedition(4, [5])], shift: 1), // 輸送船団護衛を強化せよ！
    QuestDefinition(
        426,
        () => [
              _expedition(1, [3], '警備任務'),
              _expedition(1, [4], '対潜警戒任務'),
              _expedition(1, [5], '海上護衛任務'),
              _expedition(1, [10], '強行偵察任務'),
            ]), // 海上通商航路の警戒を厳とせよ！
    QuestDefinition(
        428,
        () => [
              _expedition(2, [4], '対潜警戒任務'),
              _expedition(2, [101], '海峡警備行動'),
              _expedition(2, [102], '長時間対潜警戒'),
            ]), // 近海に侵入する敵潜を制圧せよ！
    // ---- 補給・入渠 ----
    QuestDefinition(503, () => [_simple(QuestCounterKind.docking, 5)]), // 艦隊大整備！
    QuestDefinition(504, () => [_simple(QuestCounterKind.supply, 15)]), // 艦隊酒保祭り！
    // ---- 工廠 ----
    QuestDefinition(605, () => [_simple(QuestCounterKind.development, 1)]), // 新装備「開発」指令
    QuestDefinition(606, () => [_simple(QuestCounterKind.construction, 1)]), // 新造艦「建造」指令
    QuestDefinition(607, () => [_simple(QuestCounterKind.development, 3)], shift: 1), // 装備「開発」集中強化！
    QuestDefinition(608, () => [_simple(QuestCounterKind.construction, 3)], shift: 1), // 艦娘「建造」艦隊強化！
    QuestDefinition(609, () => [_simple(QuestCounterKind.destruction, 2)]), // 軍縮条約対応！
    QuestDefinition(613, () => [_discard(24, amount: false)]), // 資源の再利用
    QuestDefinition(619, () => [_simple(QuestCounterKind.improvement, 1)]), // 装備の改修強化
    QuestDefinition(638, () => [_discard(6, categories: [21])]), // 対空機銃量産
    QuestDefinition(663, () => [_discard(10, categories: [3])]), // 新型艤装の継続研究
    QuestDefinition(673, () => [_discard(4, categories: [1])], shift: 1), // 装備開発力の整備
    QuestDefinition(674, () => [_discard(3, categories: [21])], shift: 2), // 工廠環境の整備
    QuestDefinition(
        675,
        () => [
              _discard(6, categories: [6], label: '艦上戦闘機'),
              _discard(4, categories: [21], label: '対空機銃'),
            ]), // 運用装備の統合整備
    QuestDefinition(
        676,
        () => [
              _discard(3, categories: [2], label: '中口径主砲'),
              _discard(3, categories: [4], label: '副砲'),
              _discard(1, categories: [30], label: '簡易輸送部材'),
            ]), // 装備開発力の集中整備
    QuestDefinition(
        677,
        () => [
              _discard(4, categories: [3], label: '大口径主砲'),
              _discard(2, categories: [10], label: '水上偵察機'),
              _discard(3, categories: [5], label: '魚雷'),
            ]), // 継戦支援能力の整備
    QuestDefinition(
        680,
        () => [
              _discard(4, categories: [21], label: '対空機銃'),
              _discard(4, categories: [12, 13], label: '電探'),
            ]), // 対空兵装の整備拡充
    QuestDefinition(
        688,
        () => [
              _discard(3, categories: [6], label: '艦上戦闘機'),
              _discard(3, categories: [7], label: '艦上爆撃機'),
              _discard(3, categories: [8], label: '艦上攻撃機'),
              _discard(3, categories: [10], label: '水上偵察機'),
            ]), // 航空戦力の強化
    QuestDefinition(1166, () => [_simple(QuestCounterKind.improvement, 1)]), // 続：装備の改修強化1
    QuestDefinition(1167, () => [_simple(QuestCounterKind.improvement, 3)]), // 装備の改修集中強化3
    // ---- 改装 ----
    QuestDefinition(702, () => [_simple(QuestCounterKind.modernization, 2)]), // 艦の「近代化改修」を実施せよ！
    QuestDefinition(703, () => [_simple(QuestCounterKind.modernization, 15)]), // 「近代化改修」を進め、戦備を整えよ！
  ])
    def.id: def
};

/// 周期がデイリーでなくても1日で進捗がリセットされる任務 (EO QuestManager)
const Set<int> _kDailyResetQuestIds = {
  211, 212, 311, 313, 314, 318, 326, 330, 337, 339, 342, 345, 346, 348, 350, //
  353, 354, 355, 356, 357, 362, 363, 367, 368, 371, 372,
};

class QuestProgressEntry {
  final QuestDefinition definition;
  final List<QuestCounter> counters;

  /// EO の QuestType (label >= 100 なら label、それ以外は api_type)
  int questType;

  QuestProgressEntry(this.definition, this.questType) : counters = definition.counters();

  int get progress => counters.fold(0, (sum, c) => sum + c.progress);

  int get max => counters.fold(0, (sum, c) => sum + c.max);

  bool get isMulti => counters.length > 1;

  double get percentage {
    if (definition.weightedEqually) {
      return counters.fold(0.0, (sum, c) => sum + min(c.progress / c.max, 1.0)) / counters.length;
    }
    return max == 0 ? 0 : min(progress / max, 1.0);
  }

  String get text => '$progress/$max';

  /// 複数条件の任務の内訳 ("警備任務 0/1" など)
  List<String> get details => [for (final c in counters) '${counterLabel(c)} ${c.progress}/${c.max}'];

  static String counterLabel(QuestCounter c) {
    if (c.label.isNotEmpty) return c.label;
    return switch (c.kind) {
      QuestCounterKind.battle => c.minRank >= 5 ? '${_rankLabel(c.minRank)}勝利' : '勝利',
      QuestCounterKind.practice => '演習',
      QuestCounterKind.expedition => '遠征',
      _ => '',
    };
  }

  /// ゲームの進捗表示 (50%/80%) に合わせて補正 (EO ProgressData.CheckProgress)
  void applyProgressFlag(int? flag) {
    if (isMulti || counters.isEmpty) return;
    final counter = counters.first;
    final shift = definition.shift;
    final rate = switch (flag) {
      1 => 0.5,
      2 => 0.8,
      _ => null,
    };
    if (rate == null) return;
    final floor = ((counter.max + shift) * rate).ceil() - shift;
    counter.progress = math.min(math.max(counter.progress, floor), counter.max);
  }

  Map<String, dynamic> toJson() => {
        'type': questType,
        'progress': [for (final c in counters) c.progress],
      };
}

/// 1件分の任務の状態 (任務一覧 API から)
class QuestListItem {
  final int id;
  final int state; // 1=未受注, 2=遂行中, 3=達成
  final int type;
  final int label;
  final int progressFlag;

  const QuestListItem({
    required this.id,
    required this.state,
    required this.type,
    this.label = 0,
    this.progressFlag = 0,
  });
}

class QuestProgressTracker {
  final Map<int, QuestProgressEntry> entries = {};

  /// 任務ID -> 状態 (最後に見た任務一覧)
  final Map<int, int> questStates = {};

  DateTime? lastUpdate;

  int? _mapId;
  int? _eventId;

  QuestProgressEntry? progressOf(int questId) => entries[questId];

  // ---- 任務一覧 ----

  void onQuestList(Iterable<QuestListItem> quests, {DateTime? now}) {
    now ??= DateTime.now();
    final previous = lastUpdate;
    if (previous != null) _resetCrossedPeriods(previous, now);

    for (final quest in quests) {
      questStates[quest.id] = quest.state;
      if (quest.state == 3) {
        // 達成済み: 報酬受け取り待ち。表示は満タンにする
        final entry = entries[quest.id];
        if (entry != null) {
          for (final c in entry.counters) {
            c.progress = c.max;
          }
        }
        continue;
      }
      final definition = kQuestDefinitions[quest.id];
      if (definition == null) continue;
      final questType = quest.label >= 100 ? quest.label : quest.type;
      final entry = entries.putIfAbsent(quest.id, () => QuestProgressEntry(definition, questType));
      entry.questType = questType;
      entry.applyProgressFlag(quest.progressFlag);
    }
    lastUpdate = now;
  }

  void onQuestCleared(int questId) {
    entries.remove(questId);
    questStates.remove(questId);
  }

  void onQuestStop(int questId) {
    if (questStates.containsKey(questId)) questStates[questId] = 1;
  }

  void onQuestStart(int questId) {
    questStates[questId] = 2;
  }

  /// JST 5:00 を境に、日・週・月・四半期・年の切り替わりを越えた任務の進捗を消す (EO QuestManager)
  void _resetCrossedPeriods(DateTime previous, DateTime now) {
    final prev = _gameTime(previous);
    final cur = _gameTime(now);
    final crossedDay = _dayKey(prev) != _dayKey(cur);
    final crossedWeek = _weekKey(prev) != _weekKey(cur);
    final crossedMonth = prev.year != cur.year || prev.month != cur.month;
    final crossedQuarter = _quarterKey(prev) != _quarterKey(cur);

    bool shouldReset(int id, int type) {
      if (crossedDay && (type == 1 || _kDailyResetQuestIds.contains(id))) return true;
      if (crossedWeek && type == 2) return true;
      if (crossedMonth && type == 3) return true;
      if (crossedQuarter && type == 5) return true;
      if (type > 100 && type <= 112) {
        final month = type - 100;
        if (_yearKey(prev, month) != _yearKey(cur, month)) return true;
      }
      return false;
    }

    final removeIds = [
      for (final e in entries.entries)
        if (shouldReset(e.key, e.value.questType)) e.key
    ];
    for (final id in removeIds) {
      entries.remove(id);
      questStates.remove(id);
    }
  }

  /// JST 5:00 を日付の区切りとした「ゲーム内の日時」(UTC 基準で +9h -5h)
  static DateTime _gameTime(DateTime time) => time.toUtc().add(const Duration(hours: 4));

  static int _dayKey(DateTime t) => DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/ 86400000;

  static int _weekKey(DateTime t) => _dayKey(t) - (t.weekday - DateTime.monday);

  static int _quarterKey(DateTime t) => (t.year * 12 + t.month - 3) ~/ 3; // 3,6,9,12月1日に切り替わり

  static int _yearKey(DateTime t, int month) => t.month >= month ? t.year : t.year - 1;

  // ---- カウント ----

  Iterable<QuestCounter> _activeCounters(QuestCounterKind kind) sync* {
    for (final e in entries.entries) {
      if (questStates[e.key] != 2) continue;
      for (final c in e.value.counters) {
        if (c.kind == kind) yield c;
      }
    }
  }

  void onSortieStart() {
    for (final c in _activeCounters(QuestCounterKind.sortie)) {
      c.add();
    }
  }

  /// api_req_map/start, api_req_map/next
  void onMapPoint({required int mapId, required int eventId, required bool isEndPoint}) {
    _mapId = mapId;
    _eventId = eventId;
    // 船団護衛成功イベント
    if (eventId == 8) _countBattle(0, isEndPoint);
  }

  /// api_req_sortie/battleresult, api_req_combined_battle/battleresult
  void onBattleResult({required String rank, required List<int> sunkEnemyShipTypes}) {
    for (final shipType in sunkEnemyShipTypes) {
      for (final c in _activeCounters(QuestCounterKind.slaughter)) {
        if (c.targets?.contains(shipType) ?? false) c.add();
      }
    }
    _countBattle(winRankValue(rank), _eventId == 5);
  }

  void _countBattle(int rank, bool isBoss) {
    final areaId = _mapId ?? -1;
    for (final c in _activeCounters(QuestCounterKind.battle)) {
      if (c.matchesBattle(rank, areaId, isBoss)) c.add();
    }
  }

  void onPracticeResult(String rank) {
    final value = winRankValue(rank);
    for (final c in _activeCounters(QuestCounterKind.practice)) {
      if (value >= c.minRank) c.add();
    }
  }

  void onExpeditionResult({required int missionId, required bool success}) {
    if (!success) return;
    for (final c in _activeCounters(QuestCounterKind.expedition)) {
      if (c.areas == null || c.areas!.contains(missionId)) c.add();
    }
  }

  void _countSimple(QuestCounterKind kind, [int amount = 1]) {
    for (final c in _activeCounters(kind)) {
      c.add(amount);
    }
  }

  void onDocking() => _countSimple(QuestCounterKind.docking);

  void onSupply() => _countSimple(QuestCounterKind.supply);

  void onDevelopment(int trials) => _countSimple(QuestCounterKind.development, trials);

  void onConstruction() => _countSimple(QuestCounterKind.construction);

  void onDestruction(int amount) => _countSimple(QuestCounterKind.destruction, amount);

  void onImprovement() => _countSimple(QuestCounterKind.improvement);

  void onModernization(bool success) {
    if (success) _countSimple(QuestCounterKind.modernization);
  }

  void onDiscard(List<DiscardedEquipment> equipments) {
    for (final c in _activeCounters(QuestCounterKind.discard)) {
      final amount = c.discardAmount(equipments);
      if (amount > 0) c.add(amount);
    }
  }

  // ---- 保存 ----

  String encode() => jsonEncode({
        'lastUpdate': lastUpdate?.toUtc().toIso8601String(),
        'states': {for (final e in questStates.entries) '${e.key}': e.value},
        'entries': {for (final e in entries.entries) '${e.key}': e.value.toJson()},
      });

  static QuestProgressTracker decode(String? jsonString) {
    final tracker = QuestProgressTracker();
    if (jsonString == null) return tracker;
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      tracker.lastUpdate = DateTime.tryParse(json['lastUpdate'] as String? ?? '');
      final states = json['states'] as Map<String, dynamic>? ?? {};
      for (final e in states.entries) {
        final id = int.tryParse(e.key);
        if (id != null && e.value is int) tracker.questStates[id] = e.value as int;
      }
      final entries = json['entries'] as Map<String, dynamic>? ?? {};
      for (final e in entries.entries) {
        final id = int.tryParse(e.key);
        final definition = id == null ? null : kQuestDefinitions[id];
        final value = e.value;
        if (definition == null || value is! Map<String, dynamic>) continue;
        final entry = QuestProgressEntry(definition, value['type'] as int? ?? 0);
        final progress = (value['progress'] as List?)?.whereType<int>().toList() ?? [];
        for (final (index, counter) in entry.counters.indexed) {
          if (index < progress.length) counter.progress = min(progress[index], counter.max);
        }
        tracker.entries[id!] = entry;
      }
    } catch (_) {
      return QuestProgressTracker();
    }
    return tracker;
  }
}

/// 任務一覧に出す進捗の文字列 (定義のない任務はゲームの 50%/80% 表示)
String questProgressFlagText(int? flag, int? state) {
  if (state == 3) return repairText('達成', 'Done');
  return switch (flag) {
    1 => repairText('50%以上', '50%+'),
    2 => repairText('80%以上', '80%+'),
    _ => '',
  };
}
