import 'dart:convert';
import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

import 'repair_timer.dart';
import 'ship.dart';

/// 艦娘一覧のフィルター・並び替えに使う値
enum ShipStat {
  level('Lv', 'Lv'),
  condition('Cond', 'Cond'),
  baseAsw('基本対潜', 'Base ASW'),
  asw('対潜', 'ASW'),
  firepower('火力', 'Firepower'),
  torpedo('雷装', 'Torpedo'),
  nightPower('夜戦火力', 'Night power'),
  aa('対空', 'AA'),
  armor('装甲', 'Armor'),
  evasion('回避', 'Evasion'),
  los('索敵', 'LoS'),
  luck('運', 'Luck'),
  maxHP('耐久', 'HP');

  const ShipStat(this.labelJa, this.labelEn);

  final String labelJa;
  final String labelEn;

  String get label => repairText(labelJa, labelEn);

  int valueOf(Ship ship) => switch (this) {
        ShipStat.level => ship.level,
        ShipStat.condition => ship.condition ?? 0,
        ShipStat.baseAsw => baseAswOf(ship),
        ShipStat.asw => ship.antiSubmarine?.firstOrNull ?? 0,
        ShipStat.firepower => ship.attack?.firstOrNull ?? 0,
        ShipStat.torpedo => ship.attackT?.firstOrNull ?? 0,
        ShipStat.nightPower => (ship.attack?.firstOrNull ?? 0) + (ship.attackT?.firstOrNull ?? 0),
        ShipStat.aa => ship.antiAircraft?.firstOrNull ?? 0,
        ShipStat.armor => ship.armor?.firstOrNull ?? 0,
        ShipStat.evasion => ship.evasion?.firstOrNull ?? 0,
        ShipStat.los => ship.scout?.firstOrNull ?? 0,
        ShipStat.luck => ship.luck?.firstOrNull ?? 0,
        ShipStat.maxHP => ship.maxHP,
      };

  /// 装備の対潜値を除いた対潜 (EO の基本対潜)
  static int baseAswOf(Ship ship) {
    final total = ship.antiSubmarine?.firstOrNull ?? 0;
    final equip = [...?ship.equipment, ...?ship.exEquipment].fold<int>(0, (sum, eq) => sum + (eq.asw ?? 0));
    return total - equip;
  }
}

enum CompareOp {
  gte('以上', 'or more'),
  lte('以下', 'or less'),
  eq('と等しい', 'equals');

  const CompareOp(this.labelJa, this.labelEn);

  final String labelJa;
  final String labelEn;

  String get label => repairText(labelJa, labelEn);

  bool test(int left, int right) => switch (this) {
        CompareOp.gte => left >= right,
        CompareOp.lte => left <= right,
        CompareOp.eq => left == right,
      };
}

class StatCondition {
  final ShipStat stat;
  final CompareOp op;
  final int value;

  const StatCondition({required this.stat, required this.op, required this.value});

  bool matches(Ship ship) => op.test(stat.valueOf(ship), value);

  String get text => repairText('${stat.label} $value${op.label}', '${stat.label} ${op.label} $value');

  Map<String, dynamic> toJson() => {'stat': stat.name, 'op': op.name, 'value': value};

  static StatCondition? fromJson(Map<String, dynamic> json) {
    final stat = ShipStat.values.where((e) => e.name == json['stat']).firstOrNull;
    final op = CompareOp.values.where((e) => e.name == json['op']).firstOrNull;
    final value = json['value'];
    if (stat == null || op == null || value is! int) return null;
    return StatCondition(stat: stat, op: op, value: value);
  }
}

/// 並び替えのキー1つ分
class SortKey {
  final ShipStat stat;
  final bool descending;

  const SortKey(this.stat, {this.descending = true});

  String get text => repairText('${stat.label} ${descending ? "降順" : "昇順"}', '${stat.label} ${descending ? "desc" : "asc"}');

  Map<String, dynamic> toJson() => {'stat': stat.name, 'descending': descending};

  static SortKey? fromJson(Map<String, dynamic> json) {
    final stat = ShipStat.values.where((e) => e.name == json['stat']).firstOrNull;
    if (stat == null) return null;
    return SortKey(stat, descending: json['descending'] != false);
  }
}

/// 保存できるフィルター (艦種 + 値の条件 最大3つ + 並び替え 最大3つ)
class ShipFilterPreset {
  static const int maxConditions = 3;
  static const int maxSortKeys = 3;

