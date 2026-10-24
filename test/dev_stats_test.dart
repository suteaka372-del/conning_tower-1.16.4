import 'dart:convert';

import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/data/kcsapi/start2/get_data_entity.dart';
import 'package:conning_tower/models/feature/kancolle/battle_info.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/data_info.dart';
import 'package:conning_tower/models/feature/kancolle/dev_stats.dart';
import 'package:conning_tower/models/feature/kancolle/fleet.dart';
import 'package:conning_tower/models/feature/kancolle/operation_queue.dart';
import 'package:conning_tower/models/feature/kancolle/quest_eo_tracker.dart';
import 'package:conning_tower/models/feature/kancolle/sea_force_base.dart';
import 'package:conning_tower/models/feature/kancolle/ship.dart';
import 'package:conning_tower/models/feature/kancolle/squad.dart';
import 'package:conning_tower/pages/dashboard_pages/development_page.dart';
import 'package:conning_tower/providers/dev_stats_provider.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 艦ID: 赤城 83 / 加賀 84 (正規空母・日本)、Intrepid 900 (正規空母・アメリカ)、吹雪 9 (駆逐)
const _akagi = 83, _kaga = 84, _intrepid = 900, _fubuki = 9;
// 装備ID: 烈風 22、F6F-3 900、12.7cm連装砲 2
const _reppu = 22, _f6f = 900, _gun = 2;

GetDataApiDataApiMstShipEntity _ship(int id, String name, int stype, int sortId) => GetDataApiDataApiMstShipEntity(
      apiId: id,
      apiSortId: sortId,
      apiName: name,
      apiYomi: '',
      apiStype: stype,
      apiCtype: 1,
    );

GetDataApiDataApiMstSlotitemEntity _item(int id, String name, int category) => GetDataApiDataApiMstSlotitemEntity(
      apiId: id, apiSortno: id, apiName: name, apiType: [0, 0, category, 0, 0], //
      apiTaik: 0, apiSouk: 0, apiHoug: 0, apiRaig: 0, apiSoku: 0, apiBaku: 0, apiTyku: 0, apiTais: 0, apiAtap: 0,
      apiHoum: 0, apiRaim: 0, apiHouk: 0, apiRaik: 0, apiBakk: 0, apiSaku: 0, apiSakb: 0, apiLuck: 0, apiLeng: 0,
      apiRare: 0, apiBroken: [0, 0, 0, 0], apiUsebull: '0',
    );

final _master = DataInfo(
  shipInfo: {
    _akagi: _ship(_akagi, '赤城', 11, 1100),
    _kaga: _ship(_kaga, '加賀', 11, 1110),
    _intrepid: _ship(_intrepid, 'Intrepid', 11, 32010),
    _fubuki: _ship(_fubuki, '吹雪', 2, 1010),
  },
  slotItemInfo: {
    _reppu: _item(_reppu, '烈風', 6),
    _f6f: _item(_f6f, 'F6F-3', 6),
    _gun: _item(_gun, '12.7cm連装砲', 1),
  },
  equipmentTypeNameMap: {1: '小口径主砲', 6: '艦上戦闘機'},
);

/// [燃, 弾, 鋼, ボ, 秘書艦, 試行, [装備, 回数...]]
const _json = '''
{"v":1,"months":["2026-09","2026-10"],"generated":"2026-10-24T17:00:00Z","rows":[
 [20,60,10,110,83,100,[22,10]],
 [20,60,10,110,84,81,[22,8]],
 [40,60,10,100,83,1,[22,1]],
 [20,60,10,110,900,60,[900,12,22,1]],
 [10,10,10,10,9,500,[2,150]],
 [10,10,10,10,83,40,[]],
 "broken",
 [10,10,10]
]}''';

