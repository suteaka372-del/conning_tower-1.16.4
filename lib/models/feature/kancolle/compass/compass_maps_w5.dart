import 'compass_engine.dart';

// 5-1〜5-6 の分岐条件。艦これ攻略 Wiki* の各海域ページ「ルート分岐法則」の内容を元に書き直したもの。
// 表記は compass_maps_w12.dart と同じ。「重巡」は艦種が重巡のもの (航巡は含まない)。
// 「?」付きなど Wiki でも確かでない条件や、割合が書かれていないランダムは estimated (推定) として扱う。

const _kLosNote = '索敵スコアは司令部Lv120のときの値なので、120未満なら+1以上の余裕を';
const _kDaihatsuNote = '大発動艇系は大発動艇・特大発動艇・武装大発・特二式/特四式内火艇など (戦車第11連隊・M4A1 DD などは数えない)';

String _los(double los) => '索敵スコア${los.toStringAsFixed(1)}';

final List<CompassMap> kCompassMapsWorld5 = [
  // ---- 5-1 南方海域前面 ----
  CompassMap(
    area: 5,
    no: 1,
    title: '南方海域前面',
    boss: 'J',
    edges: {
      1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('B', 'C'), 4: ('A', 'D'), 5: ('B', 'E'), 6: ('C', 'F'), 7: ('E', 'G'), //
      8: ('F', 'H'), 9: ('G', 'I'), 10: ('F', 'J'), 11: ('D', 'E'), 12: ('F', 'G'), 13: ('G', 'J'),
    },
    rules: {
      'Start': (f) {
        final heavy = f.bbClass + f.carriers;
        if (heavy >= 5) return go('A', '(戦艦級+空母系)5隻以上');
        if (heavy <= 2 && f.dd >= 2) return go('B', '(戦艦級+空母系)2隻以下 かつ 駆逐2隻以上');
        if (f.caClass >= 4 && f.cl >= 1) return go('B', '重巡級4隻以上 かつ 軽巡1隻以上');
        if (f.caClass >= 2 && f.cl == 1) return go('B', '重巡級2隻以上 かつ 軽巡ちょうど1隻');
        if (f.bbClass == 3 && f.cl == 1 && f.dd == 2) return lean('B', 'A', '戦艦級3隻 かつ 軽巡1隻 かつ 駆逐2隻 (Bマス寄り)', 75);
        return even(['A', 'B'], 'それ以外 (割合不明)', estimated: true);
      },
      'B': (f) {
        if (f.standardCarriers >= 1) return go('E', '正規空母を含む');
        if (f.cvl >= 2) return go('E', '軽空母2隻以上');
        if (f.bbClass <= 2) return go('C', '戦艦級2隻以下');
        if (f.cl == 1) return go('E', '軽巡ちょうど1隻');
        if (f.dd >= 2) return go('C', '駆逐2隻以上');
        return even(['C', 'E'], 'それ以外 (Wikiでも推測)', estimated: true);
      },
      'F': (f) {
        final heavy = f.bbClass + f.cvl;
        if (f.cl + f.dd == 0) return go('H', '(軽巡+駆逐)0隻');
        if (heavy >= 4) return go('H', '(戦艦級+軽空母)4隻以上');
        if (heavy == 3) return even(['G', 'H', 'J'], '(戦艦級+軽空母)3隻 (割合不明)', estimated: true);
        if (f.allFastest) return go('J', '最速統一');
        if (f.cl >= 1) {
          if (f.dd >= 2) return go('J', '軽巡1隻以上 かつ 駆逐2隻以上');
          return go('G', '軽巡1隻以上 かつ 駆逐1隻以下');
        }
        if (f.dd >= 4) return go('J', '駆逐4隻以上');
        if (f.dd == 3) return lean('J', 'G', '駆逐3隻 (Jマス寄り・割合不明)');
        if (f.dd == 2) return lean('G', 'J', '駆逐2隻 (Gマス寄り・割合不明)');
        return go('G', '駆逐1隻以下');
      },
      'G': (f) {
        final heavy = f.bbClass + f.carriers;
        if (heavy >= 5) return go('I', '(戦艦級+空母系)5隻以上');
        if (f.carriers >= 1 && heavy >= 3) return even(['I', 'J'], '空母系1隻以上 かつ (戦艦級+空母系)3隻以上 (割合不明)', estimated: true);
        if (f.subs >= 1) return even(['I', 'J'], '潜水艦を含む (割合不明)', estimated: true);
        if (f.allFastPlus) return go('J', '高速+以上統一');
        if (f.caClass >= 4) {
          if (heavy + f.clt == 0) return split({'J': 1}, '重巡級4隻以上 かつ (戦艦級+空母系+雷巡)0隻 (Wikiでも推測)', estimated: true);
          return lean('J', 'I', '重巡級4隻以上 (Jマス寄り・割合不明)');
        }
        if (f.standardCarriers >= 1) return lean('I', 'J', '正規空母を含む (Iマス寄り・割合不明)');
        if (f.dd >= 4) return go('J', '駆逐4隻以上');
        if (f.caClass >= 2 && f.dd >= 2) return go('J', '重巡級2隻以上 かつ 駆逐2隻以上');
        if (f.cl >= 1 && f.dd >= 2) return go('J', '軽巡1隻以上 かつ 駆逐2隻以上');
        if (f.bbClass == 3 && f.cl == 1 && f.caClass == 2) return lean('J', 'I', '戦艦級3隻 かつ 軽巡1隻 かつ 重巡級2隻 (Jマス寄り)', 85);
        return lean('I', 'J', 'それ以外 (Iマス寄り・割合不明)');
      },
    },
    note: 'ルート分岐法則 2020/03/18',
  ),

  // ---- 5-2 珊瑚諸島沖 ----
  CompassMap(
    area: 5,
    no: 2,
    title: '珊瑚諸島沖',
    boss: 'O',
    coefficient: 2,
    edges: {
      1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('B', 'C'), 4: ('C', 'D'), 5: ('C', 'E'), 6: ('D', 'F'), 7: ('D', 'G'), //
      8: ('F', 'H'), 9: ('F', 'I'), 10: ('G', 'J'), 11: ('L', 'K'), 12: ('J', 'L'), 13: ('L', 'M'), 14: ('L', 'N'),
      15: ('F', 'O'), 16: ('A', 'B'), 17: ('E', 'F'), 18: ('M', 'K'), 19: ('G', 'L'), 20: ('I', 'O'), 21: ('K', 'O'),
    },
    rules: {
      'Start': (f) {
        if (f.bbClass + f.carriers >= 5) return even(['A', 'B'], '(戦艦級+空母系)5隻以上 (割合不明)', estimated: true);
        if (f.bbClass >= 4) return even(['A', 'B'], '戦艦級4隻以上 (割合不明)', estimated: true);
        if (f.standardCarriers >= 3) return even(['A', 'B'], '正規空母3隻以上 (割合不明)', estimated: true);
        if (f.subs >= 1) return even(['A', 'B'], '潜水艦を含む (割合不明)', estimated: true);
        return go('B', 'それ以外');
      },
      'C': (f) {
        final shoho = f.has('祥鳳'), yubari = f.has('夕張');
        if (f.carriers == 2 && f.caClass == 2 && f.dd == 2) return go('D', '空母系2隻 かつ 重巡級2隻 かつ 駆逐2隻');
        if (yubari && f.cvl + f.caClass + f.dd + f.ao == 5) return go('D', '夕張 かつ (軽空母+重巡級+駆逐+補給艦)5隻');
        if (shoho && f.caClass + f.cl + f.ct + f.dd + f.ao == 5) return go('D', '祥鳳 かつ (重巡級+軽巡+練巡+駆逐+補給艦)5隻');
        if (f.anySlow) return go('E', '低速の艦を含む');
        if (f.has('翔鶴') && f.has('瑞鶴') && f.dd >= 2) return go('D', '翔鶴 と 瑞鶴 かつ 駆逐2隻以上');
        if (f.bbClass + f.standardCarriers >= 1) return go('E', '戦艦級 または 正規空母を含む');
        if (f.cvl == 2 && f.dd >= 2) return go('D', '軽空母2隻 かつ 駆逐2隻以上');
        if (f.cvl == 1 && f.caClass >= 1 && f.dd >= 2) return go('D', '軽空母1隻 かつ 重巡級1隻以上 かつ 駆逐2隻以上');
        return go('E', 'それ以外');
      },
      'D': (f) {
        final shoho = f.has('祥鳳'), yubari = f.has('夕張');
        if (f.n == 6) {
          if (shoho && yubari && f.dd == 2 && (f.ca == 2 || f.ao == 2) && f.dd + f.ca + f.ao == 4) {
            return go('G', '祥鳳 と 夕張 + 駆逐2隻 + (重巡2隻 または 補給艦2隻)');
          }
          if (shoho) {
            if (f.dd == 3 && f.ca == 1 && (f.cl == 1 || f.ao == 1) && f.dd + f.ca + f.cl + f.ao == 5) {
              return go('G', '祥鳳 + 駆逐3隻 + 重巡1隻 + (軽巡 または 補給艦)1隻');
            }
            if (f.dd == 3 && f.ao == 2) return go('G', '祥鳳 + 駆逐3隻 + 補給艦2隻');
          }
          if (yubari && f.dd + f.ao + f.ca == 5) {
            final ok = f.dd == 5 ||
                (f.dd == 4 && f.ao == 1) ||
                (f.dd == 3 && f.ao == 2) ||
                (f.dd == 2 && f.ao == 2 && f.ca == 1) ||
                (f.dd == 2 && f.ao == 1 && f.ca == 2);
            if (ok) return go('G', '夕張 + 駆逐・補給艦・重巡の決まった組み合わせ');
          }
        }
        return go('F', 'それ以外');
      },
      'F': (f) {
        final los = f.losScore(2);
        final score = _los(los);
        final bbcv = f.bbClass + f.standardCarriers;
        if (los < 63) return go('H', '$score (63未満。境目はWikiでも推測)');
        if (los < 70) {
          if (bbcv >= 5) return even(['H', 'I'], '$score (63以上70未満) かつ (戦艦級+正規空母)5隻以上 (割合不明)', estimated: true);
          if (f.bbClass >= 3) return even(['H', 'I', 'O'], '$score (63以上70未満) かつ 戦艦級3隻以上 (割合不明)', estimated: true);
          if (f.carriers >= 3) return even(['H', 'I', 'O'], '$score (63以上70未満) かつ 空母系3隻以上 (割合不明)', estimated: true);
          return even(['H', 'O'], '$score (63以上70未満。割合不明)', estimated: true);
        }
        if (bbcv >= 5) return go('I', '$score (70以上) かつ (戦艦級+正規空母)5隻以上');
        if (f.bbClass >= 3) return lean('I', 'O', '$score (70以上) かつ 戦艦級3隻以上 (Iマス寄り・割合不明)');
        if (f.carriers >= 3) return lean('I', 'O', '$score (70以上) かつ 空母系3隻以上 (Iマス寄り・割合不明)');
        return go('O', '$score (70以上)');
      },
      'G': (f) {
        if (f.has('祥鳳') && f.has('夕張')) return split({'J': 55, 'L': 45}, '祥鳳 と 夕張 を含む (Jマス寄り・Wikiでも推測)', estimated: true);
        return split({'J': 85, 'L': 15}, 'それ以外 (Jマス寄り・Wikiでも推測)', estimated: true);
      },
      'L': (f) {
        final los = f.losScore(2);
        final score = _los(los);
        if (!f.has('祥鳳') && !f.has('夕張')) {
          const base = '祥鳳・夕張なし かつ';
          if (f.allFastPlus) return even(['K', 'N'], '$base 高速+以上統一 (割合不明)', estimated: true);
          if (los < 60) return even(['M', 'N'], '$base $score (60未満。割合不明)', estimated: true);
          if (los < 62) return even(['K', 'M', 'N'], '$base $score (60以上62未満。割合不明)', estimated: true);
          return even(['K', 'N'], '$base $score (62以上。割合不明)', estimated: true);
        }
        if (f.allFastPlus) return go('K', '高速+以上統一');
        if (los < 60) return go('M', '$score (60未満)');
        if (los < 62) return even(['K', 'M'], '$score (60以上62未満はランダム・割合不明)', estimated: true);
        return go('K', '$score (62以上)');
      },
    },
    note: '分岐点係数2。翔鶴・瑞鶴・祥鳳・夕張は改造後も含む。$_kLosNote。ルート分岐法則 2026/01/28',
  ),

  // ---- 5-3 サブ島沖海域 ----
  CompassMap(
    area: 5,
    no: 3,
    title: 'サブ島沖海域',
    boss: 'Q',
    edges: {
      1: ('B', 'A'), 2: ('E', 'B'), 3: ('Start', 'C'), 4: ('Start', 'D'), 5: ('H', 'E'), 6: ('B', 'F'), 7: ('D', 'G'), //
      8: ('K', 'H'), 9: ('G', 'I'), 10: ('G', 'J'), 11: ('O', 'K'), 12: ('J', 'L'), 13: ('J', 'M'), 14: ('J', 'N'),
      15: ('I', 'O'), 16: ('O', 'P'), 17: ('E', 'Q'), 18: ('C', 'D'), 19: ('K', 'E'), 20: ('I', 'J'), 21: ('P', 'K'),
      22: ('L', 'O'), 23: ('N', 'O'),
    },
    rules: {
      'Start': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.allFastPlus) return go('D', '高速+以上統一');
        if (heavy >= 3) return go('C', '(戦艦級+空母系)3隻以上');
        if (heavy == 2 && f.anySlow) return go('C', '(戦艦級+空母系)2隻 かつ 低速の艦を含む');
        if (f.subs >= 1) return lean('D', 'C', '潜水艦を含む (Dマス寄り)', 60);
        return go('D', 'それ以外');
      },
      'B': (f) => split({'A': 65, 'F': 35}, 'ランダム (Aマス寄り・Wikiでも推測)', estimated: true),
      'E': (f) {
        if (f.subs >= 1) return even(['B', 'Q'], '潜水艦を含む (割合不明)', estimated: true);
        if (f.bbClass + f.carriers >= 1 && f.dd <= 1) {
          return even(['B', 'Q'], '(戦艦級+空母系)1隻以上 かつ 駆逐1隻以下 (割合不明・Wikiでも推測)', estimated: true);
        }
        if (f.cl >= 1) return go('Q', '軽巡を含む');
        if (f.caClass >= 4) return go('Q', '重巡級4隻以上');
        if (f.dd >= 4) return go('Q', '駆逐4隻以上');
        return even(['B', 'Q'], 'それ以外 (割合不明)', estimated: true);
      },
      'G': (f) {
        if (f.bbv + f.standardCarriers + f.subs >= 1) return go('J', '航空戦艦 / 正規空母 / 潜水艦を含む');
        if (f.dd == 0) return go('I', '駆逐0隻');
        if (f.cvl >= 2) return go('I', '軽空母2隻以上');
        if (f.cvl == 1) return go('J', '軽空母1隻');
        if (f.dd == 1) return go('I', '駆逐1隻');
        if (f.bb >= 2) return go('J', '(低速)戦艦2隻以上');
        return go('I', 'それ以外');
      },
      'I': (f) {
        if (f.cvl >= 1) return go('J', '軽空母を含む');
        if (f.bbClass >= 3) return go('J', '戦艦級3隻以上');
        if (f.dd >= 3) return go('O', '駆逐3隻以上');
        if (f.cl >= 1 && f.dd >= 2) return go('O', '軽巡1隻以上 かつ 駆逐2隻以上');
        if (f.bbClass >= 2) return go('J', '戦艦級2隻以上');
        if (f.dd >= 2) return go('O', '駆逐2隻以上');
        if (f.cl >= 1 && f.caClass >= 4 && f.caClass + f.cl + f.dd == 6) {
          return go('O', '軽巡1隻以上 かつ 重巡級4隻以上 かつ (重巡級+軽巡+駆逐)6隻');
        }
        return even(['J', 'O'], 'それ以外 (割合不明)', estimated: true);
      },
      'J': (f) {
        if (f.subs >= 1) return even(['L', 'M', 'N'], '潜水艦を含む (割合不明)', estimated: true);
        if (f.bbClass + f.carriers >= 4) return go('M', '(戦艦級+空母系)4隻以上');
        if (f.standardCarriers >= 1) return go('M', '正規空母を含む');
        if (f.cvl >= 2) return go('M', '軽空母2隻以上');
        if (f.cvl == 1) {
          if (f.bb >= 2) return go('N', '軽空母1隻 かつ (低速)戦艦2隻以上');
          if (f.bbv >= 1) return even(['L', 'N'], '軽空母1隻 かつ 航空戦艦を含む (割合不明)', estimated: true);
          if (f.dd >= 3) return go('L', '軽空母1隻 かつ 駆逐3隻以上');
          if (f.cl >= 1 && f.dd >= 2) return go('L', '軽空母1隻 かつ 軽巡1隻以上 かつ 駆逐2隻以上');
          if (f.caClass == 3 && f.dd == 2) return split({'L': 1}, '軽空母1隻 かつ 重巡級3隻 かつ 駆逐2隻 (Wikiでも推測)', estimated: true);
        }
        return even(['L', 'N'], 'それ以外 (駆逐が多いほどLマス寄り・Wikiでも推測)', estimated: true);
      },
      'O': (f) => choose(['K', 'P']),
      'K': (f) {
        if (f.dd >= 4) return go('H', '駆逐4隻以上');
        if (f.dd == 3 && f.cl == 1) return go('H', '駆逐3隻 かつ 軽巡1隻');
        if (f.dd == 2 && (f.allFastPlus || f.bbv + f.ao + f.as >= 1 || f.drumShips >= 2 || f.daihatsuShips >= 2)) {
          return go('H', '駆逐2隻 かつ (高速+以上統一 / 航空戦艦 / 補給艦 / 潜水母艦 / ドラム缶を積んだ艦2隻以上 / 大発動艇系を積んだ艦2隻以上 のどれか)');
        }
        return go('E', 'それ以外');
      },
    },
    note: 'Oマスは能動分岐。$_kDaihatsuNote。ルート分岐法則 2023/02/11',
  ),

  // ---- 5-4 サーモン海域 ----
  CompassMap(
    area: 5,
    no: 4,
    title: 'サーモン海域',
    boss: 'P',
    coefficient: 2,
    edges: {
      1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('B', 'C'), 4: ('A', 'D'), 5: ('B', 'E'), 6: ('A', 'F'), 7: ('C', 'G'), //
      8: ('E', 'H'), 9: ('H', 'I'), 10: ('I', 'J'), 11: ('G', 'K'), 12: ('G', 'L'), 13: ('J', 'M'), 14: ('L', 'N'),
      15: ('M', 'O'), 16: ('L', 'P'), 17: ('B', 'D'), 18: ('D', 'E'), 19: ('D', 'F'), 20: ('F', 'H'), 21: ('K', 'L'),
      22: ('M', 'P'),
    },
    rules: {
      'Start': (f) {
        if (f.carriers >= 1) return go('B', '空母系を含む');
        if (f.bbClass >= 3) return go('A', '戦艦級3隻以上');
        if (f.caClass >= 5) return go('A', '重巡級5隻以上');
        if (f.drumShips + f.daihatsuShips >= 5) return go('B', 'ドラム缶を積んだ艦と大発動艇系を積んだ艦が合わせて5隻以上 (両方積んだ艦は2隻分)');
        if (f.dd >= 4) return go('B', '駆逐4隻以上');
        if (f.cl == 1 && f.dd >= 3) return go('B', '軽巡ちょうど1隻 かつ 駆逐3隻以上');
        return go('A', 'それ以外');
      },
      'A': (f) {
        if (f.subs >= 1) return go('D', '潜水艦を含む');
        if (f.bbClass >= 5) return go('D', '戦艦級5隻以上');
        if (f.dd >= 2) return go('D', '駆逐2隻以上');
        if (f.caClass >= 3) return go('D', '重巡級3隻以上');
        return go('F', 'それ以外');
      },
      'B': (f) {
        if (f.carriers + f.subs >= 1) return go('C', '空母系 または 潜水艦を含む');
        if (f.bbClass >= 1 && f.anySlow) return go('D', '戦艦級 かつ 低速の艦を含む');
        if (f.bbv + f.bb >= 2) return go('D', '(航空戦艦+(低速)戦艦)2隻以上');
        if (f.allFastPlus) return go('E', '高速+以上統一');
        if (f.cl == 1 && f.dd >= 3) return go('E', '軽巡ちょうど1隻 かつ 駆逐3隻以上');
        if (f.dd >= 4) return go('E', '駆逐4隻以上');
        if (f.dd == 0) return go('D', '駆逐0隻');
        return even(['D', 'E'], 'それ以外 (割合不明)', estimated: true);
      },
      'D': (f) {
        if (f.subs >= 1) return go('F', '潜水艦を含む');
        if (f.bb >= 2) return go('F', '(低速)戦艦2隻以上');
        if (f.bbClass >= 3) return go('F', '戦艦級3隻以上');
        if (f.dd >= 2) return go('E', '駆逐2隻以上');
        return go('F', 'それ以外');
      },
      'G': (f) {
        if (f.subs >= 1) return split({'K': 1}, '潜水艦を含む (Wikiでも推測)', estimated: true);
        if (f.bbClass >= 4) return split({'K': 1}, '戦艦級4隻以上 (Wikiでも推測)', estimated: true);
        if (f.standardCarriers <= 2) return go('L', '正規空母2隻以下');
        return lean('K', 'L', 'それ以外 (Kマス寄り)', 70);
      },
      'L': (f) {
        if (f.allFastPlus) return go('P', '高速+以上統一');
        final los = f.losScore(2);
        final score = _los(los);
        if (los < 56) return go('N', '$score (56未満。境目はWikiでも推測)');
        if (los < 60) return even(['N', 'P'], '$score (56以上60未満はランダム・割合不明)', estimated: true);
        if (f.bbClass + f.standardCarriers >= 5) return even(['N', 'P'], '$score かつ (戦艦級+正規空母)5隻以上 (割合不明)', estimated: true);
        return go('P', '$score (60以上。境目はWikiでも推測)');
      },
      'M': (f) {
        if (f.allFastPlus) return go('P', '高速+以上統一');
        final los = f.losScore(2);
        final range = los < 41 ? '41未満。境目はWikiでも推測' : (los < 45 ? '41以上45未満はランダム・割合不明' : '45以上');
        var p = los < 41 ? 0.0 : (los < 45 ? 0.5 : 1.0);
        final sub = f.subs >= 1;
        if (sub) p *= 0.7;
        final reason = '${_los(los)} ($range)${sub ? '。潜水艦を含むのでPマスの割合は0.7倍' : ''}';
        if (p <= 0) return go('O', reason);
        if (p >= 1) return go('P', reason);
        final unknown = los < 45;
        return BranchOutcome([RouteOption('P', p, estimated: unknown), RouteOption('O', 1 - p, estimated: unknown)], reason);
      },
    },
    note: '分岐点係数2。$_kDaihatsuNote。$_kLosNote。ルート分岐法則 2020/06/08',
  ),

  // ---- 5-5 サーモン海域北方 ----
  CompassMap(
    area: 5,
    no: 5,
    title: 'サーモン海域北方',
    boss: 'S',
    coefficient: 2,
    edges: {
      1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('A', 'C'), 4: ('F', 'D'), 5: ('C', 'E'), 6: ('B', 'F'), 7: ('E', 'G'), //
      8: ('D', 'H'), 9: ('G', 'I'), 10: ('F', 'J'), 11: ('B', 'K'), 12: ('H', 'L'), 13: ('I', 'M'), 14: ('H', 'N'),
      15: ('M', 'O'), 16: ('H', 'P'), 17: ('P', 'Q'), 18: ('O', 'R'), 19: ('O', 'S'), 20: ('E', 'H'), 21: ('I', 'L'),
      22: ('M', 'L'), 23: ('N', 'M'), 24: ('L', 'N'), 25: ('N', 'O'), 26: ('J', 'P'), 27: ('K', 'P'), 28: ('P', 'S'),
    },
    rules: {
      'Start': (f) {
        if (f.dd >= 4) return go('A', '駆逐4隻以上');
        if (f.drumShips >= 4) return go('A', 'ドラム缶を積んだ艦4隻以上');
        if (f.daihatsuShips >= 4) return go('A', '大発動艇系を積んだ艦4隻以上');
        return go('B', 'それ以外');
      },
      'B': (f) {
        if (f.standardCarriers >= 3) return go('K', '正規空母3隻以上');
        if (f.bbClass + f.clt >= 4) return go('K', '(戦艦級+雷巡)4隻以上');
        if (f.clt >= 3) return go('K', '雷巡3隻以上');
        if (f.dd <= 1) return go('K', '駆逐1隻以下');
        return go('F', 'それ以外');
      },
      'E': (f) {
        if (f.allFastest) return go('H', '最速統一');
        if (f.dd >= 2 && f.allFastPlus) return go('H', '駆逐2隻以上 かつ 高速+統一');
        return go('G', 'それ以外');
      },
      'F': (f) => choose(['D', 'J']),
      'H': (f) {
        if (f.allFastest) return go('N', '最速統一');
        if (f.bbClass + f.carriers >= 4) return go('P', '(戦艦級+空母系)4隻以上');
        if (f.dd <= 1) return go('L', '駆逐1隻以下');
        return go('N', 'それ以外');
      },
      'I': (f) {
        if (f.bbClass + f.carriers == 3 && f.dd >= 2) return go('L', '(戦艦級+空母系)ちょうど3隻 かつ 駆逐2隻以上');
        return go('M', 'それ以外');
      },
      'O': (f) {
        if (f.allFastPlus) return go('S', '高速+以上統一');
        final los = f.losScore(2);
        final score = _los(los);
        if (los < 63) return go('R', '$score (63未満)');
        if (los < 66) return even(['R', 'S'], '$score (63以上66未満はランダム・割合不明)', estimated: true);
        if (f.subs >= 1) return even(['R', 'S'], '$score (66以上) かつ 潜水艦を含む (割合不明)', estimated: true);
        return go('S', '$score (66以上)');
      },
      'P': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.allFastest) return go('S', '最速統一');
        if (f.allFastPlus) {
          if (f.subs >= 1) return even(['Q', 'S'], '高速+統一 かつ 潜水艦を含む (割合不明)', estimated: true);
          if (heavy <= 5) return go('S', '高速+統一 かつ (戦艦級+空母系)5隻以下');
          return even(['Q', 'S'], '高速+統一 (それ以外。割合不明)', estimated: true);
        }
        final los = f.losScore(2);
        final score = _los(los);
        if (los < 73) return go('Q', '$score (73未満)');
        if (los < 80) return even(['Q', 'S'], '$score (73以上80未満はランダム・割合不明)', estimated: true);
        if (f.subs >= 1) return even(['Q', 'S'], '$score (80以上) かつ 潜水艦を含む (割合不明)', estimated: true);
        if (heavy >= 5) return even(['Q', 'S'], '$score (80以上) かつ (戦艦級+空母系)5隻以上 (割合不明)', estimated: true);
        return go('S', '$score (80以上)');
      },
    },
    pathRules: {
      'M': (f, path) {
        if (path.contains('N')) return go('O', 'Nマスを通ってきた');
        if (f.bbClass + f.carriers >= 4) return go('L', '(戦艦級+空母系)4隻以上');
        if (f.dd <= 1) return go('L', '駆逐1隻以下');
        return go('O', 'それ以外');
      },
      'N': (f, path) {
        if (path.contains('M')) return go('O', 'Mマスを通ってきた');
        if (f.allFastPlus) return go('O', '高速+以上統一');
        if (f.ao >= 1) return go('O', '補給艦を含む');
        if (f.standardCarriers >= 1) return go('M', '正規空母1隻以上');
        if (f.bbClass + f.cvl >= 3) return go('M', '(戦艦級+軽空母)3隻以上');
        if (f.dd <= 1) return go('M', '駆逐1隻以下');
        return go('O', 'それ以外');
      },
    },
    note: '分岐点係数2。Fマスは能動分岐。$_kDaihatsuNote。$_kLosNote。ルート分岐法則 2020/02/08',
  ),

  // ---- 5-6 ラバウル方面海域 (第1ゲージ・第2ゲージ・第3ゲージ) ----
  _map56('第1ゲージ G', 'G', start2Open: false, gauge2Broken: false),
  _map56('第2ゲージ N', 'N', start2Open: true, gauge2Broken: false),
  _map56('第3ゲージ Z', 'Z', start2Open: true, gauge2Broken: true),
];

