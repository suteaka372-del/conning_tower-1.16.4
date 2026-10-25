import 'dart:convert';
import 'dart:math';

import 'data_info.dart';
import 'expedition_check.dart';
import 'quest_eo_tracker.dart';
import 'quest_fleet_condition.dart';
import 'repair_timer.dart';

// 装備開発の統計 (どのレシピ・秘書艦で、どの装備が何回出たか)。
// GitHub Actions の「Development stats」ワークフロー (tool/dev_stats/aggregate.mjs) が
// poi の公開データを毎日集計して data ブランチに置いたものを、各端末で取得する
// (providers/dev_stats_provider.dart)。

const kDevStatsUrl =
    'https://raw.githubusercontent.com/suteaka372-del/conning_tower-1.16.4/data/devstats/latest.json';

/// 投入する資材 (燃料・弾薬・鋼材・ボーキサイト)
class DevRecipe {
  final int fuel;
  final int ammo;
  final int steel;
  final int bauxite;

  const DevRecipe(this.fuel, this.ammo, this.steel, this.bauxite);

  String get text => '$fuel/$ammo/$steel/$bauxite';

  @override
  bool operator ==(Object other) =>
      other is DevRecipe &&
      other.fuel == fuel &&
      other.ammo == ammo &&
      other.steel == steel &&
      other.bauxite == bauxite;

  @override
  int get hashCode => Object.hash(fuel, ammo, steel, bauxite);

  @override
  String toString() => text;
}

/// レシピ×秘書艦1隻ぶんの記録
class DevStatRow {
  final DevRecipe recipe;

  /// 秘書艦の艦ID (api_mst_ship の id。改装後は別の ID)
  final int secretary;
  final int tries;

  /// 装備ID → 出た回数
  final Map<int, int> hits;

  const DevStatRow({required this.recipe, required this.secretary, required this.tries, required this.hits});
}

class DevStats {
  /// 集計に使った月 (2026-08 など)
  final List<String> months;
  final DateTime? generated;
  final List<DevStatRow> rows;

  /// 開発の回数 (全体)
  final int totalTries;

  /// 装備ID → 出た回数 (全体)
  final Map<int, int> itemHits;

  DevStats({required this.months, required this.generated, required this.rows})
      : totalTries = rows.fold(0, (sum, r) => sum + r.tries),
        itemHits = _itemHits(rows);

  static Map<int, int> _itemHits(List<DevStatRow> rows) {
    final hits = <int, int>{};
    for (final row in rows) {
      row.hits.forEach((item, count) => hits[item] = (hits[item] ?? 0) + count);
    }
    return hits;
  }

  /// latest.json を読む (形がおかしい行は飛ばす)
  factory DevStats.parse(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    final rows = <DevStatRow>[];
    for (final raw in json['rows'] as List) {
      if (raw is! List || raw.length < 7) continue;
      final numbers = raw.take(6).whereType<int>().toList();
      final hitList = raw[6];
      if (numbers.length < 6 || hitList is! List) continue;
      final hits = <int, int>{};
      for (var i = 0; i + 1 < hitList.length; i += 2) {
        final item = hitList[i];
        final count = hitList[i + 1];
        if (item is int && count is int && item > 0 && count > 0) hits[item] = count;
      }
      rows.add(DevStatRow(
        recipe: DevRecipe(numbers[0], numbers[1], numbers[2], numbers[3]),
        secretary: numbers[4],
        tries: numbers[5],
        hits: hits,
      ));
    }
    return DevStats(
      months: [for (final m in json['months'] as List? ?? const []) '$m'],
      generated: DateTime.tryParse('${json['generated']}'),
      rows: rows,
    );
  }
}

/// [DevStats.parse] を別の Isolate で呼ぶため (compute) の入口
DevStats parseDevStats(String text) => DevStats.parse(text);

/// おすすめの並べ方
enum DevSort {
  /// 目的の装備が出る確率の高い順
  rate,

  /// 1個出すまでに使う釘 (開発資材) の少ない順
  nails,

  /// 1個出すまでに使う資材 (燃料+弾薬+鋼材+ボーキ) の少ない順
  resources;

  String get label => switch (this) {
        rate => repairText('確率', 'Rate'),
        nails => repairText('釘', 'Nails'),
        resources => repairText('資材', 'Resources'),
      };
}

/// おすすめ1件 (レシピ × 秘書艦のまとまり)
class DevSuggestion {
  final DevRecipe recipe;

  /// まとまりの番号 (艦種別なら [devSecretaryGroup]、艦娘別なら艦ID)
  final int group;
  final int tries;

  /// 目的の装備が出た回数
  final int hits;

  /// 開発に成功した回数 (何かの装備が出た回数。失敗はペンギン)
  final int successes;

  const DevSuggestion({
    required this.recipe,
    required this.group,
    required this.tries,
    required this.hits,
    required this.successes,
  });

