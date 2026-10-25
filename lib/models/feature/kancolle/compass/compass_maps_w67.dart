import 'compass_engine.dart';

// 6-1〜7-5 の分岐条件。艦これ攻略 Wiki* の各海域ページ「ルート分岐法則」の内容を元に書き直したもの。
// 表記は compass_maps_w12.dart と同じ。「重巡」は艦種が重巡のもの (航巡は含まない)。
// 「?」付きなど Wiki でも確かでない条件や、割合が書かれていないランダムは estimated (推定) として扱う。

const _kLosNote = '索敵スコアは司令部Lv120のときの値なので、120未満なら+1以上の余裕を';

String _los(double los) => '索敵スコア${los.toStringAsFixed(1)}';

/// 大鷹型 (大鷹・雲鷹・神鷹。改・改二も含む) の数
int _taiyo(CompassFleet f) => f.named('大鷹') + f.named('雲鷹') + f.named('神鷹');

final List<CompassMap> kCompassMapsWorld67 = [
  // ---- 6-1 中部海域哨戒線 ----
  CompassMap(
    area: 6,
    no: 1,
    title: '中部海域哨戒線',
    boss: 'K',
    coefficient: 4,
    edges: {
      1: ('Start', 'B'), 2: ('Start', 'A'), 3: ('Start', 'C'), 4: ('A', 'D'), 5: ('A', 'F'), 6: ('F', 'G'), 7: ('G', 'I'), //
      8: ('G', 'H'), 9: ('H', 'E'), 10: ('H', 'J'), 11: ('H', 'K'), 12: ('C', 'F'), 13: ('D', 'F'),
    },
    rules: {
      'Start': (f) {
        if (f.bbClass + f.carriers + f.caClass >= 3 || f.bbClass >= 2) return go('B', '(戦艦級+空母系+重巡級)3隻以上 または 戦艦級2隻以上');
        if (f.subs >= 3 && f.subs == f.n) return go('A', '潜水艦3隻以上 かつ 潜水艦だけ');
        if (f.as == 1 && f.subs >= 3 && f.subs + f.as == f.n) return go('A', '潜水母艦1隻 かつ 潜水艦3隻以上 (ほかの艦種なし)');
        if (f.as == 1 && f.subs == 3 && f.dd == 2) return go('A', '潜水母艦1隻 かつ 潜水艦3隻 かつ 駆逐2隻');
        if (f.as == 1 && f.subs == 4 && f.cl + f.dd == 1) return go('A', '潜水母艦1隻 かつ 潜水艦4隻 かつ (軽巡+駆逐)1隻');
        if (f.cl + f.dd == 0) return go('B', '(軽巡+駆逐)0隻');
        return go('C', 'それ以外');
      },
      'A': (f) => f.as >= 1 ? go('F', '潜水母艦を含む') : go('D', 'それ以外'),
      'G': (f) {
        final los = f.losScore(4);
        final score = _los(los);
        if (f.subs <= 2) return go('I', '潜水艦2隻以下');
        if (f.bbClass + f.carriers + f.caClass == 2) return go('I', '(戦艦級+空母系+重巡級)2隻');
        if (los < 12) return go('I', '$score (12未満)');
        if (los >= 16) {
          if (f.as >= 1) return go('H', '$score (16以上) かつ 潜水母艦を含む');
          return lean('H', 'I', '$score (16以上) (Hマス寄り)', 85);
        }
        return even(['H', 'I'], '$score (12以上16未満はランダム・割合不明)', estimated: true);
      },
      'H': (f) {
        final los = f.losScore(4);
        final score = _los(los);
        if (los < 20) return go('E', '$score (20未満)');
        if (f.as >= 1) {
          if (los < 25) return even(['E', 'K'], '$score (20以上25未満) かつ 潜水母艦を含む (割合不明)', estimated: true);
          return go('K', '$score (25以上) かつ 潜水母艦を含む');
        }
        if (los < 25) return even(['E', 'J', 'K'], '$score (20以上25未満はランダム・割合不明)', estimated: true);
        if (los < 36) return even(['J', 'K'], '$score (25以上36未満はランダム・割合不明)', estimated: true);
        return go('K', '$score (36以上)');
      },
    },
    note: '分岐点係数4。潜水母艦は大鯨・迅鯨・長鯨・平安丸 (潜水空母ではない)。$_kLosNote。ルート分岐法則 2019/10/16',
  ),

  // ---- 6-2 MS諸島沖 ----
  CompassMap(
    area: 6,
    no: 2,
    title: 'MS諸島沖',
    boss: 'K',
    coefficient: 3,
    edges: {
      1: ('Start', 'B'), 2: ('Start', 'C'), 3: ('C', 'A'), 4: ('B', 'D'), 5: ('D', 'F'), 6: ('C', 'E'), 7: ('D', 'H'), //
      8: ('H', 'G'), 9: ('F', 'I'), 10: ('E', 'J'), 11: ('H', 'K'), 12: ('B', 'C'), 13: ('C', 'D'), 14: ('E', 'F'),
      15: ('I', 'G'), 16: ('E', 'I'), 17: ('I', 'K'), 18: ('J', 'K'),
    },
    rules: {
      'Start': (f) {
        if (f.cl + f.dd >= 4) return go('B', '(軽巡+駆逐)4隻以上');
        if (f.bbv + f.cav + f.av + f.lha <= 1 && f.subs <= 4) {
          const base = '(航空戦艦+航巡+水母+揚陸艦)1隻以下 かつ 潜水艦4隻以下 かつ';
          final heavy = f.bbClass + f.carriers;
          if (heavy >= 5) return go('B', '$base (戦艦級+空母系)5隻以上');
          if (heavy == 4) return lean('B', 'C', '$base (戦艦級+空母系)4隻 (Bマス寄り)', 65);
        }
        return go('C', 'それ以外');
      },
      'B': (f) {
        if (f.cl + f.dd >= 5) return go('D', '(軽巡+駆逐)5隻以上');
        if (f.carriers <= 2 && f.bbClass == 0) return lean('C', 'D', '空母系2隻以下 かつ 戦艦級0隻 (Cマス寄り)', 70);
        return go('C', 'それ以外');
      },
      'C': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.subs >= 6) return go('A', '潜水艦6隻');
        if (heavy >= 5) return go('A', '(戦艦級+空母系)5隻以上');
        if (heavy + f.caClass >= 6) return go('A', '(戦艦級+空母系+重巡級)6隻');
        if (heavy + f.subs >= 6) return go('A', '(戦艦級+空母系+潜水艦)6隻');
        if (heavy <= 2) return go('E', '(戦艦級+空母系)2隻以下');
        return go('D', 'それ以外');
      },
      'D': (f) {
        if (f.dd <= 2) return go('F', '駆逐2隻以下');
        if (f.bbClass + f.carriers >= 1) return go('F', '戦艦級 または 空母系を含む');
        if (f.cl + f.dd <= 4) return go('F', '(軽巡+駆逐)4隻以下');
        return go('H', 'それ以外');
      },
      'E': (f) {
        if (f.bbClass >= 2 || f.carriers >= 2 || f.dd <= 1) return go('F', '戦艦級2隻以上 / 空母系2隻以上 / 駆逐1隻以下 のどれか');
        return byLos(f, 3, low: 43, high: 50, below: 'I', above: 'J');
      },
      'H': (f) => byLos(f, 3, low: 32, high: 32, below: 'G', above: 'K'),
      'I': (f) {
        if (f.subs >= 4) return go('G', '潜水艦4隻以上');
        return byLos(f, 3, low: 35, high: 40, below: 'G', above: 'K', guessed: true);
      },
    },
    note: '分岐点係数3。$_kLosNote。ルート分岐法則 2019/10/16',
  ),

  // ---- 6-3 グアノ環礁沖海域 ----
  CompassMap(
    area: 6,
    no: 3,
    title: 'グアノ環礁沖海域',
    boss: 'J',
    coefficient: 3,
    edges: {
      1: ('Start', 'A'), 2: ('A', 'B'), 3: ('A', 'C'), 4: ('B', 'D'), 5: ('C', 'E'), 6: ('E', 'F'), 7: ('E', 'G'), //
      8: ('F', 'H'), 9: ('H', 'I'), 10: ('H', 'J'), 11: ('D', 'E'), 12: ('G', 'H'),
    },
    rules: {
      'A': (f) => choose(['B', 'C']),
      'E': (f) {
        if (f.av <= 1) {
          if (f.cl <= 1 && f.dd >= 3) return go('G', '水母1隻以下 かつ 軽巡1隻以下 かつ 駆逐3隻以上');
          if (f.cl <= 2) return lean('F', 'G', '水母1隻以下 かつ 軽巡2隻以下 (Fマス寄り)', 60);
        }
        return go('F', 'それ以外');
      },
      'H': (f) => byLos(f, 3, low: 36, high: 38, below: 'I', above: 'J'),
    },
    note: '分岐点係数3。Aマスは能動分岐。$_kLosNote。ルート分岐法則 2019/10/12',
  ),

  // ---- 6-4 中部北海域ピーコック島沖 ----
  CompassMap(
    area: 6,
    no: 4,
    title: '中部北海域ピーコック島沖',
    boss: 'N',
    edges: {
      1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('D', 'C'), 4: ('A', 'D'), 5: ('A', 'E'), 6: ('C', 'F'), 7: ('E', 'G'), //
      8: ('K', 'H'), 9: ('J', 'I'), 10: ('H', 'J'), 11: ('M', 'K'), 12: ('J', 'L'), 13: ('Start', 'M'), 14: ('F', 'N'),
      15: ('B', 'D'), 16: ('E', 'D'), 17: ('G', 'D'), 18: ('K', 'J'), 19: ('L', 'I'), 20: ('I', 'N'), 21: ('J', 'N'),
    },
    rules: {
      'Start': (f) {
        final nagamutsu = f.bbClass == 2 && f.has('長門改二') && f.has('陸奥改二');
        if (f.lha >= 1 || f.carriers >= 1 || (f.bbClass >= 2 && !nagamutsu) || f.cav >= 3) {
          return go('M', '揚陸艦 / 空母系 / 戦艦級2隻 (長門改二と陸奥改二の組は除く) / 航巡3隻以上 のどれかを含む');
        }
        if (f.allFast && ((f.flagshipType == kCL && f.dd >= 3) || f.dd >= 4)) {
          return go('B', '高速統一 かつ (軽巡旗艦で駆逐3隻 または 駆逐4隻以上)');
        }
        if (f.dd >= 2) return go('A', '駆逐2隻以上');
        return go('M', 'それ以外');
      },
      'A': (f) {
        if (f.has('秋津洲') && (f.cav == 1 || f.cl >= 1 || f.dd >= 3)) {
          return go('D', '秋津洲 かつ (航巡ちょうど1隻 / 軽巡1隻以上 / 駆逐3隻以上 のどれか)');
        }
        if (f.bbClass >= 1) return go('E', '戦艦級を含む');
        if (f.anySlow) return go('E', '低速の艦を含む');
        if (f.flagshipType == kCL) return go('D', '軽巡旗艦');
        if (f.dd >= 3) return go('D', '駆逐3隻以上');
        return go('E', 'それ以外');
      },
      'E': (f) {
        if (f.has('秋津洲') || f.has('如月')) return go('D', '秋津洲 または 如月を含む');
        if (f.caClass <= 1 && f.cl >= 1 && f.allFast) return go('D', '重巡級1隻以下 かつ 軽巡1隻以上 かつ 高速統一');
        return go('G', 'それ以外');
      },
      'J': (f) {
        if (f.cl == 0) return go('L', '軽巡0隻');
        if (f.dd <= 1) return go('L', '駆逐1隻以下');
        if (f.lha >= 1) return go('N', '揚陸艦を含む');
        if (f.carriers == 2 && f.anySlow) return go('L', '空母系2隻 かつ 低速の艦を含む');
        if (f.carriers == 2 && f.bbClass >= 1) return go('L', '空母系2隻 かつ 戦艦級を含む');
        return go('I', 'それ以外');
      },
      'K': (f) {
        if (f.bbClass == 2) return go('H', '戦艦級2隻');
        if (f.bbClass + f.caClass >= 3) return go('H', '(戦艦級+重巡級)3隻以上');
        if (f.dd >= 2) return go('J', '駆逐2隻以上');
        return go('H', 'それ以外');
      },
    },
    note: '長門改二・陸奥改二・秋津洲・如月は艦名で判定。ルート分岐法則 2019/10/16',
  ),

  // ---- 6-5 KW環礁沖海域 ----
  CompassMap(
    area: 6,
    no: 5,
    title: 'KW環礁沖海域',
    boss: 'M',
    coefficient: 3,
    edges: {
      1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('A', 'C'), 4: ('C', 'D'), 5: ('C', 'E'), 6: ('B', 'F'), 7: ('D', 'G'), //
      8: ('E', 'H'), 9: ('E', 'I'), 10: ('I', 'J'), 11: ('G', 'K'), 12: ('J', 'L'), 13: ('G', 'M'), 14: ('B', 'C'),
      15: ('H', 'G'), 16: ('I', 'H'), 17: ('F', 'I'), 18: ('J', 'M'),
    },
    rules: {
      'Start': (f) {
        if (f.cl == 0) return go('A', '軽巡0隻');
        if (f.carriers + f.clt >= 1) return go('A', '空母系 または 雷巡を含む');
        if (f.bbClass >= 4) return go('A', '戦艦級4隻以上');
        return go('B', 'それ以外');
      },
      'B': (f) {
        if (f.bbClass == 3) return go('C', '戦艦級3隻');
        if (f.dd <= 1) return go('C', '駆逐1隻以下');
        return go('F', 'それ以外');
      },
      'C': (f) {
        if (f.dd == 0) return go('E', '駆逐0隻');
        if (f.clt >= 2) return go('E', '雷巡2隻以上');
        if (f.bbClass + f.carriers >= 4) return go('E', '(戦艦級+空母系)4隻以上');
        if (f.bbClass + f.carriers + f.caClass >= 5) return go('E', '(戦艦級+空母系+重巡級)5隻以上');
        return go('D', 'それ以外');
      },
      'E': (f) {
        if (f.carriers >= 1 && f.cl >= 1 && f.dd >= 1) return go('H', '空母系 かつ 軽巡 かつ 駆逐を含む');
        return go('I', 'それ以外');
      },
      'G': (f) => byLos(f, 3, low: 50, high: 50, below: 'K', above: 'M'),
      'I': (f) {
        if (f.cl == 0) return go('H', '軽巡0隻');
        if (f.dd >= 2) return go('J', '駆逐2隻以上');
        if (f.bbClass == 0 && f.carriers + f.caClass <= 4 && f.carriers <= 2 && f.caClass <= 4) {
          return go('J', '戦艦級0隻 かつ (空母系+重巡級)4隻以下 かつ 空母系2隻以下 かつ 重巡級4隻以下');
        }
        return go('H', 'それ以外');
      },
      'J': (f) => byLos(f, 3, low: 35, high: 35, below: 'L', above: 'M', guessed: true),
    },
    note: '分岐点係数3。$_kLosNote。ルート分岐法則 2019/11/09',
  ),

  // ---- 7-1 ブルネイ泊地沖 ----
  CompassMap(
    area: 7,
    no: 1,
    title: 'ブルネイ泊地沖',
    boss: 'K',
    edges: {
      1: ('B', 'A'), 2: ('Start', 'B'), 3: ('A', 'C'), 4: ('Start', 'D'), 5: ('C', 'E'), 6: ('Start', 'F'), 7: ('E', 'G'), //
      8: ('G', 'H'), 9: ('H', 'I'), 10: ('H', 'J'), 11: ('H', 'K'), 12: ('B', 'C'), 13: ('D', 'C'), 14: ('D', 'E'),
      15: ('F', 'G'),
    },
    rules: {
      'Start': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.subs >= 1) {
          if (heavy >= 1) return even(['B', 'D'], '潜水艦 かつ (戦艦級+空母系)1隻以上 (割合不明)', estimated: true);
          if (f.n >= 5) return even(['B', 'D'], '潜水艦 かつ 5隻以上の編成 (割合不明)', estimated: true);
          return even(['B', 'D', 'F'], '潜水艦 かつ 4隻以下の編成 (割合不明)', estimated: true);
        }
        if (heavy >= 1) return go('B', '(戦艦級+空母系)1隻以上');
        if (f.n >= 6) return go('B', '6隻編成');
        if (f.n == 5 || f.ao >= 1) return go('D', '5隻編成 または 補給艦を含む');
        return go('F', '4隻以下の編成');
      },
      'B': (f) {
        if (f.bbClass + f.standardCarriers >= 1) return go('A', '(戦艦級+正規空母)1隻以上');
        if (f.cvl >= 2) return go('A', '軽空母2隻以上');
        if (f.caClass >= 3) return go('A', '重巡級3隻以上');
        if (f.ddde >= 2) return go('C', '(駆逐+海防)2隻以上');
        return even(['A', 'C'], 'それ以外 (割合不明)', estimated: true);
      },
      'D': (f) {
        if (f.cl == 1 && f.dd == 4) return go('E', '軽巡1隻 かつ 駆逐4隻');
        if (f.dd >= 1 && f.de >= 3) return go('E', '駆逐1隻以上 かつ 海防艦3隻以上');
        if (f.ao >= 1 && f.de >= 3) return go('E', '補給艦1隻以上 かつ 海防艦3隻以上');
        if (f.ddde == 5) return go('E', '(駆逐+海防)5隻');
        if (f.ddde == 4) {
          if (f.ct >= 1) return go('E', '(駆逐+海防)4隻 かつ 練巡を含む');
          if (f.ao >= 1) return go('E', '(駆逐+海防)4隻 かつ 補給艦を含む');
          if (f.av >= 1) return even(['C', 'E'], '(駆逐+海防)4隻 かつ 水母を含む (割合不明)', estimated: true);
        }
        return go('C', 'それ以外');
      },
      'H': (f) {
        final heavy = f.bbClass + f.carriers;
        if (f.cl >= 1 && f.dd >= 4) return go('K', '軽巡1隻以上 かつ 駆逐4隻以上');
        if (f.dd >= 1 && f.de >= 3) return go('K', '駆逐1隻以上 かつ 海防艦3隻以上');
        if (f.ao >= 1) return even(['I', 'K'], '補給艦を含む (Wikiでも推測)', estimated: true);
        if (heavy >= 2) return go('J', '(戦艦級+空母系)2隻以上');
        return split({'I': 22.5, 'J': 7.5, 'K': 70},
            '${heavy == 1 ? '(戦艦級+空母系)1隻' : 'それ以外'} (ランダム。割合はWikiでも推測)', estimated: true);
      },
    },
    note: 'ルート分岐法則 2020/03/07',
  ),

  // ---- 7-2 タウイタウイ泊地沖 (第1ゲージ・第2ゲージ) ----
  _map72('第1ゲージ G', 'G'),
  _map72('第2ゲージ M', 'M'),

  // ---- 7-3 ペナン島沖 (第1ゲージ・第2ゲージ) ----
  CompassMap(
    area: 7,
    no: 3,
    title: 'ペナン島沖',
    boss: 'E',
    phase: '第1ゲージ E',
    edges: {1: ('Start', 'A'), 2: ('A', 'B'), 3: ('A', 'C'), 4: ('C', 'D'), 5: ('C', 'E'), 6: ('D', 'F'), 7: ('B', 'C'), 8: ('D', 'E')},
    rules: {
      'A': (f) {
        if (f.n == 1) return go('C', '1隻編成');
        if (f.ca == 0) return go('B', '重巡0隻');
        if (f.carriers >= 1) return go('B', '空母系を含む');
        if (f.ddde == 0) return go('B', '(駆逐+海防)0隻');
        if (f.n >= 5) return go('B', '5隻以上の編成');
        if (_hagurokamikaze(f)) return go('C', '羽黒 と 神風を含む');
        return _a73small(f);
      },
      'C': (f) {
        if (f.bbClass + f.carriers >= 1) return go('D', '(戦艦級+空母系)1隻以上');
        if (f.ddde == 0) return go('D', '(駆逐+海防)0隻');
        if (f.n >= 5) return go('D', '5隻以上の編成');
        if (_hagurokamikaze(f)) return _c73hk(f);
        return _c73small(f);
      },
      'D': (f) {
        if (f.bbClass + f.carriers >= 1) return go('F', '(戦艦級+空母系)1隻以上');
        if (f.n >= 6) return go('F', '6隻編成');
        if (f.caClass >= 4) return go('F', '重巡級4隻以上');
        if (f.cav >= 2) return go('F', '航巡2隻以上');
        return go('E', 'それ以外');
      },
    },
    note: '羽黒・神風・足柄・妙高・高雄は艦名で判定。ルート分岐法則 2020/09/23',
  ),
  CompassMap(
    area: 7,
    no: 3,
    title: 'ペナン島沖',
    boss: 'P',
    phase: '第2ゲージ P',
    edges: {
      1: ('Start', 'A'), 2: ('A', 'B'), 3: ('A', 'C'), 4: ('C', 'D'), 5: ('C', 'E'), 6: ('D', 'F'), 7: ('B', 'C'), //
      8: ('D', 'E'), 9: ('D', 'G'), 10: ('G', 'H'), 11: ('C', 'I'), 12: ('G', 'J'), 13: ('G', 'K'), 14: ('I', 'L'),
      15: ('I', 'M'), 16: ('M', 'N'), 17: ('M', 'O'), 18: ('G', 'P'), 19: ('G', 'I'), 20: ('I', 'J'), 21: ('J', 'M'),
      22: ('L', 'M'), 23: ('J', 'P'), 24: ('K', 'P'), 25: ('M', 'P'),
    },
    rules: {
      'A': (f) {
        if (f.n == 1) return go('C', '1隻編成');
        if (f.carriers >= 1) return go('B', '空母系を含む');
        if (f.ao == 1 && f.ddde >= 3) return go('C', '補給艦1隻 かつ (駆逐+海防)3隻以上');
        if (f.ca == 0) return go('B', '重巡0隻');
        if (f.ddde == 0) return go('B', '(駆逐+海防)0隻');
        if (f.bbClass >= 1 && !f.has('羽黒')) return go('B', '戦艦級を含み 羽黒を含まない');
        if (_hagurokamikaze(f)) return go('C', '羽黒 と 神風を含む');
        if (f.n >= 5) {
          if (!f.has('羽黒') && f.anySlow) return go('B', '5隻以上の編成 かつ 羽黒なし かつ 低速の艦を含む');
          if (f.ddde <= 2) return go('B', '5隻以上の編成 かつ (駆逐+海防)2隻以下');
          return go('C', '5隻以上の編成 (それ以外)');
        }
        return _a73small(f);
      },
      'C': (f) {
        if (f.bbClass + f.carriers >= 1) return go('D', '(戦艦級+空母系)1隻以上');
        if (f.ddde == 0) return go('D', '(駆逐+海防)0隻');
        if (f.allFastest) return go('I', '最速統一');
        if (f.n >= 5) {
          if (f.allFastPlus && f.cl + f.dd >= 4) return go('I', '5隻以上 かつ 高速+統一 かつ (軽巡+駆逐)4隻以上');
          if (f.n >= 6) return go('D', '6隻編成');
          if (_hagurokamikaze(f)) {
            if (f.ddde <= 1) return go('D', '5隻編成 かつ 羽黒と神風 かつ (駆逐+海防)1隻以下');
            if (f.cl >= 1 || f.has('足柄')) return go('I', '5隻編成 かつ 羽黒と神風 かつ (軽巡 または 足柄を含む)');
            return go('D', '5隻編成 かつ 羽黒と神風 (それ以外)');
          }
          if (f.allFast && f.ca == 1 && f.cl == 1 && f.dd == 3) return go('I', '5隻編成 かつ 高速統一 かつ 重巡1隻・軽巡1隻・駆逐3隻');
          return go('D', '5隻編成 (それ以外)');
        }
        if (f.n == 4 && _hagurokamikaze(f)) return _c73hk(f);
        return _c73small(f);
      },
      'D': (f) {
        if (f.bbClass >= 3) return go('F', '戦艦級3隻以上');
        if (f.carriers >= 3) return go('F', '空母系3隻以上');
        if (f.cav >= 3) return go('F', '航巡3隻以上');
        return go('G', 'それ以外 (Eマスへの条件は不明)');
      },
      'G': (f) {
        if (f.ca == 0 && f.ddde >= 2) {
          if (f.ao >= 1) return go('H', '重巡0隻 かつ (駆逐+海防)2隻以上 かつ 補給艦を含む');
          if (f.av >= 2) return go('H', '重巡0隻 かつ (駆逐+海防)2隻以上 かつ 水母2隻以上');
        }
        if (f.subs >= 1) return go('I', '潜水艦を含む');
        if (f.bbClass + f.carriers >= 1) return go('J', '(戦艦級+空母系)1隻以上');
        if (_hagurokamikaze(f)) {
          if (f.n <= 4) return go('P', '羽黒と神風 かつ 4隻以下の編成');
          if (f.dd <= 2) return go('J', '羽黒と神風 かつ 駆逐2隻以下');
          if (f.allFastPlus) return go('P', '羽黒と神風 かつ 高速+統一');
          final trio = [f.has('足柄'), f.has('妙高'), f.has('高雄')].where((b) => b).length;
          if (trio >= 2) return go('K', '羽黒と神風 かつ 足柄・妙高・高雄から2隻');
          if (f.caClass >= 3) return go('J', '羽黒と神風 かつ 重巡級3隻以上');
          if (f.anySlow) return go('J', '羽黒と神風 かつ 低速の艦を含む');
          if (f.has('足柄')) return go('P', '羽黒と神風 かつ 足柄');
          return go('K', '羽黒と神風 (それ以外)');
        }
        if (f.ddde <= 2) return go('J', '(駆逐+海防)2隻以下');
        if (f.caClass >= 3) return go('J', '重巡級3隻以上');
        return go('I', 'それ以外');
      },
      'I': (f) {
        if (f.bbClass + f.carriers >= 1) return go('J', '(戦艦級+空母系)1隻以上');
        if (f.caClass >= 3) return go('J', '重巡級3隻以上');
        if (f.ddde == 0) return go('J', '(駆逐+海防)0隻');
        if (_hagurokamikaze(f)) {
          if (f.ddde >= 3) {
            if (f.allFastPlus) return go('J', '羽黒と神風 かつ (駆逐+海防)3隻以上 かつ 高速+以上統一');
            return go('M', '羽黒と神風 かつ (駆逐+海防)3隻以上');
          }
          if (f.ddde == 2) {
            if (f.allFastest) return go('M', '羽黒と神風 かつ (駆逐+海防)2隻 かつ 最速統一');
            return go('L', '羽黒と神風 かつ (駆逐+海防)2隻');
          }
          return go('L', '羽黒と神風 かつ (駆逐+海防)1隻');
        }
        if (f.allFastest && f.dd >= 3) return go('J', '最速統一 かつ 駆逐3隻以上');
        if ((f.has('羽黒') || f.has('神風')) && f.has('足柄') && f.ddde >= 3) {
          return go('M', '(羽黒 または 神風) かつ 足柄 かつ (駆逐+海防)3隻以上');
        }
        return go('L', 'それ以外');
      },
      'J': (f) {
        if (f.bbClass + f.carriers >= 1) return go('M', '(戦艦級+空母系)1隻以上');
        if (f.anySlow) return go('M', '低速の艦を含む');
        if (f.caClass >= 4) return go('M', '重巡級4隻以上');
        if (f.dd >= 3) {
          if (f.has('羽黒') && (f.has('足柄') || f.has('神風'))) return go('P', '駆逐3隻以上 かつ (羽黒と足柄 または 羽黒と神風)');
          return go('M', '駆逐3隻以上 (それ以外)');
        }
        if (f.dd == 2) {
          if (_hagurokamikaze(f) && f.has('足柄')) return go('P', '駆逐2隻 かつ 羽黒・神風・足柄');
          return go('M', '駆逐2隻 (それ以外)');
        }
        return go('M', '駆逐1隻以下');
      },
      'M': (f) {
        if (f.standardCarriers >= 1) return go('N', '正規空母を含む');
        if (f.bbClass + f.carriers >= 2) return go('N', '(戦艦級+空母系)2隻以上');
        if (f.subs >= 4) return go('N', '潜水艦4隻以上');
        if (f.bb >= 1) return go('O', '(低速)戦艦を含む');
        if (f.ao >= 1) return go('O', '補給艦を含む');
        if (f.av >= 2) return go('O', '水母2隻以上');
        return go('P', 'それ以外');
      },
    },
    note: '羽黒・神風・足柄・妙高・高雄は艦名で判定。ルート分岐法則 2020/09/23',
  ),

  // ---- 7-4 昭南本土航路 ----
  CompassMap(
    area: 7,
    no: 4,
    title: '昭南本土航路',
    boss: 'P',
    coefficient: 4,
    edges: {
      // kancolle-replay では 3 は A→C だが、Wiki の分岐法則と道のり (C-D-F-…) では出撃地点から直接 C
      1: ('Start', 'A'), 2: ('A', 'B'), 3: ('Start', 'C'), 4: ('C', 'D'), 5: ('B', 'E'), 6: ('D', 'F'), 7: ('E', 'G'), //
      8: ('F', 'H'), 9: ('G', 'I'), 10: ('E', 'J'), 11: ('H', 'K'), 12: ('G', 'L'), 13: ('K', 'M'), 14: ('M', 'N'),
      15: ('M', 'O'), 16: ('J', 'P'), 17: ('C', 'E'), 18: ('F', 'J'), 19: ('J', 'K'), 20: ('J', 'L'), 21: ('K', 'P'),
      22: ('L', 'P'), 23: ('M', 'P'),
    },
    rules: {
      'Start': (f) {
        if (f.battleships + f.standardCarriers + f.subs >= 1) return go('C', '戦艦 / 正規空母 / 潜水艦のどれかを含む');
        if (f.caClass >= 2) return go('C', '重巡級2隻以上');
        if (f.clClass >= 2) return go('C', '軽巡級2隻以上');
        final akitsu = f.named('あきつ丸');
        if (akitsu >= 1 && f.de >= 2 && f.ddde >= 3) return go('A', 'あきつ丸 かつ 海防艦2隻 かつ (駆逐+海防)もう1隻');
        if (f.bbv + f.cvl + akitsu >= 3) return go('C', '(航空戦艦+軽空母+あきつ丸)3隻以上');
        if (f.ddde >= 3) return go('A', '(駆逐+海防)3隻以上');
        if (f.de >= 2) return go('A', '海防艦2隻以上');
        return go('C', 'それ以外');
      },
      'C': (f) {
        if (f.battleships + f.standardCarriers + f.subs >= 1) return go('D', '戦艦 / 正規空母 / 潜水艦のどれかを含む');
        if (f.cvl + f.named('あきつ丸') >= 3) return go('D', '(軽空母+あきつ丸)3隻以上');
        if (f.ddde >= 4) return go('E', '(駆逐+海防)4隻以上');
        if (f.ct >= 1 && f.ddde >= 3) return go('E', '練巡1隻以上 かつ (駆逐+海防)3隻以上');
        if (f.de >= 3) return go('E', '海防艦3隻以上');
        if (f.allFastPlus && f.dd >= 2) return go('E', '高速+統一 かつ 駆逐2隻以上');
        return go('D', 'それ以外');
      },
      'E': (f) {
        if (f.n == 6 && f.de >= 4 && f.ao + f.lha >= 1 && f.de + f.ao + f.lha + f.dd + _taiyo(f) == 6) {
          return go('G', '海防艦4隻 + (補給艦・揚陸艦)1隻 + (大鷹型・補給艦・揚陸艦・駆逐・海防)1隻の6隻編成');
        }
        return go('J', 'それ以外');
      },
      'F': (f) => choose(['H', 'J']),
      'G': (f) => lean('L', 'I', '索敵で分岐 (必要な索敵スコアは不明。足りればLマス)'),
      'K': (f) => split({'M': 1}, 'Pマスへ進む編成は見つかっていない (Wikiでも不明)', estimated: true),
      'M': (f) {
        final los = f.losScore(4);
        final score = _los(los);
        if (los < 45) return go('N', '$score (45未満)');
        final akitsu = f.named('あきつ丸');
        final heavy = f.bb + f.standardCarriers >= 1 ||
            f.fbb >= 2 ||
            f.bbv >= 2 ||
            f.cvl + akitsu >= 2 ||
            f.fbb + f.bbv + f.cvl + akitsu >= 3 ||
            f.ddde <= 1;
        if (!heavy) return go('P', '$score (45以上) かつ 重い編成の条件に当てはまらない');
        const cond = '(低速)戦艦・正規空母 / 高速戦艦2隻以上 / 航空戦艦2隻以上 / (軽空母+あきつ丸)2隻以上 / (高速戦艦+航空戦艦+軽空母+あきつ丸)3隻以上 / (駆逐+海防)1隻以下 のどれか';
        if (los < 47) return even(['N', 'O'], '$score (45以上47未満はランダム・割合不明) かつ $cond', estimated: true);
        return go('O', '$score (47以上) かつ $cond');
      },
    },
    pathRules: {
      'J': (f, path) {
        if (path.contains('D')) return go('K', 'Dマスを通ってきた');
        final los = f.losScore(4);
        final score = _los(los);
        if (los < 33) return go('K', '$score (33未満)');
        final taiyo = _taiyo(f);
        final others = f.n - taiyo - f.ct - f.dd - f.de;
        final bool toL;
        if (others >= 1) {
          toL = true;
        } else if (f.n == 6) {
          toL = f.de < f.n;
        } else if (f.de == 3) {
          toL = (f.ct >= 1 && taiyo + f.dd == 0) || f.dd >= 2 || taiyo >= 2;
        } else if (f.de <= 2) {
          toL = !(f.n == 3 && f.dd == 1 && f.de == 2);
        } else {
          toL = false;
        }
        final next = toL ? 'L' : 'P';
        final why = toL ? 'Lマスへの編成条件に当てはまる' : 'Lマスへの編成条件に当てはまらない';
        if (los < 37) {
          return BranchOutcome(
            [const RouteOption('K', 0.5, estimated: true), RouteOption(next, 0.5, estimated: true)],
            '$score (33以上37未満はKマスかランダム・割合不明。Kでなければ$why ので$nextマス)',
          );
        }
        return go(next, '$score (37以上) かつ $why');
      },
    },
    note: '分岐点係数4。Fマスは能動分岐。Gマスの索敵の境目はWikiでも不明。あきつ丸・大鷹型は艦名で判定。$_kLosNote。ルート分岐法則 2025/03/17',
  ),

  // ---- 7-5 ジャワ島沖 (第1・第2・第3ゲージ) ----
  _map75('第1ゲージ K', 'K'),
  _map75('第2ゲージ Q', 'Q'),
  _map75('第3ゲージ T', 'T'),
];

