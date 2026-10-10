import '../../data/kcsapi/start2/get_data_entity.dart';
import 'expedition_check.dart';
import 'ship.dart';

// Fleet composition conditions of quests (編成条件).
// Ported from ElectronicObserver (MIT License, Copyright (c) 2014 Andante)
// https://github.com/dais-k/ElectronicObserver
// Data/Quest/ProgressSpecialBattle.cs, ProgressPractice.cs, ProgressDiscard.cs (Increment の任務ごとの判定)
// Data/ShipDataMaster.cs (RemodelTier, ShipNationality)

// api_stype
const _de = 1, _dd = 2, _cl = 3, _clt = 4, _ca = 5, _cav = 6, _cvl = 7, _fbb = 8, _bb = 9, _bbv = 10;
const _cv = 11, _ss = 13, _ssv = 14, _av = 16, _lha = 17, _cvb = 18, _as = 20, _ct = 21, _ao = 22;

const Set<int> _carriers = {_cvl, _cv, _cvb};
const Set<int> _smallShips = {_dd, _de};

/// 装備1つ分 (工廠任務の秘書艦の判定用)
class QuestEquipment {
  final int itemId;
  final int level;
  final int proficiency;

  const QuestEquipment({required this.itemId, this.level = 0, this.proficiency = 0});
}

/// 編成条件の判定に使う艦の情報
class QuestShip {
  final int shipId;
  final int shipType;
  final int shipClass;

  /// 読み (api_yomi)。同じ艦の改装後も同じ読みになる
  final String yomi;

  /// 改装段階 (0 = 未改装)
  final int remodelTier;
  final int level;
  final String name;
  final List<QuestEquipment> equipment;

  const QuestShip({
    required this.shipId,
    required this.shipType,
    this.shipClass = 0,
    this.yomi = '',
    this.remodelTier = 0,
    this.level = 1,
    this.name = '',
    this.equipment = const [],
  });

  /// 国籍 (1=米, 2=英, 3=伊, 4=独, 5=仏, 6=露, 7=豪, 8=蘭, 9=瑞, 10=中, 11=亜, 12=諾, 13=泰, 0=日本など)
  int get nationality {
    if (shipId == 147) return 6; // Верный
    if (shipId == 651) return 10; // 丹陽
    if (shipId == 957) return 11; // General Belgrano
    return switch (shipClass) {
      65 || 69 || 83 || 84 || 87 || 91 || 93 || 95 || 99 || 102 || 105 || 106 || 107 || 110 || 114 || 116 || 118 ||
      121 || 122 || 125 =>
        1,
      67 || 78 || 82 || 88 || 108 || 112 || 134 || 135 => 2,
      58 || 61 || 64 || 68 || 92 || 113 => 3,
      47 || 48 || 55 || 57 || 63 || 80 || 124 => 4,
      70 || 79 || 128 || 129 || 138 || 139 || 141 => 5,
      73 || 81 || 131 => 6,
      96 => 7,
      98 => 8,
      89 || 140 => 9,
      133 => 12,
      137 => 13,
      _ => 0,
    };
  }
}

/// 編成条件の判定に使う艦隊 (退避した艦は除く)
class QuestFleet {
  /// 艦隊番号 (1〜4)
  final int fleetNumber;
  final List<QuestShip> ships;

  const QuestFleet(this.fleetNumber, this.ships);

  QuestShip? at(int index) => index < ships.length ? ships[index] : null;

  QuestShip? get flagship => at(0);

  int count(bool Function(QuestShip ship) test) => ships.where(test).length;

  int countTypes(Set<int> types) => count((s) => types.contains(s.shipType));

  /// 読みが [names] のどれかの艦の数
  int countNames(Set<String> names) => count((s) => names.contains(s.yomi));

  int countIds(Set<int> ids) => count((s) => ids.contains(s.shipId));

  bool hasName(String yomi, {int minTier = 0}) =>
      ships.any((s) => s.yomi == yomi && s.remodelTier >= minTier);

  /// 艦娘と艦船マスターから作る
  factory QuestFleet.fromShips(
    int fleetNumber,
    Iterable<Ship> ships,
    Map<int, GetDataApiDataApiMstShipEntity>? shipInfo,
  ) {
    return QuestFleet(fleetNumber, [
      for (final ship in ships)
        if (ship.escape != true)
          QuestShip(
            shipId: ship.shipId,
            shipType: ship.shipType ?? shipInfo?[ship.shipId]?.apiStype ?? 0,
            shipClass: shipInfo?[ship.shipId]?.apiCtype ?? 0,
            yomi: shipInfo?[ship.shipId]?.apiYomi ?? '',
            remodelTier: remodelTierOf(ship.shipId, shipInfo),
            level: ship.level,
            name: ship.name ?? '',
            equipment: [
              for (final e in ship.equipment ?? const [])
                QuestEquipment(itemId: e.itemId ?? 0, level: e.level ?? 0, proficiency: e.proficiency ?? 0)
            ],
          )
    ]);
  }
}