void main() {
  setUp(() => Intl.defaultLocale = 'ja');

  test('reads the published file, skipping broken rows', () {
    final stats = DevStats.parse(_json);
    expect(stats.months, ['2026-09', '2026-10']);
    expect(stats.generated, DateTime.utc(2026, 10, 24, 17));
    expect(stats.rows.length, 6);
    expect(stats.totalTries, 100 + 81 + 1 + 60 + 500 + 40);
    expect(stats.itemHits, {_reppu: 10 + 8 + 1 + 1, _f6f: 12, _gun: 150});
    expect(stats.rows.first.recipe, const DevRecipe(20, 60, 10, 110));
  });

  test('few tries give a cautious estimate', () {
    // 1回で出ても 100% とは見なさない (さらに試行回数の少ないものは devSuggestions で除く)
    expect(wilsonLowerBound(1, 1), lessThan(0.25));
    expect(wilsonLowerBound(18, 181), inInclusiveRange(0.06, 0.1));
    // 同じ割合なら回数が多いほうが上
    expect(wilsonLowerBound(20, 200), greaterThan(wilsonLowerBound(2, 20)));
    expect(wilsonLowerBound(0, 10), 0);
    expect(wilsonLowerBound(10, 10), greaterThan(0.6));
  });

  test('suggestions by secretary type (and nationality) and by ship', () {
    final stats = DevStats.parse(_json);
    final byGroup = devSuggestions(stats, _reppu, groupOf: (id) => devSecretaryGroup(_master, id));
    // 赤城と加賀は同じ「正規空母 (日本)」にまとまる。1回だけの記録は試行回数が足りないので出ない
    expect(byGroup.first.recipe, const DevRecipe(20, 60, 10, 110));
    expect(byGroup.first.group, 1101);
    expect(byGroup.first.tries, 181);
    expect(byGroup.first.hits, 18);
    expect(byGroup.map((s) => s.recipe), isNot(contains(const DevRecipe(40, 60, 10, 100))));
    expect(devSecretaryGroupName(1101), '正規空母');
    expect(devSecretaryGroupName(byGroup[1].group), '正規空母 (アメリカ)');

    // 海外の艦上戦闘機はアメリカの空母で
    final f6f = devSuggestions(stats, _f6f, groupOf: (id) => devSecretaryGroup(_master, id));
    expect(f6f.single.group, 1104);
    expect(devRateText(f6f.single.rate), '20%');

    // 艦娘別: 試行回数の足りないものは除く
    final byShip = devSuggestions(stats, _reppu, groupOf: (id) => id, minTries: 30);
    expect(byShip.map((s) => s.group), [_akagi, _kaga, _intrepid]);
    expect(devRateText(byShip.last.rate), '1.7%');

    // 数が少ない装備は、条件を下げて出す
    final rare = devSuggestions(stats, _reppu, groupOf: (id) => id, minTries: 1000, fallbackMinTries: 1);
    expect(rare, isNotEmpty);
  });

  test('equipment list: filter by name, sorted by kind', () {
    questMasterData = _master;
    final stats = DevStats.parse(_json);
    expect(devItemsMatching(stats, ''), [_gun, _reppu, _f6f]);
    expect(devItemsMatching(stats, '烈'), [_reppu]);
    expect(devItemsMatching(stats, 'f6f'), [_f6f]);
    expect(devItemsMatching(stats, 'なし'), isEmpty);
  });

  testWidgets('detail page: best recipes, ships you have, current secretary', (tester) async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(402, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    DevStatsLoader.stats = DevStats.parse(_json);
    DevStatsLoader.updatedAt = DateTime(2026, 10, 25);
    addTearDown(() {
      DevStatsLoader.stats = null;
      DevStatsLoader.updatedAt = null;
    });

    var uid = 1;
    Ship ship(int shipId, String name, int level) => Ship(
          uid: uid++,
          shipId: shipId,
          name: name,
          level: level,
          nowHP: 30,
          maxHP: 30,
          shipType: _master.shipInfo![shipId]!.apiStype,
          condition: 49,
          attack: [0, 0],
          antiAircraft: [0, 0],
          antiSubmarine: [0, 0],
          scout: [0, 0],
          equipment: const [],
          onSlot: const [],
        );
    final kaga = ship(_kaga, '加賀', 99);
    final fubuki = ship(_fubuki, '吹雪', 50);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        kancolleDataProvider.overrideWith((ref) => KancolleData(
              queue: OperationQueue(map: {}),
              squads: [
                Squad(id: 1, name: '第1艦隊', ships: [fubuki]),
              ],
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
              fleet: Fleet(ships: [kaga, fubuki], equipment: {}),
              ref: ref,
              dataInfo: _master,
              battleInfo: BattleInfo(),
            )),
      ],
      child: const CupertinoApp(home: DevItemDetailPage(itemId: _reppu)),
    ));
    await tester.pump();

    expect(find.text('烈風'), findsOneWidget);
    expect(find.text('今の秘書艦: 吹雪 (駆逐)'), findsOneWidget);
    expect(find.text('燃20 弾60 鋼10 ボ110'), findsWidgets);
    expect(find.text('10%'), findsOneWidget); // 正規空母 18/181
    expect(find.text('18/181回'), findsOneWidget);
    expect(find.textContaining('持っている艦: 加賀 Lv99'), findsOneWidget);
    expect(find.textContaining('持っている艦: なし'), findsOneWidget); // アメリカの空母
    expect(find.text('加賀 ✓'), findsOneWidget);
    expect(find.text('赤城'), findsOneWidget);
    expect(find.textContaining('poi の統計 2026-09〜2026-10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('published file round trip (same shape as tool/dev_stats/aggregate.mjs)', () {
    final text = jsonEncode({
      'v': 1,
      'months': ['2026-10'],
      'generated': '2026-10-24T17:00:00.000Z',
      'rows': [
        [10, 30, 90, 10, 400, 3, [46, 2]],
      ],
    });
    final stats = parseDevStats(text);
    expect(stats.rows.single.hits, {46: 2});
    expect(stats.rows.single.secretary, 400);
  });
}
