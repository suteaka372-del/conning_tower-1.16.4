import 'dart:convert';

import 'data_info.dart';
import 'expedition_check.dart';
import 'quest_fleet_condition.dart';
import 'quest_progress.dart';
import 'repair_timer.dart';

// ElectronicObserver EN の任務トラッカー (QuestTrackers.json / QuestsMetadata.json) を読み込む。
// データの形・数え方・編成条件の判定は ElectronicObserver EN (MIT License,
// Copyright (c) 2014 Andante, Translation work copyright (c) 2015 Ryuu Kitsune)
// https://github.com/ElectronicObserverEN/ElectronicObserver
// Window/Dialog/QuestTrackerManager (Models, ViewModels) から移植。
// データ本体 (https://github.com/ElectronicObserverEN/Data) はライセンスの表示がないので、
// アプリには含めず、各端末で取得する (providers/eo_quest_tracker_provider.dart)。

const kEoQuestTrackersUrl =
    'https://raw.githubusercontent.com/ElectronicObserverEN/Data/master/Data/QuestTrackers.json';
const kEoQuestsMetadataUrl =
    'https://raw.githubusercontent.com/ElectronicObserverEN/Data/master/Data/QuestsMetadata.json';

/// 表示に使うマスターデータ (艦名・装備名など)。KancolleData が作られたときに入る
DataInfo? questMasterData;

// ---- 名前 ----

String questShipName(int shipId) =>
    questMasterData?.shipInfo?[shipId]?.apiName ?? repairText('艦$shipId', 'Ship $shipId');

Object? _classNameSource;
final Map<int, String> _classNames = {};

/// 艦型の名前 (その艦型で図鑑番号が一番若い艦の未改装の名前 + 「型」)
String questShipClassName(int shipClass) {
  final shipInfo = questMasterData?.shipInfo;
  if (shipInfo == null) return repairText('艦型$shipClass', 'Class $shipClass');
  if (!identical(_classNameSource, shipInfo)) {
    _classNames.clear();
    _classNameSource = shipInfo;
  }
  return _classNames.putIfAbsent(shipClass, () {
    questUseShipMaster(shipInfo);
    int? bestId;
    int? bestSort;
    for (final ship in shipInfo.values) {
      final sortNo = ship.apiSortno;
      if (ship.apiCtype != shipClass || sortNo == null || sortNo <= 0) continue;
      if (bestSort == null || sortNo < bestSort) {
        bestSort = sortNo;
        bestId = ship.apiId;
      }
    }
    if (bestId == null) return repairText('艦型$shipClass', 'Class $shipClass');
    return repairText('${questShipName(questBaseShipId(bestId))}型', '${questShipName(questBaseShipId(bestId))} class');
  });
}

String questEquipmentName(int itemId) =>
    questMasterData?.slotItemInfo?[itemId]?.apiName ?? repairText('装備$itemId', 'Equipment $itemId');

String questEquipmentTypeName(int type) =>
    questMasterData?.equipmentTypeNameMap?[type] ?? repairText('装備種別$type', 'Type $type');

const _iconTypeNames = {
  1: '小口径主砲', 2: '中口径主砲', 3: '大口径主砲', 4: '副砲', 5: '魚雷', 6: '艦上戦闘機', 7: '艦上爆撃機', //
  8: '艦上攻撃機', 9: '艦上偵察機', 10: '水上機', 11: '電探', 12: '対空強化弾', 13: '対艦強化弾', 14: '応急修理要員',
  15: '対空機銃', 16: '高角砲', 17: '爆雷', 18: 'ソナー', 19: '機関部強化', 20: '上陸用舟艇', 21: 'オートジャイロ',
  22: '対潜哨戒機', 23: '追加装甲', 24: '探照灯', 25: '簡易輸送部材', 26: '艦艇修理施設', 27: '照明弾', 28: '司令部施設',
  29: '航空要員', 30: '高射装置', 31: '対地装備', 32: '水上艦要員', 33: '大型飛行艇', 34: '戦闘糧食', 35: '補給物資',
  36: '特型内火艇', 37: '陸上攻撃機', 38: '局地戦闘機', 41: '輸送機材', 42: '潜水艦装備', 43: '水上戦闘機',
  44: '陸軍戦闘機', 45: '夜間戦闘機', 46: '夜間攻撃機', 47: '陸上対潜哨戒機', 48: '陸上攻撃機', 49: '重爆撃機', 50: '夜間水上機',
};

String questEquipmentIconTypeName(int icon) =>
    repairText('アイコン「${_iconTypeNames[icon] ?? icon}」の装備', 'icon ${_iconTypeNames[icon] ?? icon}');