Map<int, GetDataApiDataApiMstShipEntity>? _remodelSource;
Map<int, int> _remodelBefore = {};

/// 改装段階 (ShipDataMaster.RemodelTier)。改装前の艦をたどった回数
int remodelTierOf(int shipId, Map<int, GetDataApiDataApiMstShipEntity>? shipInfo) {
  if (shipInfo == null) return 0;
  if (!identical(_remodelSource, shipInfo)) {
    final before = <int, int>{};
    for (final ship in shipInfo.values) {
      final after = int.tryParse(ship.apiAftershipid ?? '') ?? 0;
      if (after <= 0 || after == ship.apiId) continue;
      final current = before[after];
      if (current == null || ship.apiId < current) before[after] = ship.apiId;
    }
    _remodelBefore = before;
    _remodelSource = shipInfo;
  }
  var tier = 0;
  var current = shipId;
  final visited = {shipId};
  while (true) {
    final previous = _remodelBefore[current];
    if (previous == null || !visited.add(previous)) break;
    tier++;
    current = previous;
  }
  return tier;
}

/// 編成条件の1項目
class QuestFleetRequirement {
  final String label;
  final bool Function(QuestFleet fleet) _test;

  const QuestFleetRequirement(this.label, this._test);

  bool isMet(QuestFleet fleet) => _test(fleet);
}

/// 任務の編成条件 (すべての項目を満たす必要がある)
class QuestFleetCondition {
  final List<QuestFleetRequirement> requirements;

  /// 第1艦隊の旗艦 (秘書艦) の条件 (工廠任務)
  final bool secretary;

  const QuestFleetCondition(this.requirements, {this.secretary = false});

  bool isMet(QuestFleet fleet) => requirements.every((r) => r.isMet(fleet));
}

// ---- 条件の定義用 ----
String _typeNames(Set<int> types) {
  if (types.length == 3 && types.containsAll(_carriers)) return '空母系';
  return types.map(expeditionShipTypeName).join('・');
}

QuestFleetRequirement _custom(String label, bool Function(QuestFleet fleet) test) =>
    QuestFleetRequirement(label, test);

QuestFleetRequirement _flagshipType(Set<int> types) =>
    _custom('旗艦: ${_typeNames(types)}', (f) => types.contains(f.flagship?.shipType));

QuestFleetRequirement _atLeast(Set<int> types, int n, [String? label]) =>
    _custom('${label ?? _typeNames(types)} $n隻以上', (f) => f.countTypes(types) >= n);

QuestFleetRequirement _atMost(Set<int> types, int n) =>
    _custom('${_typeNames(types)} $n隻以下', (f) => f.countTypes(types) <= n);

QuestFleetRequirement _exactly(Set<int> types, int n) =>
    _custom('${_typeNames(types)} ちょうど$n隻', (f) => f.countTypes(types) == n);

QuestFleetRequirement _onlyTypes(Set<int> types) =>
    _custom('${_typeNames(types)}のみ', (f) => f.ships.every((s) => types.contains(s.shipType)));

QuestFleetRequirement _noTypes(Set<int> types) =>
    _custom('${_typeNames(types)}なし', (f) => f.countTypes(types) == 0);

/// その艦 (改装後も含む) がいる
QuestFleetRequirement _ship(String yomi, String name, {int minTier = 0}) =>
    _custom(name, (f) => f.hasName(yomi, minTier: minTier));

QuestFleetRequirement _shipIds(Set<int> ids, String name) => _custom(name, (f) => f.countIds(ids) > 0);

QuestFleetRequirement _flagshipIds(Set<int> ids, String name) =>
    _custom('旗艦: $name', (f) => ids.contains(f.flagship?.shipId));

QuestFleetRequirement _flagshipName(Set<String> yomi, String name) =>
    _custom('旗艦: $name', (f) => yomi.contains(f.flagship?.yomi));

QuestFleetRequirement _names(Map<String, String> ships, int n) =>
    _custom('${ships.values.join('・')}${n >= ships.length ? '' : ' から$n隻以上'}',
        (f) => f.countNames(ships.keys.toSet()) >= n);

QuestFleetRequirement _ids(Set<int> ids, int n, String names) =>
    _custom('$names${n >= ids.length ? '' : ' から$n隻以上'}', (f) => f.countIds(ids) >= n);

QuestFleetRequirement _classes(Set<int> classes, int n, String names) =>
    _custom('$names $n隻以上', (f) => f.count((s) => classes.contains(s.shipClass)) >= n);

QuestFleetRequirement _fleetNumber(int n, [String note = '']) =>
    _custom('第$n艦隊$note', (f) => f.fleetNumber == n);

