import 'package:conning_tower/models/feature/kancolle/data.dart';
import 'package:conning_tower/providers/kancolle_data_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 横並びモードのダッシュボードで今表示しているタブ (null なら分からないので、すべて表示中として扱う)
final visibleDashboardTabProvider = StateProvider<int?>((ref) => null);

/// ダッシュボードのタブの中身を囲み、何番目のタブかを伝える
class DashboardTabScope extends InheritedWidget {
  const DashboardTabScope({super.key, required this.index, required super.child});

  final int index;

  static int? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<DashboardTabScope>()?.index;

  @override
  bool updateShouldNotify(DashboardTabScope oldWidget) => index != oldWidget.index;
}

/// タブごとのゲームのデータ。タブが隠れている間は更新を止め、表示されたら最新にする
/// (一度開いたタブは裏でも残るので、ゲームのデータが届くたびに全部のタブを作り直さないように)
final dashboardTabDataProvider =
    NotifierProvider.autoDispose.family<DashboardTabData, KancolleData, int>(DashboardTabData.new);

class DashboardTabData extends AutoDisposeFamilyNotifier<KancolleData, int> {
  bool _visible(int? shown) => shown == null || shown == arg;

  @override
  KancolleData build(int arg) {
    ref.listen(kancolleDataProvider, (_, next) {
      if (_visible(ref.read(visibleDashboardTabProvider))) state = next;
    });
    ref.listen(visibleDashboardTabProvider, (_, shown) {
      if (_visible(shown)) state = ref.read(kancolleDataProvider);
    });
    return ref.read(kancolleDataProvider);
  }
}

/// ゲームのデータを読んで、変わったら作り直す。ダッシュボードのタブの中なら、そのタブを表示している間だけ
KancolleData watchKancolleData(WidgetRef ref, BuildContext context) {
  final tab = DashboardTabScope.maybeOf(context);
  return tab == null ? ref.watch(kancolleDataProvider) : ref.watch(dashboardTabDataProvider(tab));
}