const _cardTypeNames = {
  1: '主砲', 2: '副砲', 3: '魚雷', 4: '特殊潜航艇', 5: '艦上機', 6: '対空機銃', 7: '偵察機', 8: '電探', 9: '強化', //
  10: 'ソナー', 14: '大発動艇', 15: 'オートジャイロ',
};

String questEquipmentCardTypeName(int cardType) =>
    repairText('図鑑の分類「${_cardTypeNames[cardType] ?? cardType}」の装備', 'card type ${_cardTypeNames[cardType] ?? cardType}');

const _nationalityNames = {
  1: '日本', 2: 'ドイツ', 3: 'イタリア', 4: 'アメリカ', 5: 'イギリス', 6: 'フランス', //
  7: 'ロシア', 8: 'タイ', 9: 'ノルウェー', 10: 'スウェーデン', 11: 'オランダ', 12: 'オーストラリア',
};

/// 国籍 (ElectronicObserver EN の ShipDataExtensions.Nationality。図鑑の並び順で決まる)
int eoShipNationality(QuestShip ship) => switch (ship.sortId) {
      < 1000 => 0,
      < 30000 => 1,
      < 31000 => 2,
      < 32000 => 3,
      < 33000 => 4,
      < 34000 => 5,
      < 35000 => 6,
      < 36000 => 7,
      < 36060 => 8,
      < 36100 => 9,
      < 37000 => 10,
      < 38000 => 11,
      < 39000 => 12,
      _ => 0,
    };

String _typeNames(Iterable<int> types) =>
    types.map((t) => t == 99 ? repairText('全艦種', 'any type') : expeditionShipTypeName(t)).join('・');

String _countText(int count, int comparison) => switch (comparison) {
      1 => count == 0 ? repairText('なし', 'none') : repairText('ちょうど$count隻', 'exactly $count'),
      2 => repairText('$count隻以下', '$count or fewer'),
      _ => repairText('$count隻以上', '$count or more'),
    };

bool _compare(int value, int count, int comparison) => switch (comparison) {
      1 => value == count,
      2 => value <= count,
      _ => value >= count,
    };

// ---- 編成条件 ----

/// 編成条件1つ (ElectronicObserver EN の ICondition)
abstract class EoCondition {
  bool isMet(QuestFleet fleet);

  String get label;
}

/// 0: GroupConditionModel (AND / OR)
class EoGroupCondition extends EoCondition {
  final bool isOr;
  final List<EoCondition> conditions;

  EoGroupCondition(this.isOr, this.conditions);

  @override
  bool isMet(QuestFleet fleet) {
    if (conditions.isEmpty) return true;
    return isOr ? conditions.any((c) => c.isMet(fleet)) : conditions.every((c) => c.isMet(fleet));
  }

  @override
  String get label {
    // 旗艦の候補を並べただけの OR は「旗艦: A・B・C のどれか」にまとめる
    final flagships = [
      for (final c in conditions)
        if (c is EoShipCondition && c.mustBeFlagship)
          c.shipLabel
        else if (c is EoShipPositionCondition && c.position == 1)
          EoShipCondition(c.shipId, false, c.remodel).shipLabel
    ];
    if (isOr && conditions.length > 1 && flagships.length == conditions.length) {
      return repairText('旗艦: ${flagships.join('・')} のどれか', 'Flagship: one of ${flagships.join(', ')}');
    }
    final parts = [for (final c in conditions) c is EoGroupCondition ? '(${c.label})' : c.label];
    return parts.join(isOr ? repairText(' または ', ' or ') : repairText('、', ', '));
  }
}

/// 1 / 7: ShipConditionModel (V1 / V2)。艦 (改装段階の比べ方つき) と艦型
class EoShipCondition extends EoCondition {
  final int shipId;
  final bool mustBeFlagship;

  /// 0 = 改装問わず, 1 = この改装以上, 2 = この改装のみ
  final int remodel;
  final int shipClass;

  EoShipCondition(this.shipId, this.mustBeFlagship, this.remodel, [this.shipClass = 0]);

  bool get isClassOnly => shipClass != 0 && shipId == 0;

  static bool matches(QuestShip ship, int shipId, int remodel) => switch (remodel) {
        0 => ship.baseShipId == questBaseShipId(shipId),
        1 => ship.isRemodelOf(shipId),
        2 => ship.shipId == shipId,
        _ => false,
      };

