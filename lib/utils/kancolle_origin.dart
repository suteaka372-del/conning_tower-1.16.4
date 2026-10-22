// ゲームの通信データ (kcsapi) をアプリに渡してよい送り元かの判定。
// アプリ内ブラウザで開いた別のページや広告が、偽のデータを送り込めないようにする。
// ゲームサーバー: w01y.kancolle-server.com 〜 w20h.kancolle-server.com
// (ElectronicObserver EN の ServerManager と同じ)。古いサーバーの 203.104.209.x も認める

final RegExp _legacyServer = RegExp(r'^203\.104\.209\.\d{1,3}$');

/// ゲームサーバーのホスト名か
bool isKancolleGameHost(String host) {
  final h = host.toLowerCase();
  return h == 'kancolle-server.com' || h.endsWith('.kancolle-server.com') || _legacyServer.hasMatch(h);
}

/// [sourceOrigin] (メッセージを送ったページの origin) から届いた [responseUrl] のデータを受け取ってよいか。
/// 送り元がゲームサーバーで、データの URL も同じサーバーの kcsapi であること
bool isTrustedKancolleMessage({required String? sourceOrigin, required String responseUrl}) {
  if (sourceOrigin == null || sourceOrigin.isEmpty) return false;
  final origin = Uri.tryParse(sourceOrigin);
  final response = Uri.tryParse(responseUrl);
  if (origin == null || response == null) return false;
  if (!isKancolleGameHost(origin.host)) return false;
  return response.host.toLowerCase() == origin.host.toLowerCase() && response.path.contains('/kcsapi/');
}
