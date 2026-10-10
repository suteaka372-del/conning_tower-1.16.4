import 'package:conning_tower/helper.dart';
import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/models/feature/kancolle/resource_history.dart';
import 'package:conning_tower/models/feature/log/kancolle_log.dart';
import 'package:conning_tower/utils/objectbox.dart';
import 'package:conning_tower/widgets/resource_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pull_down_button/pull_down_button.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

/// 資源ごとの線の色 (司令部タブの箱と同じ色。背景に合わせて明るさだけ変える)
Color resourceLineColor(String resource, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (resource) {
    'fuel' => dark ? const Color(0xFF4CAF50) : const Color.fromRGBO(32, 89, 29, 1.0),
    'ammo' => dark ? const Color(0xFFC9A66B) : const Color.fromRGBO(126, 102, 54, 1.0),
    'steel' => dark ? const Color.fromRGBO(181, 180, 180, 1.0) : const Color(0xFF7A7A7A),
    'bauxite' => const Color.fromRGBO(219, 150, 102, 1.0),
    'ic' => const Color.fromRGBO(255, 176, 7, 1.0),
    'ir' => dark ? const Color.fromRGBO(195, 212, 75, 1.0) : const Color(0xFF8FA020),
    'dm' => dark ? const Color(0xFF4FB3BD) : const Color.fromRGBO(56, 126, 132, 1.0),
    'im' => dark ? const Color.fromRGBO(186, 186, 186, 1.0) : const Color(0xFF7A7A7A),
    _ => CupertinoColors.systemGrey,
  };
}

/// 表の見出し用の短い名前
String resourceShortName(String resource) => switch (resource) {
      'fuel' => repairText('燃料', 'Fuel'),
      'ammo' => repairText('弾薬', 'Ammo'),
      'steel' => repairText('鋼材', 'Steel'),
      'bauxite' => repairText('ボーキ', 'Baux'),
      'ic' => repairText('高速建造', 'Burner'),
      'ir' => repairText('高速修復', 'Bucket'),
      'dm' => repairText('開発資材', 'DevMat'),
      'im' => repairText('改修資材', 'Screw'),
      _ => resource,
    };

/// 増減の色 (増えたら緑、減ったら赤)
Color resourceDiffColor(int diff, BuildContext context) {
  if (diff > 0) return CupertinoColors.systemGreen.resolveFrom(context);
  if (diff < 0) return CupertinoColors.systemRed.resolveFrom(context);
  return CupertinoColors.secondaryLabel.resolveFrom(context);
}

/// 資源の推移 (4種類を1枚の折れ線グラフと日ごとの表で表示する)
class ResourceHistoryPage extends StatefulWidget {
  const ResourceHistoryPage({
    super.key,
    required this.admiralName,
    this.showMaterials = false,
    this.days,
  });

  final String admiralName;

  /// テスト用: 記録を直接渡す (null ならデータベースから読む)
  final List<ResourceDay>? days;

  /// true なら資材 (高速建造材・高速修復材・開発資材・改修資材) を最初に表示する
  final bool showMaterials;

  @override
  State<ResourceHistoryPage> createState() => _ResourceHistoryPageState();
}

class _ResourceHistoryPageState extends State<ResourceHistoryPage> {
  late bool _materials = widget.showMaterials;
  int _periodDays = 30;
  List<ResourceDay> _days = [];
  late final TrackballBehavior _trackball = TrackballBehavior(
    enable: true,
    activationMode: ActivationMode.singleTap,
    tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
    hideDelay: 3000,
    tooltipSettings: const InteractiveTooltip(format: 'series.name : point.y'),
  );

  static const _periods = {14: '2週間', 30: '1ヶ月', 90: '3ヶ月', 0: '全期間'};
  static const _periodsEn = {14: '2W', 30: '1M', 90: '3M', 0: 'All'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (widget.days != null) {
      _days = widget.days!;
      return;
    }
    try {
      final logs = <KancolleResourceLogEntity>[
        for (final key in [...kMainResourceKeys, ...kMaterialKeys])
          ...objectbox.queryResource(widget.admiralName, key),
      ];
      _days = groupResourceLogs(logs, gameDaySinceMs: resourceGameDaySinceMs());
    } catch (_) {
      _days = [];
    }
  }

  List<String> get _keys => _materials ? kMaterialKeys : kMainResourceKeys;

  void _openCandleChart(String resource) {
    List<KancolleResourceLogEntity> data;
    try {
      data = objectbox.queryResource(widget.admiralName, resource)
        ..sort((a, b) => a.time.compareTo(b.time));
    } catch (_) {
      return;
    }
    if (data.isEmpty) return;
    navigatorToCupertino(context, ResourceChart(data: data));
  }