bool _hagurokamikaze(CompassFleet f) => f.has('羽黒') && f.has('神風');

/// 7-3 の A マス (4隻以下の編成)
BranchOutcome _a73small(CompassFleet f) {
  const only = {kCA, kCL, kDD, kDE};
  if (f.n == 4) {
    if (f.ca >= 2) return go('B', '4隻編成 かつ 重巡2隻以上');
    if (f.ddde <= 1) return go('B', '4隻編成 かつ (駆逐+海防)1隻以下');
    if (f.only(only)) return go('C', '4隻編成 かつ (重巡+軽巡+駆逐+海防)だけ');
    return go('B', '4隻編成 (それ以外)');
  }
  if (f.only(only)) return go('C', '3隻以下 かつ (重巡+軽巡+駆逐+海防)だけ');
  return go('B', '3隻以下 (それ以外)');
}

/// 7-3 の C マス (4隻以下の編成で羽黒と神風を含む)
BranchOutcome _c73hk(CompassFleet f) {
  if (f.caClass >= 3) return go('D', '羽黒と神風 かつ 重巡級3隻以上');
  if (f.has('足柄') || f.has('妙高')) return go('E', '羽黒と神風 かつ 足柄 または 妙高');
  if (f.ddde <= 1) return go('D', '羽黒と神風 かつ (駆逐+海防)1隻以下');
  return go('E', '羽黒と神風を含む');
}

