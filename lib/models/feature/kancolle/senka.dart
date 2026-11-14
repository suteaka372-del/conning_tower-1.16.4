// 戦果の記録 (ElectronicObserver EN の「戦果ビューア」と同じ考え方)。
//
// 戦果は半日ごと (14:00 と 2:00 で区切る。月末だけ 22:00 で締める) にまとめ、3種類に分ける:
//   通常の戦果 = 提督経験値の増加 × 7 ÷ 10000
//   EO海域の戦果 = 戦闘結果の api_get_exmap_rate と、進撃の api_get_eo_rate
//   任務の戦果 = 任務報酬 (api_bounus の api_type 18) の api_count
// 区切りと式は ElectronicObserver EN の SenkaViewerViewModel (MIT License) を元にしている。

import 'dart:async';
import 'dart:convert';

import 'package:conning_tower/main.dart';
import 'package:flutter/foundation.dart';

/// 任務報酬の種類: 戦果 (api_bounus の api_type)
const kSenkaBonusType = 18;

/// 提督経験値 → 戦果
double senkaOfExp(int exp) => exp * 7 / 10000;

/// [time] の月の締め (月末の 22:00 JST = 13:00 UTC)
DateTime senkaEndOfMonth(DateTime time) {
  final t = time.toUtc();
  return DateTime.utc(t.year, t.month + 1, 0, 13);
}

/// [time] より後の最初の区切り (5:00 UTC = 14:00 JST、17:00 UTC = 2:00 JST、月末の 13:00 UTC = 22:00 JST)
DateTime senkaSessionEnd(DateTime time) {
  final t = time.toUtc();
  final candidates = [
    for (var day = 0; day <= 1; day++) ...[
      DateTime.utc(t.year, t.month, t.day + day, 5),
      DateTime.utc(t.year, t.month, t.day + day, 17),
    ],
    senkaEndOfMonth(t),
    senkaEndOfMonth(DateTime.utc(t.year, t.month + 1, 1)),
  ].where((c) => c.isAfter(t)).toList()
    ..sort();
  return candidates.first;
}

/// [time] を含む半日の始まり ([time] 以前の最後の区切り)
DateTime senkaSessionStart(DateTime time) {
  final t = time.toUtc();
  final candidates = [
    for (var day = -1; day <= 0; day++) ...[
      DateTime.utc(t.year, t.month, t.day + day, 5),
      DateTime.utc(t.year, t.month, t.day + day, 17),
    ],
    senkaEndOfMonth(t),
    senkaEndOfMonth(DateTime.utc(t.year, t.month, 0)),
  ].where((c) => !c.isAfter(t)).toList()
    ..sort();
  return candidates.last;
}

/// [time] を含む戦果の月の始まり (前の月の締め)
DateTime senkaMonthStart(DateTime time) {
  final t = time.toUtc();
  final end = senkaEndOfMonth(t);
  return t.isBefore(end) ? senkaEndOfMonth(DateTime.utc(t.year, t.month, 0)) : end;
}

/// [time] を含む戦果の1日の始まり (2:00 JST = 17:00 UTC。月の締めをまたがない)
DateTime senkaDayStart(DateTime time) {
  final t = time.toUtc();
  final day = t.hour < 17 ? DateTime.utc(t.year, t.month, t.day - 1, 17) : DateTime.utc(t.year, t.month, t.day, 17);
  final month = senkaMonthStart(t);
  return day.isBefore(month) ? month : day;
}

/// 半日ぶんの記録
class SenkaSession {
  SenkaSession({required this.start, this.firstExp, this.lastExp, this.eo = 0, this.quest = 0});

  /// 半日の始まり (UTC)
  final DateTime start;

  /// この半日で最初・最後に見た提督経験値
  int? firstExp;
  int? lastExp;

  /// EO海域・任務でもらった戦果
  int eo;
  int quest;

  DateTime get end => senkaSessionEnd(start);

  Map<String, dynamic> toJson() => {
        't': start.millisecondsSinceEpoch,
        if (firstExp != null) 'f': firstExp,
        if (lastExp != null) 'l': lastExp,
        if (eo != 0) 'e': eo,
        if (quest != 0) 'q': quest,
      };

  static SenkaSession? fromJson(dynamic json) {
    if (json is! Map || json['t'] is! int) return null;
    int? i(String key) => json[key] is int ? json[key] as int : null;
    return SenkaSession(
      start: DateTime.fromMillisecondsSinceEpoch(json['t'] as int, isUtc: true),
      firstExp: i('f'),
      lastExp: i('l'),
      eo: i('e') ?? 0,
      quest: i('q') ?? 0,
    );
  }
}

/// 表示用: 半日ぶんの戦果
class SenkaRecord {
  const SenkaRecord({required this.start, required this.end, required this.expGain, required this.eo, required this.quest});

  final DateTime start;
  final DateTime end;

  /// 提督経験値の増加 (前の記録の最後の値から。記録が途切れた間に増えた分もここに入る)
  final int expGain;
  final int eo;
  final int quest;

  double get normal => senkaOfExp(expGain);
  double get total => normal + eo + quest;
}

/// 記録から表示用の一覧を作る (新しい順)
List<SenkaRecord> senkaRecords(List<SenkaSession> sessions) {
  final sorted = [...sessions]..sort((a, b) => a.start.compareTo(b.start));
  final records = <SenkaRecord>[];
  int? previousExp;
  for (final s in sorted) {
    final base = previousExp ?? s.firstExp;
    final gain = s.lastExp != null && base != null && s.lastExp! > base ? s.lastExp! - base : 0;
    records.add(SenkaRecord(start: s.start, end: s.end, expGain: gain, eo: s.eo, quest: s.quest));
    if (s.lastExp != null) previousExp = s.lastExp;
  }
  return records.reversed.toList();
}

