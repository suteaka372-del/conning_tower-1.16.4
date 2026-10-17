import 'repair_timer.dart';

// 戦闘情報タブの「航空戦」: 各航空戦の機数・撃墜数と、発動した対空カットイン。
// 戦闘の API の応答 (api_data) をそのまま読む (対空カットインの api_air_fire は戦闘のデータモデルにないため)。
// 項目の意味は ElectronicObserver (MIT License) の PhaseAirBattleBase を参考にした

/// 空対空 (stage1) / 対空砲火 (stage2) の機数
class AirBattleStage {
  final int friendCount;
  final int friendLost;
  final int enemyCount;
  final int enemyLost;

  const AirBattleStage({
    required this.friendCount,
    required this.friendLost,
    required this.enemyCount,
    required this.enemyLost,
  });

  static AirBattleStage? fromJson(dynamic json) {
    if (json is! Map) return null;
    int value(String key) => json[key] is num ? (json[key] as num).toInt() : 0;
    return AirBattleStage(
      friendCount: value('api_f_count'),
      friendLost: value('api_f_lostcount'),
      enemyCount: value('api_e_count'),
      enemyLost: value('api_e_lostcount'),
    );
  }
}

/// 発動した対空カットイン (api_air_fire)
class AirBattleCutIn {
  /// 種別 (api_kind)
  final int kind;

  /// 発動した艦の位置 (api_idx。連合艦隊の第2艦隊は 6〜)
  final int shipIndex;

  /// 発動した艦 (分からなければ null)
  final int? shipUid;
  final String shipName;

  /// 発動に使った装備 (api_use_items)
  final List<int> useItems;

  const AirBattleCutIn({
    required this.kind,
    required this.shipIndex,
    this.shipUid,
    this.shipName = '',
    this.useItems = const [],
  });
}

/// 航空戦1回分
class AirBattlePhase {
  final String label;

  /// 制空 (api_disp_seiku。0=均衡 1=確保 2=優勢 3=劣勢 4=喪失)
  final int? airSuperiority;
  final AirBattleStage? stage1;
  final AirBattleStage? stage2;
  final AirBattleCutIn? cutIn;

  const AirBattlePhase({required this.label, this.airSuperiority, this.stage1, this.stage2, this.cutIn});
}

/// 発動した艦を調べる ([friendly] は友軍艦隊)。(uid, 名前) を返す
typedef AirBattleShipLookup = (int, String)? Function(int index, {required bool friendly});

/// 今のマス (演習なら今の演習) の航空戦
class AirBattleRecord {
  final List<AirBattlePhase> phases = [];

  void clear() => phases.clear();

  /// 戦闘の API の応答を読む。昼戦→夜戦のように同じマスで続く戦闘は後ろに足す
  void addBattle(String path, Map<dynamic, dynamic> apiData, {AirBattleShipLookup? shipAt}) {
    void add(String label, dynamic round, {bool friendly = false, bool withSuperiority = false}) {
      if (round is! Map) return;
      final stage1 = AirBattleStage.fromJson(round['api_stage1']);
      final stage2Json = round['api_stage2'];
      final stage2 = AirBattleStage.fromJson(stage2Json);
      if (stage1 == null && stage2 == null) return;
      AirBattleCutIn? cutIn;
      final airFire = stage2Json is Map ? stage2Json['api_air_fire'] : null;
      if (airFire is Map && airFire['api_kind'] is num && airFire['api_idx'] is num) {
        final index = (airFire['api_idx'] as num).toInt();
        final ship = shipAt?.call(index, friendly: friendly);
        cutIn = AirBattleCutIn(
          kind: (airFire['api_kind'] as num).toInt(),
          shipIndex: index,
          shipUid: ship?.$1,
          shipName: ship?.$2 ?? '',
          useItems: [
            for (final item in (airFire['api_use_items'] as List? ?? const []))
              if (item is num) item.toInt()
          ],
        );
      }
      final seiku = round['api_stage1'] is Map ? round['api_stage1']['api_disp_seiku'] : null;
      phases.add(AirBattlePhase(
        label: label,
        airSuperiority: withSuperiority && seiku is num ? seiku.toInt() : null,
        stage1: stage1,
        stage2: stage2,
        cutIn: cutIn,
      ));
    }

    add(repairText('基地航空隊 (噴式)', 'Land base (jet)'), apiData['api_air_base_injection']);
    add(repairText('噴式強襲', 'Jet assault'), apiData['api_injection_kouku']);
    final baseAttacks = apiData['api_air_base_attack'];
    if (baseAttacks is List) {
      final waves = <int, int>{};
      for (final attack in baseAttacks) {
        if (attack is! Map) continue;
        final baseId = attack['api_base_id'] is num ? (attack['api_base_id'] as num).toInt() : 0;
        final wave = waves[baseId] = (waves[baseId] ?? 0) + 1;
        add(repairText('第$baseId基地航空隊 第$wave波', 'Land base $baseId wave $wave'), attack);
      }
    }
    add(repairText('友軍艦隊', 'Friend fleet'), apiData['api_friendly_kouku'], friendly: true);
    final isRaid = path.contains('ld_airbattle');
    final hasSecondWave = apiData['api_kouku2'] is Map;
    add(
      isRaid
          ? repairText('空襲', 'Air raid')
          : hasSecondWave
              ? repairText('航空戦 第1波', 'Air battle 1')
              : repairText('航空戦', 'Air battle'),
      apiData['api_kouku'],
      withSuperiority: true,
    );
    final support = apiData['api_support_info'];
    if (support is Map) add(repairText('支援艦隊 (航空)', 'Support (air)'), support['api_support_airatack']);
    add(repairText('航空戦 第2波', 'Air battle 2'), apiData['api_kouku2'], withSuperiority: true);
    // 夜戦の支援 (航空)
    final nightSupport = apiData['api_n_support_info'];
    if (nightSupport is Map) add(repairText('夜戦支援 (航空)', 'Night support (air)'), nightSupport['api_support_airatack']);
  }
}
