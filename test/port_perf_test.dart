import 'dart:convert';

import 'package:conning_tower/models/data/kcsapi/kcsapi.dart';
import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/equipment.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/raw_data.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const shipCount = 500;
const masterCount = 1500;

Map<String, dynamic> shipJson(int uid, int shipId) => {
      'api_id': uid, 'api_sortno': shipId, 'api_ship_id': shipId, 'api_lv': 99, 'api_exp': [0, 100, 0],
      'api_nowhp': 15, 'api_maxhp': 15, 'api_soku': 10, 'api_leng': 1,
      'api_slot': [uid * 10, uid * 10 + 1, -1, -1, -1], 'api_onslot': [0, 0, 0, 0, 0], 'api_slot_ex': 0,
      'api_kyouka': [0, 0, 0, 0, 0, 0, 0], 'api_backs': 2, 'api_fuel': 15, 'api_bull': 20, 'api_slotnum': 2,
      'api_ndock_time': 0, 'api_ndock_item': [0, 0], 'api_srate': 0, 'api_cond': 49,
      'api_karyoku': [12, 29], 'api_raisou': [27, 69], 'api_taiku': [14, 39], 'api_soukou': [5, 19],
      'api_kaihi': [41, 79], 'api_taisen': [20, 49], 'api_sakuteki': [5, 19], 'api_lucky': [10, 49],
      'api_locked': 1, 'api_locked_equip': 0, 'api_sally_area': 0,
    };

String portJson() => jsonEncode({
      'api_result': 1,
      'api_result_msg': '成功',
      'api_data': {
        'api_material': [for (var i = 1; i <= 8; i++) {'api_member_id': 1, 'api_id': i, 'api_value': 1000}],
        'api_deck_port': [
          for (var d = 1; d <= 4; d++)
            {
              'api_member_id': 1, 'api_id': d, 'api_name': '第$d艦隊', 'api_name_id': '', 'api_mission': [0, 0, 0, 0],
              'api_flagship': '0', 'api_ship': [for (var i = 0; i < 6; i++) (d - 1) * 6 + i + 1],
            }
        ],
        'api_ndock': [
          for (var i = 1; i <= 4; i++)
            {
              'api_member_id': 1, 'api_id': i, 'api_state': 0, 'api_ship_id': 0, 'api_complete_time': 0,
              'api_complete_time_str': '0', 'api_item1': 0, 'api_item2': 0, 'api_item3': 0, 'api_item4': 0,
            }
        ],
        'api_ship': [for (var i = 1; i <= shipCount; i++) shipJson(i, 1 + (i * 7) % masterCount)],
        'api_basic': {
          'api_member_id': '1', 'api_nickname': '', 'api_nickname_id': '1', 'api_active_flag': 1,
          'api_starttime': 0, 'api_level': 120, 'api_rank': 1, 'api_experience': 0, 'api_fleetname': null,
          'api_comment': '', 'api_comment_id': '', 'api_max_chara': 600, 'api_max_slotitem': 2000, 'api_max_kagu': 0,
          'api_playtime': 0, 'api_tutorial': 0, 'api_furniture': [1, 2, 3, 4, 5, 6], 'api_count_deck': 4,
          'api_count_kdock': 4, 'api_count_ndock': 4, 'api_fcoin': 0, 'api_st_win': 0, 'api_st_lose': 0,
          'api_ms_count': 0, 'api_ms_success': 0, 'api_pt_win': 0, 'api_pt_lose': 0, 'api_pt_challenged': 0,
          'api_pt_challenged_win': 0, 'api_firstflag': 1, 'api_tutorial_progress': 100, 'api_pvp': [0, 0],
          'api_medals': 0, 'api_large_dock': 1,
        },
        'api_log': [
          for (var i = 0; i < 4; i++) {'api_no': i, 'api_type': '1', 'api_state': '0', 'api_message': 'log'}
        ],
        'api_p_bgm_id': 1,
        'api_parallel_quest_count': 5,
      },
    });

/// 艦のマスターデータ: 3段階の改造 (n → n+1 → n+2)
Map<int, GetDataApiDataApiMstShipEntity> masterShips() => {
      for (var id = 1; id <= masterCount; id++)
        id: GetDataApiDataApiMstShipEntity(
          apiId: id,
          apiSortId: id,
          apiSortno: id,
          apiName: '艦$id',
          apiYomi: '',
          apiStype: 2,
          apiCtype: 0,
          apiAftershipid: id % 3 == 0 || id == masterCount ? '0' : '${id + 1}',
          apiAfterlv: 20,
        ),
    };

KancolleData data(Ref ref) {
  final info = DataInfo(shipInfo: masterShips());
  info.initShipUpgradeMap();
  return KancolleData(
    queue: OperationQueue(map: {}),
    squads: [],
    seaForceBase: SeaForceBase(
      resource: const SeaForceBaseResource(
          fuel: 0,
          ammo: 0,
          steel: 0,
          bauxite: 0,
          instantCreateShip: 0,
          instantRepairs: 0,
          developmentMaterials: 0,
          improvementMaterials: 0),
      admiral: const Admiral(name: '', level: 1, rank: 10, maxShip: 0, maxItem: 0),
    ),
    fleet: Fleet(ships: [], equipment: {}),
    ref: ref,
    dataInfo: info,
    battleInfo: BattleInfo(),
  );
}

void main() {
  // 母港 (艦500隻・艦のマスター1500件) の読み込み。PC で 29ms → 6ms (うち 22ms が「未所持の艦」の数え直しだった)
  test('port with 500 ships: fleet, squads and ships not owned', () {
    final text = portJson();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final d = container.read(Provider(data));
    final raw = RawData(source: 'local/kcsapi/api_port/port', data: text, timestamp: 0);
    d.parse(raw);
    expect(d.fleet.ships.length, shipCount);
    expect(d.squads.length, 4);
    expect(d.squads.first.ships.map((s) => s.uid), [1, 2, 3, 4, 5, 6]);

    // 以前の数え方 (改造の系統のどれも持っていない艦) と同じ結果になる
    final owned = {for (final s in d.fleet.ships) s.shipId};
    final expected = {
      for (final e in d.dataInfo.shipUpgradeMap!.entries)
        if (!owned.contains(e.key) && !e.value.any(owned.contains)) e.key,
    };
    expect(d.fleet.notInFleetIds, expected);
    expect(expected, isNotEmpty);
    expect(expected.length, lessThan(d.dataInfo.shipUpgradeMap!.length));

    final sw = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      d.parse(raw);
    }
    // 目安: 以前は1回 29ms。遅いPCでも余裕がある上限にしておく
    expect(sw.elapsedMilliseconds / 10, lessThan(25));
  });

  test('equipment collections walk the equipment list only once', () {
    var created = 0;
    final source = [for (var i = 1; i <= 2000; i++) (id: i, itemId: 1 + i % 400)];
    // ゲームのデータから作りながら読む一覧 (読むたびに作り直される)
    final equipments = source.map((e) {
      created++;
      return Equipment(id: e.id, itemId: e.itemId, sortNo: e.itemId, type: [1, 1, 1, 1, 0], name: '装備${e.itemId}');
    });
    final fleet = Fleet(ships: [], equipment: {});
    fleet.initEquipmentCollections(equipments);
    expect(created, 2000);
    expect(fleet.equipmentCollections!.length, 400);
    expect(fleet.equipmentCollections![1]!.equipments.map((e) => e.id), [400, 800, 1200, 1600, 2000]);
    expect(fleet.equipmentCollections![2]!.name, '装備2');
  });
}