/// 7-3 の C マス (4隻以下の編成)
BranchOutcome _c73small(CompassFleet f) {
  if (f.n == 4) {
    if (f.has('羽黒') && f.ddde == 3) return go('E', '4隻編成 かつ 羽黒 かつ (駆逐+海防)3隻');
    if (f.has('神風') && f.ddde == 4) return go('E', '4隻編成 かつ 神風 かつ (駆逐+海防)4隻');
    return go('D', '4隻編成 (それ以外)');
  }
  if (f.n == 3) {
    if (f.caClass >= 2) return go('D', '3隻編成 かつ 重巡級2隻以上');
    if (f.ddde <= 1) return go('D', '3隻編成 かつ (駆逐+海防)1隻以下');
    if (f.only({kCA, kDD, kDE})) return go('E', '3隻編成 かつ (重巡+駆逐+海防)だけ');
    return go('D', '3隻編成 (それ以外)');
  }
  return go('E', '2隻以下の編成');
}

CompassMap _map72(String phase, String boss) => CompassMap(
      area: 7,
      no: 2,
      title: 'タウイタウイ泊地沖',
      boss: boss,
      phase: phase,
      coefficient: 4,
      edges: {
        1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('Start', 'C'), 4: ('C', 'D'), 5: ('C', 'E'), 6: ('E', 'F'), 7: ('E', 'G'), //
        8: ('A', 'B'), 9: ('B', 'C'), 10: ('D', 'H'), 11: ('D', 'I'), 12: ('I', 'J'), 13: ('J', 'K'), 14: ('I', 'L'),
        15: ('I', 'M'), 16: ('H', 'I'),
      },
      rules: {
        'Start': (f) {
          final bbcv = f.bbClass + f.standardCarriers;
          if (f.ddde <= 1) return go('A', '(駆逐+海防)1隻以下');
          if (f.subs >= 1) return go('A', '潜水艦を含む');
          if (f.n >= 6) {
            if (f.standardCarriers >= 2) return go('A', '6隻編成 かつ 正規空母2隻以上');
            if (bbcv >= 4) return go('A', '6隻編成 かつ (戦艦級+正規空母)4隻以上');
            if (f.cl + f.ct >= 3) return go('A', '6隻編成 かつ (軽巡+練巡)3隻以上');
            return go('B', '6隻編成 (それ以外)');
          }
          if (f.n == 5) {
            if (f.standardCarriers >= 3) return go('A', '5隻編成 かつ 正規空母3隻以上');
            if (bbcv >= 1) return go('B', '5隻編成 かつ (戦艦級+正規空母)1隻以上');
            if (f.cl + f.ct >= 2) return go('B', '5隻編成 かつ (軽巡+練巡)2隻以上');
            if (f.de <= 2) return go('B', '5隻編成 かつ 海防艦2隻以下');
            return go('C', '5隻編成 (それ以外)');
          }
          if (bbcv >= 1) return go('B', '4隻以下 かつ (戦艦級+正規空母)1隻以上');
          if (f.ddde <= 2) return go('B', '4隻以下 かつ (駆逐+海防)2隻以下');
          return go('C', '4隻以下 (それ以外)');
        },
        'C': (f) {
          final bbcv = f.bbClass + f.standardCarriers;
          if (f.ao >= 1) return go('D', '補給艦を含む');
          if (f.subs >= 1) return go('D', '潜水艦を含む');
          if (f.n >= 6) {
            if (bbcv >= 1) return go('D', '6隻編成 かつ (戦艦級+正規空母)1隻以上');
            if (f.ddde >= 4) return go('E', '6隻編成 かつ (駆逐+海防)4隻以上');
            return go('D', '6隻編成 (それ以外)');
          }
          if (f.n == 5) {
            if (bbcv >= 2) return go('D', '5隻編成 かつ (戦艦級+正規空母)2隻以上');
            if (f.ddde >= 4) return go('E', '5隻編成 かつ (駆逐+海防)4隻以上');
            if (f.de >= 3) return go('E', '5隻編成 かつ 海防艦3隻以上');
            return go('D', '5隻編成 (それ以外)');
          }
          if (bbcv >= 2) return go('D', '4隻以下 かつ (戦艦級+正規空母)2隻以上');
          if (f.ddde >= 3) return go('E', '4隻以下 かつ (駆逐+海防)3隻以上');
          if (f.de >= 2) return go('E', '4隻以下 かつ 海防艦2隻以上');
          return go('D', '4隻以下 (それ以外)');
        },
        'D': (f) {
          final heavy = f.bbClass + f.carriers;
          if (f.allFastPlus) return go('I', '高速+以上統一');
          if (heavy >= 4) return go('H', '(戦艦級+空母系)4隻以上');
          if (f.allFast) return go('I', '高速以上統一');
          if (heavy == 3) return go('H', '(戦艦級+空母系)3隻');
          if (heavy == 2) return lean('I', 'H', '(戦艦級+空母系)2隻 (Iマス寄り)', 65);
          return go('I', '(戦艦級+空母系)1隻以下');
        },
        'E': (f) {
          if (f.n <= 5) return go('G', '5隻以下の編成');
          if (f.ddde >= 5) return go('G', '(駆逐+海防)5隻以上');
          if (f.dd >= 1 && f.de >= 3) return go('G', '駆逐1隻以上 かつ 海防艦3隻以上');
          return byLos(f, 4, low: 46, high: 46, below: 'F', above: 'G', guessed: true);
        },
        'I': (f) {
          if (f.ao >= 1) return go('J', '補給艦を含む');
          if (f.av >= 1 && f.ddde >= 3) return go('J', '水母1隻以上 かつ (駆逐+海防)3隻以上');
          return byLos(f, 4, low: 63, high: 69, below: 'L', above: 'M', guessed: true);
        },
      },
      note: '分岐点係数4。$_kLosNote。ルート分岐法則 2020/04/19',
    );