  String _weekday(DateTime date) {
    const ja = ['月', '火', '水', '木', '金', '土', '日'];
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return repairText(ja[date.weekday - 1], en[date.weekday - 1]);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final keys = _keys;
    final days = resourceDaysInPeriod(_days, _periodDays, DateTime.now());
    final secondaryStyle = TextStyle(
      fontSize: 12,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    );

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        middle: Text(repairText('資源の推移', 'Resource history')),
        trailing: PullDownButton(
          useRootNavigator: true,
          itemBuilder: (context) => [
            PullDownMenuTitle(title: Text(repairText('ローソク足で見る', 'Candlestick chart'))),
            for (final key in keys)
              PullDownMenuItem(
                title: resourceNameMap[key] ?? key,
                onTap: () => _openCandleChart(key),
              ),
          ],
          buttonBuilder: (context, showMenu) => CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: showMenu,
            child: const Icon(CupertinoIcons.ellipsis),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, constraints) {
          final chartHeight = (constraints.maxHeight * 0.55).clamp(180.0, 320.0);
          return CupertinoScrollbar(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoSlidingSegmentedControl<bool>(
                            groupValue: _materials,
                            onValueChanged: (value) =>
                                setState(() => _materials = value ?? false),
                            children: {
                              false: Text(repairText('資源', 'Resources')),
                              true: Text(repairText('資材', 'Materials')),
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoSlidingSegmentedControl<int>(
                            groupValue: _periodDays,
                            onValueChanged: (value) =>
                                setState(() => _periodDays = value ?? 30),
                            children: {
                              for (final e in _periods.entries)
                                e.key: Text(
                                  repairText(e.value, _periodsEn[e.key]!),
                                  style: const TextStyle(fontSize: 13),
                                ),
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (days.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        repairText('この期間の記録がありません。\nゲームにログインすると記録されます。',
                            'No records in this period.\nRecords are saved when you log in to the game.'),
                        textAlign: TextAlign.center,
                        style: secondaryStyle,
                      ),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: chartHeight,
                      child: _buildChart(days, keys, brightness),
                    ),
                  ),
                  SliverToBoxAdapter(child: _buildTableHeader(context, keys, brightness)),
                  SliverList.builder(
                    itemCount: days.length,
                    // 新しい日付を上にする (期間で絞った日は全体の末尾と同じ並び)
                    itemBuilder: (context, index) =>
                        _buildTableRow(context, _days.length - 1 - index, keys),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Text(
                        repairText(
                            '1日は朝5時で区切っています (この機能を入れる前の記録は0時区切り)。\n増減は記録のある前の日との差です。',
                            'Days change at 5:00 JST (older records use midnight).\nChanges are against the previous recorded day.'),
                        style: secondaryStyle,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildChart(List<ResourceDay> days, List<String> keys, Brightness brightness) {
    final showMarkers = days.length <= 31;
    return SfCartesianChart(
      plotAreaBorderWidth: 0,
      margin: const EdgeInsets.fromLTRB(4, 8, 12, 4),
      legend: const Legend(
        isVisible: true,
        position: LegendPosition.top,
        toggleSeriesVisibility: true,
        overflowMode: LegendItemOverflowMode.wrap,
      ),
      trackballBehavior: _trackball,
      primaryXAxis: DateTimeAxis(
        majorGridLines: const MajorGridLines(width: 0),
        dateFormat: DateFormat('M/d'),
        intervalType: DateTimeIntervalType.days,
        edgeLabelPlacement: EdgeLabelPlacement.shift,
      ),
      primaryYAxis: NumericAxis(
        axisLine: const AxisLine(width: 0),
        rangePadding: ChartRangePadding.round,
        numberFormat: NumberFormat('#,##0'),
      ),
      series: <CartesianSeries<ResourceDay, DateTime>>[
        for (final key in keys)
          LineSeries<ResourceDay, DateTime>(
            name: resourceShortName(key),
            dataSource: days,
            xValueMapper: (day, _) => day.localDate,
            yValueMapper: (day, _) => day.close(key),
            color: resourceLineColor(key, brightness),
            width: 2,
            markerSettings: MarkerSettings(isVisible: showMarkers, height: 4, width: 4),
          ),
      ],
    );
  }

  Widget _buildTableHeader(BuildContext context, List<String> keys, Brightness brightness) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(repairText('日付', 'Date'), style: const TextStyle(fontSize: 12)),
          ),
          for (final key in keys)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: resourceLineColor(key, brightness),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      resourceShortName(key),
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, int dayIndex, List<String> keys) {
    final day = _days[dayIndex];
    final valueStyle = TextStyle(
      fontSize: 13,
      color: CupertinoColors.label.resolveFrom(context),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              '${day.date.month}/${day.date.day}(${_weekday(day.date)})',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          for (final key in keys)
            Expanded(
              child: Builder(builder: (context) {
                final value = day.close(key);
                final diff = diffFromPreviousDay(_days, dayIndex, key);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value == null ? '-' : formatResourceValue(value),
                        style: valueStyle,
                      ),
                    ),
                    if (diff != null)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatResourceDiff(diff),
                          style: TextStyle(
                            fontSize: 11,
                            color: resourceDiffColor(diff, context),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ),
        ],
      ),
    );
  }
}
