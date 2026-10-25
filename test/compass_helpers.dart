import 'package:conning_tower/models/feature/kancolle/compass/compass_maps.dart';

/// 羅針盤のテスト用の艦隊 (艦種の並び。速力・索敵スコアなどは全艦同じ)
CompassFleet fleet(
  List<int> types, {
  int speed = 10,
  double los = 0,
  int drumShips = 0,
  int radarShips = 0,
  int daihatsuShips = 0,
  List<String> names = const [],
}) =>
    CompassFleet(
      [
        for (final (i, t) in types.indexed)
          CompassShip(
            shipType: t,
            speed: speed,
            drums: i < drumShips ? 1 : 0,
            radars: i < radarShips ? 1 : 0,
            daihatsu: i < daihatsuShips ? 1 : 0,
            name: i < names.length ? names[i] : '',
          ),
      ],
      losScore: (_) => los,
    );

/// [map] は 1-5 のような名前。ゲージが複数ある海域は [phase] 番目のゲージ
CompassMap mapNamed(String map, [int phase = 0]) => kCompassMaps.where((m) => m.name == map).elementAt(phase);

double boss(String map, CompassFleet f, [int phase = 0]) => simulateCompass(mapNamed(map, phase), f).bossProbability;

const kAllTypes = [kDE, kDD, kCL, kCLT, kCA, kCAV, kCVL, kFBB, kBB, kBBV, kCV, kSS, kSSV, kAV, kLHA, kCVB, kAR, kAS, kCT, kAO];

// 特定の艦で分岐する海域があるので、ランダムな編成にも混ぜる
const kNames = ['祥鳳', '夕張改二', '翔鶴', '瑞鶴改二甲', 'あきつ丸改', '秋津洲', '如月', '長門改二', '陸奥改二', '羽黒', '神風', '足柄', '妙高', '高雄', '大鷹'];
