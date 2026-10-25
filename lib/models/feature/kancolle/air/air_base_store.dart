import 'dart:convert';

import 'package:conning_tower/main.dart';
import 'package:flutter/foundation.dart';

/// 基地航空隊の1中隊 (api_plane_info)
class AirBaseSquadron {
  final int id;

  /// 0 = 未配備、1 = 配備済み、2 = 配置転換中
  final int state;

  /// 装備の固有ID (api_slotid)
  final int slotId;
  final int count;
  final int maxCount;
  final int cond;

  const AirBaseSquadron({required this.id, this.state = 0, this.slotId = 0, this.count = 0, this.maxCount = 0, this.cond = 1});

  factory AirBaseSquadron.fromApi(Map json) => AirBaseSquadron(
        id: _int(json['api_squadron_id']) ?? 0,
        state: _int(json['api_state']) ?? 0,
        slotId: _int(json['api_slotid']) ?? 0,
        count: _int(json['api_count']) ?? 0,
        maxCount: _int(json['api_max_count']) ?? 0,
        cond: _int(json['api_cond']) ?? 1,
      );

  Map<String, dynamic> toJson() =>
      {'api_squadron_id': id, 'api_state': state, 'api_slotid': slotId, 'api_count': count, 'api_max_count': maxCount, 'api_cond': cond};
}

/// 基地航空隊1部隊
class AirBaseData {
  final int areaId;
  final int rid;
  final String name;
  final int distance;

  /// 0 = 待機、1 = 出撃、2 = 防空、3 = 退避、4 = 休息
  final int actionKind;
  final List<AirBaseSquadron> squadrons;

  const AirBaseData({
    required this.areaId,
    required this.rid,
    this.name = '',
    this.distance = 0,
    this.actionKind = 0,
    this.squadrons = const [],
  });

  factory AirBaseData.fromApi(Map json) {
    final distance = json['api_distance'];
    return AirBaseData(
      areaId: _int(json['api_area_id']) ?? 0,
      rid: _int(json['api_rid']) ?? 0,
      name: '${json['api_name'] ?? ''}',
      distance: distance is Map ? (_int(distance['api_base']) ?? 0) + (_int(distance['api_bonus']) ?? 0) : (_int(distance) ?? 0),
      actionKind: _int(json['api_action_kind']) ?? 0,
      squadrons: [for (final s in (json['api_plane_info'] as List? ?? const [])) if (s is Map) AirBaseSquadron.fromApi(s)],
    );
  }

  AirBaseData copyWith({String? name, int? distance, int? actionKind, List<AirBaseSquadron>? squadrons}) => AirBaseData(
        areaId: areaId,
        rid: rid,
        name: name ?? this.name,
        distance: distance ?? this.distance,
        actionKind: actionKind ?? this.actionKind,
        squadrons: squadrons ?? this.squadrons,
      );

  Map<String, dynamic> toJson() => {
        'api_area_id': areaId,
        'api_rid': rid,
        'api_name': name,
        'api_distance': distance,
        'api_action_kind': actionKind,
        'api_plane_info': [for (final s in squadrons) s.toJson()],
      };
}

int? _int(dynamic value) => switch (value) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v),
      _ => null,
    };

List<int> _ints(dynamic value) => [for (final s in '${value ?? ''}'.split(',')) if (int.tryParse(s.trim()) != null) int.parse(s.trim())];

/// 基地航空隊の状態をゲームの通信から覚えておく (端末に保存)
class AirBaseStore {
  AirBaseStore({this.load, this.save});

  final String? Function()? load;
  final void Function(String json)? save;

  List<AirBaseData>? _bases;

  /// 状態が変わったら増える
  final ValueNotifier<int> revision = ValueNotifier(0);

  List<AirBaseData> get bases => _bases ??= _read();

  /// [area] 海域の基地航空隊 (番号順)
  List<AirBaseData> basesIn(int area) => [for (final b in bases) if (b.areaId == area) b]..sort((a, b) => a.rid.compareTo(b.rid));

  List<AirBaseData> _read() {
    try {
      final text = load?.call();
      if (text == null || text.isEmpty) return [];
      return [for (final b in jsonDecode(text) as List) if (b is Map) AirBaseData.fromApi(b)];
    } catch (_) {
      return [];
    }
  }

  void _changed(List<AirBaseData> next) {
    _bases = next;
    try {
      save?.call(jsonEncode([for (final b in next) b.toJson()]));
    } catch (_) {}
    revision.value++;
  }

  void _update(int? area, int? rid, AirBaseData Function(AirBaseData base) change) {
    if (area == null || rid == null) return;
    _changed([for (final b in bases) b.areaId == area && b.rid == rid ? change(b) : b]);
  }

  /// ゲームの通信を受け取るたびに呼ぶ
  void onApi(String path, dynamic json, Map<String, dynamic>? params) {
    try {
      final data = json is Map ? json['api_data'] : null;
      switch (path) {
        case '/api_get_member/mapinfo':
          if (data is Map && data['api_air_base'] is List) {
            _changed([for (final b in data['api_air_base'] as List) if (b is Map) AirBaseData.fromApi(b)]);
          }
        case '/api_get_member/base_air_corps':
          if (data is List) _changed([for (final b in data) if (b is Map) AirBaseData.fromApi(b)]);
        case '/api_req_air_corps/set_plane' || '/api_req_air_corps/supply':
          if (data is! Map) return;
          final changed = {
            for (final s in (data['api_plane_info'] as List? ?? const [])) if (s is Map) _int(s['api_squadron_id']): AirBaseSquadron.fromApi(s),
          };
          final distance = data['api_distance'];
          _update(_int(params?['api_area_id']), _int(params?['api_base_id']), (base) {
            final ids = {for (final s in base.squadrons) s.id};
            return base.copyWith(
              distance: distance is Map ? (_int(distance['api_base']) ?? 0) + (_int(distance['api_bonus']) ?? 0) : null,
              squadrons: [
                for (final s in base.squadrons) changed[s.id] ?? s,
                for (final s in changed.values) if (!ids.contains(s.id)) s,
              ],
            );
          });
        case '/api_req_air_corps/set_action':
          final area = _int(params?['api_area_id']);
          final rids = _ints(params?['api_base_id']);
          final kinds = _ints(params?['api_action_kind']);
          for (final (i, rid) in rids.indexed) {
            if (i < kinds.length) _update(area, rid, (base) => base.copyWith(actionKind: kinds[i]));
          }
        case '/api_req_air_corps/change_name':
          final name = params?['api_name'];
          if (name != null) _update(_int(params?['api_area_id']), _int(params?['api_base_id']), (base) => base.copyWith(name: '$name'));
        case '/api_req_air_corps/expand_base':
          if (data is Map && data['api_base_info'] is List) {
            _changed([...bases, for (final b in data['api_base_info'] as List) if (b is Map) AirBaseData.fromApi(b)]);
          }
      }
    } catch (_) {}
  }
}

/// アプリ全体で使う基地航空隊の記録
final AirBaseStore airBaseStore = AirBaseStore(
  load: () => localStorage.getString('air_bases'),
  save: (json) => localStorage.setString('air_bases', json),
);