CompassMap _map75(String phase, String boss) => CompassMap(
      area: 7,
      no: 5,
      title: 'ジャワ島沖',
      boss: boss,
      phase: phase,
      coefficient: 4,
      edges: {
        1: ('Start', 'A'), 2: ('A', 'B'), 3: ('B', 'C'), 4: ('B', 'D'), 5: ('D', 'E'), 6: ('D', 'F'), 7: ('F', 'G'), //
        8: ('G', 'H'), 9: ('H', 'I'), 10: ('F', 'J'), 11: ('H', 'K'), 12: ('C', 'D'), 13: ('E', 'F'), 14: ('I', 'L'),
        15: ('I', 'M'), 16: ('J', 'N'), 17: ('N', 'O'), 18: ('O', 'P'), 19: ('O', 'Q'), 20: ('L', 'M'), 21: ('J', 'O'),
        22: ('P', 'R'), 23: ('P', 'S'), 24: ('P', 'T'), 25: ('R', 'T'),
      },
      rules: {
        'B': (f) {
          if (f.allFastPlus) return go('D', '高速+以上統一');
          if (f.standardCarriers >= 2) return go('C', '正規空母2隻以上');
          if (f.bb >= 2) return go('C', '(低速)戦艦2隻以上');
          if (f.subs >= 1) return go('C', '潜水艦を含む');
          if (f.cl == 0) return go('C', '軽巡0隻');
          if (f.ddde <= 1) return go('C', '(駆逐+海防)1隻以下');
          if (f.ddde >= 3) return go('D', '(駆逐+海防)3隻以上');
          if (f.standardCarriers >= 1) return go('C', '正規空母を含む');
          if (f.cvl >= 2) return go('C', '軽空母2隻以上');
          if (f.bbClass >= 3) return go('C', '戦艦級3隻以上');
          if (f.caClass >= 3) return go('C', '重巡級3隻以上');
          return go('D', 'それ以外');
        },
        'D': (f) {
          if (f.allFastest) return go('F', '最速統一');
          if (f.standardCarriers >= 2) return go('E', '正規空母2隻以上');
          if (f.carriers >= 3) return go('E', '空母系3隻以上');
          if (f.bbClass + f.standardCarriers + f.caClass >= 3) return go('E', '(戦艦級+正規空母+重巡級)3隻以上');
          if (f.subs >= 1) return go('E', '潜水艦を含む');
          if (f.cl + f.dd == 0) return go('E', '(軽巡+駆逐)0隻');
          if (f.allFastPlus) return go('F', '高速+統一');
          if (f.bbClass == 2) {
            if (f.allFast && f.ddde >= 2) return go('F', '戦艦級2隻 かつ 高速統一 かつ (駆逐+海防)2隻以上');
            if (f.ddde >= 3) return go('F', '戦艦級2隻 かつ (駆逐+海防)3隻以上');
            return go('E', '戦艦級2隻 (それ以外)');
          }
          if (f.cl + f.dd + f.de >= 2) return go('F', '(軽巡+駆逐+海防)2隻以上');
          return go('E', 'それ以外');
        },
        'F': (f) => choose(['G', 'J']),
        'H': (f) => choose(['I', 'K']),
        'I': (f) => byLos(f, 4, low: 53, high: 59, below: 'L', above: 'M'),
        'J': (f) {
          if (f.cvl == 1 && f.caClass == 2 && f.cl == 1 && f.ddde == 2 && f.n == 6) {
            return go('O', '軽空母1隻・重巡級2隻・軽巡1隻・(駆逐+海防)2隻 ちょうど');
          }
          if (f.allFastPlus) return go('O', '高速+以上統一');
          if (f.standardCarriers >= 1) return go('N', '正規空母を含む');
          if (f.cvl >= 3) return go('N', '軽空母3隻以上');
          if (f.bb >= 2) return go('N', '(低速)戦艦2隻以上');
          if (f.bbClass + f.caClass >= 3) return go('N', '(戦艦級+重巡級)3隻以上');
          if (f.ddde <= 1) return go('N', '(駆逐+海防)1隻以下');
          if (f.ddde >= 3) return go('O', '(駆逐+海防)3隻以上');
          if (f.allFast) return go('O', '高速統一');
          return go('N', 'それ以外');
        },
        'O': (f) => choose(['P', 'Q']),
        'P': (f) {
          final los = f.losScore(4);
          final score = _los(los);
          if (los < 58) return go('S', '$score (58未満)');
          final (String next, String why) = switch (f) {
            _ when f.allFastest => ('T', '最速統一'),
            _ when f.standardCarriers >= 1 => ('R', '正規空母を含む'),
            _ when f.bbClass + f.cvl >= 2 => ('R', '(戦艦級+軽空母)2隻以上'),
            _ when f.bbClass + f.caClass >= 3 => ('R', '(戦艦級+重巡級)3隻以上'),
            _ when f.cl == 0 => ('R', '軽巡0隻'),
            _ => ('T', 'それ以外'),
          };
          if (los < 63) {
            return BranchOutcome(
              [const RouteOption('S', 0.5, estimated: true), RouteOption(next, 0.5, estimated: true)],
              '$score (58以上63未満はランダムでSマス・割合不明。Sでなければ $why なので$nextマス)',
            );
          }
          return go(next, '$score (63以上) かつ $why');
        },
      },
      note: '分岐点係数4。F・H・Oマスは能動分岐 (選んだゲージのボスへ行きやすい方で計算)。$_kLosNote。ルート分岐法則 2024/11/12',
    );