/// 旗艦がリストの艦で、リストの艦が旗艦を含めて n 隻以上 (名前の重複は数えない)
List<QuestFleetRequirement> _flagshipAndNames(Map<String, String> ships, int n) => [
      _custom('旗艦: 下の艦のどれか', (f) => ships.containsKey(f.flagship?.yomi)),
      _custom('${ships.values.join('・')} から$n隻以上', (f) => f.countNames(ships.keys.toSet()) >= n),
    ];

/// 1番艦と2番艦がどちらもリストの艦
QuestFleetRequirement _firstTwo(Map<String, String> ships, {bool Function(QuestShip ship)? extra}) => _custom(
      '旗艦と2番艦: ${ships.values.join('・')}',
      (f) {
        bool ok(QuestShip? s) => s != null && ships.containsKey(s.yomi) && (extra?.call(s) ?? true);
        return ok(f.at(0)) && ok(f.at(1));
      },
    );

/// 旗艦の装備 (第1スロットなど) の条件
bool _slot(QuestShip? ship, int index, int itemId, {int minLevel = 0}) {
  if (ship == null || index >= ship.equipment.length) return false;
  final e = ship.equipment[index];
  return e.itemId == itemId && e.level >= minLevel;
}

QuestFleetCondition _secretary(List<QuestFleetRequirement> requirements) =>
    QuestFleetCondition(requirements, secretary: true);