  @override
  bool isMet(QuestFleet fleet) {
    final ships = mustBeFlagship ? fleet.ships.take(1).toList() : fleet.ships;
    if (shipClass != 0 && !ships.any((s) => s.shipClass == shipClass)) return false;
    if (shipId == 0) return true;
    return ships.any((s) => matches(s, shipId, remodel));
  }

  /// 艦の名前 (改装の比べ方つき。旗艦は含まない)
  String get shipLabel {
    final parts = <String>[];
    if (shipClass != 0) parts.add(questShipClassName(shipClass));
    if (shipId != 0) {
      parts.add(switch (remodel) {
        1 => repairText('${questShipName(shipId)}以上', '${questShipName(shipId)} or later'),
        2 => repairText('${questShipName(shipId)}のみ', '${questShipName(shipId)} only'),
        _ => questShipName(questBaseShipId(shipId)),
      });
    }
    return parts.join(' ');
  }

  @override
  String get label => mustBeFlagship ? repairText('旗艦: $shipLabel', 'Flagship: $shipLabel') : shipLabel;
}

/// 3 / 8: PartialShipConditionModel (V1 / V2)。挙げた艦のうち何隻以上
class EoPartialShipCondition extends EoCondition {
  final List<EoShipCondition> conditions;
  final int count;
  final bool v2;

  EoPartialShipCondition(this.conditions, this.count, {required this.v2});

  @override
  bool isMet(QuestFleet fleet) {
    if (!v2) return conditions.where((c) => c.isMet(fleet)).length >= count;
    // V2: 艦型だけの条件は、当てはまる艦の数を数える
    final classConditions = conditions.where((c) => c.isClassOnly).toList();
    var matched = 0;
    for (final ship in fleet.ships) {
      final single = QuestFleet(fleet.fleetNumber, [ship]);
      matched += classConditions.where((c) => c.isMet(single)).length;
    }
    matched += conditions.where((c) => !c.isClassOnly && c.isMet(fleet)).length;
    return matched >= count;
  }

  @override
  String get label {
    final names = [for (final c in conditions) c.label].join('・');
    return repairText('$names のうち$count隻以上', '$count or more of $names');
  }
}

/// 2: ShipTypeConditionModel。艦種の数 (旗艦・レベルの条件つき)
class EoShipTypeCondition extends EoCondition {
  final List<int> types;
  final int count;
  final bool mustBeFlagship;
  final int comparison;
  final int level;

  EoShipTypeCondition(this.types, this.count, this.mustBeFlagship, this.comparison, this.level);

  @override
  bool isMet(QuestFleet fleet) {
    final ships = fleet.ships;
    final flagshipOk = !mustBeFlagship || (ships.isNotEmpty && types.contains(ships.first.shipType));
    var valid = types.contains(99) ? ships : ships.where((s) => types.contains(s.shipType));
    if (level > 0) valid = valid.where((s) => s.level >= level);
    return flagshipOk && _compare(valid.length, count, comparison);
  }

  @override
  String get label {
    final names = _typeNames(types);
    final lv = level > 0 ? repairText(' (Lv$level以上)', ' (Lv $level+)') : '';
    final parts = <String>[
      if (mustBeFlagship) repairText('旗艦: $names', 'Flagship: $names'),
      if (!(mustBeFlagship && comparison == 0 && count <= 1 && level == 0)) '$names$lv ${_countText(count, comparison)}',
    ];
    return parts.join(repairText('、', ', '));
  }
}

/// 4: AllowedShipTypesConditionModel。この艦種だけで編成
class EoAllowedShipTypesCondition extends EoCondition {
  final List<int> types;

  EoAllowedShipTypesCondition(this.types);

  @override
  bool isMet(QuestFleet fleet) => fleet.ships.every((s) => types.contains(s.shipType));

  @override
  String get label => repairText('${_typeNames(types)}のみ', 'Only ${_typeNames(types)}');
}

/// 5: ShipPositionConditionModel。何番艦に何の艦
class EoShipPositionCondition extends EoCondition {
  final int shipId;
  final int position;
  final int remodel;

  EoShipPositionCondition(this.shipId, this.position, this.remodel);

  @override
  bool isMet(QuestFleet fleet) {
    final index = position - 1;
    if (index < 0 || index >= fleet.ships.length) return false;
    return EoShipCondition.matches(fleet.ships[index], shipId, remodel);
  }

  @override
  String get label {
    final name = EoShipCondition(shipId, false, remodel).shipLabel;
    return position == 1
        ? repairText('旗艦: $name', 'Flagship: $name')
        : repairText('$position番艦: $name', 'Position $position: $name');
  }
}

