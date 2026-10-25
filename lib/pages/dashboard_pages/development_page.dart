import 'package:conning_tower/helper.dart';
import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/models/feature/kancolle/dev_stats.dart';
import 'package:conning_tower/models/feature/kancolle/quest_eo_tracker.dart';
import 'package:conning_tower/models/feature/kancolle/repair_timer.dart';
import 'package:conning_tower/providers/dev_stats_provider.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:conning_tower/utils/local_navigator.dart';
import 'package:conning_tower/widgets/components/edge_insets_constants.dart';
import 'package:conning_tower/widgets/kancolle_quest_detail_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「開発」タブ: 作りたい装備を選ぶと、出やすいレシピと秘書艦を統計から出す
class DevelopmentPage extends ConsumerStatefulWidget {
  const DevelopmentPage({super.key});

  @override
  ConsumerState createState() => _DevelopmentPageState();
}

class _DevelopmentPageState extends ConsumerState<DevelopmentPage> with AutomaticKeepAliveClientMixin {
  @override
  void initState() {
    super.initState();
    // 画面を描き終えてから読み込む (読み込み中の表示の切り替えが、描いている途中に起きないように)
    WidgetsBinding.instance.addPostFrameCallback((_) => DevStatsLoader.load().catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: tabContentMargin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10.0),
        // LocalNavigatorBuilder の builder は最初に渡したものが使われ続けるので、中で毎回最新のデータを読む
        child: LocalNavigatorBuilder(builder: (context) => const DevItemListView()),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

/// 統計に出てくる装備の一覧 (名前で絞り込み)
class DevItemListView extends ConsumerStatefulWidget {
  const DevItemListView({super.key});

  @override
  ConsumerState<DevItemListView> createState() => _DevItemListViewState();
}

class _DevItemListViewState extends ConsumerState<DevItemListView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    ref.watch(kancolleDataProvider); // 装備名 (マスターデータ) が届いたら作り直す
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      child: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<int>(
          valueListenable: DevStatsLoader.revision,
          builder: (context, _, __) {
            final stats = DevStatsLoader.stats;
            final items = stats == null ? const <int>[] : devItemsMatching(stats, _query);
            return CupertinoScrollbar(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: CupertinoSearchTextField(
                      placeholder: repairText('作りたい装備の名前', 'Equipment name'),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  _StatusLine(),
                  if (stats != null)
                    CupertinoListSection.insetGrouped(
                      margin: tabBottomListMargin,
                      children: [
                        if (items.isEmpty)
                          CupertinoListTile(title: Text(repairText('見つかりません', 'Not found'))),
                        for (final itemId in items)
                          CupertinoListTile(
                            title: Text(questEquipmentName(itemId)),
                            subtitle: Text(_categoryName(itemId)),
                            additionalInfo: Text(repairText('${stats.itemHits[itemId]}回', '${stats.itemHits[itemId]}')),
                            trailing: const CupertinoListTileChevron(),
                            onTap: () => navigatorToCupertino(context, DevItemDetailPage(itemId: itemId)),
                          ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _categoryName(int itemId) {
  final type = questMasterData?.slotItemInfo?[itemId]?.apiType;
  return type != null && type.length > 2 ? questEquipmentTypeName(type[2]) : '';
}

/// 統計に出てくる装備 ([query] を名前に含むもの)。装備の種類 → 図鑑番号の順
List<int> devItemsMatching(DevStats stats, String query) {
  final q = query.trim().toLowerCase();
  final items = [
    for (final id in stats.itemHits.keys)
      if (q.isEmpty || questEquipmentName(id).toLowerCase().contains(q)) id,
  ];
  int category(int id) {
    final type = questMasterData?.slotItemInfo?[id]?.apiType;
    return type != null && type.length > 2 ? type[2] : 999;
  }

  items.sort((a, b) {
    final c = category(a).compareTo(category(b));
    return c != 0 ? c : a.compareTo(b);
  });
  return items;
}

/// 取得の状態 (失敗していたら ⟳ で取り直せる)
class _StatusLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(child: Text(DevStatsLoader.statusText(text: repairText), style: style)),
          if (!DevStatsLoader.loading)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 32,
              onPressed: () => DevStatsLoader.load(force: true).catchError((_) {}),
              child: const Icon(CupertinoIcons.refresh, size: 18),
            ),
        ],
      ),
    );
  }
}

/// 自分の艦娘 (艦ID → その艦のレベルの高い順の名前)。おすすめの秘書艦に使えるかの表示用
class DevOwnedShip {
  final int shipId;
  final String name;
  final int level;

  const DevOwnedShip(this.shipId, this.name, this.level);
}

List<DevOwnedShip> devOwnedShips(KancolleData data) => [
      for (final ship in data.fleet.ships) DevOwnedShip(ship.shipId, ship.name ?? questShipName(ship.shipId), ship.level),
    ]..sort((a, b) => b.level.compareTo(a.level));

/// 「赤城改二 Lv99・加賀改二 Lv98 ほか3隻」
String devOwnedText(List<DevOwnedShip> ships) {
  if (ships.isEmpty) return repairText('持っている艦: なし', 'You have none');
  final names = ships.take(3).map((s) => '${s.name} Lv${s.level}').join('・');
  final more = ships.length > 3 ? repairText(' ほか${ships.length - 3}隻', ' +${ships.length - 3}') : '';
  return repairText('持っている艦: $names$more', 'Yours: $names$more');
}

/// 装備1つの詳細: 出やすいレシピ × 秘書艦 (今の秘書艦・艦種別・艦娘別)
class DevItemDetailPage extends ConsumerStatefulWidget {
  const DevItemDetailPage({super.key, required this.itemId});

  final int itemId;

  @override
  ConsumerState<DevItemDetailPage> createState() => _DevItemDetailPageState();
}

class _DevItemDetailPageState extends ConsumerState<DevItemDetailPage> {
  DevSort _sort = DevSort.rate;

  @override
  Widget build(BuildContext context) {
    final itemId = widget.itemId;
    final data = ref.watch(kancolleDataProvider);
    final stats = DevStatsLoader.stats;
    final master = questMasterData;
    final owned = devOwnedShips(data);
    final secretaryId = data.squads.isNotEmpty && data.squads.first.ships.isNotEmpty
        ? data.squads.first.ships.first.shipId
        : null;
    final secretaryGroup = secretaryId == null ? -1 : devSecretaryGroup(master, secretaryId);
    final secondary = TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel.resolveFrom(context));

    List<DevSuggestion> suggest(int Function(int) groupOf, int minTries, int fallback, {int limit = 10}) =>
        stats == null
            ? const <DevSuggestion>[]
            : devSuggestions(stats, itemId,
                groupOf: groupOf, sort: _sort, minTries: minTries, fallbackMinTries: fallback, limit: limit);

    // 今の秘書艦 (第1艦隊の旗艦) だけの記録
    final mine =
        secretaryId == null ? const <DevSuggestion>[] : suggest((id) => id == secretaryId ? 0 : -1, 20, 5, limit: 5);
    final byGroup = suggest((id) => devSecretaryGroup(master, id), 100, 20);
    final byShip = suggest((id) => id, 50, 10);

    Widget recipeTitle(DevRecipe r) => Text(
          repairText('燃${r.fuel} 弾${r.ammo} 鋼${r.steel} ボ${r.bauxite}', 'F${r.fuel} A${r.ammo} S${r.steel} B${r.bauxite}'),
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        );
    // 右側の大きい数字は、選んでいる並べ方の値
    Widget value(DevSuggestion s) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              switch (_sort) {
                DevSort.rate => devRateText(s.rate),
                DevSort.nails => devNailsText(s.nailsPerItem),
                DevSort.resources => devResourcesText(s.resourcesPerItem),
              },
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            Text(repairText('${s.hits}/${s.tries}回', '${s.hits}/${s.tries}'), style: secondary),
          ],
        );
    String metrics(DevSuggestion s) => repairText(
        '出る${devRateText(s.rate)}・成功${devRateText(s.successRate)}・1個あたり 釘${devNailsText(s.nailsPerItem)} 資材${devResourcesText(s.resourcesPerItem)}',
        '${devRateText(s.rate)}, success ${devRateText(s.successRate)}, per item: nails ${devNailsText(s.nailsPerItem)}, resources ${devResourcesText(s.resourcesPerItem)}');
    Widget empty() => CupertinoListTile(title: Text(repairText('データがありません', 'No data')));

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        middle: Text(questEquipmentName(itemId)),
      ),
      child: SafeArea(
        bottom: false,
        child: CupertinoScrollbar(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: CupertinoSlidingSegmentedControl<DevSort>(
                  groupValue: _sort,
                  onValueChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                  children: {
                    DevSort.rate: Text(repairText('確率の高い順', 'Best rate')),
                    DevSort.nails: Text(repairText('釘の少ない順', 'Fewest nails')),
                    DevSort.resources: Text(repairText('資材の少ない順', 'Fewest resources')),
                  },
                ),
              ),
              if (secretaryId != null)
                QuestDetailSection(
                  title: repairText('今の秘書艦なら: ${questShipName(secretaryId)} (${devSecretaryGroupName(secretaryGroup)})',
                      'With your secretary: ${questShipName(secretaryId)}'),
                  footer: repairText('第1艦隊の旗艦で開発したときの記録', 'Records with your fleet 1 flagship as secretary'),
                  children: [
                    if (mine.isEmpty)
                      CupertinoListTile(
                          title: Text(repairText('この秘書艦で出た記録がありません', 'No records with this secretary'))),
                    for (final s in mine)
                      CupertinoListTile(
                        title: recipeTitle(s.recipe),
                        subtitle: Text(metrics(s), maxLines: 2),
                        additionalInfo: value(s),
                      ),
                  ],
                ),
              QuestDetailSection(
                title: repairText('おすすめ (秘書艦の艦種別)', 'Best recipes by secretary type'),
                footer: repairText('試行100回以上。艦種と国籍で分けています。釘は開発に成功したときだけ減る (ペンギンでは減らない) として計算',
                    '100+ tries. Grouped by ship type and nationality. Nails are used only on success'),
                children: [
                  if (byGroup.isEmpty) empty(),
                  for (final s in byGroup)
                    CupertinoListTile(
                      title: recipeTitle(s.recipe),
                      subtitle: Text(
                        '${repairText('秘書艦', 'Secretary')}: ${devSecretaryGroupName(s.group)}'
                        '${s.group == secretaryGroup ? repairText(' ← 今の秘書艦', ' (current)') : ''}\n'
                        '${metrics(s)}\n'
                        '${devOwnedText([for (final o in owned) if (devSecretaryGroup(master, o.shipId) == s.group) o])}',
                        maxLines: 4,
                      ),
                      additionalInfo: value(s),
                    ),
                ],
              ),
              QuestDetailSection(
                title: repairText('艦娘別', 'By ship'),
                footer: repairText('秘書艦1隻ごとの記録 (試行50回以上)。✓ は持っている艦', 'Per secretary ship (50+ tries). ✓ = you have it'),
                children: [
                  if (byShip.isEmpty) empty(),
                  for (final s in byShip)
                    CupertinoListTile(
                      title: recipeTitle(s.recipe),
                      subtitle: Text(
                        '${questShipName(s.group)}${owned.any((o) => o.shipId == s.group) ? ' ✓' : ''}'
                        '${s.group == secretaryId ? repairText(' ← 今の秘書艦', ' (current)') : ''}\n'
                        '${metrics(s)}',
                        maxLines: 3,
                      ),
                      additionalInfo: value(s),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  '${DevStatsLoader.statusText(text: repairText)}\n'
                  '${repairText('poi・KC3改・Kcanotify の利用者が報告した開発結果を集計したものです。確率は報告された結果の割合で、試行回数が少ないとぶれます。並べ替えは試行回数も考えた控えめな見積もりで行っています。', 'Aggregated from development results reported by poi, KC3Kai and Kcanotify users. Rates are observed shares and vary when tries are few. Sorting uses a conservative estimate that accounts for the number of tries.')}',
                  style: secondary,
                ),
              ),
              if (master == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(repairText('ゲームを起動すると艦種別のおすすめが出ます', 'Start the game to see suggestions by ship type'),
                      style: secondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
