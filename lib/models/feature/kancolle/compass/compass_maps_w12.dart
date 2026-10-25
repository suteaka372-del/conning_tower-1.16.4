import 'compass_engine.dart';

// 1-1〜2-5 の分岐条件。艦これ攻略 Wiki* の各海域ページ「ルート分岐法則」の内容を元に書き直したもの。
// 表記: 戦艦級 = 高速戦艦 + 戦艦 / 空母系 = 正規空母 + 装甲空母 + 軽空母 / 正規空母 = 正規空母 + 装甲空母 /
// 重巡級 = 重巡 + 航巡 / 「軽巡」は艦種が軽巡のもの (練巡・雷巡は含まない) / (低速)戦艦 = 艦種が戦艦 (速力は関係ない)
// 「?」付きなど Wiki でも確かでない条件や、割合が書かれていないランダムは estimated (推定) として扱う。

final List<CompassMap> kCompassMapsWorld12 = [
  // ---- 1-1 鎮守府正面海域 ----
  CompassMap(
    area: 1,
    no: 1,
    title: '鎮守府正面海域',
    boss: 'C',
    edges: {1: ('Start', 'A'), 2: ('A', 'B'), 3: ('A', 'C')},
    rules: {
      'A': (f) {
        final c = switch (f.n) { >= 6 => 55.0, 5 => 60.0, 4 => 65.0, 3 => 70.0, 2 => 75.0, _ => 80.0 };
        return lean('C', 'B', 'ランダム (${f.n}隻編成: Cマス$c%)', c);
      },
    },
  ),

  // ---- 1-2 南西諸島沖 ----
  CompassMap(
    area: 1,
    no: 2,
    title: '南西諸島沖',
    boss: 'E',
    edges: {1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('B', 'C'), 4: ('A', 'D'), 5: ('A', 'E'), 6: ('D', 'E')},
    rules: {
      'Start': (f) {
        if (f.ddde == 4 && f.n <= 5) return go('A', '(駆逐+海防)ちょうど4隻 かつ 5隻以下');
        final a = switch (f.n) { >= 6 => 40.0, 5 => 50.0, 4 => 60.0, _ => 70.0 };
        return lean('A', 'B', 'ランダム (${f.n}隻編成: Aマス$a%)', a);
      },
      'A': (f) {
        if (f.allFast) return go('E', '高速以上統一');
        if (f.ddde <= 3) return go('D', '(駆逐+海防)3隻以下');
        if (f.ddde == 6) return go('E', '(駆逐+海防)6隻');
        if (f.cl + f.ct >= 1 && f.ddde == 5) return go('E', '(軽巡+練巡)1隻 かつ (駆逐+海防)5隻');
        if (f.cl == 1 && f.dd >= 4) return go('E', '軽巡1隻 かつ 駆逐4隻以上');
        return lean('E', 'D', 'それ以外 (Eマス寄り)', 65);
      },
    },
    note: '速力強化 (高速以上統一) でボスへ固定',
  ),

  // ---- 1-3 製油所地帯沿岸 ----
  CompassMap(
    area: 1,
    no: 3,
    title: '製油所地帯沿岸',
    boss: 'J',
    edges: {
      1: ('Start', 'A'), 2: ('D', 'B'), 3: ('Start', 'C'), 4: ('A', 'D'), 5: ('A', 'E'), 6: ('C', 'F'), //
      7: ('H', 'G'), 8: ('F', 'H'), 9: ('H', 'I'), 10: ('F', 'J'), 11: ('B', 'E'), 12: ('E', 'F'), 13: ('H', 'J'),
    },
    rules: {
      'Start': (f) {
        if (f.ao >= 1) return go('A', '補給艦を含む');
        if (f.av >= 1) return go('A', '水母を含む');
        if (f.carriers >= 1) return go('C', '空母系を含む');
        return even(['A', 'C'], 'それ以外 (片寄りなし)');
      },
      'A': (f) {
        if (f.ao >= 1) return go('D', '補給艦を含む');
        if (f.de >= 4) return go('D', '海防艦4隻以上');
        if (f.av >= 1) return lean('D', 'E', '水母を含む (Dマス寄り)', 80);
        if (f.ddde >= 4) return lean('D', 'E', '(駆逐+海防)4隻以上 (Dマス寄り)', 80);
        if (f.subs >= 1) return go('E', '潜水艦を含む');
        return even(['D', 'E'], 'それ以外 (片寄りなし)');
      },
      'F': (f) {
        if (f.standardCarriers >= 1) return go('H', '正規空母を含む');
        if (f.bb >= 1) return go('H', '(低速)戦艦を含む');
        if (f.cav >= 1 && f.dd >= 2) return go('J', '航巡1隻以上 かつ 駆逐2隻以上');
        if (f.dd >= 4) return go('J', '駆逐4隻以上');
        if (f.cl + f.ct >= 1 && f.ddde >= 4) return go('J', '(軽巡+練巡)1隻以上 かつ (駆逐+海防)4隻以上');
        if (f.allFast) return lean('J', 'H', '高速以上統一 (Jマス寄り・割合不明)');
        return lean('H', 'J', 'それ以外 (Hマス寄り・割合不明)');
      },
      'H': (f) {
        if (f.ao >= 1) return go('G', '補給艦を含む');
        if (f.av >= 1) return go('J', '水母を含む');
        if (f.cav >= 1) return go('J', '航巡を含む');
        if (f.cl + f.ct >= 1 && f.dd >= 2) return go('J', '(軽巡+練巡)1隻以上 かつ 駆逐2隻以上');
        if (f.dd >= 2) return lean('J', 'I', '駆逐2隻以上 (Iマスは低め・割合不明)');
        return lean('I', 'J', 'それ以外 (Iマス寄り・割合不明)');
      },
    },
    note: 'ルート分岐法則 2020/02/28',
  ),

  // ---- 1-4 南西諸島防衛線 ----
  CompassMap(
    area: 1,
    no: 4,
    title: '南西諸島防衛線',
    boss: 'L',
    edges: {
      1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('B', 'C'), 4: ('A', 'D'), 5: ('D', 'E'), 6: ('C', 'F'), //
      7: ('D', 'G'), 8: ('E', 'H'), 9: ('F', 'I'), 10: ('G', 'J'), 11: ('J', 'K'), 12: ('H', 'L'),
      13: ('B', 'D'), 14: ('F', 'E'), 15: ('F', 'H'), 16: ('I', 'L'), 17: ('J', 'L'),
    },
    rules: {
      'Start': (f) => even(['A', 'B'], 'ランダム (片寄りなし)'),
      'B': (f) {
        if (f.carriers >= 3) return go('D', '空母系3隻以上');
        if (f.bbClass >= 3) return go('D', '戦艦級3隻以上');
        if (f.ddde == 0) return go('D', '(駆逐+海防)0隻');
        if (f.ddde >= 3) return go('C', '(駆逐+海防)3隻以上');
        if (f.cl >= 1) return lean('C', 'D', '軽巡を含む (Cマス寄り)', 80);
        return lean('C', 'D', 'それ以外 (Cマス寄り)', 60);
      },
      'D': (f) {
        if (f.as >= 1) return go('E', '潜水母艦を含む');
        if (f.av >= 1) return go('G', '水母を含む');
        return even(['E', 'G'], 'それ以外 (片寄りなし)');
      },
      'F': (f) {
        if (f.ddde >= 4) return go('E', '(駆逐+海防)4隻以上');
        if (f.ddde >= 2) {
          if (f.av + f.as + f.ao >= 1 || f.bbv == 2) return go('E', '(駆逐+海防)2隻以上 かつ (水母+潜水母艦+補給艦)1隻以上 または 航空戦艦2隻');
          return lean('E', 'H', '(駆逐+海防)${f.ddde}隻 (Eマス寄り)', f.ddde >= 3 ? 80 : 60);
        }
        return even(['H', 'I'], '(駆逐+海防)1隻以下 (片寄りなし)');
      },
      'J': (f) {
        if (f.cl >= 1 && f.av >= 1 && f.ddde >= 2) return go('L', '軽巡1隻以上 かつ 水母1隻以上 かつ (駆逐+海防)2隻以上');
        if (f.dd >= 4) return go('L', '駆逐4隻以上');
        if (f.dd >= 2) return lean('L', 'K', '駆逐2隻以上 (Lマス寄り)', 75);
        return lean('L', 'K', 'それ以外 (Lマス寄り)', 65);
      },
    },
  ),

  // ---- 1-5 鎮守府近海 ----
  CompassMap(
    area: 1,
    no: 5,
    title: '鎮守府近海',
    boss: 'J',
    edges: {
      1: ('Start', 'A'), 2: ('C', 'B'), 3: ('E', 'C'), 4: ('A', 'D'), 5: ('D', 'E'), 6: ('D', 'F'), //
      7: ('F', 'G'), 8: ('G', 'H'), 9: ('F', 'I'), 10: ('C', 'J'), 11: ('E', 'J'), 12: ('G', 'J'),
    },
    rules: {
      'D': (f) {
        if (f.n == 1) return go('E', '1隻編成');
        if (f.n >= 5) {
          if (f.subs >= 1) return go('F', '5隻以上 かつ 潜水艦を含む');
          return even(['E', 'F'], '5隻以上の編成 (割合不明)', estimated: true);
        }
        if (f.only({kDE})) return go('E', '海防艦のみ');
        if (f.ao >= 1) return go('E', '補給艦を含む');
        return go('F', 'それ以外');
      },
      'E': (f) {
        if (f.n >= 5) return go('C', '5隻以上の編成');
        if (f.only({kDE})) return go('J', '海防艦のみ');
        return go('C', 'それ以外');
      },
      'C': (f) {
        if (f.only({kDE})) return go('J', '海防艦のみ');
        if (f.cl == 1 && f.de == 4 && f.n == 5) {
          return split({'J': 1}, '軽巡1隻 かつ 海防4隻の5隻編成 (Wikiでも推測)', estimated: true);
        }
        if (f.subs >= 1) return go('B', '潜水艦を含む');
        if (f.n <= 4 && f.ao >= 1) return even(['B', 'J'], '4隻以下 かつ 補給艦を含む (割合不明)', estimated: true);
        return go('B', 'それ以外');
      },
      'F': (f) {
        if (f.bbClass >= 1 || f.standardCarriers >= 1 || f.subs >= 1) return go('I', '戦艦 (航空戦艦は除く) / 正規空母 / 潜水艦を含む');
        if (f.cvl >= 2) return go('I', '軽空母2隻以上');
        if (f.cl >= 3) return go('I', '軽巡3隻以上');
        return go('G', 'それ以外');
      },
      'G': (f) {
        if (f.n >= 5) return go('H', '5隻以上の編成');
        return go('J', '4隻以下の編成');
      },
    },
    note: 'ルート分岐法則 2024/10/20',
  ),

  // ---- 1-6 鎮守府近海航路 ----
  CompassMap(
    area: 1,
    no: 6,
    title: '鎮守府近海航路',
    boss: 'N',
    coefficient: 3,
    edges: {
      1: ('Start', 'A'), 2: ('Start', 'C'), 3: ('A', 'E'), 4: ('E', 'G'), 5: ('C', 'H'), 6: ('G', 'K'), //
      7: ('K', 'M'), 8: ('M', 'L'), 9: ('M', 'J'), 10: ('L', 'I'), 11: ('J', 'D'), 12: ('G', 'F'),
      13: ('F', 'B'), 14: ('D', 'N'), 15: ('H', 'K'), 16: ('I', 'D'), 17: ('B', 'N'),
    },
    rules: {
      'Start': (f) {
        if (f.bbv >= 1 || f.cvl >= 1 || f.ca >= 1) return go('C', '航空戦艦 / 軽空母 / 重巡を含む');
        if (f.cav >= 2) return go('C', '航巡2隻以上');
        if (f.ddde <= 3) return go('C', '(駆逐+海防)3隻以下');
        return go('A', 'それ以外');
      },
      'G': (f) {
        if (f.cl == 1 && f.ddde == 5) return go('F', '軽巡1隻 かつ (駆逐+海防)5隻');
        return lean('F', 'K', 'それ以外 (Fマス寄り)', 75);
      },
      'M': (f) {
        if (f.bbv + f.ca + f.cvl >= 3) return go('L', '(航空戦艦+重巡+軽空母)3隻以上');
        if (f.bbv + f.ca + f.cav >= 3) return go('L', '(航空戦艦+重巡+航巡)3隻以上');
        if (f.ddde <= 2) return go('L', '(駆逐+海防)2隻以下');
        final los = f.losScore(3);
        final score = los.toStringAsFixed(1);
        if (los < 28) return go('L', '索敵スコア$score (28未満。28はWikiでも推測)');
        if (los < 30) return even(['J', 'L'], '索敵スコア$score (28以上30未満はランダム・割合不明)', estimated: true);
        return go('J', '索敵スコア$score (30以上)');
      },
    },
    note: '分岐点係数3。索敵スコアは司令部Lv120のときの値なので、120未満なら+1以上の余裕を。ルート分岐法則 2019/11/03',
  ),

  // ---- 2-1 南西諸島近海 ----
  CompassMap(
    area: 2,
    no: 1,
    title: '南西諸島近海',
    boss: 'H',
    edges: {
      1: ('B', 'A'), 2: ('C', 'B'), 3: ('Start', 'C'), 4: ('C', 'D'), 5: ('C', 'E'), 6: ('E', 'F'), //
      7: ('F', 'G'), 8: ('D', 'H'), 9: ('E', 'D'), 10: ('E', 'H'), 11: ('F', 'H'),
    },
    rules: {
      'C': (f) {
        if (f.carriers >= 3) return go('B', '空母系3隻以上');
        if (f.bbv >= 2) return go('B', '航空戦艦2隻以上');
        if (f.ao >= 1 && f.subs == 0) return go('B', '補給艦1隻以上 かつ 潜水艦0隻');
        if (f.bbv >= 1) {
          if (f.av + f.as >= 1) return lean('B', 'E', '航空戦艦 かつ (水母+潜水母艦)を含む (Bマス寄り)', 70);
          return lean('B', 'D', '航空戦艦を含む (Bマス寄り)', 70);
        }
        if (f.av + f.as >= 1) return go('E', '(水母+潜水母艦)1隻以上');
        return even(['D', 'E'], 'それ以外 (片寄りなし)');
      },
      'E': (f) {
        final heavy = f.bbClass + f.carriers;
        if (heavy >= 5) return go('F', '(戦艦級+空母系)5隻以上');
        if (f.n >= 6) {
          if (heavy >= 1) return go('D', '6隻編成 かつ (戦艦級+空母系)を含む');
          if (f.ddde == 6) return go('H', '6隻編成 かつ (駆逐+海防)6隻');
          if (f.cl == 1 && f.ddde == 5) return go('H', '6隻編成 かつ 軽巡1隻 かつ (駆逐+海防)5隻');
          if (f.allFast && f.cl == 1 && f.dd == 4) return go('H', '6隻編成 かつ 高速以上統一 かつ 軽巡1隻 かつ 駆逐4隻');
          return go('D', '6隻編成 (それ以外)');
        }
        if (f.ddde == 5) return go('H', '5隻以下 かつ (駆逐+海防)5隻');
        if (f.cl == 1 && f.ddde == 4) return go('H', '5隻以下 かつ 軽巡1隻 かつ (駆逐+海防)4隻');
        if (f.allFast && f.cl == 1 && f.dd == 3) return go('H', '5隻以下 かつ 高速以上統一 かつ 軽巡1隻 かつ 駆逐3隻');
        return lean('D', 'F', '5隻以下 (それ以外。Dマス寄り)', 60);
      },
      'F': (f) {
        if (f.bbClass + f.carriers >= 5) return go('G', '(戦艦級+空母系)5隻以上');
        if (f.dd >= 3) return go('H', '駆逐3隻以上');
        if (f.cl >= 1 && f.dd >= 2) return go('H', '軽巡1隻以上 かつ 駆逐2隻以上');
        return lean('H', 'G', 'それ以外 (Hマス寄り)', 60);
      },
    },
  ),

  // ---- 2-2 バシー海峡 ----
  CompassMap(
    area: 2,
    no: 2,
    title: 'バシー海峡',
    boss: 'K',
    edges: {
      1: ('B', 'A'), 2: ('C', 'B'), 3: ('Start', 'C'), 4: ('C', 'D'), 5: ('C', 'E'), 6: ('E', 'F'), 7: ('E', 'G'), //
      8: ('F', 'H'), 9: ('H', 'I'), 10: ('H', 'J'), 11: ('E', 'K'), 12: ('G', 'H'), 13: ('G', 'K'), 14: ('H', 'K'),
    },
    rules: {
      'C': (f) {
        if (f.carriers >= 3) return go('B', '空母系3隻以上');
        if (f.bbv >= 2) return go('B', '航空戦艦2隻以上');
        if (f.ao >= 1 && f.subs == 0) return go('B', '補給艦1隻以上 かつ 潜水艦0隻');
        if (f.bbv >= 1) {
          if (f.av + f.as >= 1) return lean('B', 'E', '航空戦艦 かつ (水母+潜水母艦)を含む (Bマス寄り)', 70);
          if (f.cl + f.ct == 1 && f.ddde == 4) {
            return split({'B': 70, 'D': 10, 'E': 20}, '航空戦艦 かつ (軽巡+練巡)1隻 かつ (駆逐+海防)4隻');
          }
          return lean('B', 'D', '航空戦艦を含む (Bマス寄り)', 70);
        }
        if (f.av + f.as >= 1) return go('E', '(水母+潜水母艦)1隻以上');
        if (f.cl + f.ct >= 1 && f.ddde >= 4) return lean('E', 'D', '(軽巡+練巡)1隻以上 かつ (駆逐+海防)4隻以上 (Eマス寄り)', 90);
        return even(['D', 'E'], 'それ以外 (片寄りなし)');
      },
      'E': (f) {
        final heavy = f.bbClass + f.carriers;
        if (heavy >= 4) return go('G', '(戦艦級+空母系)4隻以上');
        if (f.de >= 2) return go('F', '海防艦2隻以上');
        if (heavy == 3) return lean('G', 'K', '(戦艦級+空母系)3隻 (Gマス寄り)', 70);
        if (heavy == 2) return even(['G', 'K'], '(戦艦級+空母系)2隻 (片寄りなし)');
        if (heavy == 1) return lean('K', 'G', '(戦艦級+空母系)1隻 (Kマス寄り)', 70);
        if (f.ddde >= 3 && f.as >= 1) return go('F', '(駆逐+海防)3隻以上 かつ 潜水母艦を含む');
        if (f.ddde >= 2) {
          if (f.cl >= 1 && f.allFast) return go('K', '(駆逐+海防)2隻以上 かつ 軽巡1隻以上 かつ 高速以上統一');
          return lean('K', 'F', '(駆逐+海防)2隻以上 (Kマス寄り)', 70);
        }
        return even(['G', 'K'], 'それ以外 (片寄りなし)');
      },
      'G': (f) {
        if (f.carriers >= 1) return go('H', '空母系を含む');
        if (f.dd == 0) return go('H', '駆逐0隻');
        return even(['H', 'K'], 'それ以外 (割合不明)', estimated: true);
      },
      'H': (f) {
        if (f.bbClass + f.carriers >= 4) return lean('I', 'K', '(戦艦級+空母系)4隻以上 (Iマス寄り・割合不明)');
        if (f.carriers + f.cav + f.av >= 1) return go('K', '(空母系+航巡+水母)1隻以上');
        if (f.subs >= 1) return lean('I', 'K', '潜水艦を含む (Iマス寄り・割合不明)');
        if (f.ddde >= 2) return even(['J', 'K'], '(駆逐+海防)2隻以上 (割合不明)', estimated: true);
        if (f.ddde == 1) return even(['I', 'J', 'K'], '(駆逐+海防)1隻 (割合不明)', estimated: true);
        return even(['I', 'K'], 'それ以外 (割合不明)', estimated: true);
      },
    },
  ),

  // ---- 2-3 東部オリョール海 ----
  CompassMap(
    area: 2,
    no: 3,
    title: '東部オリョール海',
    boss: 'N',
    edges: {
      1: ('Start', 'A'), 2: ('Start', 'B'), 3: ('Start', 'C'), 4: ('A', 'D'), 5: ('B', 'E'), 6: ('C', 'F'), //
      7: ('D', 'G'), 8: ('F', 'H'), 9: ('G', 'I'), 10: ('F', 'J'), 11: ('G', 'K'), 12: ('J', 'L'), 13: ('J', 'M'),
      14: ('J', 'N'), 15: ('C', 'D'), 16: ('D', 'F'), 17: ('E', 'F'), 18: ('F', 'G'), 19: ('I', 'K'), 20: ('K', 'N'),
    },
    rules: {
      'Start': (f) {
        if (f.only({kSS, kSSV, kAS})) return go('C', '(潜水艦+潜水母艦)のみ');
        return even(['A', 'B'], 'それ以外 (片寄りなし)');
      },
      'C': (f) => lean('D', 'F', 'ランダム (Dマス寄り)', 60),
      'D': (f) {
        if (f.av + f.ao >= 1 && f.ddde >= 2) return go('G', '(水母+補給艦)1隻以上 かつ (駆逐+海防)2隻以上');
        if (f.subs >= 2 && f.as >= 1) return go('G', '潜水艦2隻以上 かつ 潜水母艦を含む');
        if (f.only({kSS, kSSV})) return lean('G', 'F', '潜水艦のみ (Gマス寄り)', 65);
        if (f.subs >= 1 && f.bbClass + f.carriers >= 1) {
          return split({'F': 65, 'G': 35}, '潜水艦 かつ (戦艦級+空母系)を含む (Fマス寄り・Wikiでも推測)', estimated: true);
        }
        return even(['F', 'G'], 'それ以外 ((駆逐+海防)が多いほどGマス寄り・割合不明)', estimated: true);
      },
      'F': (f) {
        if (f.carriers + f.cl + f.av >= 1) return lean('J', 'G', '(空母系+軽巡+水母)1隻以上 (Jマス寄り)', 90);
        if (f.subs >= 2 && f.as >= 1) {
          return split({'G': 80, 'J': 20}, '潜水艦2隻以上 かつ 潜水母艦を含む (Wikiでも推測)', estimated: true);
        }
        return split({'G': 25, 'H': 35, 'J': 40}, 'それ以外 (ランダム)');
      },
      'G': (f) {
        if (f.subs >= 2 && f.as >= 1) return split({'I': 60, 'K': 40}, '潜水艦2隻以上 かつ 潜水母艦を含む (Iマス寄り・Wikiでも推測)', estimated: true);
        if (f.only({kSS, kSSV})) return lean('I', 'K', '潜水艦のみ (Iマス寄り)', 55);
        if (f.cl + f.dd + f.de <= 1) return go('K', '(軽巡+駆逐+海防)1隻以下');
        if (f.av + f.ao >= 1 && f.ddde >= 2) return lean('I', 'K', '(水母+補給艦)1隻以上 かつ (駆逐+海防)2隻以上 (Iマス寄り)', 65);
        if (f.ddde >= 3) return lean('K', 'I', '(駆逐+海防)3隻以上 (Kマス寄り)', 55);
        if (f.ddde >= 1) return lean('K', 'I', '(駆逐+海防)1隻以上 (Kマス寄り)', 65);
        return go('K', '(駆逐+海防)0隻');
      },
      'J': (f) {
        if (f.cl >= 1 && f.dd >= 4) return go('N', '軽巡1隻以上 かつ 駆逐4隻以上');
        if (f.cl == 1 && f.ca == 5) return go('N', '軽巡1隻 かつ 重巡5隻 (航巡は不可)');
        if (f.only({kSS, kSSV})) return lean('N', 'M', '潜水艦のみ (Nマス寄り)', 90);
        if (f.subs >= 1) return split({'L': 45, 'M': 10, 'N': 45}, '潜水艦を含む (Mマス10%。L・Nの割合は不明)', estimated: true);
        final heavy = f.bbClass + f.carriers;
        if (heavy >= 6) return go('L', '(戦艦級+空母系)6隻');
        if (heavy == 5) return lean('L', 'N', '(戦艦級+空母系)5隻 (Lマス寄り)', 85);
        if (heavy == 4) return lean('N', 'L', '(戦艦級+空母系)4隻 (Nマス寄り)', 75);
        if (heavy == 3) return lean('N', 'L', '(戦艦級+空母系)3隻 (Nマス寄り)', 80);
        return lean('N', 'L', '(戦艦級+空母系)2隻以下 (Nマス寄り)', 90);
      },
    },
  ),

  // ---- 2-4 沖ノ島海域 ----
  CompassMap(
    area: 2,
    no: 4,
    title: '沖ノ島海域',
    boss: 'P',
    edges: {
      1: ('F', 'A'), 2: ('Start', 'B'), 3: ('B', 'C'), 4: ('E', 'D'), 5: ('I', 'E'), 6: ('C', 'F'), 7: ('B', 'G'), //
      8: ('G', 'H'), 9: ('H', 'I'), 10: ('F', 'J'), 11: ('I', 'K'), 12: ('H', 'L'), 13: ('J', 'M'), 14: ('K', 'N'),
      15: ('K', 'O'), 16: ('L', 'P'), 17: ('C', 'G'), 18: ('J', 'L'), 19: ('K', 'L'), 20: ('L', 'M'), 21: ('M', 'P'),
    },
    rules: {
      'B': (f) {
        if (f.dd == 6) return split({'G': 1}, '駆逐6隻 (Wikiでも推測)', estimated: true);
        if (f.n == 6 && f.cl + f.ct == 1 && f.dd >= 4 && f.cl + f.ct + f.dd + f.caClass + f.de == 6) {
          return go('G', '(軽巡+練巡)1隻 かつ 駆逐4隻 + (重巡級/駆逐/海防)1隻');
        }
        if (f.ddde <= 2) {
          if (f.carriers >= 3) return go('C', '(駆逐+海防)2隻以下 かつ 空母系3隻以上');
          final heavy = f.bbClass + f.standardCarriers;
          if (heavy >= 3) return go('C', '(駆逐+海防)2隻以下 かつ (戦艦級+正規空母)3隻以上');
          if (heavy == 2) return lean('C', 'G', '(駆逐+海防)2隻以下 かつ (戦艦級+正規空母)2隻 (Cマス寄り)', 80);
          if (f.standardCarriers >= 1) return lean('C', 'G', '(駆逐+海防)2隻以下 かつ 正規空母を含む (Cマス寄り)', 60);
          if (f.subs >= 1) return lean('C', 'G', '(駆逐+海防)2隻以下 かつ 潜水艦を含む (Cマス寄り・割合不明)');
        }
        return lean('G', 'C', 'それ以外 (Gマス寄り・割合不明)');
      },
      'C': (f) {
        if (f.as + f.ao >= 1) return go('G', '(潜水母艦+補給艦)1隻以上');
        return even(['F', 'G'], 'それ以外 (片寄りなし)');
      },
      'F': (f) {
        if (f.cvl >= 1 && f.ddde >= 2) return lean('J', 'A', '軽空母1隻以上 かつ (駆逐+海防)2隻以上 (Jマス寄り)', 92.5);
        if (f.cvl >= 1) return lean('J', 'A', '軽空母を含む (Jマス寄り)', 82.5);
        if (f.dd >= 2) return lean('J', 'A', '駆逐2隻以上 (Jマス寄り)', 75);
        return go('A', '駆逐1隻以下');
      },
      'H': (f) {
        if (f.n == 6 && f.cl + f.ct >= 1 && f.dd >= 4 && f.caClass + f.cl + f.ct + f.dd == 6) {
          return go('L', '(軽巡+練巡)1隻 かつ 駆逐4隻 + (重巡級/軽巡/練巡/駆逐)1隻');
        }
        return go('I', 'それ以外');
      },
      'I': (f) {
        if (f.cvl >= 1 && f.cl >= 1) return lean('K', 'E', '軽空母 かつ 軽巡を含む (Kマス寄り)', 92.5);
        if (f.cvl >= 1) return lean('K', 'E', '軽空母を含む (Kマス寄り)', 82.5);
        if (f.cl >= 1) return lean('K', 'E', '軽巡を含む (Kマス寄り)', 75);
        return lean('E', 'K', 'それ以外 (Eマス寄り・割合不明)');
      },
      'J': (f) {
        final heavy = f.bbClass + f.carriers;
        if (heavy >= 4) return go('L', '(戦艦級+空母系)4隻以上');
        if (heavy == 3) return go('M', '(戦艦級+空母系)3隻');
        if (f.standardCarriers == 2) return go('M', '正規空母2隻');
        if (f.standardCarriers == 0) return go('L', '正規空母0隻');
        return lean('M', 'L', 'それ以外 (Mマス寄り)', 65);
      },
      'K': (f) {
        if (f.as + f.ao >= 2) return go('N', '(潜水母艦+補給艦)2隻以上');
        if (f.av + f.as + f.ao >= 1) {
          if (f.ddde >= 2) return lean('L', 'N', '(水母+潜水母艦+補給艦)を含む かつ (駆逐+海防)2隻以上 (Lマス寄り・割合不明)');
          if (f.ddde == 1) return split({'L': 37.5, 'N': 37.5, 'O': 25}, '(水母+潜水母艦+補給艦)を含む かつ (駆逐+海防)1隻 (Wikiでも推測)', estimated: true);
          return split({'L': 25, 'N': 35, 'O': 40}, '(水母+潜水母艦+補給艦)を含む かつ (駆逐+海防)0隻 (Wikiでも推測)', estimated: true);
        }
        if (f.de >= 2) return lean('L', 'N', '海防2隻以上 (Lマス寄り・割合不明)');
        if (f.ddde >= 2) return go('L', '(駆逐+海防)2隻以上');
        if (f.ddde == 1) return lean('L', 'O', '(駆逐+海防)1隻 (Lマス寄り)', 65);
        // ここから下は Wiki でも「?」付き
        if (f.cav >= 1) {
          if (f.bbClass >= 1) return lean('O', 'L', '航巡 かつ 戦艦を含む (Oマス寄り・Wikiでも推測)');
          return lean('L', 'O', '航巡を含む (Lマス寄り・Wikiでも推測)');
        }
        if (f.bbClass >= 2) return split({'O': 77.5, 'L': 22.5}, '戦艦級2隻以上 (Oマス寄り・Wikiでも推測)', estimated: true);
        return split({'O': 65, 'L': 35}, 'それ以外 (Oマス寄り・Wikiでも推測)', estimated: true);
      },
      'L': (f) {
        if (f.bbClass + f.carriers == 4) return go('M', '(戦艦級+空母系)ちょうど4隻');
        if (f.cl >= 1 && f.dd >= 2) return go('P', '軽巡1隻以上 かつ 駆逐2隻以上');
        if (f.bbClass + f.standardCarriers <= 2) return go('P', '(戦艦級+正規空母)2隻以下');
        return split({'M': 60, 'P': 40}, 'それ以外 (Mマス寄り・Wikiでも推測)', estimated: true);
      },
    },
  ),

  // ---- 2-5 沖ノ島沖 ----
  CompassMap(
    area: 2,
    no: 5,
    title: '沖ノ島沖',
    boss: 'O',
    coefficient: 1,
    edges: {
      1: ('B', 'A'), 2: ('Start', 'B'), 3: ('Start', 'C'), 4: ('C', 'D'), 5: ('C', 'E'), 6: ('B', 'F'), 7: ('E', 'G'), //
      8: ('I', 'H'), 9: ('E', 'I'), 10: ('F', 'J'), 11: ('G', 'K'), 12: ('G', 'L'), 13: ('J', 'M'), 14: ('L', 'N'),
      15: ('I', 'O'), 16: ('F', 'E'), 17: ('J', 'H'), 18: ('G', 'I'), 19: ('J', 'O'), 20: ('L', 'O'),
    },
    rules: {
      'Start': (f) {
        if (f.subs >= 4) return go('B', '潜水艦4隻以上');
        if (f.subs >= 1 && f.bbClass <= 3) {
          if (f.carriers >= 1) return even(['B', 'C'], '潜水艦 かつ 空母系を含む (割合不明)', estimated: true);
          if (f.av >= 2) return even(['B', 'C'], '潜水艦 かつ 水母2隻以上 (割合不明)', estimated: true);
        }
        if (f.carriers >= 1) return go('C', '空母系を含む');
        if (f.av >= 2) return go('C', '水母2隻以上');
        if (f.drumShips >= 2) return go('B', 'ドラム缶を積んだ艦2隻以上');
        if (f.ddde >= 4) return go('B', '(駆逐+海防)4隻以上');
        if (f.cl >= 1 && f.ddde >= 3) return go('B', '軽巡1隻以上 かつ (駆逐+海防)3隻以上');
        if (f.bbClass >= 1) return go('C', '戦艦級を含む');
        if (f.cl + f.clt >= 1 && f.cav >= 2) return go('C', '(軽巡+雷巡)1隻以上 かつ 航巡2隻以上');
        if (f.cl + f.clt >= 1 && f.cav >= 1 && f.caClass + f.cl + f.clt >= 5) {
          return go('C', '(軽巡+雷巡)1隻以上 かつ 航巡1隻以上 かつ (重巡級+軽巡+雷巡)5隻以上');
        }
        if (f.n >= 6) return split({'B': 80, 'C': 20}, '6隻編成 (Bマス寄り・Wikiでも推測)', estimated: true);
        return split({'C': 90, 'B': 10}, 'それ以外 (かなりCマス寄り・Wikiでも推測)', estimated: true);
      },
      'B': (f) {
        if (f.subs >= 3) return go('A', '潜水艦3隻以上');
        return go('F', 'それ以外');
      },
      'C': (f) {
        if (f.carriers >= 3) return go('D', '空母系3隻以上');
        if (f.bbClass >= 3) return go('D', '戦艦級3隻以上');
        if (f.cl >= 1 && f.dd >= 2) return go('E', '軽巡1隻以上 かつ 駆逐2隻以上');
        if (f.cav >= 2 && f.dd >= 2) return go('E', '航巡2隻以上 かつ 駆逐2隻以上');
        return lean('E', 'D', 'それ以外 (Eマス寄り)', 70);
      },
      'E': (f) {
        if (f.bbClass >= 1) return go('G', '戦艦級を含む');
        if (f.cl >= 1 && f.ddde >= 4) return go('I', '軽巡1隻以上 かつ (駆逐+海防)4隻以上');
        if (f.anySlow) return go('G', '低速の艦を含む');
        if (f.standardCarriers + f.caClass >= 2) return go('G', '(正規空母+重巡級)2隻以上');
        if (f.cl >= 1 && f.dd >= 3) return go('I', '軽巡1隻以上 かつ 駆逐3隻以上');
        return go('G', 'それ以外');
      },
      'F': (f) {
        if (f.anySlow) return go('J', '低速の艦を含む');
        if (f.dd >= 3) return go('E', '駆逐3隻以上');
        if (f.cl >= 1 && f.dd >= 2) return go('E', '軽巡1隻以上 かつ 駆逐2隻以上');
        if (f.bbClass >= 3) return go('J', '戦艦級3隻以上');
        return lean('J', 'E', 'それ以外 (Jマス寄り)', 65);
      },
      'G': (f) {
        final heavy = f.bbClass + f.carriers;
        if (heavy <= 1 && f.ddde >= 4) return go('I', '(戦艦級+空母系)1隻以下 かつ (駆逐+海防)4隻以上');
        if (heavy == 0 && f.cl >= 1 && f.dd >= 3) return go('I', '(戦艦級+空母系)0隻 かつ 軽巡1隻以上 かつ 駆逐3隻以上');
        final los = f.losScore(1);
        final score = los.toStringAsFixed(1);
        if (los < 37) return go('K', '索敵スコア$score (37未満。37・41はWikiでも推測)');
        if (los < 41) return even(['K', 'L'], '索敵スコア$score (37以上41未満はランダム・割合不明)', estimated: true);
        return go('L', '索敵スコア$score (41以上)');
      },
      'I': (f) {
        final los = f.losScore(1);
        final score = los.toStringAsFixed(1);
        if (los < 31) return go('H', '索敵スコア$score (31未満)');
        if (los < 34) return even(['H', 'O'], '索敵スコア$score (31以上34未満はランダム・割合不明)', estimated: true);
        return go('O', '索敵スコア$score (34以上)');
      },
      'J': (f) {
        final heavy = f.bbClass + f.carriers;
        final los = f.losScore(1);
        final score = los.toStringAsFixed(1);
        if (los < 42) return go('H', '索敵スコア$score (42未満。42・49はWikiでも推測)');
        if (los < 49) {
          if (heavy >= 4) return even(['H', 'M', 'O'], '索敵スコア$score (42以上49未満) かつ (戦艦級+空母系)4隻以上 (割合不明)', estimated: true);
          return even(['H', 'O'], '索敵スコア$score (42以上49未満。割合不明)', estimated: true);
        }
        if (heavy >= 4) return even(['M', 'O'], '索敵スコア$score (49以上) かつ (戦艦級+空母系)4隻以上 (割合不明)', estimated: true);
        return go('O', '索敵スコア$score (49以上)');
      },
      'L': (f) {
        if (f.cl >= 1 && f.dd >= 2) return go('O', '軽巡を含み 駆逐2隻以上');
        if (f.bbClass + f.carriers == 0) return split({'O': 60, 'N': 40}, '(戦艦級+空母系)0隻 (Oマス寄り・Wikiでも推測)', estimated: true);
        return split({'N': 60, 'O': 40}, 'それ以外 (Nマス寄り・Wikiでも推測)', estimated: true);
      },
    },
    note: '分岐点係数1',
  ),
];
