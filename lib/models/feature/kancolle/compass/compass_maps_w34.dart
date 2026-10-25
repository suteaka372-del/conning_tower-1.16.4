import 'compass_engine.dart';

// 3-1〜4-5 の分岐条件。艦これ攻略 Wiki* の各海域ページ「ルート分岐法則」の内容を元に書き直したもの。
// 表記は compass_maps_w12.dart と同じ (戦艦級 = 高速戦艦 + (低速)戦艦 + 航空戦艦 / 空母系 = 正規空母 + 装甲空母 + 軽空母 / ...)。
// 「?」付きなど Wiki でも確かでない条件や、割合が書かれていないランダムは estimated (推定) として扱う。

const _kLosNote = '索敵スコアは司令部Lv120のときの値なので、120未満なら+1以上の余裕を';

final List<CompassMap> kCompassMapsWorld34 = [
  // ---- 3-1 モーレイ海 ----
  CompassMap(
    area: 3,
    no: 1,
    title: 'モーレイ海',
    boss: 'G',
    edges: {
      1: ('B', 'A'), 2: ('C', 'B'), 3: ('Start', 'C'), 4: ('C', 'D'), 5: ('D', 'E'), 6: ('C', 'F'), 7: ('D', 'G'), //
      8: ('D', 'F'), 9: ('F', 'G'),
    },
    rules: {
      'C': (f) {
        if (f.ddde <= 1) return go('D', '(駆逐+海防)1隻以下');
        if (f.bbv + f.cl + f.av + f.ao >= 3) {
          if (f.bbClass + f.carriers >= 3) {
            return even(['B', 'D'], '(航空戦艦+軽巡+水母+補給艦)3隻以上 かつ (戦艦級+空母系)3隻以上 (割合不明)', estimated: true);
          }
          return even(['B', 'F'], '(航空戦艦+軽巡+水母+補給艦)3隻以上 (割合不明)', estimated: true);
        }
        if (f.av + f.ao >= 1 && f.ddde >= 3) return even(['B', 'F'], '(水母+補給艦)1隻以上 かつ (駆逐+海防)3隻以上 (割合不明)', estimated: true);
        if (f.subs >= 3) return even(['D', 'F'], '潜水艦3隻以上 (割合不明)', estimated: true);
        if (f.bbClass + f.carriers >= 3) return go('D', '(戦艦級+空母系)3隻以上');
        return go('F', 'それ以外');
      },
      'D': (f) {
        if (f.bbClass + f.carriers >= 5) return go('E', '(戦艦級+空母系)5隻以上');
        if (f.subs >= 6) return go('E', '潜水艦6隻');
        if (f.as == 1 && f.subs == 5) return go('G', '潜水母艦1隻 かつ 潜水艦5隻');
        return go('F', 'それ以外');
      },
    },
    note: 'ルート分岐法則 2020/04/13',
  ),

  // ---- 3-2 キス島沖 ----
  CompassMap(
    area: 3,
    no: 2,
    title: 'キス島沖',
    boss: 'L',
    edges: {
      1: ('Start', 'A'), 2: ('A', 'B'), 3: ('Start', 'C'), 4: ('E', 'D'), 5: ('C', 'E'), 6: ('E', 'F'), 7: ('C', 'G'), //
      8: ('G', 'H'), 9: ('H', 'I'), 10: ('G', 'J'), 11: ('J', 'K'), 12: ('F', 'L'), 13: ('C', 'A'), 14: ('G', 'F'),
      15: ('H', 'F'),
    },
    rules: {
      'Start': (f) {
        if (f.bbClass + f.carriers >= 1) return go('C', '(戦艦級+空母系)1隻以上');
        if (f.cl == 1 && f.dd >= 4) return go('C', '軽巡ちょうど1隻 かつ 駆逐4隻以上');
        if (f.dd == 6) return go('C', '駆逐6隻');
        return go('A', 'それ以外');
      },
      'C': (f) {
        if (f.dd <= 3) return go('A', '駆逐3隻以下');
        if (f.bbClass + f.standardCarriers >= 2) return go('A', '(戦艦級+正規空母)2隻以上');
        if (f.subs >= 1) return even(['A', 'G'], '潜水艦を含む (割合不明)', estimated: true);
        if (f.anySlow) return go('G', '低速の艦を含む');
        if (f.radarShips == 0) return go('G', '電探を積んだ艦が0隻');
        if (f.cl + f.dd + f.ao <= 5) return go('G', '(軽巡+駆逐+補給艦)5隻以下');
        if (f.allFastest && f.radarShips >= 4) return go('E', '最速統一 かつ 電探を積んだ艦4隻以上');
        if (f.allFastPlus) return lean('G', 'E', '高速+以上統一 (Gマス寄り)', 60);
        if (f.ao >= 1) return lean('G', 'E', '補給艦を含む (Gマス寄り)', 60);
        return go('G', 'それ以外');
      },
      'E': (f) {
        if (f.allFastPlus) return go('F', '高速+以上統一');
        return lean('F', 'D', 'それ以外 (Fマス寄り)', 80);
      },
      'G': (f) {
        if (f.subs >= 1) return go('J', '潜水艦を含む');
        if (f.standardCarriers >= 1) return go('J', '正規空母を含む');
        if (f.bbClass + f.cvl == 2) return go('J', '(戦艦級+軽空母)2隻');
        if (f.anySlow) return go('H', '低速の艦を含む');
        if (f.radarShips == 0) return go('H', '電探を積んだ艦が0隻');
        if (f.cl + f.dd + f.ao <= 5) return go('H', '(軽巡+駆逐+補給艦)5隻以下');
        if (f.allFastPlus) return go('F', '高速+以上統一');
        if (f.ao >= 1) return lean('F', 'H', '補給艦を含む (Fマス寄り)', 55);
        return lean('H', 'F', 'それ以外 (Hマス寄り)', 65);
      },
      'H': (f) {
        if (f.cl + f.dd + f.ao >= 6) return go('F', '(軽巡+駆逐+補給艦)6隻');
        return go('I', 'それ以外');
      },
    },
    note: 'ルート分岐法則 2020/03/07',
  ),

  // ---- 3-3 アルフォンシーノ方面 ----
  CompassMap(
    area: 3,
    no: 3,
    title: 'アルフォンシーノ方面',
    boss: 'M',
    edges: {
      1: ('Start', 'A'), 2: ('A', 'B'), 3: ('A', 'C'), 4: ('B', 'D'), 5: ('C', 'E'), 6: ('B', 'F'), 7: ('C', 'G'), //
      8: ('F', 'H'), 9: ('G', 'I'), 10: ('F', 'J'), 11: ('J', 'K'), 12: ('K', 'L'), 13: ('G', 'M'), 14: ('E', 'G'),
      15: ('F', 'G'), 16: ('J', 'M'), 17: ('K', 'M'),
    },
    rules: {
      'A': (f) {
        if (f.standardCarriers >= 1) return go('C', '正規空母を含む');
        if (f.bbClass + f.cvl >= 4) return go('C', '(戦艦級+軽空母)4隻以上');
        if (f.bbClass + f.cvl == 1 && f.cl == 1 && f.dd == 4) return go('C', '(戦艦級+軽空母)1隻 かつ 軽巡1隻 かつ 駆逐4隻');
        return go('B', 'それ以外');
      },
      'B': (f) {
        if (f.subs >= 1) return even(['D', 'F'], '潜水艦を含む (割合不明)', estimated: true);
        if (f.bbClass + f.cvl <= 1) return go('F', '(戦艦級+軽空母)1隻以下');
        if (f.bbClass + f.cvl <= 2 && f.dd >= 2) return go('F', '(戦艦級+軽空母)2隻以下 かつ 駆逐2隻以上');
        return even(['D', 'F'], 'それ以外 (片寄りなし)');
      },
      'C': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.ddde <= 1) return go('E', '(駆逐+海防)1隻以下');
        if (f.standardCarriers >= 2) return go('E', '正規空母2隻以上');
        if (heavy >= 3) return go('E', '(戦艦級+空母系)3隻以上');
        if (heavy == 2) return go('G', '(戦艦級+空母系)2隻');
        if (heavy == 1 && f.cl == 1 && f.dd == 4) return go('G', '(戦艦級+空母系)1隻 かつ 軽巡1隻 かつ 駆逐4隻');
        return go('E', 'それ以外');
      },
      'F': (f) {
        if (f.dd <= 1) return go('G', '駆逐1隻以下');
        if (f.bbClass >= 3) return go('G', '戦艦級3隻以上');
        if (f.subs >= 1) return even(['H', 'J'], '潜水艦を含む (割合不明)', estimated: true);
        if (f.cl >= 1) return go('J', '軽巡を含む');
        if (f.cav >= 1) return go('J', '航巡を含む');
        if (f.av >= 1) return go('J', '水母を含む');
        return even(['H', 'J'], 'それ以外 (片寄りなし)');
      },
      'G': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.subs >= 1) return even(['I', 'M'], '潜水艦を含む (割合不明)', estimated: true);
        if (heavy <= 3) return go('M', '(戦艦級+空母系)3隻以下');
        if (heavy == 4) return split({'I': 50, 'M': 50}, '(戦艦級+空母系)4隻 (片寄りなし・Wikiでも推測)', estimated: true);
        if (heavy == 5) return split({'I': 65, 'M': 35}, '(戦艦級+空母系)5隻 (Iマス寄り・Wikiでも推測)', estimated: true);
        return split({'I': 85, 'M': 15}, '(戦艦級+空母系)6隻 (Iマス寄り・Wikiでも推測)', estimated: true);
      },
      'J': (f) {
        if (f.dd >= 5) return go('M', '駆逐5隻以上');
        if (f.cl == 1 && f.dd >= 4) return go('M', '軽巡ちょうど1隻 かつ 駆逐4隻以上');
        return go('K', 'それ以外');
      },
      'K': (f) {
        final heavy = f.bbClass + f.cvl;
        if (f.subs >= 1) return even(['L', 'M'], '潜水艦を含む (割合不明・Wikiでも推測)', estimated: true);
        if (heavy <= 1) return go('M', '(戦艦級+軽空母)1隻以下');
        if (heavy == 2) return split({'M': 75, 'L': 25}, '(戦艦級+軽空母)2隻 (Mマス寄り・Wikiでも推測)', estimated: true);
        if (heavy == 3) return split({'L': 50, 'M': 50}, '(戦艦級+軽空母)3隻 (片寄りなし・Wikiでも推測)', estimated: true);
        return even(['L', 'M'], '(戦艦級+軽空母)4隻以上 (Wikiに記載なし)', estimated: true);
      },
    },
    note: 'ルート分岐法則 2020/03/07',
  ),

  // ---- 3-4 北方海域全域 ----
  CompassMap(
    area: 3,
    no: 4,
    title: '北方海域全域',
    boss: 'P',
    edges: {
      1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('A', 'C'), 4: ('Start', 'D'), 5: ('C', 'E'), 6: ('C', 'F'), 7: ('E', 'G'), //
      8: ('B', 'H'), 9: ('F', 'I'), 10: ('F', 'J'), 11: ('M', 'K'), 12: ('H', 'L'), 13: ('F', 'M'), 14: ('L', 'N'),
      15: ('L', 'O'), 16: ('J', 'P'), 17: ('C', 'B'), 18: ('F', 'G'), 19: ('H', 'G'), 20: ('D', 'H'), 21: ('G', 'J'),
      22: ('L', 'J'), 23: ('M', 'P'), 24: ('N', 'P'),
    },
    rules: {
      'Start': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.cl + f.dd + f.de == 0) return go('A', '(軽巡+駆逐+海防)0隻');
        if (heavy >= 3) return go('A', '(戦艦級+空母系)3隻以上');
        if (heavy == 2 || f.subs >= 1) {
          return split({'B': 65, 'A': 35}, '(戦艦級+空母系)2隻 または 潜水艦を含む (Bマス寄り・Wikiでも推測)', estimated: true);
        }
        if (heavy == 1) return go('B', '(戦艦級+空母系)1隻');
        if (f.dd <= 2) return split({'B': 65, 'D': 35}, '(戦艦級+空母系)0隻 かつ 駆逐2隻以下 (Bマス寄り・Wikiでも推測)', estimated: true);
        return go('D', '(戦艦級+空母系)0隻 かつ 駆逐3隻以上');
      },
      'C': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.standardCarriers >= 3) return go('B', '正規空母3隻以上');
        if (f.cl + f.dd + f.de == 0) return go('B', '(軽巡+駆逐+海防)0隻');
        if (heavy >= 5) return go('B', '(戦艦級+空母系)5隻以上');
        if (heavy == 2) return go('F', '(戦艦級+空母系)ちょうど2隻');
        if (f.av + f.ao >= 1) return go('E', '(水母+補給艦)1隻以上');
        if (f.as >= 1) return even(['E', 'F'], '潜水母艦を含む (割合不明)', estimated: true);
        return go('F', 'それ以外');
      },
      'F': (f) {
        if (f.bbClass + f.carriers + f.caClass >= 5) return go('G', '(戦艦級+空母系+重巡級)5隻以上');
        if (f.bbClass + f.standardCarriers <= 2 && f.cl >= 1 && f.ddde >= 2) {
          const base = '(戦艦級+正規空母)2隻以下 かつ 軽巡1隻以上 かつ (駆逐+海防)2隻以上';
          if (f.allFastPlus) return go('J', '$base かつ 高速+以上統一');
          return split({'G': 10, 'J': 45, 'M': 45}, '$base (割合はWikiでも推測)', estimated: true);
        }
        return even(['G', 'M'], 'それ以外 (割合不明。Iマスへの条件は不明)', estimated: true);
      },
      'H': (f) {
        if (f.dd <= 2) return go('G', '駆逐2隻以下');
        if (f.cl + f.dd <= 3) return go('G', '(軽巡+駆逐)3隻以下');
        if (f.standardCarriers >= 1) return go('G', '正規空母を含む');
        if (f.bbClass + f.cvl >= 2) return go('G', '(戦艦級+軽空母)2隻以上');
        if (f.cl + f.dd >= 5) return go('L', '(軽巡+駆逐)5隻以上');
        if (f.cl == 0) return go('G', '軽巡0隻');
        return lean('L', 'G', 'それ以外 (Lマス寄り)', 65);
      },
      'L': (f) {
        if (f.caClass + f.cl + f.dd >= 6) return go('J', '(重巡級+軽巡+駆逐)6隻');
        if (f.bbClass + f.cvl == 0) return go('N', '(戦艦級+軽空母)0隻');
        return even(['N', 'O'], 'それ以外 (割合不明)', estimated: true);
      },
      'M': (f) {
        if (f.cl >= 1 && f.dd >= 1) return go('P', '軽巡1隻以上 かつ 駆逐1隻以上');
        return even(['K', 'P'], 'それ以外 (割合不明)', estimated: true);
      },
    },
    note: 'ルート分岐法則 2020/05/27',
  ),

  // ---- 3-5 北方AL海域 ----
  CompassMap(
    area: 3,
    no: 5,
    title: '北方AL海域',
    boss: 'K',
    coefficient: 4,
    edges: {
      1: ('Start', 'B'), 2: ('B', 'A'), 3: ('B', 'C'), 4: ('B', 'D'), 5: ('B', 'E'), 6: ('Start', 'F'), 7: ('F', 'G'), //
      8: ('D', 'H'), 9: ('H', 'J'), 10: ('G', 'I'), 11: ('G', 'K'), 12: ('F', 'E'), 13: ('C', 'F'), 14: ('E', 'H'),
      15: ('H', 'K'),
    },
    rules: {
      'Start': (f) {
        if (f.subs >= 3) return go('B', '潜水艦3隻以上');
        if (f.bbClass >= 2) return go('B', '戦艦級2隻以上');
        if (f.bbClass + f.caClass >= 3) return go('B', '(戦艦級+重巡級)3隻以上');
        if (f.carriers + f.clt >= 1) return go('B', '空母系 または 雷巡を含む');
        if (f.dd >= 5) return go('F', '駆逐5隻以上');
        if (f.dd == 4) return lean('F', 'B', '駆逐4隻 (Fマス寄り)', 75);
        return even(['B', 'F'], '駆逐3隻以下 (片寄りなし)');
      },
      'B': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.subs >= 4) return go('A', '潜水艦4隻以上');
        if (f.carriers >= 4) return go('A', '空母系4隻以上');
        if (heavy >= 5) return go('A', '(戦艦級+空母系)5隻以上');
        if (f.clt >= 2) return go('D', '雷巡2隻以上');
        if (f.carriers >= 2) return go('D', '空母系2隻以上');
        if (f.bbClass >= 3) return go('D', '戦艦級3隻以上');
        if (heavy + f.caClass >= 5) return go('D', '(戦艦級+空母系+重巡級)5隻以上');
        if (f.carriers == 0 && f.cl == 1 && f.dd >= 2) return go('E', '空母系0隻 かつ 軽巡1隻 かつ 駆逐2隻以上');
        return go('C', 'それ以外');
      },
      'F': (f) {
        if (f.bbClass + f.carriers + f.lha >= 1) return go('E', '(戦艦級+空母系+揚陸艦)1隻以上');
        if (f.cl + f.clt >= 4) return go('E', '(軽巡+雷巡)4隻以上');
        if (f.caClass >= 2) return go('E', '重巡級2隻以上');
        if (f.caClass == 1) return lean('G', 'E', '重巡級1隻 (Gマス寄り)', 75);
        if (f.cl >= 3) return lean('G', 'E', '重巡級0隻 かつ 軽巡3隻 (Gマス寄り)', 85);
        return go('G', '重巡級0隻 かつ 軽巡2隻以下');
      },
      'G': (f) => byLos(f, 4, low: 23, high: 28, below: 'I', above: 'K'),
      'H': (f) {
        if (f.bbClass + f.carriers >= 4) return go('J', '(戦艦級+空母系)4隻以上');
        if (f.lha >= 1) return go('J', '揚陸艦を含む');
        return byLos(f, 4, low: 35, high: 40, below: 'J', above: 'K', guessed: true);
      },
    },
    note: '分岐点係数4。$_kLosNote',
  ),

  // ---- 4-1 ジャム島沖 ----
  CompassMap(
    area: 4,
    no: 1,
    title: 'ジャム島沖',
    boss: 'J',
    edges: {
      1: ('Start', 'A'), 2: ('A', 'B'), 3: ('Start', 'C'), 4: ('B', 'D'), 5: ('C', 'E'), 6: ('C', 'F'), 7: ('D', 'G'), //
      8: ('D', 'H'), 9: ('H', 'I'), 10: ('G', 'J'), 11: ('F', 'D'), 12: ('F', 'H'), 13: ('H', 'J'),
    },
    rules: {
      'Start': (f) => even(['A', 'C'], 'ランダム (片寄りなし)'),
      'C': (f) {
        final heavy = f.bbClass + f.carriers;
        if (heavy >= 5) return go('E', '(戦艦級+空母系)5隻以上');
        if (heavy == 4) return lean('E', 'F', '(戦艦級+空母系)4隻 (Eマス寄り)', 70);
        if (heavy == 3) return even(['E', 'F'], '(戦艦級+空母系)3隻 (片寄りなし)');
        return go('F', '(戦艦級+空母系)2隻以下');
      },
      'D': (f) {
        final heavy = f.bbClass + f.carriers;
        if (heavy >= 5) return go('H', '(戦艦級+空母系)5隻以上');
        if (f.subs >= 1) return split({'H': 70, 'G': 30}, '潜水艦を含む (Hマス寄り・Wikiでも推測)', estimated: true);
        if (heavy == 4) return go('G', '(戦艦級+空母系)4隻');
        if (f.ddde <= 1) return go('G', '(駆逐+海防)1隻以下');
        if (heavy == 0) return go('H', '(戦艦級+空母系)0隻');
        if (f.ddde >= 4) return go('H', '(駆逐+海防)4隻以上');
        if (f.ddde == 3) return go('G', '(駆逐+海防)3隻');
        if (f.cl == 0) return go('G', '軽巡0隻');
        if (f.caClass >= 1 && f.caClass + f.cl + f.ct == 3) return go('H', '重巡級1隻以上 かつ (重巡級+軽巡+練巡)ちょうど3隻');
        return even(['G', 'H'], 'それ以外 (片寄りなし)');
      },
      'F': (f) {
        if (f.bbClass + f.carriers >= 1) return go('D', '(戦艦級+空母系)1隻以上');
        if (f.ddde <= 3) return go('D', '(駆逐+海防)3隻以下');
        if (f.cl + f.ct >= 1) return go('H', '(軽巡+練巡)を含む');
        if (f.caClass == 0) return go('H', '重巡級0隻');
        return go('D', 'それ以外');
      },
      'H': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.subs >= 2) return split({'I': 1}, '潜水艦2隻以上 (Wikiでも推測)', estimated: true);
        if (f.subs == 1) return even(['I', 'J'], '潜水艦1隻 (割合不明)', estimated: true);
        if (heavy >= 5) return go('I', '(戦艦級+空母系)5隻以上');
        if (heavy <= 1) return go('J', '(戦艦級+空母系)1隻以下');
        return even(['I', 'J'], 'それ以外 (割合不明)', estimated: true);
      },
    },
    note: 'ルート分岐法則 2020/10/03',
  ),

  // ---- 4-2 カレー洋海域 ----
  CompassMap(
    area: 4,
    no: 2,
    title: 'カレー洋海域',
    boss: 'L',
    edges: {
      1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('A', 'C'), 4: ('B', 'D'), 5: ('A', 'E'), 6: ('G', 'F'), 7: ('C', 'G'), //
      8: ('D', 'H'), 9: ('G', 'I'), 10: ('F', 'J'), 11: ('H', 'K'), 12: ('C', 'L'), 13: ('D', 'C'), 14: ('E', 'G'),
      15: ('H', 'G'), 16: ('G', 'L'),
    },
    rules: {
      'Start': (f) {
        if (f.ddde >= 2) return lean('A', 'B', '(駆逐+海防)2隻以上 (多いほどAマス寄り・割合不明)');
        return lean('B', 'A', '(駆逐+海防)1隻以下 (Bマス寄り・割合不明)');
      },
      'A': (f) {
        if (f.ddde <= 1) return go('E', '(駆逐+海防)1隻以下');
        if (f.subs >= 1) return even(['C', 'E'], '潜水艦を含む (割合不明)', estimated: true);
        if (f.ddde >= 4) return go('C', '(駆逐+海防)4隻以上');
        if (f.cl >= 1 && f.ddde >= 3) return go('C', '軽巡1隻以上 かつ (駆逐+海防)3隻以上');
        if (f.ddde == 3) return lean('C', 'E', '(駆逐+海防)3隻 (Cマス寄り)', 85);
        if (f.cl >= 1) return lean('C', 'E', '軽巡1隻以上 かつ (駆逐+海防)2隻 (Cマス寄り)', 85);
        return split({'C': 55, 'E': 45}, 'それ以外 (Cマス寄り・Wikiでも推測)', estimated: true);
      },
      'C': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.ddde <= 1) return go('G', '(駆逐+海防)1隻以下');
        if (heavy >= 4) return go('G', '(戦艦級+空母系)4隻以上');
        if (heavy == 3) {
          if (f.cl == 0) return split({'G': 85, 'L': 15}, '(戦艦級+空母系)3隻 かつ 軽巡0隻 (Gマス寄り・Wikiでも推測)', estimated: true);
          return split({'G': 65, 'L': 35}, '(戦艦級+空母系)3隻 (Gマス寄り・Wikiでも推測)', estimated: true);
        }
        if (f.cl >= 1) return go('L', '軽巡1隻以上');
        if (f.ddde >= 4) return go('L', '(駆逐+海防)4隻以上');
        return split({'G': 65, 'L': 35}, 'それ以外 (Gマス寄り・Wikiでも推測)', estimated: true);
      },
      'D': (f) {
        final heavy = f.bbClass + f.carriers;
        if (heavy >= 6) return go('H', '(戦艦級+空母系)6隻');
        if (heavy <= 2) {
          if (f.ddde >= 2) return go('C', '(戦艦級+空母系)2隻以下 かつ (駆逐+海防)2隻以上');
          return lean('H', 'C', '(戦艦級+空母系)2隻以下 (Hマス寄り)', 60);
        }
        if (f.ddde <= 1) return lean('H', 'C', '(駆逐+海防)1隻以下 (Hマス寄り)', 85);
        if (f.bbClass == 4) return lean('H', 'C', '戦艦級4隻 (Hマス寄り)', 70);
        return even(['C', 'H'], 'それ以外 (片寄りなし)');
      },
      'G': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.ddde >= 3) return go('L', '(駆逐+海防)3隻以上');
        if (f.ddde == 2) {
          if (f.cl + f.cav + f.av >= 1) return go('L', '(駆逐+海防)2隻 かつ (軽巡+航巡+水母)1隻以上');
          if (f.bbClass == 4) return go('L', '(駆逐+海防)2隻 かつ 戦艦級4隻');
          return lean('L', 'F', '(駆逐+海防)2隻 (Lマス寄り)', 65);
        }
        if (f.subs >= 1) return lean('F', 'L', '潜水艦を含む (Fマス寄り・割合不明)');
        if (heavy >= 5) return lean('I', 'L', '(戦艦級+空母系)5隻以上 (Iマス寄り・割合不明)');
        if (heavy <= 1) return split({'L': 85, 'F': 15}, '(戦艦級+空母系)1隻以下 (Lマス寄り・Wikiでも推測)', estimated: true);
        return lean('L', 'F', 'それ以外 (Lマス寄り・割合不明)');
      },
      'H': (f) {
        if (f.dd >= 2) return go('G', '駆逐2隻以上');
        if (f.ddde >= 2) return split({'G': 80, 'K': 20}, '(駆逐+海防)2隻以上 (Gマス寄り・Wikiでも推測)', estimated: true);
        if (f.bbClass + f.carriers >= 5) return split({'K': 80, 'G': 20}, '(戦艦級+空母系)5隻以上 (Kマス寄り・Wikiでも推測)', estimated: true);
        return split({'G': 50, 'K': 50}, 'それ以外 (片寄りなし・Wikiでも推測)', estimated: true);
      },
    },
    note: 'ルート分岐法則 2020/03/18',
  ),

  // ---- 4-3 リランカ島 ----
  CompassMap(
    area: 4,
    no: 3,
    title: 'リランカ島',
    boss: 'N',
    edges: {
      1: ('Start', 'A'), 2: ('A', 'B'), 3: ('Start', 'C'), 4: ('Start', 'D'), 5: ('B', 'E'), 6: ('C', 'F'), 7: ('B', 'G'), //
      8: ('D', 'H'), 9: ('G', 'I'), 10: ('G', 'J'), 11: ('F', 'K'), 12: ('K', 'L'), 13: ('L', 'M'), 14: ('H', 'N'),
      15: ('A', 'D'), 16: ('C', 'D'), 17: ('E', 'G'), 18: ('F', 'H'), 19: ('G', 'H'), 20: ('H', 'I'), 21: ('K', 'N'),
      22: ('L', 'N'),
    },
    rules: {
      'Start': (f) {
        if (f.standardCarriers >= 1) return go('C', '正規空母を含む');
        if (f.ddde >= 4) {
          if (f.allFast) return go('D', '(駆逐+海防)4隻以上 かつ 高速以上統一');
          if (f.bbClass + f.cvl == 0) return go('D', '(駆逐+海防)4隻以上 かつ (戦艦級+軽空母)0隻');
        }
        if (f.ddde >= 3 && f.cl >= 1) return go('D', '(駆逐+海防)3隻以上 かつ 軽巡1隻以上');
        if (f.ddde >= 2 && f.cl + f.ao >= 1) return go('A', '(駆逐+海防)2隻以上 かつ (軽巡+補給艦)1隻以上');
        return even(['A', 'C'], 'それ以外 (割合不明)', estimated: true);
      },
      'A': (f) {
        if (f.av + f.ao + f.bbv >= 1) return go('B', '(水母+補給艦+航空戦艦)1隻以上');
        if (f.ca >= 2 && f.ddde >= 2) return go('D', '重巡2隻以上 かつ (駆逐+海防)2隻以上');
        if (f.cvl >= 1) return go('B', '軽空母を含む');
        return even(['B', 'D'], 'それ以外 (割合不明)', estimated: true);
      },
      'B': (f) {
        if (f.ddde <= 1) return go('E', '(駆逐+海防)1隻以下');
        if (f.bbClass + f.cvl >= 3) return go('E', '(戦艦級+軽空母)3隻以上');
        if (f.allFast) return go('G', '高速以上統一');
        return lean('E', 'G', 'それ以外 (Eマス寄り)', 65);
      },
      'C': (f) {
        if (f.bbClass + f.carriers >= 4) return go('F', '(戦艦級+空母系)4隻以上');
        if (f.subs == 0 && f.cl == 1 && f.ddde >= 2) return go('D', '潜水艦0隻 かつ 軽巡ちょうど1隻 かつ (駆逐+海防)2隻以上');
        return split({'F': 80, 'D': 20}, 'それ以外 (Fマス寄り・Wikiでも推測)', estimated: true);
      },
      'F': (f) {
        if (f.subs >= 1) return go('K', '潜水艦を含む');
        if (f.dd == 0) return go('K', '駆逐0隻');
        if (f.carriers == 0) return go('K', '空母系0隻');
        if (f.allFast && f.bbClass + f.carriers <= 2 && f.dd >= 2) {
          return go('H', '高速以上統一 かつ (戦艦級+空母系)2隻以下 かつ 駆逐2隻以上');
        }
        return lean('K', 'H', 'それ以外 (Kマス寄り・割合不明)');
      },
      'G': (f) {
        if (f.cvl == 0) return go('J', '軽空母0隻');
        return lean('H', 'I', 'それ以外 (Hマス寄り)', 65);
      },
      'H': (f) {
        if (f.carriers == 2) return lean('N', 'I', '空母系ちょうど2隻 (Nマス寄り)', 90);
        if (f.carriers == 0 && f.ca == 2) {
          return split({'N': 80, 'I': 20}, '空母系0隻 かつ 重巡ちょうど2隻 (Nマス寄り・75〜85%。Wikiでも推測)', estimated: true);
        }
        return lean('N', 'I', 'それ以外 (Nマス寄り)', 70);
      },
      'K': (f) {
        if (f.subs >= 1) return go('L', '潜水艦を含む');
        if (f.carriers >= 3 || f.carriers == 0) return go('L', '空母系3隻以上 または 0隻');
        if (f.ddde <= 1) return go('L', '(駆逐+海防)1隻以下');
        if (f.standardCarriers == 1 && f.av + f.cvl == 1) {
          return split({'L': 55, 'N': 45}, '正規空母1隻 かつ (水母+軽空母)1隻 (Lマス寄り・Wikiでも推測)', estimated: true);
        }
        if (f.carriers == 2) return split({'L': 67.5, 'N': 32.5}, '空母系2隻 (Lマス寄り・65〜70%。Wikiでも推測)', estimated: true);
        return split({'L': 85, 'N': 15}, '空母系1隻 (Lマス寄り・80〜90%。Wikiでも推測)', estimated: true);
      },
      'L': (f) {
        if (f.cl + f.dd + f.de == 0) return go('M', '(軽巡+駆逐+海防)0隻');
        if (f.bbClass + f.carriers >= 5) return go('M', '(戦艦級+空母系)5隻以上');
        if (f.carriers == 0) return go('M', '空母系0隻');
        if (f.standardCarriers == 3) return split({'M': 1}, '正規空母3隻 (Wikiでも推測)', estimated: true);
        if (f.ca >= 2) return go('N', '重巡2隻以上');
        if (f.subs >= 1) return even(['M', 'N'], '潜水艦を含む (割合不明)', estimated: true);
        if (f.bbClass + f.carriers <= 2) return go('N', '(戦艦級+空母系)2隻以下');
        return even(['M', 'N'], 'それ以外 (割合不明)', estimated: true);
      },
    },
    note: 'ルート分岐法則 2020/06/23',
  ),

  // ---- 4-4 カスガダマ島 ----
  CompassMap(
    area: 4,
    no: 4,
    title: 'カスガダマ島',
    boss: 'K',
    edges: {
      1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('E', 'C'), 4: ('B', 'D'), 5: ('A', 'E'), 6: ('B', 'F'), 7: ('E', 'G'), //
      8: ('F', 'H'), 9: ('E', 'I'), 10: ('G', 'J'), 11: ('I', 'K'), 12: ('B', 'A'), 13: ('G', 'C'), 14: ('D', 'E'),
      15: ('I', 'H'), 16: ('F', 'I'), 17: ('G', 'I'),
    },
    rules: {
      'Start': (f) {
        if (f.ddde >= 2) return go('A', '(駆逐+海防)2隻以上');
        return even(['A', 'B'], 'それ以外 (片寄りなし)');
      },
      'B': (f) {
        if (f.bbClass + f.carriers >= 4) return go('A', '(戦艦級+空母系)4隻以上');
        if (f.caClass >= 1) return lean('D', 'F', '重巡級を含む (Dマス寄り・割合不明)');
        return split({'D': 1}, 'それ以外 (固定か、とても高い確率でDマス・Wikiでも推測)', estimated: true);
      },
      'E': (f) {
        if (f.bbClass + f.standardCarriers >= 4) return go('G', '(戦艦級+正規空母)4隻以上');
        if (f.caClass + f.cl >= 1 && f.ddde >= 2) return go('I', '(重巡級+軽巡)1隻以上 かつ (駆逐+海防)2隻以上');
        if (f.de >= 3) return go('C', '海防艦3隻以上');
        if (f.de >= 2 && f.ao + f.as >= 1) return go('C', '海防艦2隻以上 かつ (補給艦+潜水母艦)1隻以上');
        if (f.ddde >= 2) {
          if (f.bbClass + f.carriers >= 4) {
            return split({'G': 80, 'I': 20}, '(駆逐+海防)2隻以上 かつ (戦艦級+空母系)4隻以上 (Gマス寄り・Wikiでも推測)', estimated: true);
          }
          return split({'I': 65, 'G': 35}, '(駆逐+海防)2隻以上 かつ (戦艦級+空母系)3隻以下 (Iマス寄り・Wikiでも推測)', estimated: true);
        }
        if (f.subs >= 4) return split({'G': 1}, '潜水艦4隻以上 (Wikiでも推測)', estimated: true);
        return even(['G', 'I'], 'それ以外 (割合不明)', estimated: true);
      },
      'F': (f) {
        if (f.bbClass + f.carriers >= 3) return split({'H': 1}, '(戦艦級+空母系)3隻以上 (Wikiでも推測)', estimated: true);
        return split({'I': 1}, 'それ以外 (Wikiでも推測)', estimated: true);
      },
      'G': (f) => split({'C': 25, 'I': 50, 'J': 25}, 'ランダム (割合はWikiでも推測)', estimated: true),
      'I': (f) {
        if (f.ddde >= 2) {
          if (f.standardCarriers == 2) return go('K', '(駆逐+海防)2隻以上 かつ 正規空母ちょうど2隻');
          if (f.caClass == 2) return go('K', '(駆逐+海防)2隻以上 かつ 重巡級ちょうど2隻');
          if (f.standardCarriers == 0 && f.cl >= 1) return go('K', '(駆逐+海防)2隻以上 かつ 正規空母0隻 かつ 軽巡1隻以上');
          return lean('K', 'H', '(駆逐+海防)2隻以上 (Kマス寄り)', 75);
        }
        return split({'H': 50, 'K': 50}, 'それ以外 (片寄りなし・Wikiでも推測)', estimated: true);
      },
    },
  ),

  // ---- 4-5 カレー洋リランカ島沖 ----
  CompassMap(
    area: 4,
    no: 5,
    title: 'カレー洋リランカ島沖',
    boss: 'T',
    coefficient: 2,
    edges: {
      1: ('Start', 'A'), 2: ('A', 'B'), 3: ('Start', 'C'), 4: ('A', 'D'), 5: ('B', 'E'), 6: ('C', 'F'), 7: ('I', 'G'), //
      8: ('D', 'H'), 9: ('F', 'I'), 10: ('I', 'J'), 11: ('E', 'K'), 12: ('K', 'L'), 13: ('E', 'M'), 14: ('M', 'N'),
      15: ('Q', 'O'), 16: ('Q', 'P'), 17: ('S', 'Q'), 18: ('M', 'R'), 19: ('R', 'S'), 20: ('H', 'T'), 21: ('C', 'D'),
      22: ('G', 'D'), 23: ('G', 'H'), 24: ('J', 'H'), 25: ('H', 'K'), 26: ('K', 'M'), 27: ('O', 'N'), 28: ('Q', 'N'),
      29: ('R', 'N'), 30: ('K', 'T'), 31: ('N', 'T'), 32: ('O', 'T'),
    },
    rules: {
      'Start': (f) => even(['A', 'C'], 'ランダム (片寄りなし)'),
      'A': (f) => choose(['B', 'D']),
      'C': (f) => choose(['D', 'F']),
      'E': (f) {
        if (f.allFastPlus) return go('M', '高速+以上統一');
        if (f.ao >= 1) return go('M', '補給艦を含む');
        if (f.bbClass + f.carriers >= 3) return go('M', '(戦艦級+空母系)3隻以上');
        if (f.cl >= 1 && f.ddde >= 2) return go('M', '軽巡1隻以上 かつ (駆逐+海防)2隻以上');
        return go('K', 'それ以外');
      },
      'G': (f) {
        if (f.cl >= 1 && f.ddde >= 2) return split({'H': 1}, '軽巡1隻以上 かつ (駆逐+海防)2隻以上 (Wikiでも推測)', estimated: true);
        return even(['D', 'H'], 'それ以外 (Wikiでも推測)', estimated: true);
      },
      'I': (f) => choose(['G', 'J']),
      'M': (f) {
        if (f.allFastest) return go('N', '最速統一');
        if (f.dd <= 1) return go('R', '駆逐1隻以下');
        if (f.allFastPlus) return go('N', '高速+統一');
        if (f.anySlow) return go('R', '低速の艦を含む');
        if (f.bbClass + f.standardCarriers <= 1) return go('N', '(戦艦級+正規空母)1隻以下');
        return go('R', 'それ以外');
      },
      'O': (f) {
        if (f.bbClass + f.carriers >= 5) return split({'N': 1}, '(戦艦級+空母系)5隻以上 (Wikiでも推測)', estimated: true);
        return even(['N', 'T'], 'それ以外 (Wikiでも推測)', estimated: true);
      },
      'Q': (f) {
        final heavy = f.bbClass + f.carriers;
        final los = f.losScore(2);
        final score = '索敵スコア${los.toStringAsFixed(1)}';
        if (los < 55) return go('P', '$score (55未満。境目はWikiでも推測)');
        if (los < 59) {
          if (heavy >= 5) return even(['O', 'P'], '$score (55以上59未満) かつ (戦艦級+空母系)5隻以上 (割合不明)', estimated: true);
          if (f.dd == 0) return even(['O', 'P'], '$score (55以上59未満) かつ 駆逐0隻 (割合不明)', estimated: true);
          return even(['N', 'P'], '$score (55以上59未満。割合不明)', estimated: true);
        }
        if (heavy >= 5) return go('O', '$score (59以上) かつ (戦艦級+空母系)5隻以上');
        if (f.dd == 0) return go('O', '$score (59以上) かつ 駆逐0隻');
        return go('N', '$score (59以上。境目はWikiでも推測)');
      },
      'R': (f) {
        if (f.allFastPlus) return go('N', '高速+統一');
        if (f.allFast && f.cl + f.cav >= 1 && f.dd >= 2) return go('N', '高速以上統一 かつ (軽巡+航巡)1隻以上 かつ 駆逐2隻以上');
        return go('S', 'それ以外');
      },
    },
    pathRules: {
      'H': (f, path) {
        if (f.allFastPlus && f.bbClass + f.carriers <= 4) return go('T', '高速+以上統一 かつ (戦艦級+空母系)4隻以下');
        if (f.cl == 1 && f.ddde >= 3) return go('T', '軽巡1隻 かつ (駆逐+海防)3隻以上');
        if (!path.contains('D') && f.cl == 1 && f.ddde >= 2) return go('T', 'Dマスを通っていない かつ 軽巡1隻 かつ (駆逐+海防)2隻以上');
        return go('K', 'それ以外');
      },
      'K': (f, path) {
        if (path.contains('E')) return split({'M': 1}, 'Eマスを通ってきた (Wikiでも推測・例外あり)', estimated: true);
        if (f.bbClass + f.standardCarriers >= 4) return go('M', '(戦艦級+正規空母)4隻以上');
        if (f.bbClass + f.carriers >= 5) return go('M', '(戦艦級+空母系)5隻以上');
        if (f.ao >= 1) return go('M', '補給艦を含む');
        final los = f.losScore(2);
        final score = '索敵スコア${los.toStringAsFixed(1)}';
        if (los < 63) return go('L', '$score (63未満。境目はWikiでも推測)');
        if (los < 70) {
          if (f.subs >= 1) return even(['L', 'M', 'T'], '$score (63以上70未満) かつ 潜水艦を含む (割合不明)', estimated: true);
          return even(['L', 'T'], '$score (63以上70未満。割合不明)', estimated: true);
        }
        if (f.subs >= 1) return even(['M', 'T'], '$score (70以上) かつ 潜水艦を含む (割合不明)', estimated: true);
        return go('T', '$score (70以上。境目はWikiでも推測)');
      },
    },
    note: '分岐点係数2。A・C・Iマスは能動分岐 (ボスへ行きやすい方を選んだとして計算)。$_kLosNote。ルート分岐法則 2020/03/18',
  ),
];