  double get rate => tries == 0 ? 0 : hits / tries;

  double get successRate => tries == 0 ? 0 : successes / tries;

  /// 1回に使う資材 (失敗しても減る)
  int get cost => recipe.fuel + recipe.ammo + recipe.steel + recipe.bauxite;

  /// 目的の装備1個を出すまでに使う釘の見込み。釘は開発に成功したときだけ1本減る (失敗では減らない)
  double get nailsPerItem => hits == 0 ? double.infinity : successes / hits;

  /// 目的の装備1個を出すまでに使う資材の見込み
  double get resourcesPerItem => hits == 0 ? double.infinity : cost * tries / hits;

  /// 確率の控えめな見積もり (95% の Wilson 下限)。試行回数が少ないものを上に来にくくする
  double get score => wilsonLowerBound(hits, tries);

  /// 並べ替えの値 (小さいほど上)。釘・資材も控えめな確率で見積もる
  double sortKey(DevSort sort) {
    final low = score;
    return switch (sort) {
      DevSort.rate => -low,
      DevSort.nails => low <= 0 ? double.infinity : successRate / low,
      DevSort.resources => low <= 0 ? double.infinity : cost / low,
    };
  }
}

double wilsonLowerBound(int hits, int tries) {
  if (tries <= 0) return 0;
  const z = 1.96;
  final p = hits / tries;
  final n = tries.toDouble();
  final center = p + z * z / (2 * n);
  final margin = z * sqrt(p * (1 - p) / n + z * z / (4 * n * n));
  return max(0, (center - margin) / (1 + z * z / n)); // 0回のとき計算の誤差でわずかに負になるため
}

/// [itemId] が出たレシピ × 秘書艦のまとまり ([groupOf] で決める。-1 は数えない) を [sort] の順に。
/// 試行回数が [minTries] 未満のものは除く (たまたま高く出たものが上に来ないように。
/// 1件も残らなければ [fallbackMinTries] まで下げる)
List<DevSuggestion> devSuggestions(
  DevStats stats,
  int itemId, {
  required int Function(int secretary) groupOf,
  DevSort sort = DevSort.rate,
  int minTries = 100,
  int fallbackMinTries = 20,
  int limit = 10,
}) {
  final tries = <(DevRecipe, int), int>{};
  final successes = <(DevRecipe, int), int>{};
  final hits = <(DevRecipe, int), int>{};
  for (final row in stats.rows) {
    final group = groupOf(row.secretary);
    if (group < 0) continue;
    final key = (row.recipe, group);
    tries[key] = (tries[key] ?? 0) + row.tries;
    var success = 0;
    for (final count in row.hits.values) {
      success += count;
    }
    successes[key] = (successes[key] ?? 0) + success;
    final hit = row.hits[itemId];
    if (hit != null) hits[key] = (hits[key] ?? 0) + hit;
  }
  List<DevSuggestion> pick(int min) => [
        for (final MapEntry(key: key, value: hit) in hits.entries)
          if (tries[key]! >= min)
            DevSuggestion(recipe: key.$1, group: key.$2, tries: tries[key]!, hits: hit, successes: successes[key]!),
      ]..sort((a, b) => a.sortKey(sort).compareTo(b.sortKey(sort)));
  var list = pick(minTries);
  if (list.isEmpty) list = pick(fallbackMinTries);
  return list.take(limit).toList();
}

// ---- 秘書艦のまとまり (艦種 + 国籍) ----

/// 艦種と国籍で決まる番号 (艦種 × 100 + 国籍)。分からない艦は -1。
/// 開発できる装備は秘書艦の艦種で決まり、海外艦は自国の装備が出やすいので国籍でも分ける
int devSecretaryGroup(DataInfo? master, int shipId) {
  final ship = master?.shipInfo?[shipId];
  if (ship == null) return -1;
  final nationality = eoShipNationality(QuestShip(shipId: shipId, shipType: ship.apiStype, sortId: ship.apiSortId));
  return ship.apiStype * 100 + nationality;
}

/// 「正規空母」「駆逐 (アメリカ)」など
String devSecretaryGroupName(int group) {
  final type = expeditionShipTypeName(group ~/ 100);
  final nationality = group % 100;
  if (nationality <= 1) return type; // 日本 (または不明)
  return repairText('$type (${eoNationalityName(nationality)})', '$type (${eoNationalityName(nationality)})');
}

/// 割合の表示 (18.2%)
String devRateText(double rate) => '${(rate * 100).toStringAsFixed(rate >= 0.1 ? 0 : 1)}%';

/// 釘の見込みの表示 (7.2本)
String devNailsText(double nails) => nails.isFinite ? repairText('${nails.toStringAsFixed(1)}本', nails.toStringAsFixed(1)) : '-';

/// 資材の見込みの表示 (1404)
String devResourcesText(double resources) => resources.isFinite ? resources.round().toString() : '-';