// 5-6 は出撃地点が2つある。api_no 35 は出撃地点2そのもの (kancolle-replay では自分自身への線)。
// 出撃地点1へは API で番号が来ないので、-1 を仮に使う。
const Map<int, (String, String)> _kEdges56 = {
  -1: ('Start', 'Start 1'), 35: ('Start', 'Start 2'), //
  1: ('Start 1', 'A1'), 2: ('Start 1', 'A2'), 3: ('Start 1', 'A'), 4: ('A2', 'B'), 5: ('B', 'C1'), 6: ('A', 'C2'),
  7: ('A2', 'C'), 8: ('C2', 'D'), 9: ('D', 'E'), 10: ('E', 'F'), 11: ('E', 'G'), 12: ('A1', 'A2'), 13: ('A', 'B'),
  14: ('B', 'C2'), 15: ('C1', 'C2'), 16: ('B', 'C'), 17: ('C1', 'C'), 18: ('C', 'H'), 19: ('H', 'R'), 20: ('Start 2', 'I'),
  21: ('I', 'J'), 22: ('J', 'K1'), 23: ('J', 'K'), 24: ('K', 'K2'), 25: ('K', 'L'), 26: ('L', 'M'), 27: ('L', 'N'),
  28: ('I', 'O'), 29: ('O', 'P'), 30: ('O', 'Q'), 31: ('P', 'Q1'), 32: ('Q', 'Q2'), 33: ('K1', 'K'), 34: ('K2', 'L'),
  36: ('Q1', 'S'), 37: ('Q1', 'T'), 38: ('Q', 'U'), 39: ('Q2', 'V'), 40: ('V', 'W'), 41: ('U', 'X'), 42: ('X', 'Y'),
  43: ('X', 'Z'), 44: ('V', 'X'), 45: ('W', 'X'), 46: ('Q1', 'Q2'), 47: ('Q2', 'T'), 48: ('Q', 'W'),
};

