import 'dart:convert';
import 'dart:math';
import 'dart:math' as math;

import 'quest_fleet_condition.dart';
import 'quest_tree.dart';
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

  /// battle: ボスが複数ある海域のゲージ番号 (1〜3)。null なら区別しない
  final int? gauge;

  /// 任務の編成条件 (kQuestFleetConditions) を満たしたときだけ数える
  final bool special;

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
    this.gauge,
    this.special = false,
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

  /// 期間限定任務の数える期限 (EO と同じ。過ぎたらゲームの 50%/80% 表示だけにする)
  final DateTime? validUntil;

  /// 任務名 (編成条件の表示用。第2段階の任務だけ)
  final String? title;

  const QuestDefinition(this.id, this.counters,
      {this.shift = 0, this.weightedEqually = false, this.validUntil, this.title});

  /// 編成条件 (条件付きで数えるものがある任務だけ)
  QuestFleetCondition? get condition => kQuestFleetConditions[id];
}

// ---- 定義用ヘルパー ----
QuestCounter _battle(int max, String rank,
        {List<int>? areas, bool boss = false, String label = '', int? gauge, bool special = false}) =>
    QuestCounter(QuestCounterKind.battle, max,
        minRank: winRankValue(rank),
        areas: areas?.toSet(),
        bossOnly: boss,
        label: label,
        gauge: gauge,
        special: special);

QuestCounter _slaughter(int max, List<int> shipTypes) =>
    QuestCounter(QuestCounterKind.slaughter, max, targets: shipTypes.toSet());

QuestCounter _practice(int max, {String rank = '', bool special = false}) =>
    QuestCounter(QuestCounterKind.practice, max, minRank: winRankValue(rank), special: special);

QuestCounter _expedition(int max, [List<int>? missions, String label = '']) =>
    QuestCounter(QuestCounterKind.expedition, max, areas: missions?.toSet(), label: label);

QuestCounter _discard(int max,
        {bool amount = true, List<int>? categories, int index = 2, String label = '', bool special = false}) =>
    QuestCounter(QuestCounterKind.discard, max,
        countsAmount: amount,
        targets: categories?.toSet(),
        categoryIndex: index,
        label: label,
        special: special);

QuestCounter _simple(QuestCounterKind kind, int max) => QuestCounter(kind, max);

const _carrier = [7, 11]; // 軽空母, 正規空母
const _transport = [15]; // 補給艦
const _submarine = [13]; // 潜水艦

