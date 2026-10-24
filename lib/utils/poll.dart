/// [check] が true を返すまで [interval] ごとに最大 [attempts] 回確かめる。見つかったら true。
/// [cancelled] が true を返したら途中でやめる (別のページを読み込み始めたときなど)
Future<bool> pollUntil(
  Future<bool> Function() check, {
  Duration interval = const Duration(milliseconds: 500),
  int attempts = 30,
  bool Function()? cancelled,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (cancelled?.call() ?? false) return false;
    try {
      if (await check()) return true;
    } catch (_) {
      // ページの切り替え中などで確かめられなかったときは、次の回にもう一度
    }
    if (i < attempts - 1) await Future.delayed(interval);
  }
  return false;
}