/// 索敵で分岐するが、必要な索敵スコアがわからないマス (足りれば [pass] へ進むとして、割合不明の推定にする)
BranchOutcome _unknownLos(String pass, String fail) => lean(pass, fail, '索敵で分岐 (必要な索敵スコアは不明。足りれば$passマス)');

CompassMap _map56(String phase, String boss, {required bool start2Open, required bool gauge2Broken}) => CompassMap(
      area: 5,
      no: 6,
      title: 'ラバウル方面海域',
      boss: boss,
      phase: phase,
      edges: _kEdges56,
      rules: {
        'Start': (f) {
          if (!start2Open) return go('Start 1', '出撃地点2が開く前');
          if (f.bbClass >= 2 && f.anySlow) return go('Start 1', '戦艦級2隻以上 かつ 低速の艦を含む');
          if (f.av + f.lha >= 1) return go('Start 1', '(水母+揚陸艦)1隻以上');
          return go('Start 2', 'それ以外');
        },
        'Start 1': (f) {
          if (f.standardCarriers == 0 && f.dd >= 4) return go('A', '正規空母0隻 かつ 駆逐4隻以上');
          if (f.lha >= 1 && f.dd >= 2) return go('A', '揚陸艦1隻以上 かつ 駆逐2隻以上');
          if (f.bbClass >= 2 && f.dd <= 2) return go('A1', '戦艦級2隻以上 かつ 駆逐2隻以下');
          if (f.standardCarriers == 0 && f.dd >= 2) return go('A2', '正規空母0隻 かつ 駆逐2隻以上');
          return go('A1', 'それ以外');
        },
        'A': (f) {
          if (f.caClass >= 1 && f.anySlow) return go('B', '重巡級 かつ 低速の艦を含む');
          if (f.bbClass + f.carriers + f.named('あきつ丸') == 0) return go('C2', '(戦艦級+空母系+あきつ丸)0隻');
          return go('B', 'それ以外');
        },
        'A2': (f) {
          final ok = f.allFast &&
              f.standardCarriers == 0 &&
              f.bbClass + f.cvl + f.caClass <= 2 &&
              f.caClass <= 1 &&
              ((f.cl >= 1 && f.dd >= 2) || f.dd >= 3);
          if (ok) return go('C', '高速以上統一 かつ 正規空母0隻 かつ (戦艦級+軽空母+重巡級)2隻以下 かつ 重巡級1隻以下 かつ (軽巡1隻以上と駆逐2隻以上 または 駆逐3隻以上)');
          return go('B', 'それ以外');
        },
        'B': (f) {
          if (f.bbv == 2 && f.dd == 4) return go('C2', '航空戦艦2隻 かつ 駆逐4隻');
          final light = f.bbClass + f.cvl;
          if (light <= 1 && !(f.anySlow && light == 1 && f.dd > 3) && f.standardCarriers == 0) {
            return go('C', '(戦艦級+軽空母)1隻以下 かつ 正規空母0隻 (低速の艦を含み戦艦級か軽空母が1隻なら駆逐3隻以下)');
          }
          return go('C1', 'それ以外');
        },
        'E': (f) => _unknownLos('G', 'F'),
        'I': (f) => choose(['J', 'O']),
        'J': (f) {
          if (f.anySlow && f.bbClass + f.standardCarriers >= 3) return go('K1', '低速の艦を含む かつ (戦艦級+正規空母)3隻以上');
          if ((f.cl >= 1 && f.dd >= 2) || f.dd >= 3) return go('K', '軽巡1隻以上と駆逐2隻以上 または 駆逐3隻以上');
          return go('K1', 'それ以外');
        },
        'K': (f) {
          if (f.allFast && f.bbClass + f.carriers <= 2 && f.cl >= 1 && f.dd >= 2) {
            return go('L', '高速以上統一 かつ (戦艦級+空母系)2隻以下 かつ 軽巡1隻以上 かつ 駆逐2隻以上');
          }
          return go('K2', 'それ以外');
        },
        'L': (f) => _unknownLos('N', 'M'),
        'O': (f) => choose(['P', 'Q']),
        'Q': (f) {
          if (!gauge2Broken) return go('Q2', '第2ゲージを壊す前');
          if (f.allFastPlus) return go('W', '高速+以上統一');
          if (f.cl >= 1 && f.dd >= 3) return go('W', '軽巡1隻以上 かつ 駆逐3隻以上');
          final bbcv = f.bbClass + f.standardCarriers;
          if (bbcv <= 3 && (bbcv < 3 || f.cl >= 1) && f.dd >= 2) {
            return go('U', '(戦艦級+正規空母)3隻以下 (3隻なら軽巡1隻以上) かつ 駆逐2隻以上');
          }
          return go('Q2', 'それ以外');
        },
        'Q1': (f) {
          final pass = f.standardCarriers <= 1 && f.dd >= 2 ? 'T' : 'Q2';
          return lean(pass, 'S', '索敵が足りないとSマス (必要な索敵スコアは不明)。足りれば${pass == 'T' ? '正規空母1隻以下 かつ 駆逐2隻以上なのでTマス' : 'Q2マス'}');
        },
        'V': (f) {
          if (f.allFast && f.bbClass + f.carriers <= 3 && f.carriers <= 2 && f.dd >= 2) {
            return go('X', '高速以上統一 かつ (戦艦級+空母系)3隻以下 かつ 空母系2隻以下 かつ 駆逐2隻以上');
          }
          return go('W', 'それ以外');
        },
        'X': (f) => _unknownLos('Z', 'Y'),
      },
      pathRules: {
        'C1': (f, path) => path.contains('A') ? go('C2', 'Aマスを通ってきた') : go('C', 'それ以外'),
        'Q2': (f, path) => path.contains('P') ? go('T', 'Pマスを通ってきた') : go('V', 'それ以外'),
      },
      note: '出撃地点が2つ (出撃地点2はギミック後)。I・Oマスは能動分岐。索敵の境目と分岐点係数はWikiに記載がないため、'
          '索敵マスは「足りれば進む」を75%とした推定。ルート分岐法則 2026/07/01',
    );