/// 対応する任務 (第1段階: デイリー・ウィークリーと、よく使うもの / 第2段階: それ以外の EO 対応任務)
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
    // ======== 第2段階 (マンスリー・クォータリー・イヤリー・期間限定など) ========
    QuestDefinition(
        234,
        () => [
              _battle(1, 'S', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(1, 'S', areas: [14], boss: true, special: true, label: '1-4'),
              _battle(1, 'S', areas: [21], boss: true, special: true, label: '2-1'),
            ], title: 'バレンタイン2026特別限定任務', validUntil: DateTime(2026, 12, 31)),
    QuestDefinition(249, () => [_battle(1, 'S', areas: [25], boss: true, special: true)], title: '「第五戦隊」出撃せよ！'),
    QuestDefinition(257, () => [_battle(1, 'S', areas: [14], boss: true, special: true)], title: '「水雷戦隊」南西へ！'),
    QuestDefinition(259, () => [_battle(1, 'S', areas: [51], boss: true, special: true)], title: '「水上打撃部隊」南方へ！'),
    QuestDefinition(264, () => [_battle(1, 'S', areas: [42], boss: true, special: true)], title: '「空母機動部隊」西へ！'),
    QuestDefinition(266, () => [_battle(1, 'S', areas: [25], boss: true, special: true)], title: '「水上反撃部隊」突入せよ！'),
    QuestDefinition(
        280,
        () => [
              _battle(1, 'S', areas: [12], boss: true, special: true, label: '1-2'),
              _battle(1, 'S', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(1, 'S', areas: [14], boss: true, special: true, label: '1-4'),
              _battle(1, 'S', areas: [21], boss: true, special: true, label: '2-1'),
            ], title: '兵站線確保！海上警備を強化実施せよ！'),
    QuestDefinition(
        284,
        () => [
              _battle(1, 'S', areas: [14], boss: true, special: true, label: '1-4'),
              _battle(1, 'S', areas: [21], boss: true, special: true, label: '2-1'),
              _battle(1, 'S', areas: [22], boss: true, special: true, label: '2-2'),
              _battle(1, 'S', areas: [23], boss: true, special: true, label: '2-3'),
            ], title: '南西諸島方面「海上警備行動」発令！'),
    QuestDefinition(318, () => [_practice(3, rank: 'B', special: true)], title: '給糧艦「伊良湖」の支援'),
    QuestDefinition(329, () => [_practice(3, rank: 'B', special: true)], title: '【節分任務:枡】節分演習！二〇二六', validUntil: DateTime(2026, 2, 13)),
    QuestDefinition(330, () => [_practice(4, rank: 'B', special: true)], title: '空母機動部隊、演習始め！'),
    QuestDefinition(337, () => [_practice(3, rank: 'S', special: true)], title: '「十八駆」演習！'),
    QuestDefinition(339, () => [_practice(3, rank: 'S', special: true)], title: '「十九駆」演習！'),
    QuestDefinition(340, () => [_practice(3, rank: 'S', special: true)], title: '【桃の節句任務】桃の節句艦隊演習2026'),
    QuestDefinition(342, () => [_practice(4, rank: 'A', special: true)], title: '小艦艇群演習強化任務'),
    QuestDefinition(345, () => [_practice(4, rank: 'A', special: true)], title: '演習ティータイム！'),
    QuestDefinition(346, () => [_practice(4, rank: 'S', special: true)], title: '最精鋭！主力オブ主力、演習開始！'),
    QuestDefinition(348, () => [_practice(4, rank: 'A', special: true)], title: '「精鋭軽巡」演習！'),
    QuestDefinition(349, () => [_practice(5, rank: 'S', special: true)], title: 'バレンタイン2026限定任務【スイーツ演習】', validUntil: DateTime(2026, 12, 31)),
    QuestDefinition(350, () => [_practice(3, rank: 'A', special: true)], title: '精鋭「第七駆逐隊」演習開始！'),
    QuestDefinition(353, () => [_practice(5, rank: 'B', special: true)], title: '「巡洋艦戦隊」演習！'),
    QuestDefinition(354, () => [_practice(4, rank: 'S', special: true)], title: '「改装特設空母」任務部隊演習！'),
    QuestDefinition(355, () => [_practice(4, rank: 'S', special: true)], title: '精鋭「第十五駆逐隊」第一小隊演習！'),
    QuestDefinition(356, () => [_practice(3, rank: 'S', special: true)], title: '精鋭「第十九駆逐隊」演習！'),
    QuestDefinition(357, () => [_practice(3, rank: 'S', special: true)], title: '「大和型戦艦」第一戦隊演習、始め！'),
    QuestDefinition(362, () => [_practice(4, rank: 'A', special: true)], title: '特型初代「第十一駆逐隊」演習スペシャル！'),
    QuestDefinition(363, () => [_practice(5, rank: 'A', special: true)], title: '【艦隊12周年記念任務】記念艦隊演習！', validUntil: DateTime(2025, 5, 31)),
    QuestDefinition(367, () => [_practice(4, rank: 'A', special: true)], title: '【梅雨限定任務】海上護衛隊、雨中演習！', validUntil: DateTime(2026, 12, 31)),
    QuestDefinition(368, () => [_practice(3, rank: 'S', special: true)], title: '「十六駆」演習！'),
    QuestDefinition(371, () => [_practice(4, rank: 'A', special: true)], title: '春です！「春雨」、演習しますっ！'),
    QuestDefinition(372, () => [_practice(4, rank: 'A', special: true)], title: '水上艦「艦隊防空演習」を実施せよ！'),
    QuestDefinition(373, () => [_practice(4, rank: 'A', special: true)], title: '「フランス艦隊」演習！'),
    QuestDefinition(374, () => [_practice(3, rank: 'S', special: true)], title: '【期間限定任務】「三十二駆」特別演習！'),
    QuestDefinition(375, () => [_practice(4, rank: 'S', special: true)], title: '「第三戦隊」第二小隊、演習開始！'),
    QuestDefinition(377, () => [_practice(4, rank: 'S', special: true)], title: '「第二駆逐隊(後期編成)」、練度向上！'),
    QuestDefinition(378, () => [_practice(4, rank: 'A', special: true)], title: '新春限定！第六艦隊特別演習'),
    QuestDefinition(379, () => [_practice(4, rank: 'S', special: true)], title: '【期間限定任務】「精鋭十一駆」特別演習！'),
    QuestDefinition(380, () => [_practice(3, rank: 'A', special: true)], title: '【期間限定任務】揚陸船団護衛演習'),
    QuestDefinition(381, () => [_practice(3, rank: 'A', special: true)], title: '【期間限定任務】秋月型演習任務'),
    QuestDefinition(382, () => [_practice(3, rank: 'A', special: true)], title: '【期間限定任務】第三十一戦隊 緊急演習！'),
    QuestDefinition(383, () => [_practice(3, rank: 'A', special: true)], title: '【期間限定任務】フランス艦隊、特別演習！'),
    QuestDefinition(384, () => [_practice(4, rank: 'B', special: true)], title: '【期間限定任務】提督との秋祭り演習！'),
    QuestDefinition(385, () => [_practice(4, rank: 'S', special: true)], title: '【期間限定拡張任務】秋祭り拡張演習！'),
    QuestDefinition(
        434,
        () => [
              _expedition(1, [3], '警備任務'),
              _expedition(1, [5], '海上護衛任務'),
              _expedition(1, [100], '兵站強化任務'),
              _expedition(1, [101], '海峡警備行動'),
              _expedition(1, [9], 'タンカー護衛任務'),
            ], title: '特設護衛船団司令部、活動開始！'),
    QuestDefinition(
        436,
        () => [
              _expedition(1, [1], '練習航海'),
              _expedition(1, [2], '長距離練習航海'),
              _expedition(1, [3], '警備任務'),
              _expedition(1, [4], '対潜警戒任務'),
              _expedition(1, [10], '強行偵察任務'),
            ], title: '練習航海及び警備任務を実施せよ！'),
    QuestDefinition(
        437,
        () => [
              _expedition(1, [4], '対潜警戒任務'),
              _expedition(1, [104], '小笠原沖哨戒線'),
              _expedition(1, [105], '小笠原沖戦闘哨戒'),
              _expedition(1, [110], '南西方面航空偵察作戦'),
            ], title: '小笠原沖哨戒線の強化を実施せよ！'),
    QuestDefinition(
        438,
        () => [
              _expedition(1, [4], '対潜警戒任務'),
              _expedition(1, [100], '兵站強化任務'),
              _expedition(1, [9], 'タンカー護衛任務'),
              _expedition(1, [114], '南西諸島捜索撃滅戦'),
            ], title: '南西諸島方面の海上護衛を強化せよ！'),
    QuestDefinition(
        439,
        () => [
              _expedition(1, [5], '海上護衛任務'),
              _expedition(1, [100], '兵站強化任務'),
              _expedition(1, [11], 'ボーキサイト輸送任務'),
              _expedition(1, [110], '南西方面航空偵察作戦'),
            ], title: '兵站強化遠征任務【基本作戦】'),
    QuestDefinition(
        440,
        () => [
              _expedition(1, [41], 'ブルネイ泊地沖哨戒'),
              _expedition(1, [5], '海上護衛任務'),
              _expedition(1, [40], '水上機前線輸送'),
              _expedition(1, [142], '強行鼠輸送作戦'),
              _expedition(1, [46], '南西海域戦闘哨戒'),
            ], title: '兵站強化遠征任務【拡張作戦】'),
    QuestDefinition(
        441,
        () => [
              _expedition(1, [5], '海上護衛任務'),
              _expedition(1, [102], '長時間対潜警戒'),
              _expedition(1, [9], 'タンカー護衛任務'),
              _expedition(1, [100], '兵站強化任務'),
              _expedition(1, [39], '遠洋潜水艦作戦'),
            ], title: '【節分任務:恵方】令和八年節分遠征'),
    QuestDefinition(
        442,
        () => [
              _expedition(1, [131], '西方海域偵察作戦'),
              _expedition(1, [29], '潜水艦派遣演習'),
              _expedition(1, [30], '潜水艦派遣作戦'),
              _expedition(1, [133], '欧州方面友軍との接触'),
            ], title: '西方連絡作戦準備を実施せよ！'),
    QuestDefinition(
        444,
        () => [
              _expedition(1, [5], '海上護衛任務'),
              _expedition(1, [12], '資源輸送任務'),
              _expedition(1, [9], 'タンカー護衛任務'),
              _expedition(1, [110], '南西方面航空偵察作戦'),
              _expedition(1, [11], 'ボーキサイト輸送任務'),
            ], title: '新兵装開発資材輸送を船団護衛せよ！'),
    QuestDefinition(
        445,
        () => [
              _expedition(1, [5], '海上護衛任務'),
              _expedition(1, [100], '兵站強化任務'),
              _expedition(1, [9], 'タンカー護衛任務'),
              _expedition(1, [18], '航空機輸送作戦'),
              _expedition(1, [45], 'ボーキサイト船団護衛'),
              _expedition(1, [36], '水上機基地建設'),
              _expedition(1, [40], '水上機前線輸送'),
            ], title: '航空基地を整備拡張せよ！'),
    QuestDefinition(
        446,
        () => [
              _expedition(1, [3], '警備任務'),
              _expedition(1, [4], '対潜警戒任務'),
              _expedition(1, [5], '海上護衛任務'),
              _expedition(1, [101], '海峡警備行動'),
              _expedition(1, [100], '兵站強化任務'),
            ], title: '【作戦準備】第一段階任務(対潜整備)'),
    QuestDefinition(
        447,
        () => [
              _expedition(1, [4], '対潜警戒任務'),
              _expedition(1, [5], '海上護衛任務'),
              _expedition(1, [9], 'タンカー護衛任務'),
              _expedition(1, [100], '兵站強化任務'),
              _expedition(1, [110], '南西方面航空偵察作戦'),
            ], title: '海上輸送航路の護衛強化'),
    QuestDefinition(
        449,
        () => [
              _expedition(2, [5], '海上護衛任務'),
              _expedition(2, [9], 'タンカー護衛任務'),
              _expedition(2, [11], 'ボーキサイト輸送任務'),
            ], title: '【艦隊12周年記念任務】資源輸出', validUntil: DateTime(2025, 5, 31)),
    QuestDefinition(
        626,
        () => [
              _discard(2, categories: [20], index: -1, special: true, label: '零式艦戦21型'),
              _discard(1, categories: [19], index: -1, special: true, label: '九六式艦戦'),
            ], title: '精鋭「艦戦」隊の新編成'),
    QuestDefinition(628, () => [_discard(2, categories: [21], index: -1, special: true)], title: '機種転換'),
    QuestDefinition(643, () => [_discard(2, categories: [20], index: -1)], title: '主力「陸攻」の調達'),
    QuestDefinition(645, () => [_discard(1, categories: [18])], title: '「洋上補給」物資の調達'),
    QuestDefinition(653, () => [_discard(6, categories: [4], index: -1)], title: '工廠稼働！次期作戦準備！'),
    QuestDefinition(
        654,
        () => [
              _discard(1, categories: [242], index: -1, special: true, label: 'Swordfish'),
              _discard(2, categories: [249], index: -1, special: true, label: 'Fulmar'),
            ], title: '精鋭複葉機飛行隊の編成'),
    QuestDefinition(
        655,
        () => [
              _discard(5, categories: [1], label: '小口径主砲'),
              _discard(5, categories: [2], label: '中口径主砲'),
              _discard(5, categories: [3], label: '大口径主砲'),
              _discard(5, categories: [8], label: '艦上攻撃機'),
              _discard(5, categories: [10], label: '水上偵察機'),
            ], title: '工廠フル稼働！新兵装を開発せよ！'),
    QuestDefinition(
        657,
        () => [
              _discard(6, categories: [1], label: '小口径主砲'),
              _discard(5, categories: [2], label: '中口径主砲'),
              _discard(4, categories: [5], label: '魚雷'),
            ], title: '新型兵装開発整備の強化'),
    QuestDefinition(
        678,
        () => [
              _discard(3, categories: [19], index: -1, label: '九六式艦戦'),
              _discard(5, categories: [20], index: -1, label: '零式艦戦21型'),
            ], title: '主力艦上戦闘機の更新'),
    QuestDefinition(
        681,
        () => [
              _discard(4, categories: [7], label: '艦上爆撃機'),
              _discard(4, categories: [8], label: '艦上攻撃機'),
            ], title: '航空戦力の再編増強準備'),
    QuestDefinition(
        686,
        () => [
              _discard(4, categories: [3], index: -1, special: true, label: '10cm連装高角砲'),
              _discard(1, categories: [121], index: -1, special: true, label: '94式高射装置'),
            ], title: '戦時改修A型高角砲の量産'),
    QuestDefinition(
        840,
        () => [
              _battle(2, 'A', areas: [12], boss: true, special: true, label: '1-2'),
              _battle(2, 'A', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(2, 'A', areas: [14], boss: true, special: true, label: '1-4'),
            ], title: '【節分任務:豆】節分作戦二〇二六', validUntil: DateTime(2026, 2, 13)),
    QuestDefinition(
        841,
        () => [
              _battle(2, 'A', areas: [21], boss: true, special: true, label: '2-1'),
              _battle(2, 'A', areas: [22], boss: true, special: true, label: '2-2'),
              _battle(2, 'A', areas: [23], boss: true, special: true, label: '2-3'),
            ], title: '【節分任務:鬼】南西方面節分作戦二〇二六', validUntil: DateTime(2026, 2, 13)),
    QuestDefinition(
        843,
        () => [
              _battle(1, 'S', areas: [41], boss: true, special: true, label: '4-1'),
              _battle(1, 'S', areas: [42], boss: true, special: true, label: '4-2'),
              _battle(1, 'S', areas: [43], boss: true, special: true, label: '4-3'),
              _battle(1, 'S', areas: [75], boss: true, gauge: 3, special: true, label: '7-5(第三)'),
            ], title: '【節分任務:柊】節分拡張作戦二〇二六、重巡出撃！', validUntil: DateTime(2026, 2, 13)),
    QuestDefinition(
        845,
        () => [
              _battle(1, 'S', areas: [41], boss: true, label: '4-1'),
              _battle(1, 'S', areas: [42], boss: true, label: '4-2'),
              _battle(1, 'S', areas: [43], boss: true, label: '4-3'),
              _battle(1, 'S', areas: [44], boss: true, label: '4-4'),
              _battle(1, 'S', areas: [45], boss: true, label: '4-5'),
            ], title: '発令！「西方海域作戦」'),
    QuestDefinition(
        854,
        () => [
              _battle(1, 'A', areas: [24], boss: true, label: '2-4'),
              _battle(1, 'A', areas: [61], boss: true, label: '6-1'),
              _battle(1, 'A', areas: [63], boss: true, label: '6-3'),
              _battle(1, 'S', areas: [64], boss: true, label: '6-4'),
            ], title: '戦果拡張任務！「Z作戦」前段作戦'),
    QuestDefinition(861, () => [_battle(2, '', areas: [16], boss: true, special: true)], title: '強行輸送艦隊、抜錨！'),
    QuestDefinition(862, () => [_battle(2, 'A', areas: [63], boss: true, special: true)], title: '前線の航空偵察を実施せよ！'),
    QuestDefinition(
        872,
        () => [
              _battle(1, 'S', areas: [55], boss: true, label: '5-5'),
              _battle(1, 'S', areas: [62], boss: true, label: '6-2'),
              _battle(1, 'S', areas: [65], boss: true, label: '6-5'),
              _battle(1, 'S', areas: [72], boss: true, gauge: 2, special: true, label: '7-2(第二)'),
            ], title: '戦果拡張任務！「Z作戦」後段作戦'),
    QuestDefinition(
        873,
        () => [
              _battle(1, 'A', areas: [31], boss: true, special: true, label: '3-1'),
              _battle(1, 'A', areas: [32], boss: true, special: true, label: '3-2'),
              _battle(1, 'A', areas: [33], boss: true, special: true, label: '3-3'),
            ], title: '北方海域警備を実施せよ！'),
    QuestDefinition(875, () => [_battle(2, 'S', areas: [54], boss: true, special: true)], title: '精鋭「三一駆」、鉄底海域に突入せよ！'),
    QuestDefinition(
        888,
        () => [
              _battle(1, 'S', areas: [51], boss: true, special: true, label: '5-1'),
              _battle(1, 'S', areas: [53], boss: true, special: true, label: '5-3'),
              _battle(1, 'S', areas: [54], boss: true, special: true, label: '5-4'),
            ], title: '新編成「三川艦隊」、鉄底海峡に突入せよ！'),
    QuestDefinition(
        893,
        () => [
              _battle(3, 'S', areas: [15], boss: true, label: '1-5'),
              _battle(3, 'S', areas: [71], boss: true, label: '7-1'),
              _battle(3, 'S', areas: [72], boss: true, gauge: 1, special: true, label: '7-2(第一)'),
              _battle(3, 'S', areas: [72], boss: true, gauge: 2, special: true, label: '7-2(第二)'),
            ], title: '泊地周辺海域の安全確保を徹底せよ！'),
    QuestDefinition(
        894,
        () => [
              _battle(1, 'S', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(1, 'S', areas: [14], boss: true, special: true, label: '1-4'),
              _battle(1, 'S', areas: [21], boss: true, special: true, label: '2-1'),
              _battle(1, 'S', areas: [22], boss: true, special: true, label: '2-2'),
              _battle(1, 'S', areas: [23], boss: true, special: true, label: '2-3'),
            ], title: '空母戦力の投入による兵站線戦闘哨戒'),
    QuestDefinition(
        903,
        () => [
              _battle(1, 'S', areas: [51], boss: true, special: true, label: '5-1'),
              _battle(1, 'S', areas: [54], boss: true, special: true, label: '5-4'),
              _battle(1, 'S', areas: [64], boss: true, special: true, label: '6-4'),
              _battle(1, 'S', areas: [65], boss: true, special: true, label: '6-5'),
            ], title: '拡張「六水戦」、最前線へ！'),
    QuestDefinition(
        904,
        () => [
              _battle(1, 'S', areas: [25], boss: true, special: true, label: '2-5'),
              _battle(1, 'S', areas: [34], boss: true, special: true, label: '3-4'),
              _battle(1, 'S', areas: [45], boss: true, special: true, label: '4-5'),
              _battle(1, 'S', areas: [53], boss: true, special: true, label: '5-3'),
            ], title: '精鋭「十九駆」、躍り出る！'),
    QuestDefinition(
        905,
        () => [
              _battle(1, 'A', areas: [11], boss: true, special: true, label: '1-1'),
              _battle(1, 'A', areas: [12], boss: true, special: true, label: '1-2'),
              _battle(1, 'A', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(1, 'A', areas: [15], boss: true, special: true, label: '1-5'),
              _battle(1, '', areas: [16], boss: true, special: true, label: '1-6終点'),
            ], title: '「海防艦」、海を護る！'),
    QuestDefinition(
        912,
        () => [
              _battle(1, 'A', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(1, 'A', areas: [21], boss: true, special: true, label: '2-1'),
              _battle(1, 'A', areas: [22], boss: true, special: true, label: '2-2'),
              _battle(1, 'A', areas: [23], boss: true, special: true, label: '2-3'),
              _battle(1, '', areas: [16], boss: true, special: true, label: '1-6終点'),
            ], title: '工作艦「明石」護衛任務'),
    QuestDefinition(
        914,
        () => [
              _battle(1, 'A', areas: [41], boss: true, special: true, label: '4-1'),
              _battle(1, 'A', areas: [42], boss: true, special: true, label: '4-2'),
              _battle(1, 'A', areas: [43], boss: true, special: true, label: '4-3'),
              _battle(1, 'A', areas: [44], boss: true, special: true, label: '4-4'),
            ], title: '重巡戦隊、西へ！'),
    QuestDefinition(
        928,
        () => [
              _battle(2, 'S', areas: [42], boss: true, special: true, label: '4-2'),
              _battle(2, 'S', areas: [72], boss: true, gauge: 2, special: true, label: '7-2(第二)'),
              _battle(2, 'S', areas: [73], boss: true, gauge: 2, special: true, label: '7-3(第二)'),
            ], title: '歴戦「第十方面艦隊」、全力出撃！'),
    QuestDefinition(
        944,
        () => [
              _battle(2, 'A', areas: [12], boss: true, special: true, label: '1-2'),
              _battle(2, 'A', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(2, 'A', areas: [14], boss: true, special: true, label: '1-4'),
            ], title: '鎮守府近海海域の哨戒を実施せよ！'),
    QuestDefinition(
        945,
        () => [
              _battle(2, 'A', areas: [15], boss: true, special: true, label: '1-5'),
              _battle(2, '', areas: [16], boss: true, special: true, label: '1-6終点'),
              _battle(2, 'A', areas: [21], boss: true, special: true, label: '2-1'),
            ], title: '南西方面の兵站航路の安全を図れ！'),
    QuestDefinition(
        946,
        () => [
              _battle(1, 'S', areas: [22], boss: true, special: true, label: '2-2'),
              _battle(1, 'S', areas: [23], boss: true, special: true, label: '2-3'),
              _battle(1, 'S', areas: [24], boss: true, special: true, label: '2-4'),
            ], title: '空母機動部隊、出撃！敵艦隊を迎撃せよ！'),
    QuestDefinition(
        947,
        () => [
              _battle(1, 'S', areas: [31], boss: true, special: true, label: '3-1'),
              _battle(1, 'S', areas: [33], boss: true, special: true, label: '3-3'),
              _battle(1, 'S', areas: [34], boss: true, special: true, label: '3-4'),
              _battle(1, 'S', areas: [35], boss: true, special: true, label: '3-5'),
            ], title: 'AL作戦'),
    QuestDefinition(
        948,
        () => [
              _battle(2, 'S', areas: [52], boss: true, special: true, label: '5-2'),
              _battle(2, 'S', areas: [55], boss: true, special: true, label: '5-5'),
              _battle(2, 'A', areas: [64], boss: true, special: true, label: '6-4'),
              _battle(2, 'S', areas: [65], boss: true, special: true, label: '6-5'),
            ], title: '機動部隊決戦'),
    QuestDefinition(
        949,
        () => [
              _battle(2, 'S', areas: [24], boss: true, special: true, label: '2-4'),
              _battle(2, 'S', areas: [35], boss: true, special: true, label: '3-5'),
              _battle(2, 'A', areas: [64], boss: true, special: true, label: '6-4'),
            ], title: '改装特務空母「Gambier Bay Mk.II」抜錨！'),
    QuestDefinition(
        950,
        () => [
              _battle(2, 'S', areas: [14], boss: true, special: true, label: '1-4'),
              _battle(2, 'S', areas: [23], boss: true, special: true, label: '2-3'),
              _battle(2, 'S', areas: [32], boss: true, special: true, label: '3-2'),
            ], title: '【夏季限定】「渚のマーメイド」作戦！', validUntil: DateTime(2021, 9, 29)),
    QuestDefinition(
        951,
        () => [
              _battle(2, 'S', areas: [41], boss: true, special: true, label: '4-1'),
              _battle(2, 'S', areas: [43], boss: true, special: true, label: '4-3'),
              _battle(2, 'S', areas: [44], boss: true, special: true, label: '4-4'),
            ], title: '【夏季限定】「渚のシレーナ」欧州作戦！', validUntil: DateTime(2021, 9, 29)),
    QuestDefinition(
        952,
        () => [
              _battle(1, 'S', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(1, 'S', areas: [14], boss: true, special: true, label: '1-4'),
              _battle(1, 'S', areas: [21], boss: true, special: true, label: '2-1'),
              _battle(1, 'S', areas: [22], boss: true, special: true, label: '2-2'),
            ], title: '【作戦準備】第二段階任務(対地/対空整備)'),
    QuestDefinition(
        953,
        () => [
              _battle(1, 'A', areas: [12], boss: true, special: true, label: '1-2'),
              _battle(1, 'A', areas: [14], boss: true, special: true, label: '1-4'),
              _battle(1, 'A', areas: [21], boss: true, special: true, label: '2-1'),
              _battle(1, 'A', areas: [22], boss: true, special: true, label: '2-2'),
            ], title: '【梅雨限定任務】雨の南西諸島防衛戦2026', validUntil: DateTime(2026, 12, 30)),
    QuestDefinition(
        954,
        () => [
              _battle(1, 'A', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(1, 'A', areas: [15], boss: true, special: true, label: '1-5'),
              _battle(1, 'A', areas: [23], boss: true, special: true, label: '2-3'),
              _battle(1, 'A', areas: [74], boss: true, special: true, label: '7-4'),
              _battle(3, '', areas: [16], boss: true, special: true, label: '1-6終点'),
            ], title: '【梅雨拡張任務】梅雨の海上護衛強化2026', validUntil: DateTime(2026, 12, 30)),
    QuestDefinition(
        955,
        () => [
              _battle(1, 'A', areas: [51], boss: true, special: true, label: '5-1'),
              _battle(1, 'A', areas: [52], boss: true, special: true, label: '5-2'),
              _battle(1, 'A', areas: [53], boss: true, special: true, label: '5-3'),
              _battle(1, 'A', areas: [54], boss: true, special: true, label: '5-4'),
              _battle(1, 'A', areas: [55], boss: true, special: true, label: '5-5'),
              _battle(1, 'A', areas: [56], boss: true, gauge: 3, special: true, label: '5-6(第三)'),
            ], title: '【梅雨任務拡張作戦】南方反攻望楼作戦を叩け！', validUntil: DateTime(2026, 12, 30)),
    QuestDefinition(
        957,
        () => [
              _battle(1, 'S', areas: [12], boss: true, special: true, label: '1-2'),
              _battle(1, 'S', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(1, 'S', areas: [14], boss: true, special: true, label: '1-4'),
              _battle(1, 'S', areas: [15], boss: true, special: true, label: '1-5'),
            ], title: '「山風改二」、抜錨せよ！'),
    QuestDefinition(
        958,
        () => [
              _battle(1, 'S', areas: [22], boss: true, special: true, label: '2-2'),
              _battle(1, 'S', areas: [51], boss: true, special: true, label: '5-1'),
              _battle(1, 'S', areas: [64], boss: true, special: true, label: '6-4'),
              _battle(1, 'S', areas: [72], boss: true, gauge: 2, special: true, label: '7-2(第二)'),
            ], title: '改白露型駆逐艦「山風改二」、奮戦す！'),
    QuestDefinition(
        961,
        () => [
              _battle(2, 'S', areas: [24], boss: true, special: true, label: '2-4'),
              _battle(2, 'S', areas: [54], boss: true, special: true, label: '5-4'),
              _battle(2, 'S', areas: [72], boss: true, gauge: 2, special: true, label: '7-2(第二)'),
            ], title: '奮戦！精鋭「第十五駆逐隊」第一小隊'),
    QuestDefinition(
        973,
        () => [
              _battle(1, 'A', areas: [31], boss: true, special: true, label: '3-1'),
              _battle(1, 'A', areas: [33], boss: true, special: true, label: '3-3'),
              _battle(1, 'A', areas: [43], boss: true, special: true, label: '4-3'),
              _battle(1, 'A', areas: [73], boss: true, gauge: 2, special: true, label: '7-3(第二)'),
            ], title: '日英米合同水上艦隊、抜錨せよ！'),
    QuestDefinition(
        975,
        () => [
              _battle(1, 'S', areas: [15], boss: true, special: true, label: '1-5'),
              _battle(1, 'S', areas: [23], boss: true, special: true, label: '2-3'),
              _battle(1, 'S', areas: [32], boss: true, special: true, label: '3-2'),
              _battle(1, 'S', areas: [53], boss: true, special: true, label: '5-3'),
            ], title: '精鋭「第十九駆逐隊」、全力出撃！'),
    QuestDefinition(
        987,
        () => [
              _battle(1, 'S', areas: [42], boss: true, special: true, label: '4-2'),
              _battle(1, 'S', areas: [43], boss: true, special: true, label: '4-3'),
              _battle(1, 'S', areas: [44], boss: true, special: true, label: '4-4'),
            ], title: '【週間拡張任務】秋の南瓜祭り! Buono!'),
    QuestDefinition(
        1002,
        () => [
              _battle(1, 'S', areas: [32], boss: true, special: true, label: '3-2'),
              _battle(1, 'S', areas: [35], boss: true, special: true, label: '3-5'),
              _battle(1, 'S', areas: [64], boss: true, special: true, label: '6-4'),
            ], title: '【限定拡張任務】南瓜祭り2025、拡張作戦！'),
    QuestDefinition(
        1005,
        () => [
              _battle(1, 'A', areas: [12], boss: true, special: true, label: '1-2'),
              _battle(1, 'A', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(1, 'A', areas: [15], boss: true, special: true, label: '1-5'),
              _battle(1, 'A', areas: [32], boss: true, special: true, label: '3-2'),
            ], title: '精強「第七駆逐隊」緊急出動！'),
    QuestDefinition(
        1010,
        () => [
              _battle(3, 'S', areas: [15], boss: true, special: true, label: '1-5'),
              _battle(1, '', areas: [16], boss: true, special: true, label: '1-6終点'),
            ], title: '【期間限定任務】対潜掃討作戦', validUntil: DateTime(2024, 6, 28)),
    QuestDefinition(
        1011,
        () => [
              _battle(1, 'A', areas: [11], boss: true, special: true, label: '1-1'),
              _battle(1, 'A', areas: [12], boss: true, special: true, label: '1-2'),
              _battle(1, 'A', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(1, 'A', areas: [15], boss: true, special: true, label: '1-5'),
              _battle(1, 'A', areas: [21], boss: true, special: true, label: '2-1'),
            ], title: '【期間限定任務】精強海防艦、緊急近海防衛！', validUntil: DateTime(2024, 6, 28)),
    QuestDefinition(
        1012,
        () => [
              _battle(3, 'S', areas: [11], boss: true, special: true, label: '1-1'),
              _battle(2, 'A', areas: [12], boss: true, special: true, label: '1-2'),
              _battle(2, 'A', areas: [15], boss: true, special: true, label: '1-5'),
            ], title: '鵜来型海防艦、静かな海を防衛せよ！'),
    QuestDefinition(
        1018,
        () => [
              _battle(1, 'A', areas: [51], boss: true, special: true, label: '5-1'),
              _battle(1, 'A', areas: [53], boss: true, special: true, label: '5-3'),
              _battle(1, 'A', areas: [54], boss: true, special: true, label: '5-4'),
              _battle(1, 'A', areas: [55], boss: true, special: true, label: '5-5'),
            ], title: '「第三戦隊」第二小隊、鉄底海峡へ！'),
    QuestDefinition(
        1022,
        () => [
              _battle(1, 'A', areas: [23], boss: true, special: true, label: '2-3'),
              _battle(1, 'A', areas: [71], boss: true, special: true, label: '7-1'),
              _battle(1, 'A', areas: [41], boss: true, special: true, label: '4-1'),
              _battle(1, 'A', areas: [51], boss: true, special: true, label: '5-1'),
            ], title: '【期間限定任務】「三十二駆」月次戦闘哨戒！'),
    QuestDefinition(
        1030,
        () => [
              _battle(2, 'S', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(2, 'S', areas: [14], boss: true, special: true, label: '1-4'),
              _battle(2, 'S', areas: [24], boss: true, special: true, label: '2-4'),
            ], title: '【期間限定任務】Fletcher級、哨戒任務！', validUntil: DateTime(2025, 5, 31)),
    QuestDefinition(
        1031,
        () => [
              _battle(2, 'S', areas: [31], boss: true, special: true, label: '3-1'),
              _battle(2, 'S', areas: [32], boss: true, special: true, label: '3-2'),
              _battle(2, 'S', areas: [35], boss: true, special: true, label: '3-5'),
            ], title: '【初夏限定任務】北方海域 戦闘哨戒作戦2026'),
    QuestDefinition(
        1034,
        () => [
              _battle(1, 'S', areas: [12], boss: true, special: true, label: '1-2'),
              _battle(1, 'S', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(1, 'S', areas: [14], boss: true, special: true, label: '1-4'),
              _battle(1, 'S', areas: [21], boss: true, special: true, label: '2-1'),
            ], title: '【夏季限定任務】夏の日の「朝日」護衛'),
    QuestDefinition(
        1035,
        () => [
              _battle(1, 'S', areas: [51], boss: true, special: true, label: '5-1'),
              _battle(1, 'S', areas: [53], boss: true, special: true, label: '5-3'),
              _battle(1, 'S', areas: [54], boss: true, special: true, label: '5-4'),
            ], title: '【夏季限定任務】ソロモンの夏夜'),
    QuestDefinition(
        1039,
        () => [
              _battle(1, 'S', areas: [12], boss: true, special: true, label: '1-2'),
              _battle(1, 'S', areas: [14], boss: true, special: true, label: '1-4'),
              _battle(1, 'S', areas: [15], boss: true, special: true, label: '1-5'),
            ], title: '【期間限定任務】Halloween海上護衛隊出撃！'),
    QuestDefinition(
        1040,
        () => [
              _battle(2, 'S', areas: [21], boss: true, special: true, label: '2-1'),
              _battle(2, 'S', areas: [22], boss: true, special: true, label: '2-2'),
            ], title: '【期間限定任務】Halloween狼隊、夜の襲撃！'),
    QuestDefinition(
        1045,
        () => [
              _battle(1, 'S', areas: [51], boss: true, special: true, label: '5-1'),
              _battle(1, 'S', areas: [53], boss: true, special: true, label: '5-3'),
              _battle(1, 'S', areas: [54], boss: true, special: true, label: '5-4'),
              _battle(1, 'S', areas: [55], boss: true, special: true, label: '5-5'),
              _battle(1, 'S', areas: [75], boss: true, gauge: 3, special: true, label: '7-5(第三)'),
            ], title: '「吹雪改三」抜錨します！見てくださいっ！'),
    QuestDefinition(
        1047,
        () => [
              _battle(1, 'S', areas: [54], boss: true, special: true, label: '5-4'),
              _battle(1, 'S', areas: [55], boss: true, special: true, label: '5-5'),
              _battle(1, 'S', areas: [56], boss: true, gauge: 3, special: true, label: '5-6(第三)'),
            ], title: '「涼波改二」ラバウルより抜錨せよ！'),
    QuestDefinition(
        1048,
        () => [
              _battle(1, 'A', areas: [13], boss: true, special: true, label: '1-3'),
              _battle(1, 'A', areas: [14], boss: true, special: true, label: '1-4'),
            ], title: '【期間限定任務】戦略兵站物資、緊急輸送！'),
    QuestDefinition(
        1049,
        () => [
              _battle(1, 'A', areas: [23], boss: true, special: true, label: '2-3'),
              _battle(1, 'A', areas: [75], boss: true, gauge: 2, special: true, label: '7-5(第二)'),
            ], title: '【期間限定拡張作戦】戦略兵站物資、拡張輸送！'),
    QuestDefinition(
        1050,
        () => [
              _battle(1, 'S', areas: [14], boss: true, special: true, label: '1-4'),
              _battle(1, 'S', areas: [21], boss: true, special: true, label: '2-1'),
              _battle(1, 'S', areas: [22], boss: true, special: true, label: '2-2'),
              _battle(1, 'S', areas: [23], boss: true, special: true, label: '2-3'),
            ], title: '「第九戦隊」抜錨！前線展開せよッ！'),
    QuestDefinition(
        1051,
        () => [
              _battle(1, 'A', areas: [15], boss: true, special: true, label: '1-5'),
              _battle(1, '', areas: [16], boss: true, special: true, label: '1-6終点'),
              _battle(1, 'A', areas: [23], boss: true, special: true, label: '2-3'),
              _battle(1, 'A', areas: [25], boss: true, special: true, label: '2-5'),
              _battle(1, 'A', areas: [43], boss: true, special: true, label: '4-3'),
            ], title: '改装「1YB3H」旗艦、敵中を突破せよ！'),
    QuestDefinition(1103, () => [_discard(3, categories: [125], index: -1)], title: '潜水艦強化兵装の量産'),
    QuestDefinition(1104, () => [_discard(3, categories: [106], index: -1)], title: '潜水艦電子兵装の量産'),
    QuestDefinition(1105, () => [_discard(3, categories: [47])], title: '夏の格納庫整備＆航空基地整備'),
    QuestDefinition(
        1106,
        () => [
              _discard(3, categories: [25], index: -1, special: true, label: '零式水上偵察機'),
              _discard(3, categories: [26], index: -1, special: true, label: '瑞雲'),
            ], title: '精鋭三座水上偵察機隊の前線投入'),
    QuestDefinition(
        1107,
        () => [
              _discard(2, categories: [6], label: '艦上戦闘機'),
              _discard(2, categories: [8], label: '艦上攻撃機'),
            ], title: '【鋼材輸出】基地航空兵力を増備せよ！'),
    QuestDefinition(
        1108,
        () => [
              _discard(2, categories: [46], index: -1, special: true, label: '九三式水中聴音機'),
              _discard(2, categories: [47], index: -1, special: true, label: '三式水中探信儀'),
            ], title: '調整改良型「水中探信儀」の増産'),
    QuestDefinition(
        1109,
        () => [
              _discard(2, categories: [37], index: -1, special: true, label: '7.7mm機銃'),
              _discard(2, categories: [68], index: -1, special: true, label: '大発動艇'),
            ], title: '上陸作戦支援用装備の配備'),
    QuestDefinition(
        1112,
        () => [
              _discard(4, categories: [1], label: '小口径主砲'),
              _discard(4, categories: [2], label: '中口径主砲'),
              _discard(4, categories: [3], label: '大口径主砲'),
            ], title: '鎮守府「大掃除」祭り！'),
    QuestDefinition(
        1119,
        () => [
              _discard(8, categories: [1], label: '小口径主砲'),
              _discard(8, categories: [2], label: '中口径主砲'),
              _discard(8, categories: [10], label: '水上偵察機'),
            ], title: '【期間限定】Halloweenの南瓜、食べりゅ？'),
    QuestDefinition(
        1120,
        () => [
              _discard(4, categories: [6], label: '艦上戦闘機'),
              _discard(4, categories: [7], label: '艦上爆撃機'),
              _discard(4, categories: [8], label: '艦上攻撃機'),
            ], title: '【機種整理統合】新型戦闘機の量産計画'),
    QuestDefinition(
        1121,
        () => [
              _discard(11, categories: [1], label: '小口径主砲'),
              _discard(11, categories: [2], label: '中口径主砲'),
              _discard(11, categories: [10], label: '水上偵察機'),
            ], title: '【年末年始】鎮守府大掃除！良いお年を！'),
    QuestDefinition(1123, () => [_discard(2, categories: [82], index: -1, special: true)], title: '改良三座水上偵察機の増備'),
    QuestDefinition(1138, () => [_discard(4, categories: [120], index: -1, special: true)], title: '【高射装置量産】94式高射装置の追加配備'),
    QuestDefinition(
        1145,
        () => [
              _discard(8, categories: [25], index: -1, label: '零式水上偵察機'),
              _discard(15, categories: [5], label: '魚雷'),
            ], title: '【工廠任務】伊号潜水艦装備の拡充'),
    QuestDefinition(
        1146,
        () => [
              _discard(8, categories: [7], label: '艦上爆撃機'),
              _discard(8, categories: [8], label: '艦上攻撃機'),
              _discard(16, categories: [5], label: '魚雷'),
            ], title: '【年末年始】拡張大掃除&特別資源輸出-I'),
    QuestDefinition(
        1147,
        () => [
              _discard(8, categories: [3], label: '大口径主砲'),
              _discard(16, categories: [2], label: '中口径主砲'),
              _discard(20, categories: [10], label: '水上偵察機'),
            ], title: '【年末年始】拡張大掃除&特別資源輸出-II'),
    QuestDefinition(
        1149,
        () => [
              _discard(8, categories: [2], label: '中口径主砲'),
              _discard(8, categories: [5], label: '魚雷'),
              _discard(4, categories: [3], label: '大口径主砲'),
            ], title: '【期間限定任務】作戦後の不要装備等用途廃止', validUntil: DateTime(2025, 5, 31)),
    QuestDefinition(
        1151,
        () => [
              _discard(14, categories: [10], label: '水上偵察機'),
              _discard(12, categories: [2], label: '中口径主砲'),
              _discard(10, categories: [7], label: '艦上爆撃機'),
            ], title: '陸軍戦闘機及び海外戦闘機の増備'),
    QuestDefinition(1154, () => [_discard(6, categories: [47], index: -1, special: true, label: '三式水中探信儀')], title: '【新型対潜兵装開発】対潜噴進爆雷砲の開発'),
    QuestDefinition(
        1156,
        () => [
              _discard(12, categories: [7], label: '艦上爆撃機'),
              _discard(12, categories: [8], label: '艦上攻撃機'),
              _discard(12, categories: [10], label: '水上偵察機'),
            ], title: '【重南瓜祭り拡張任務】大きいの収穫すりゅ？'),
    QuestDefinition(
        1157,
        () => [
              _discard(6, categories: [44], index: -1, label: '九四式爆雷投射機'),
              _discard(6, categories: [45], index: -1, label: '三式爆雷投射機'),
              _discard(6, categories: [346], index: -1, label: '二式12cm迫撃砲改'),
            ], title: '【重南瓜祭り拡張任務】対潜装備も整理整頓！'),
    QuestDefinition(
        1160,
        () => [
              _discard(5, categories: [21], index: -1, special: true, label: '零式艦戦52型'),
              _discard(5, categories: [55], index: -1, special: true, label: '紫電改二'),
            ], title: '【工廠任務】試製震電の艦戦型改二への改修'),
    QuestDefinition(
        1161,
        () => [
              _discard(9, categories: [6], special: true, label: '艦上戦闘機'),
              _discard(9, categories: [7], special: true, label: '艦上爆撃機'),
              _discard(9, categories: [8], special: true, label: '艦上攻撃機'),
              _discard(8, categories: [15], special: true, label: '爆雷'),
              _discard(8, categories: [21], special: true, label: '対空機銃'),
              _discard(9, categories: [2], special: true, label: '中口径主砲'),
              _discard(7, categories: [3], special: true, label: '大口径主砲'),
            ], title: '【工廠任務】新装備運用のための工廠整備【壱】'),
    QuestDefinition(
        1162,
        () => [
              _discard(6, categories: [21], index: -1, label: '零式艦戦52型'),
              _discard(4, categories: [201], index: -1, label: '紫電一一型'),
              _discard(8, categories: [10], index: -1, label: '12.7cm連装高角砲'),
              _discard(2, categories: [9], index: -1, label: '46cm三連装砲'),
            ], title: '【工廠任務】新装備運用のための工廠整備【弐】'),
    QuestDefinition(
        1164,
        () => [
              _discard(8, categories: [45], index: -1, special: true, label: '三式爆雷投射機'),
              _discard(4, categories: [47], index: -1, special: true, label: '三式水中探信儀'),
              _discard(8, categories: [10], index: -1, special: true, label: '12.7cm連装高角砲'),
            ], title: '【工廠任務】水雷戦隊新改装艦、改装準備！'),
  ])
    def.id: def
};

/// 周期がデイリーでなくても1日で進捗がリセットされる任務 (EO QuestManager)
/// (第2段階で追加: EO の任務説明で「1日で進捗リセット」とある演習任務)
const Set<int> _kDailyResetQuestIds = {
  211, 212, 311, 313, 314, 318, 326, 330, 337, 339, 342, 345, 346, 348, 350, //
  353, 354, 355, 356, 357, 362, 363, 367, 368, 371, 372,
  315, 340, 373, 374, 375, 377, 378, 379, 380, 381, 382, 383, 384, 385,
};

/// ボスが複数ある海域で、ボスのマス番号 (api_no) とゲージ番号 (ProgressSpecialBattle.CheckGaugeIndex*)
const Map<int, Map<int, int>> _kGaugeCells = {
  56: {11: 1, 27: 2, 43: 3},
  72: {7: 1, 15: 2},
  73: {5: 1, 8: 1, 18: 2, 23: 2, 24: 2, 25: 2},
  75: {11: 1, 19: 2, 24: 3, 25: 3},
};

bool _gaugeMatches(int areaId, int? cell, int gauge) {
  final cells = _kGaugeCells[areaId];
  if (cells == null) return true;
  return cell != null && cells[cell] == gauge;
}

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

  /// 報酬の資源 (api_get_material: 燃料・弾薬・鋼材・ボーキサイト)
  final List<int>? materials;

  const QuestListItem({
    required this.id,
    required this.state,
    required this.type,
    this.label = 0,
    this.progressFlag = 0,
    this.materials,
  });
}

class QuestProgressTracker {
  final Map<int, QuestProgressEntry> entries = {};

  /// 任務ID -> 状態 (最後に見た任務一覧)
  final Map<int, int> questStates = {};

  DateTime? lastUpdate;

  int? _mapId;
  int? _eventId;
  int? _cell;

  /// 出撃中の艦隊番号 (api_req_map/start の api_deck_id)
  int? sortieFleet;

  /// 演習中の艦隊番号 (api_req_practice/battle の api_deck_id)
  int? practiceFleet;

  /// 任務画面「全て」タブの一覧 (任務ツリーの推定用)
  QuestListSnapshot allTab = QuestListSnapshot();

  /// 任務ID -> 報酬の資源 (任務一覧で見たもの。保存はしない)
  final Map<int, List<int>> rewardMaterials = {};

  QuestProgressEntry? progressOf(int questId) => entries[questId];

  // ---- 任務一覧 ----

  void onQuestList(Iterable<QuestListItem> quests, {DateTime? now}) {
    now ??= DateTime.now();
    final previous = lastUpdate;
    if (previous != null) _resetCrossedPeriods(previous, now);

    for (final quest in quests) {
      questStates[quest.id] = quest.state;
      final materials = quest.materials;
      if (materials != null && materials.length >= 4) rewardMaterials[quest.id] = materials.sublist(0, 4);
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
      final validUntil = definition.validUntil;
      if (validUntil != null && !now.isBefore(validUntil)) continue;
      final questType = quest.label >= 100 ? quest.label : quest.type;
      final entry = entries.putIfAbsent(quest.id, () => QuestProgressEntry(definition, questType));
      entry.questType = questType;
      entry.applyProgressFlag(quest.progressFlag);
    }
    lastUpdate = now;
  }

  void onQuestCleared(int questId) {
    allTab.onCleared(questId);
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

  Iterable<(QuestProgressEntry, QuestCounter)> _activeEntries(QuestCounterKind kind) sync* {
    for (final e in entries.entries) {
      if (questStates[e.key] != 2) continue;
      for (final c in e.value.counters) {
        if (c.kind == kind) yield (e.value, c);
      }
    }
  }

  Iterable<QuestCounter> _activeCounters(QuestCounterKind kind) =>
      _activeEntries(kind).map((e) => e.$2);

  /// 編成条件付きのカウンタは、条件を満たすときだけ数える。
  /// [countWithoutFleet]: 艦隊が分からないときに数えるか (出撃は EO と同じく数える)
  static bool _meetsCondition(QuestProgressEntry entry, QuestCounter counter, QuestFleet? fleet,
      {required bool countWithoutFleet}) {
    if (!counter.special) return true;
    final condition = entry.definition.condition;
    if (fleet == null) return countWithoutFleet;
    if (condition == null) return countWithoutFleet;
    return condition.isMet(fleet);
  }

  void onSortieStart() {
    for (final c in _activeCounters(QuestCounterKind.sortie)) {
      c.add();
    }
  }

  /// api_req_map/start, api_req_map/next ([cell] は api_no、[fleet] は出撃中の艦隊)
  void onMapPoint({
    required int mapId,
    required int eventId,
    required bool isEndPoint,
    int? cell,
    QuestFleet? fleet,
  }) {
    _mapId = mapId;
    _eventId = eventId;
    _cell = cell;
    // 船団護衛成功イベント
    if (eventId == 8) _countBattle(0, isEndPoint, fleet: fleet);
  }

  /// api_req_sortie/battleresult, api_req_combined_battle/battleresult
  void onBattleResult({required String rank, required List<int> sunkEnemyShipTypes, QuestFleet? fleet}) {
    for (final shipType in sunkEnemyShipTypes) {
      for (final c in _activeCounters(QuestCounterKind.slaughter)) {
        if (c.targets?.contains(shipType) ?? false) c.add();
      }
    }
    _countBattle(winRankValue(rank), _eventId == 5, fleet: fleet);
  }

  void _countBattle(int rank, bool isBoss, {QuestFleet? fleet}) {
    final areaId = _mapId ?? -1;
    for (final (entry, c) in _activeEntries(QuestCounterKind.battle)) {
      if (!c.matchesBattle(rank, areaId, isBoss)) continue;
      if (c.gauge != null && !_gaugeMatches(areaId, _cell, c.gauge!)) continue;
      if (!_meetsCondition(entry, c, fleet, countWithoutFleet: true)) continue;
      c.add();
    }
  }

  /// [fleet] は演習した艦隊 (編成条件付きの演習任務は艦隊が分からなければ数えない)
  void onPracticeResult(String rank, {QuestFleet? fleet}) {
    final value = winRankValue(rank);
    for (final (entry, c) in _activeEntries(QuestCounterKind.practice)) {
      if (value < c.minRank) continue;
      if (!_meetsCondition(entry, c, fleet, countWithoutFleet: false)) continue;
      c.add();
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

  /// [secretaryFleet] は第1艦隊 (秘書艦の条件がある工廠任務の判定用)
  void onDiscard(List<DiscardedEquipment> equipments, {QuestFleet? secretaryFleet}) {
    for (final (entry, c) in _activeEntries(QuestCounterKind.discard)) {
      if (!_meetsCondition(entry, c, secretaryFleet, countWithoutFleet: false)) continue;
      final amount = c.discardAmount(equipments);
      if (amount > 0) c.add(amount);
    }
  }

  // ---- 保存 ----

  String encode() => jsonEncode({
        'lastUpdate': lastUpdate?.toUtc().toIso8601String(),
        'states': {for (final e in questStates.entries) '${e.key}': e.value},
        'entries': {for (final e in entries.entries) '${e.key}': e.value.toJson()},
        'allTab': allTab.toJson(),
      });

  static QuestProgressTracker decode(String? jsonString) {
    final tracker = QuestProgressTracker();
    if (jsonString == null) return tracker;
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      tracker.lastUpdate = DateTime.tryParse(json['lastUpdate'] as String? ?? '');
      tracker.allTab = QuestListSnapshot.fromJson(json['allTab']);
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

// ---- 任務の詳細 ----

String _areaText(int area) => '${area ~/ 10}-${area % 10}';

String _enemyTypeText(Set<int> types) {
  if (types.length == 2 && types.containsAll(_carrier)) return repairText('空母', 'carriers');
  return types
      .map((t) => switch (t) {
            15 => repairText('輸送艦', 'transports'),
            13 => repairText('潜水艦', 'submarines'),
            _ => repairText('艦種$t', 'type $t'),
          })
      .join('・');
}

String _winText(int rank) => rank >= 6
    ? ' ${_rankLabel(rank)}${repairText('勝利', '')}'
    : rank >= 2
        ? ' ${_rankLabel(rank)}${repairText('勝利以上', '+')}'
        : '';

/// 条件1つ分の説明 ("2-2 ボス S勝利 1回" など)。[missionName] は遠征IDから遠征名を引く
String questCounterConditionText(QuestCounter c, {String? Function(int missionId)? missionName}) {
  final count = c.max;
  final times = repairText('$count回', '×$count');
  switch (c.kind) {
    case QuestCounterKind.battle:
      final areas = c.areas;
      // あ号作戦の「S勝利」「ボス」などは、ラベルが条件そのもの
      if (c.label.isNotEmpty && areas == null) return '${c.label} $times';
      // 地名の入ったラベル (1-2、1-6終点など) はそのまま使う
      final where = c.label.isNotEmpty
          ? c.label
          : areas == null
              ? repairText('戦闘', 'Battle')
              : (areas.toList()..sort()).map(_areaText).join('・');
      final gauge = c.gauge == null ? '' : repairText(' (第${c.gauge}ゲージ)', ' (gauge ${c.gauge})');
      final boss = c.bossOnly ? repairText(' ボス', ' boss') : '';
      return '$where$gauge$boss${_winText(c.minRank)} $times';
    case QuestCounterKind.slaughter:
      final types = _enemyTypeText(c.targets ?? const <int>{});
      return repairText('敵$typesを撃沈 $count隻', 'Sink $count $types');
    case QuestCounterKind.sortie:
      return '${c.label.isNotEmpty ? c.label : repairText('出撃', 'Sortie')} $times';
    case QuestCounterKind.practice:
      return '${repairText('演習', 'Exercise')}${_winText(c.minRank)} $times';
    case QuestCounterKind.expedition:
      final missions = c.areas;
      final String name;
      if (c.label.isNotEmpty) {
        name = c.label;
      } else if (missions == null) {
        name = repairText('遠征', 'Expedition');
      } else {
        name = (missions.toList()..sort())
            .map((id) => missionName?.call(id) ?? repairText('遠征$id', 'Expedition $id'))
            .join('・');
      }
      return '$name ${repairText('成功', 'success')} $times';
    case QuestCounterKind.docking:
      return '${repairText('入渠', 'Docking')} $times';
    case QuestCounterKind.supply:
      return '${repairText('補給', 'Resupply')} $times';
    case QuestCounterKind.development:
      return '${repairText('装備開発', 'Development')} $times';
    case QuestCounterKind.construction:
      return '${repairText('建造', 'Construction')} $times';
    case QuestCounterKind.destruction:
      return '${repairText('解体', 'Scrap ship')} $times';
    case QuestCounterKind.improvement:
      return '${repairText('装備改修', 'Improvement')} $times';
    case QuestCounterKind.modernization:
      return '${repairText('近代化改修', 'Modernization')} $times';
    case QuestCounterKind.discard:
      final what = c.label.isNotEmpty ? c.label : repairText('装備', 'equipment');
      return c.countsAmount
          ? repairText('$whatを廃棄 $count個', 'Scrap $count $what')
          : repairText('$whatを廃棄 $times', 'Scrap $what $times');
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

// ---- 艦隊タブの「受注中の任務の編成条件」 ----

/// 任務の対象 (1-2・1-3 ボスS、演習 S勝利 など)
String questTargetText(List<QuestCounter> counters) {
  final battles = counters.where((c) => c.kind == QuestCounterKind.battle).toList();
  if (battles.isNotEmpty) {
    final labels = <String>{
      for (final c in battles)
        if (c.label.isNotEmpty)
          c.label
        else
          for (final area in (c.areas ?? const <int>{}).toList()..sort()) '${area ~/ 10}-${area % 10}'
    }.join('・');
    final ranks = battles.map((c) => c.minRank).toSet();
    final boss = battles.every((c) => c.bossOnly);
    if (ranks.length == 1 && ranks.first > 0) {
      return '$labels ${boss ? repairText('ボス', 'boss ') : ''}${_rankLabel(ranks.first)}';
    }
    return labels;
  }
  if (counters.any((c) => c.kind == QuestCounterKind.practice)) {
    final rank = counters.firstWhere((c) => c.kind == QuestCounterKind.practice).minRank;
    return rank > 0 ? repairText('演習 ${_rankLabel(rank)}勝利', 'Exercise ${_rankLabel(rank)}') : repairText('演習', 'Exercise');
  }
  if (counters.any((c) => c.kind == QuestCounterKind.discard)) return repairText('工廠 (秘書艦)', 'Factory (secretary)');
  return '';
}

/// 1件分の表示
class QuestConditionItem {
  final int questId;
  final String title;
  final String target;
  final List<(QuestFleetRequirement, bool)> requirements;

  const QuestConditionItem({
    required this.questId,
    required this.title,
    required this.target,
    required this.requirements,
  });

  bool get isMet => requirements.every((r) => r.$2);
}

/// 受注中の任務のうち、編成条件付きで数える条件が残っているものを [fleet] で判定する。
/// [activeQuests] は任務タブと同じ最新の任務一覧のうち遂行中 (api_state 2) のもの。
/// 保存している任務の状態は使わない (他の端末で破棄・達成した任務が残るため)。
/// 工廠任務 (秘書艦の条件) は第1艦隊のときだけ
List<QuestConditionItem> questConditionItems({
  required QuestFleet fleet,
  required QuestProgressTracker tracker,
  required Iterable<({int id, String? title})> activeQuests,
  DateTime? now,
}) {
  now ??= DateTime.now();
  final titles = {for (final q in activeQuests) q.id: q.title};
  final ids = titles.keys.toList()..sort();
  final items = <QuestConditionItem>[];
  for (final id in ids) {
    final definition = kQuestDefinitions[id];
    final condition = definition?.condition;
    if (definition == null || condition == null) continue;
    final validUntil = definition.validUntil;
    if (validUntil != null && !now.isBefore(validUntil)) continue;
    if (condition.secretary && fleet.fleetNumber != 1) continue;
    final counters = tracker.progressOf(id)?.counters ?? definition.counters();
    final remaining = [
      for (final c in counters)
        if (c.special && !c.isCleared) c
    ];
    if (remaining.isEmpty) continue;
    items.add(QuestConditionItem(
      questId: id,
      title: (titles[id]?.isNotEmpty ?? false) ? titles[id]! : (definition.title ?? repairText('任務 $id', 'Quest $id')),
      target: questTargetText(remaining),
      requirements: [for (final r in condition.requirements) (r, r.isMet(fleet))],
    ));
  }
  return items;
}
