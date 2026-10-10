import 'dart:math';

import 'package:conning_tower/models/feature/log/kancolle_log.dart';

// 資源の記録を「ゲームの日付」(JST 5:00 区切り) でまとめる

/// 5:00 区切りで記録し始めた時刻 (ミリ秒)。これより前の記録は 0:00 区切り
const kResourceGameDaySinceKey = 'KC_RESOURCE_GAME_DAY_SINCE';

const List<String> kMainResourceKeys = ['fuel', 'ammo', 'steel', 'bauxite'];
const List<String> kMaterialKeys = ['ic', 'ir', 'dm', 'im'];

const _jstOffset = Duration(hours: 9);
const _dayBoundary = Duration(hours: 5);

/// JST 5:00 を区切りとした「ゲームの日」の開始時刻
DateTime gameDayStart(DateTime time) {
  final shifted = time.toUtc().add(_jstOffset).subtract(_dayBoundary);
  return DateTime.utc(shifted.year, shifted.month, shifted.day)
      .add(_dayBoundary)
      .subtract(_jstOffset);
}

/// ゲームの日付 (年月日だけを持つ UTC の DateTime)
DateTime gameDate(DateTime time) {
  final shifted = time.toUtc().add(_jstOffset).subtract(_dayBoundary);
  return DateTime.utc(shifted.year, shifted.month, shifted.day);
}

/// 端末の日付 (0:00 区切り。5:00 区切りにする前の記録用)
DateTime calendarDate(DateTime time) {
  final local = time.toLocal();
  return DateTime.utc(local.year, local.month, local.day);
}

/// 1日分の値 (始値・終値・高値・安値)
class ResourceDayValue {
  final int open;
  final int close;
  final int high;
  final int low;

  const ResourceDayValue({
    required this.open,
    required this.close,
    required this.high,
    required this.low,
  });

  /// 同じ日の後の記録をまとめる
  ResourceDayValue merge(ResourceDayValue later) => ResourceDayValue(
        open: open,
        close: later.close,
        high: max(high, later.high),
        low: min(low, later.low),
      );
}

class ResourceDay {
  /// 日付 (年月日だけを持つ UTC の DateTime)
  final DateTime date;
  final Map<String, ResourceDayValue> values;

  const ResourceDay({required this.date, required this.values});

  int? close(String resource) => values[resource]?.close;

  /// グラフの横軸用 (端末のタイムゾーンでの同じ日付)
  DateTime get localDate => DateTime(date.year, date.month, date.day);
}

/// 記録を日ごとにまとめる (古い順)。
/// [gameDaySinceMs] より前の記録は端末の日付 (0:00 区切り)、それ以降はゲームの日付 (5:00 区切り) で分ける
List<ResourceDay> groupResourceLogs(
  Iterable<KancolleResourceLogEntity> logs, {
  int? gameDaySinceMs,
}) {
  final sorted = logs.toList()..sort((a, b) => a.time.compareTo(b.time));
  final days = <DateTime, Map<String, ResourceDayValue>>{};
  for (final log in sorted) {
    final usesGameDay =
        gameDaySinceMs != null && log.time.millisecondsSinceEpoch >= gameDaySinceMs;
    final date = usesGameDay ? gameDate(log.time) : calendarDate(log.time);
    final value = ResourceDayValue(
        open: log.open, close: log.close, high: log.high, low: log.low);
    final map = days.putIfAbsent(date, () => {});
    final existing = map[log.resource];
    map[log.resource] = existing == null ? value : existing.merge(value);
  }
  final dates = days.keys.toList()..sort();
  return [for (final date in dates) ResourceDay(date: date, values: days[date]!)];
}

/// 記録のある前の日からの増減 (前の日がなければ null)
int? diffFromPreviousDay(List<ResourceDay> days, int index, String resource) {
  final current = days[index].close(resource);
  if (current == null) return null;
  for (var i = index - 1; i >= 0; i--) {
    final previous = days[i].close(resource);
    if (previous != null) return current - previous;
  }
  return null;
}

/// 今日 (ゲームの日付) の増減。記録のある前の日の終値と比べ、なければ今日の始値と比べる
int? todayResourceDiff(
  List<ResourceDay> days,
  String resource,
  int currentValue,
  DateTime now,
) {
  final today = gameDate(now);
  int? previousClose;
  ResourceDayValue? todayValue;
  for (final day in days) {
    if (day.date.isBefore(today)) {
      previousClose = day.close(resource) ?? previousClose;
    } else if (day.date == today) {
      todayValue = day.values[resource];
    }
  }
  if (previousClose != null) return currentValue - previousClose;
  if (todayValue != null) return currentValue - todayValue.open;
  return null;
}

/// 直近 [periodDays] 日分 (今日を含む)。0 なら全期間
List<ResourceDay> resourceDaysInPeriod(
    List<ResourceDay> days, int periodDays, DateTime now) {
  if (periodDays <= 0) return days;
  final from = gameDate(now).subtract(Duration(days: periodDays - 1));
  return [
    for (final day in days)
      if (!day.date.isBefore(from)) day
  ];
}

/// 増減の表示 (+1,234 / −560 / ±0)
String formatResourceDiff(int diff) {
  final text = _formatNumber(diff.abs());
  if (diff > 0) return '+$text';
  if (diff < 0) return '−$text';
  return '±0';
}

String _formatNumber(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 3桁区切り (1,234,567)
String formatResourceValue(int value) =>
    value < 0 ? '-${_formatNumber(-value)}' : _formatNumber(value);