/// [from] 以降に始まった半日の合計 (通常, EO, 任務)
({double normal, int eo, int quest, double total}) senkaTotal(Iterable<SenkaRecord> records, {DateTime? from, DateTime? until}) {
  var normal = 0.0;
  var eo = 0;
  var quest = 0;
  for (final r in records) {
    if (from != null && r.start.isBefore(from)) continue;
    if (until != null && !r.start.isBefore(until)) continue;
    normal += r.normal;
    eo += r.eo;
    quest += r.quest;
  }
  return (normal: normal, eo: eo, quest: quest, total: normal + eo + quest);
}

/// 戦果をゲームの通信から記録する (提督ごとに端末に保存)
class SenkaStore {
  SenkaStore({this.load, this.save, DateTime Function()? now, this.saveDelay = const Duration(seconds: 2)})
      : _now = now ?? DateTime.now;

  /// 覚えておく半日の数 (約1年ぶん)
  static const keepSessions = 750;

  final String? Function(String admiral)? load;
  final void Function(String admiral, String json)? save;
  final DateTime Function() _now;
  final Duration saveDelay;

  final Map<String, List<SenkaSession>> _sessions = {};
  final Set<String> _unsaved = {};
  Timer? _saveTimer;

  /// 記録が変わったら増える
  final ValueNotifier<int> revision = ValueNotifier(0);

  List<SenkaSession> sessionsOf(String admiral) => _sessions[admiral] ??= _read(admiral);

  List<SenkaRecord> recordsOf(String admiral) => senkaRecords(sessionsOf(admiral));

  List<SenkaSession> _read(String admiral) {
    try {
      final text = load?.call(admiral);
      if (text == null || text.isEmpty) return [];
      return [
        for (final e in jsonDecode(text) as List)
          if (SenkaSession.fromJson(e) case final session?) session,
      ];
    } catch (_) {
      return [];
    }
  }

  SenkaSession _current(String admiral) {
    final sessions = sessionsOf(admiral);
    final start = senkaSessionStart(_now());
    for (final s in sessions.reversed) {
      if (s.start == start) return s;
    }
    final session = SenkaSession(start: start);
    sessions.add(session);
    if (sessions.length > keepSessions) sessions.removeRange(0, sessions.length - keepSessions);
    return session;
  }

  void _changed(String admiral) {
    revision.value++;
    _unsaved.add(admiral);
    // 戦闘のたびに全部を書き出さないよう、少し待ってまとめて保存する
    if (saveDelay == Duration.zero) {
      flush();
    } else {
      _saveTimer ??= Timer(saveDelay, flush);
    }
  }

  /// まだ保存していない記録を書き出す (アプリが裏に回るときにも呼ぶ)
  void flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    for (final admiral in _unsaved) {
      try {
        save?.call(admiral, jsonEncode([for (final s in sessionsOf(admiral)) s.toJson()]));
      } catch (_) {}
    }
    _unsaved.clear();
  }

  /// 提督経験値を見た
  void recordExp(String admiral, int exp) {
    if (admiral.isEmpty || exp <= 0) return;
    final session = _current(admiral);
    if (session.lastExp == exp) return;
    session.firstExp ??= exp;
    session.lastExp = exp;
    _changed(admiral);
  }

  void addEo(String admiral, int senka) {
    if (admiral.isEmpty || senka <= 0) return;
    _current(admiral).eo += senka;
    _changed(admiral);
  }

  void addQuest(String admiral, int senka) {
    if (admiral.isEmpty || senka <= 0) return;
    _current(admiral).quest += senka;
    _changed(admiral);
  }

  static int? _int(dynamic value) => switch (value) {
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v),
        _ => null,
      };

  /// ゲームの通信を受け取るたびに呼ぶ。[admiral] は今の提督名 (母港ではデータの中の名前を使う)
  void onApi(String path, dynamic json, String admiral) {
    try {
      final data = json is Map ? json['api_data'] : null;
      if (data is! Map) return;
      switch (path) {
        case '/api_port/port':
          final basic = data['api_basic'];
          if (basic is! Map) return;
          final name = '${basic['api_nickname'] ?? admiral}';
          recordExp(name, _int(basic['api_experience']) ?? 0);
        case '/api_req_sortie/battleresult' || '/api_req_combined_battle/battleresult':
          recordExp(admiral, _int(data['api_member_exp']) ?? 0);
          addEo(admiral, _int(data['api_get_exmap_rate']) ?? 0);
        case '/api_req_practice/battle_result' || '/api_req_mission/result':
          recordExp(admiral, _int(data['api_member_exp']) ?? 0);
        case '/api_req_map/next':
          addEo(admiral, _int(data['api_get_eo_rate']) ?? 0);
        case '/api_req_quest/clearitemget':
          final bonus = data['api_bounus'];
          if (bonus is! List) return;
          for (final b in bonus) {
            if (b is Map && _int(b['api_type']) == kSenkaBonusType) addQuest(admiral, _int(b['api_count']) ?? 0);
          }
      }
    } catch (_) {}
  }
}

/// アプリ全体で使う戦果の記録
final SenkaStore senkaStore = SenkaStore(
  load: (admiral) => localStorage.getString('KC_SENKA_$admiral'),
  save: (admiral, json) => localStorage.setString('KC_SENKA_$admiral', json),
);