/// 6: ShipNationalityConditionModel。国籍の数
class EoShipNationalityCondition extends EoCondition {
  final List<int> nationalities;
  final int count;
  final bool mustBeFlagship;
  final int comparison;

  EoShipNationalityCondition(this.nationalities, this.count, this.mustBeFlagship, this.comparison);

  @override
  bool isMet(QuestFleet fleet) {
    final ships = fleet.ships;
    final flagshipOk =
        !mustBeFlagship || (ships.isNotEmpty && nationalities.contains(eoShipNationality(ships.first)));
    final matched = ships.where((s) => nationalities.contains(eoShipNationality(s))).length;
    return flagshipOk && _compare(matched, count, comparison);
  }

  @override
  String get label {
    final names = nationalities.map((n) => _nationalityNames[n] ?? '$n').join('・');
    final parts = <String>[
      if (mustBeFlagship) repairText('旗艦: $namesの艦', 'Flagship: $names'),
      repairText('$namesの艦 ${_countText(count, comparison)}', '$names ships ${_countText(count, comparison)}'),
    ];
    return parts.join(repairText('、', ', '));
  }
}

// ---- 読み込み ----

/// 形が想定と違うときに投げる (その任務は読み飛ばす)
class _EoFormatException implements Exception {}

int _int(dynamic value) => value is num ? value.toInt() : throw _EoFormatException();

bool _bool(dynamic value) => value is bool ? value : throw _EoFormatException();

List<dynamic> _list(dynamic value) => value is List ? value : throw _EoFormatException();

List<int> _ints(dynamic value) => [for (final v in _list(value)) _int(v)];

int _at(List<dynamic> list, int index, [int fallback = 0]) => index < list.length ? _int(list[index]) : fallback;

/// 海域 [area, info] -> エリア*10+番号
int _map(dynamic value) {
  final list = _list(value);
  return _int(list[0]) * 10 + _int(list[1]);
}

EoShipCondition _shipCondition(dynamic value, {required bool v2}) {
  final list = _list(value);
  return EoShipCondition(_int(list[0]), _bool(list[1]), _at(list, 2), v2 ? _at(list, 3) : 0);
}

/// 条件 [種類, 中身]。null (EO でも無視される) は null
EoCondition? _condition(dynamic value) {
  if (value == null) return null;
  final union = _list(value);
  final kind = _int(union[0]);
  final body = _list(union[1]);
  return switch (kind) {
    0 => _group(body),
    1 => _shipCondition(body, v2: false),
    2 => EoShipTypeCondition(_ints(body[0]), _int(body[1]), _bool(body[2]), _at(body, 3), _at(body, 4)),
    3 => EoPartialShipCondition([for (final c in _list(body[0])) _shipCondition(c, v2: false)], _int(body[1]), v2: false),
    4 => EoAllowedShipTypesCondition(_ints(body[0])),
    5 => EoShipPositionCondition(_int(body[0]), _int(body[1]), _at(body, 2)),
    6 => EoShipNationalityCondition(_ints(body[0]), _int(body[1]), _bool(body[2]), _at(body, 3)),
    7 => _shipCondition(body, v2: true),
    8 => EoPartialShipCondition([for (final c in _list(body[0])) _shipCondition(c, v2: true)], _int(body[1]), v2: true),
    _ => throw _EoFormatException(), // 知らない種類の条件
  };
}

EoGroupCondition _group(List<dynamic> body) => EoGroupCondition(
      _int(body[0]) == 1,
      [
        for (final c in _list(body[1]))
          if (_condition(c) case final condition?) condition
      ],
    );