/// 任務ごとの編成条件
final Map<int, QuestFleetCondition> kQuestFleetConditions = {
  // ======== 出撃 (ProgressSpecialBattle) ========
  234: QuestFleetCondition(_flagshipAndNames({
    'おおい': '大井', 'くま': '球磨', 'かしま': '鹿島', 'かもい': '神威', 'おおとまり': '大泊', 'かみかぜ': '神風',
    'たかなみ': '高波', 'すずなみ': '涼波', 'ふじなみ': '藤波', 'はやなみ': '早波', 'はまなみ': '浜波',
  }, 3)),
  249: QuestFleetCondition([_ship('なち', '那智'), _ship('みょうこう', '妙高'), _ship('はぐろ', '羽黒')]),
  257: QuestFleetCondition([_flagshipType({_cl}), _atMost({_cl}, 3), _onlyTypes({_dd, _cl})]),
  259: QuestFleetCondition([
    _custom('大和型・長門型・伊勢型・扶桑型の戦艦 3隻以上 (ほかの戦艦・巡洋戦艦なし)', (f) {
      var count = 0;
      for (final s in f.ships) {
        if (s.shipType == _bb || s.shipType == _bbv) {
          if (!const {2, 19, 26, 37}.contains(s.shipClass)) return false;
          count++;
        } else if (s.shipType == _fbb) {
          if (s.shipId != 911) return false; // 大和改二は数える
          count++;
        }
      }
      return count >= 3;
    }),
    _atLeast({_cl}, 1),
  ]),
  264: QuestFleetCondition([_atLeast(_carriers, 2), _atLeast({_dd}, 2)]),
  266: QuestFleetCondition([_flagshipType({_dd}), _exactly({_ca}, 1), _exactly({_cl}, 1), _exactly({_dd}, 4)]),
  280: QuestFleetCondition([_atLeast({_cvl, _cl, _clt, _ct}, 1), _atLeast(_smallShips, 3)]),
  284: QuestFleetCondition([_atLeast({_cvl, _cl, _clt, _ct}, 1), _atLeast(_smallShips, 3)]),
  840: QuestFleetCondition([
    _firstTwo({
      'ほうしょう': '鳳翔', 'あさひ': '朝日', 'あかし': '明石', 'おおよど': '大淀', 'じんげい': '迅鯨',
      'ちょうげい': '長鯨', 'おぼろ': '朧', 'うしお': '潮', 'さざなみ': '漣', 'あけぼの': '曙',
    }),
  ]),
  841: QuestFleetCondition([
    _firstTwo({
      'ジャン・バール': 'Jean Bart', 'レンジャー': 'Ranger', 'しんよう': '神鷹', 'ミネアポリス': 'Minneapolis',
      'ゆうばり': '夕張', 'グロワール': 'Gloire', 'ジョンストン': 'Johnston', 'かざぐも': '風雲', 'はやしも': '早霜',
    }),
  ]),
  843: QuestFleetCondition([
    _flagshipType({_ca}),
    _atLeast({_ca}, 2),
    _custom('軽空母 (あきつ丸・山汐丸・熊野丸・しまね丸を含む) 1隻以上', (f) {
      const maru = {'あきつまる', 'やましおまる', 'くまのまる', 'しまねまる'};
      return f.countTypes({_cvl}) + f.countNames(maru) >= 1;
    }),
  ]),
  861: QuestFleetCondition([_atLeast({_bbv, _ao}, 2)]),
  862: QuestFleetCondition([_atLeast({_av}, 1), _atLeast({_cl}, 2)]),
  872: QuestFleetCondition([_fleetNumber(1, ' (7-2のみ)')]),
  873: QuestFleetCondition([_atLeast({_cl}, 1)]),
  875: QuestFleetCondition([
    _shipIds({543, 743}, '長波改二'),
    _custom('高波改・沖波改・朝霜改のどれか', (f) {
      return f.ships.any((s) => const {'たかなみ', 'おきなみ', 'あさしも'}.contains(s.yomi) && s.remodelTier >= 1);
    }),
  ]),
  888: QuestFleetCondition([
    _names({
      'ちょうかい': '鳥海', 'あおば': '青葉', 'きぬがさ': '衣笠', 'かこ': '加古', 'ふるたか': '古鷹',
      'てんりゅう': '天龍', 'ゆうばり': '夕張',
    }, 4),
  ]),
  894: QuestFleetCondition([_atLeast(_carriers, 1)]),
  903: QuestFleetCondition([
    _custom('旗艦: 夕張改二', (f) => f.flagship?.yomi == 'ゆうばり' && (f.flagship?.remodelTier ?? 0) >= 2),
    _custom('由良改二 か 睦月・如月・弥生・卯月・菊月・望月から2隻', (f) {
      const mutsuki = {'むつき', 'きさらぎ', 'やよい', 'もちづき', 'きくづき', 'うづき'};
      return f.countIds({488}) > 0 || f.countNames(mutsuki) >= 2;
    }),
  ]),
  904: QuestFleetCondition([_shipIds({195}, '綾波改二'), _shipIds({627}, '敷波改二')]),
  905: QuestFleetCondition([_custom('5隻以下', (f) => f.ships.length <= 5), _atLeast({_de}, 3)]),
  912: QuestFleetCondition([_flagshipName({'あかし'}, '明石'), _atLeast({_dd}, 3)]),
  914: QuestFleetCondition([_atLeast({_ca}, 3), _atLeast({_dd}, 1)]),
  928: QuestFleetCondition([
    _names({'はぐろ': '羽黒', 'あしがら': '足柄', 'みょうこう': '妙高', 'たかお': '高雄', 'かみかぜ': '神風'}, 2),
  ]),
  944: QuestFleetCondition([
    _custom('旗艦が重巡なら駆逐・海防3隻以上、旗艦が駆逐なら駆逐・海防4隻以上', (f) {
      final small = f.countTypes(_smallShips);
      return (f.flagship?.shipType == _ca && small >= 3) || (f.flagship?.shipType == _dd && small >= 4);
    }),
  ]),
  945: QuestFleetCondition([
    _custom('旗艦が軽巡・練巡なら駆逐・海防3隻以上、旗艦が駆逐なら駆逐・海防4隻以上', (f) {
      final small = f.countTypes(_smallShips);
      final flagshipType = f.flagship?.shipType;
      return ((flagshipType == _cl || flagshipType == _ct) && small >= 3) || (flagshipType == _dd && small >= 4);
    }),
  ]),
  946: QuestFleetCondition([_flagshipType(_carriers), _atLeast({_ca, _cav}, 2)]),
  947: QuestFleetCondition([_atLeast({_cvl}, 2)]),
  948: QuestFleetCondition([_flagshipType(_carriers)]),
  949: QuestFleetCondition([_flagshipIds({707}, 'Gambier Bay Mk.II'), _classes({91}, 1, 'Fletcher級')]),
  950: QuestFleetCondition([
    _custom('朧・漣・潮・曙 の4隻 か 白露・時雨・村雨・夕立 (改二) の4隻', (f) {
      const sevenths = {'おぼろ', 'さざなみ', 'うしお', 'あけぼの'};
      const shiratsuyu = {'しらつゆ', 'しぐれ', 'むらさめ', 'ゆうだち'};
      return f.countNames(sevenths) >= 4 ||
          f.count((s) => shiratsuyu.contains(s.yomi) && s.remodelTier >= 2) >= 4;
    }),
  ]),
  951: QuestFleetCondition([
    _custom('伊・独・米駆逐、仏艦、Littorio・U-511・Houston・Gotland から5隻', (f) {
      const classes = {61, 48, 87, 91, 70, 79};
      const names = {'リットリオ・イタリア', 'ゆー511・ろ500', 'ヒューストン', 'ゴトランド'};
      return f.count((s) => classes.contains(s.shipClass)) + f.countNames(names) >= 5;
    }),
  ]),
  952: QuestFleetCondition([_atLeast({_dd}, 3)]),
  953: QuestFleetCondition([
    _atLeast({_dd}, 2),
    _custom('旗艦と2番艦: 海防2隻 か 水母2隻', (f) {
      final first = f.at(0)?.shipType;
      final second = f.at(1)?.shipType;
      return (first == _de && second == _de) || (first == _av && second == _av);
    }),
  ]),
  954: QuestFleetCondition([_flagshipType({_cvl}), _atLeast({_dd}, 2)]),
  955: QuestFleetCondition([
    _atLeast({_fbb, _bb, _bbv}, 1, '戦艦'),
    _custom('夕雲型 2隻 か 重巡・航巡 2隻', (f) {
      return f.count((s) => s.shipClass == 38) >= 2 || f.countTypes({_ca, _cav}) >= 2;
    }),
  ]),
  957: QuestFleetCondition([_flagshipIds({588, 667}, '山風改二'), _atLeast(_smallShips, 4, '駆逐・海防 (旗艦を含む)')]),
  958: QuestFleetCondition([_ids({588, 667, 469, 587}, 2, '山風改二・江風改二・海風改二')]),
  961: QuestFleetCondition([_shipIds({568}, '黒潮改二'), _shipIds({670}, '親潮改二')]),
  973: QuestFleetCondition([
    _noTypes(_carriers),
    _custom('米・英の艦 3隻以上', (f) => f.count((s) => s.nationality == 1 || s.nationality == 2) >= 3),
  ]),
  975: QuestFleetCondition([_ids({666, 195, 647, 627}, 4, '磯波改二・浦波改二・綾波改二・敷波改二')]),
  987: QuestFleetCondition(_flagshipAndNames({
    'ローマ': 'Roma', 'ミネアポリス': 'Minneapolis', 'むらさめ': '村雨', 'ゆうだち': '夕立', 'おぼろ': '朧',
    'あけぼの': '曙', 'マエストラーレ': 'Maestrale', 'グレカーレ': 'Grecale', 'リベッチオ': 'Libeccio',
    'シロッコ': 'Scirocco', 'ジャーヴィス': 'Jervis', 'ルイージ・トレッリ': 'Luigi Torelli',
  }, 3)),
  1002: QuestFleetCondition(_flagshipAndNames({
    'ガンビア・ベイ': 'Gambier Bay', 'ミネアポリス': 'Minneapolis', 'タスカルーサ': 'Tuscaloosa',
    'ジャーヴィス': 'Jervis', 'おぼろ': '朧', 'ゆうだち': '夕立', 'むらさめ': '村雨', 'あさしお': '朝潮',
    'のわき': '野分', 'まきなみ': '巻波',
  }, 3)),
  1005: QuestFleetCondition([_ids({231, 665, 233, 407, 230, 232}, 4, '朧改・漣改・曙改(二)・潮改(二)')]),
  1010: QuestFleetCondition([_atLeast(_smallShips, 3)]),
  1011: QuestFleetCondition([_flagshipType({_de}), _atLeast({_de}, 3)]),
  1012: QuestFleetCondition([
    _custom('旗艦: 鵜来型', (f) => f.flagship?.shipClass == 117),
    _atMost({_de}, 4),
    _onlyTypes({_de}),
  ]),
  1018: QuestFleetCondition([_ship('ひえい', '比叡'), _ship('きりしま', '霧島'), _atLeast({_dd}, 2)]),
  1022: QuestFleetCondition([
    _names({'たまなみ': '玉波', 'すずなみ': '涼波', 'ふじなみ': '藤波', 'はまなみ': '浜波', 'はやなみ': '早波'}, 3),
  ]),
  1030: QuestFleetCondition([
    _classes({91}, 2, 'Fletcher級'),
    _classes({95, 121}, 1, 'Northampton級・New Orleans級'),
  ]),
  1031: QuestFleetCondition(_flagshipAndNames({
    'トンブリ': 'Thonburi', 'ゆうばり': '夕張', 'おおい': '大井', 'タスカルーサ': 'Tuscaloosa',
    'ガンビア・ベイ': 'Gambier Bay', 'はるな': '榛名', 'そうや': '宗谷', 'おぼろ': '朧', 'うすぐも': '薄雲',
    'はまなみ': '浜波', 'はやなみ': '早波',
  }, 3)),
  1034: QuestFleetCondition([
    _flagshipName({'あさひ'}, '朝日'),
    _custom('駆逐3隻以上 か 海防1隻以上', (f) => f.countTypes({_dd}) >= 3 || f.countTypes({_de}) >= 1),
  ]),
  1035: QuestFleetCondition([
    _flagshipName({'のしろ', 'アトランタ', 'リチャード・P・リアリー'}, '能代・Atlanta・Richard P.Leary'),
    _atLeast({_dd}, 3),
  ]),
  1039: QuestFleetCondition([
    _names({
      'あぶくま': '阿武隈', 'あけぼの': '曙', 'あさしお': '朝潮', 'はまなみ': '浜波', 'まきなみ': '巻波',
      'うくる': '鵜来', 'いなぎ': '稲木', 'のうみ': '能美', 'だいよんごう': '第四号海防艦',
      'だいさんじゅうごう': '第三〇号海防艦', 'だいにじゅうにごう': '第二十二号海防艦',
    }, 4),
  ]),
  1040: QuestFleetCondition([
    _custom('旗艦: 下の艦のどれか', (f) {
      const names = {'タスカルーサ', 'くまのまる', 'おぼろ', 'ゆうだち', 'のわき', 'はやなみ'};
      return names.contains(f.flagship?.yomi) || f.flagship?.shipId == 639;
    }),
    _custom('Tuscaloosa・熊野丸・朧・夕立・野分・早波・迅鯨改 から3隻以上', (f) {
      const names = {'タスカルーサ', 'くまのまる', 'おぼろ', 'ゆうだち', 'のわき', 'はやなみ'};
      return f.countNames(names) + (f.countIds({639}) > 0 ? 1 : 0) >= 3;
    }),
  ]),
  1045: QuestFleetCondition([
    _flagshipIds({1035, 1040}, '吹雪改三'),
    _custom('2番艦: 特I型 (薄雲・浦波・白雲・深雪・白雪・磯波・初雪)', (f) {
      const names = {'うすぐも', 'うらなみ', 'しらくも', 'みゆき', 'しらゆき', 'いそなみ', 'はつゆき'};
      return names.contains(f.at(1)?.yomi);
    }),
  ]),
  1047: QuestFleetCondition([
    _flagshipIds({1034, 745}, '涼波改二'),
    _names({
      'のしろ': '能代', 'ちょうかい': '鳥海', 'もがみ': '最上', 'すずや': '鈴谷', 'たまなみ': '玉波',
      'はやなみ': '早波', 'ふじなみ': '藤波',
    }, 2),
  ]),
  1048: QuestFleetCondition([_flagshipType({_ao, _lha, _av, _bbv}), _atLeast(_smallShips, 4)]),
  1049: QuestFleetCondition([_flagshipType({_ao, _lha}), _atLeast(_smallShips, 3)]),
  1050: QuestFleetCondition([
    _flagshipIds({118, 119, 1071}, '北上改二(改三)・大井改二'),
    _ids({118, 119, 1071}, 2, '北上改二(改三)・大井改二'),
    _atLeast({_dd}, 2),
  ]),
  1051: QuestFleetCondition([
    _flagshipIds({749}, '山城改二'),
    _custom('扶桑 か 時雨', (f) => f.countNames({'ふそう', 'しぐれ'}) > 0),
    _names({'もがみ': '最上', 'みちしお': '満潮', 'あさぐも': '朝雲', 'やまぐも': '山雲'}, 2),
  ]),

  // ======== 演習 (ProgressPractice) ========
  318: QuestFleetCondition([_atLeast({_cl}, 2)]),
  329: QuestFleetCondition([
    _custom('旗艦潜水母艦+潜水艦3 / 旗艦海防+海防3 / 旗艦揚陸艦・補給艦+駆逐5', (f) {
      return switch (f.flagship?.shipType) {
        _as => f.countTypes({_ss, _ssv}) >= 3,
        _de => f.countTypes({_de}) >= 3,
        _lha || _ao => f.countTypes({_dd}) >= 5,
        _ => false,
      };
    }),
  ]),
  330: QuestFleetCondition([_flagshipType(_carriers), _atLeast(_carriers, 2), _atLeast({_dd}, 2)]),
  337: QuestFleetCondition([_names({'かすみ': '霞', 'あられ': '霰', 'かげろう': '陽炎', 'しらぬい': '不知火'}, 4)]),
  339: QuestFleetCondition([_names({'いそなみ': '磯波', 'うらなみ': '浦波', 'あやなみ': '綾波', 'しきなみ': '敷波'}, 4)]),
  340: QuestFleetCondition([
    _custom('海防3隻以上 か 駆逐4隻以上', (f) => f.countTypes({_de}) >= 3 || f.countTypes({_dd}) >= 4),
  ]),
  342: QuestFleetCondition([
    _custom('駆逐・海防4隻以上 か 駆逐・海防3隻+軽巡級1隻', (f) {
      final small = f.countTypes(_smallShips);
      return small >= 4 || (small >= 3 && f.countTypes({_cl, _ct, _clt}) >= 1);
    }),
  ]),
  345: QuestFleetCondition([
    _custom('Warspite・Ark Royal・金剛・Nelson・J級駆逐艦 から4隻', (f) {
      const names = {'こんごう', 'ネルソン', 'アークロイヤル', 'ウォースパイト'};
      return f.count((s) => s.shipClass == 82) + f.countNames(names) >= 4;
    }),
  ]),
  346: QuestFleetCondition([_ids({542, 563, 564, 648}, 4, '夕雲改二・巻雲改二・風雲改二・秋雲改二')]),
  348: QuestFleetCondition([_flagshipType({_cl, _ct}), _atLeast({_cl, _ct}, 3), _atLeast({_dd}, 2)]),
  349: QuestFleetCondition(_flagshipAndNames({
    'トンブリ': 'Thonburi', 'ヘレナ': 'Helena', 'モガドール': 'Mogador', 'ゴトランド': 'Gotland',
    'パース': 'Perth', 'コマンダン・テスト': 'Commandant Teste', 'あけぼの': '曙', 'おぼろ': '朧', 'のさき': '野埼',
  }, 3)),
  350: QuestFleetCondition([_names({'おぼろ': '朧', 'あけぼの': '曙', 'さざなみ': '漣', 'うしお': '潮'}, 4)]),
  353: QuestFleetCondition([_flagshipType({_ca, _cav}), _atLeast({_ca, _cav}, 4), _atLeast({_dd}, 2)]),
  354: QuestFleetCondition([
    _flagshipIds({707}, 'Gambier Bay Mk.II'),
    _classes({87, 91}, 2, 'Fletcher級・John C.Butler級'),
  ]),
  355: QuestFleetCondition([
    _custom('1番艦と2番艦: 黒潮改二と親潮改二', (f) {
      final first = f.at(0)?.shipId;
      final second = f.at(1)?.shipId;
      return (first == 568 && second == 670) || (first == 670 && second == 568);
    }),
  ]),
  356: QuestFleetCondition([_ids({666, 195, 647, 627}, 4, '磯波改二・浦波改二・綾波改二・敷波改二')]),
  357: QuestFleetCondition([_names({'やまと': '大和', 'むさし': '武蔵'}, 2), _atLeast({_cl}, 1), _atLeast({_dd}, 2)]),
  362: QuestFleetCondition([_names({'ふぶき': '吹雪', 'しらゆき': '白雪', 'はつゆき': '初雪', 'みゆき': '深雪'}, 4)]),
  363: QuestFleetCondition([
    _firstTwo(
      {
        'へいあんまる': '平安丸', 'モガドール': 'Mogador', 'ゴトランド': 'Gotland', 'おおとまり': '大泊',
        'おぼろ': '朧', 'あけぼの': '曙', 'きぬがさ': '衣笠改二',
      },
      extra: (s) => s.yomi != 'きぬがさ' || s.remodelTier >= 2,
    ),
  ]),
  367: QuestFleetCondition([
    _custom('海防3隻以上 か 駆逐5隻以上', (f) => f.countTypes({_de}) >= 3 || f.countTypes({_dd}) >= 5),
  ]),
  368: QuestFleetCondition([
    _names({'あまつかぜ': '天津風', 'ゆきかぜ': '雪風', 'ときつかぜ': '時津風', 'はつかぜ': '初風'}, 2),
  ]),
  371: QuestFleetCondition([
    _flagshipName({'はるさめ'}, '春雨'),
    _names({'むらさめ': '村雨', 'ゆうだち': '夕立', 'さみだれ': '五月雨', 'しらつゆ': '白露', 'しぐれ': '時雨'}, 3),
  ]),
  372: QuestFleetCondition([
    _custom('旗艦: 秋月型', (f) => f.flagship?.shipClass == 54),
    _atLeast({_dd}, 3, '駆逐 (旗艦を含む)'),
    _atLeast({_bbv}, 2),
  ]),
  373: QuestFleetCondition([
    _custom('旗艦: フランス艦', (f) => f.flagship?.nationality == 5),
    _custom('フランス艦 3隻以上', (f) => f.count((s) => s.nationality == 5) >= 3),
  ]),
  374: QuestFleetCondition([
    _names({'たまなみ': '玉波', 'すずなみ': '涼波', 'ふじなみ': '藤波', 'はやなみ': '早波', 'はまなみ': '浜波'}, 3),
  ]),
  375: QuestFleetCondition([_names({'ひえい': '比叡', 'きりしま': '霧島'}, 2), _atLeast({_cl}, 1), _atLeast({_dd}, 2)]),
  377: QuestFleetCondition([
    _flagshipName({'はやしも', 'あきしも', 'きよしも'}, '早霜・秋霜・清霜'),
    _names({'はやしも': '早霜', 'あきしも': '秋霜', 'きよしも': '清霜', 'あさしも': '朝霜'}, 3),
  ]),
  378: QuestFleetCondition([
    _flagshipType({_as}),
    _atLeast({_ss, _ssv}, 1, '潜水艦'),
    _atLeast({_ss, _ssv, _as}, 3, '潜水艦・潜水母艦'),
  ]),
  379: QuestFleetCondition([_ids({426, 986, 959, 203}, 2, '吹雪改二・白雪改二・深雪改二・初雪改')]),
  380: QuestFleetCondition([
    _custom('海防3隻以上 か 海防2隻+揚陸艦1隻',
        (f) => f.countTypes({_de}) >= 3 || (f.countTypes({_de}) >= 2 && f.countTypes({_lha}) >= 1)),
  ]),
  381: QuestFleetCondition([
    _names({
      'あきづき': '秋月', 'てるづき': '照月', 'すずつき': '涼月', 'はつづき': '初月', 'ふゆつき': '冬月',
      'あきぐも': '秋雲', 'あきしも': '秋霜', 'あきつしま': '秋津洲',
    }, 3),
  ]),
  382: QuestFleetCondition([
    _names({
      'かや': '榧', 'すぎ': '杉', 'かし': '樫', 'たけ': '竹', 'うしお': '潮', 'ひびき': '響', 'はなづき': '花月',
      'きり': '桐',
    }, 5),
  ]),
  383: QuestFleetCondition([
    _custom('フランス艦 3隻以上', (f) => f.count((s) => s.nationality == 5) >= 3),
  ]),
  384: QuestFleetCondition([
    _names({
      'あきぐも': '秋雲', 'あきづき': '秋月', 'あやなみ': '綾波', 'しきなみ': '敷波', 'しらつゆ': '白露',
      'うらかぜ': '浦風', 'はまかぜ': '浜風', 'ながなみ': '長波', 'ふじなみ': '藤波', 'あさしも': '朝霜',
      'しらくも': '白雲', 'おぼろ': '朧', 'さざなみ': '漣', 'じんげい': '迅鯨', 'ちょうげい': '長鯨',
      'たいげい': '大鯨', 'じんつう': '神通',
    }, 4),
  ]),
  385: QuestFleetCondition([
    _names({
      'アルジェリー': 'Algérie', 'ヴァトール': 'Vautour', 'モガドール': 'Mogador', 'ベアルン': 'Béarn',
      'ひえまる': '日枝丸', 'へいあんまる': '平安丸', 'おおとまり': '大泊', 'むつ': '陸奥',
      'サウスダコタ': 'South Dakota', 'ヴィクトリアス': 'Victorious',
    }, 3),
  ]),

  // ======== 工廠 (ProgressDiscard、第1艦隊の旗艦) ========
  626: _secretary([
    _custom('旗艦: 鳳翔 (熟練度最大の零式艦戦21型を装備)', (f) {
      final s = f.flagship;
      return s?.yomi == 'ほうしょう' && s!.equipment.any((e) => e.itemId == 20 && e.proficiency == 7);
    }),
  ]),
  628: _secretary([
    _custom('旗艦: 空母系 (熟練度最大の零式艦戦21型(熟練)を装備)', (f) {
      final s = f.flagship;
      return s != null && _carriers.contains(s.shipType) && s.equipment.any((e) => e.itemId == 96 && e.proficiency == 7);
    }),
  ]),
  654: _secretary([
    _custom('旗艦: Ark Royal (第1スロットに Swordfish★10)',
        (f) => f.flagship?.yomi == 'アークロイヤル' && _slot(f.flagship, 0, 242, minLevel: 10)),
  ]),
  686: _secretary([
    _custom('旗艦: 特型駆逐艦 (第1スロットに 12.7cm連装砲A型改二★10)',
        (f) => const {1, 5, 12}.contains(f.flagship?.shipClass) && _slot(f.flagship, 0, 294, minLevel: 10)),
  ]),
  1106: _secretary([
    _custom('旗艦: 由良改二 (第1スロットに 零式水上偵察機11型乙★10)',
        (f) => f.flagship?.shipId == 488 && _slot(f.flagship, 0, 238, minLevel: 10)),
  ]),
  1108: _secretary([
    _custom('旗艦: 山風改二(丁)・時雨改二 (第1スロットに 三式水中探信儀★10)',
        (f) => const {588, 667, 145}.contains(f.flagship?.shipId) && _slot(f.flagship, 0, 47, minLevel: 10)),
  ]),
  1109: _secretary([
    _custom('旗艦: 神州丸 (第1スロットに 大発戦車★10)',
        (f) => f.flagship?.yomi == 'しんしゅうまる' && _slot(f.flagship, 0, 166, minLevel: 10)),
  ]),
  1123: _secretary([
    _custom('旗艦: 利根改二・由良改二 (第1スロットに 零式水上偵察機★10)',
        (f) => const {188, 488}.contains(f.flagship?.shipId) && _slot(f.flagship, 0, 25, minLevel: 10)),
  ]),
  1138: _secretary([_custom('旗艦: 秋月型', (f) => f.flagship?.shipClass == 54)]),
  1154: _secretary([
    _custom('旗艦: Lv96以上の駆逐 (第1スロットに 三式爆雷投射機 集中配備★10、第2スロットに 12cm単装砲★6以上)', (f) {
      final s = f.flagship;
      return s != null &&
          s.shipType == _dd &&
          s.level >= 96 &&
          _slot(s, 0, 287, minLevel: 10) &&
          _slot(s, 1, 1, minLevel: 6);
    }),
  ]),
  1160: _secretary([
    _flagshipIds({196, 1031}, '飛龍改二・改三'),
    _ids({981, 982, 983, 564}, 3, '藤波改二・早波改二・浜波改二・風雲改二'),
  ]),
  1161: _secretary([_flagshipIds({196, 1031}, '飛龍改二・改三')]),
  1164: _secretary([
    _flagshipName({'たまなみ'}, '玉波'),
    _custom('藤波 と 北上', (f) => f.countNames({'ふじなみ', 'きたかみ'}) == 2),
  ]),
};