  final String name;

  /// api_stype の ID。空なら全艦種
  final List<int> shipTypes;
  final List<StatCondition> conditions;

  /// 並び替え。先頭から順に比べ、同じ値なら次のキーで比べる (エクセルの並べ替えと同じ)
  final List<SortKey> sortKeys;

  const ShipFilterPreset({
    required this.name,
    this.shipTypes = const [],
    this.conditions = const [],
    this.sortKeys = const [SortKey(ShipStat.level)],
  });

  bool matches(Ship ship) {
    if (shipTypes.isNotEmpty && !shipTypes.contains(ship.shipType)) return false;
    return conditions.every((c) => c.matches(ship));
  }

  int compare(Ship a, Ship b) {
    for (final key in sortKeys) {
      final compare = key.stat.valueOf(a).compareTo(key.stat.valueOf(b));
      if (compare != 0) return key.descending ? -compare : compare;
    }
    return a.uid.compareTo(b.uid);
  }

  List<Ship> apply(Iterable<Ship> ships) => ships.where(matches).toList()..sort(compare);

  /// 一覧に表示する値 (並び替え + 条件の値、重複なし)
  List<ShipStat> get displayStats => {...sortKeys.map((k) => k.stat), ...conditions.map((c) => c.stat)}.toList();

  String get sortText => sortKeys.map((k) => k.text).join(' → ');

  Map<String, dynamic> toJson() => {
        'name': name,
        'shipTypes': shipTypes,
        'conditions': conditions.map((c) => c.toJson()).toList(),
        'sortKeys': sortKeys.map((k) => k.toJson()).toList(),
      };

  static ShipFilterPreset? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String) return null;
    final shipTypes = (json['shipTypes'] as List?)?.whereType<int>().toList() ?? [];
    final conditions = (json['conditions'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(StatCondition.fromJson)
            .whereType<StatCondition>()
            .take(maxConditions)
            .toList() ??
        [];
    var sortKeys = (json['sortKeys'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(SortKey.fromJson)
            .whereType<SortKey>()
            .take(maxSortKeys)
            .toList() ??
        [];
    if (sortKeys.isEmpty) {
      // 以前の形式 (並び替え1つ)
      final stat = ShipStat.values.where((e) => e.name == json['sortStat']).firstOrNull ?? ShipStat.level;
      sortKeys = [SortKey(stat, descending: json['descending'] != false)];
    }
    return ShipFilterPreset(
      name: name,
      shipTypes: shipTypes,
      conditions: conditions,
      sortKeys: sortKeys,
    );
  }
}

const int _kShipTypeDestroyer = 2;

final List<ShipFilterPreset> kDefaultShipFilterPresets = [
  ShipFilterPreset(
    name: repairText('駆逐 基本対潜50', 'DD Base ASW 50'),
    shipTypes: const [_kShipTypeDestroyer],
    conditions: const [StatCondition(stat: ShipStat.baseAsw, op: CompareOp.gte, value: 50)],
    sortKeys: const [SortKey(ShipStat.condition)],
  ),
  ShipFilterPreset(
    name: repairText('駆逐 基本対潜64', 'DD Base ASW 64'),
    shipTypes: const [_kShipTypeDestroyer],
    conditions: const [StatCondition(stat: ShipStat.baseAsw, op: CompareOp.gte, value: 64)],
    sortKeys: const [SortKey(ShipStat.condition)],
  ),
];

/// フィルターの保存・読み込み (端末内 SharedPreferences)
class ShipFilterStore {
  static const String _key = 'KC_SHIP_FILTER_PRESETS';

  static List<ShipFilterPreset> decode(String? jsonString) {
    if (jsonString == null) return [...kDefaultShipFilterPresets];
    try {
      final list = jsonDecode(jsonString);
      if (list is! List) return [...kDefaultShipFilterPresets];
      return list.whereType<Map<String, dynamic>>().map(ShipFilterPreset.fromJson).whereType<ShipFilterPreset>().toList();
    } catch (e) {
      log('ShipFilterStore decode failed: $e');
      return [...kDefaultShipFilterPresets];
    }
  }

  static String encode(List<ShipFilterPreset> presets) => jsonEncode(presets.map((e) => e.toJson()).toList());

  static Future<List<ShipFilterPreset>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return decode(prefs.getString(_key));
  }

  static Future<void> save(List<ShipFilterPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, encode(presets));
  }
}