/// タスク [種類, 中身] -> カウンタを作る関数 ([special] は編成条件を満たすときだけ数える)
QuestCounter Function() _task(dynamic value, {required bool special}) {
  if (value == null) throw _EoFormatException(); // 中身の分からないタスク
  final union = _list(value);
  final kind = _int(union[0]);
  final body = _list(union[1]);
  int count(int index) => _int(body[index]).clamp(1, 1 << 30);
  String name(int index) => index < body.length && body[index] is String ? body[index] as String : '';
  switch (kind) {
    case 0: // BossKill [map, rank, count]
      final map = _map(body[0]);
      final rank = _int(body[1]);
      final max = count(2);
      return () => QuestCounter(QuestCounterKind.bossBattle, max, areas: {map}, minRank: rank, special: special);
    case 1: // Expedition [[missionId], count]
      final mission = _int(_list(body[0])[0]);
      final max = count(1);
      return () => QuestCounter(QuestCounterKind.expedition, max, areas: {mission}, special: special);
    case 2: // BattleNodeId [map, rank, count, nodes, name]
      final map = _map(body[0]);
      final rank = _int(body[1]);
      final max = count(2);
      final cells = _ints(body[3]).toSet();
      final label = name(4);
      return () => QuestCounter(QuestCounterKind.nodeBattle, max,
          areas: {map}, minRank: rank, cells: cells, label: label, special: special);
    case 3 || 4 || 5 || 6: // 装備の廃棄 (装備ID / カテゴリ / 図鑑の分類 / アイコン) [値, count]
      final target = _int(body[0]);
      final max = count(1);
      final index = switch (kind) { 3 => -1, 4 => 2, 5 => 1, _ => 3 };
      return () =>
          QuestCounter(QuestCounterKind.discard, max, targets: {target}, categoryIndex: index, countsAmount: true);
    case 7: // NodeReach [map, count, nodes, name]
      final map = _map(body[0]);
      final max = count(1);
      final cells = _ints(body[2]).toSet();
      final label = name(3);
      return () =>
          QuestCounter(QuestCounterKind.nodeReach, max, areas: {map}, cells: cells, label: label, special: special);
    case 8: // MapFirstClear [map, count]
      final map = _map(body[0]);
      final max = count(1);
      return () => QuestCounter(QuestCounterKind.mapFirstClear, max, areas: {map}, special: special);
    case 9: // Exercise [rank, count]
      final rank = _int(body[0]);
      final max = count(1);
      return () => QuestCounter(QuestCounterKind.practice, max, minRank: rank, special: special);
  }
  throw _EoFormatException(); // 知らない種類のタスク
}

/// 編成条件 (EO のトラッカー全体の条件) を、艦隊タブ・任務の詳細で使う形にする。
/// いちばん外が AND なら1つずつ、OR ならまとめて1項目にする
QuestFleetCondition? _fleetCondition(EoGroupCondition root) {
  if (root.conditions.isEmpty) return null;
  final items = root.isOr ? <EoCondition>[root] : root.conditions;
  return QuestFleetCondition([
    for (final c in items) QuestFleetRequirement.lazy(() => c.label, c.isMet),
  ]);
}

/// 1件分のトラッカー [[questId], [tasks], [op, [conditions]]] を定義にする。
/// タスクがない・読めないものは null (組み込みの定義を使う)
QuestDefinition? parseEoQuestTracker(dynamic value) {
  try {
    final tracker = _list(value);
    final id = _int(_list(tracker[0])[0]);
    final tasks = _list(tracker[1]);
    if (tasks.isEmpty) return null;
    final root = tracker.length > 2 && tracker[2] != null ? _group(_list(tracker[2])) : EoGroupCondition(false, []);
    final condition = _fleetCondition(root);
    final hasCondition = condition != null;
    final factories = [
      for (final task in tasks) _task(task, special: hasCondition),
    ];
    return QuestDefinition(
      id,
      () => [for (final make in factories) make()],
      weightedEqually: factories.length > 1, // EO は条件ごとの割合の平均
      fromEo: true,
      eoCondition: condition,
    );
  } catch (_) {
    return null;
  }
}

/// QuestTrackers.json を読む。読めない任務は飛ばす (全部読めなければ空)
/// 先頭の BOM (EF BB BF) を除いて JSON を読む。EO EN のデータは BOM 付きの UTF-8 で、そのままでは jsonDecode が失敗する
dynamic decodeEoJson(String json) => jsonDecode(json.startsWith('\uFEFF') ? json.substring(1) : json);

Map<int, QuestDefinition> parseEoQuestTrackers(String json) {
  final decoded = decodeEoJson(json);
  if (decoded is! List) return {};
  return {
    for (final tracker in decoded)
      if (parseEoQuestTracker(tracker) case final definition?) definition.id: definition
  };
}

/// QuestsMetadata.json を読む (任務ID -> リセットの種類)
Map<int, int> parseEoQuestsMetadata(String json) {
  final decoded = decodeEoJson(json);
  if (decoded is! List) return {};
  return {
    for (final item in decoded)
      if (item is Map && item['id'] is int && item['resetType'] is int) item['id'] as int: item['resetType'] as int
  };
}

/// 読み込んだ定義を使うようにする (組み込みの定義より優先)
void applyEoQuestTrackers(Map<int, QuestDefinition> definitions, Map<int, int> resetTypes) {
  kEoQuestDefinitions
    ..clear()
    ..addAll(definitions);
  kEoQuestResetTypes
    ..clear()
    ..addAll(resetTypes);
}
