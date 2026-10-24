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

/// おすすめ1件 (レシピ × 秘書艦のまとまり)
class DevSuggestion {
  final DevRecipe recipe;

  /// まとまりの番号 (艦種別なら [devSecretaryGroup]、艦娘別なら艦ID)
  final int group;
  final int tries;
  final int hits;

  const DevSuggestion({required this.recipe, required this.group, required this.tries, required this.hits});

  double get rate => tries == 0 ? 0 : hits / tries;

  /// 並べ替えに使う、確率の控えめな見積もり (95% の Wilson 下限)。試行回数が少ないものを上に来にくくする
  double get score => wilsonLowerBound(hits, tries);
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

/// [itemId] がよく出るレシピ × 秘書艦のまとまり ([groupOf] で決める。-1 は数えない) を、出やすい順に。
/// 試行回数が [minTries] 未満のものは除く (足りなければ [fallbackMinTries] まで下げる)
List<DevSuggestion> devSuggestions(
  DevStats stats,
  int itemId, {
  required int Function(int secretary) groupOf,
  int minTries = 20,
  int fallbackMinTries = 5,
  int limit = 10,
}) {
  final tries = <(DevRecipe, int), int>{};
  final hits = <(DevRecipe, int), int>{};
  for (final row in stats.rows) {
    final group = groupOf(row.secretary);
    if (group < 0) continue;
    final key = (row.recipe, group);
    tries[key] = (tries[key] ?? 0) + row.tries;
    final hit = row.hits[itemId];
    if (hit != null) hits[key] = (hits[key] ?? 0) + hit;
  }
  List<DevSuggestion> pick(int min) => [
        for (final MapEntry(key: key, value: hit) in hits.entries)
          if (tries[key]! >= min) DevSuggestion(recipe: key.$1, group: key.$2, tries: tries[key]!, hits: hit),
      ]..sort((a, b) => b.score.compareTo(a.score));
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
