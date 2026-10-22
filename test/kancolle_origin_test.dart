import 'package:conning_tower/utils/kancolle_origin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('game servers are accepted', () {
    expect(isKancolleGameHost('w01y.kancolle-server.com'), isTrue);
    expect(isKancolleGameHost('W20H.KANCOLLE-SERVER.COM'), isTrue);
    expect(isKancolleGameHost('203.104.209.71'), isTrue); // 古いサーバー
    expect(isKancolleGameHost('evil-kancolle-server.com'), isFalse);
    expect(isKancolleGameHost('kancolle-server.com.evil.example'), isFalse);
    expect(isKancolleGameHost('osapi.dmm.com'), isFalse);
    expect(isKancolleGameHost('203.104.209.71.evil.example'), isFalse);
  });

  test('messages must come from the game server that answered', () {
    bool trusted(String? origin, String url) => isTrustedKancolleMessage(sourceOrigin: origin, responseUrl: url);

    // 本物: ゲームの画面 (サーバー) が同じサーバーの kcsapi を呼んだ
    expect(trusted('https://w01y.kancolle-server.com', 'https://w01y.kancolle-server.com/kcsapi/api_port/port'), isTrue);
    expect(trusted('http://203.104.209.71', 'http://203.104.209.71/kcsapi/api_port/port'), isTrue);

    // 別のページ・広告から、偽の URL を名乗って送ってきたもの
    expect(trusted('https://evil.example', 'https://w01y.kancolle-server.com/kcsapi/api_port/port'), isFalse);
    expect(trusted('https://evil.example', 'https://evil.example/kcsapi/api_port/port'), isFalse);
    expect(trusted('https://ads.dmm.com', 'https://w01y.kancolle-server.com/kcsapi/api_port/port'), isFalse);
    // ゲームサーバーからでも、別のサーバーの URL や kcsapi 以外は受け取らない
    expect(trusted('https://w01y.kancolle-server.com', 'https://w02k.kancolle-server.com/kcsapi/api_port/port'), isFalse);
    expect(trusted('https://w01y.kancolle-server.com', 'https://w01y.kancolle-server.com/kcs2/index.php'), isFalse);
    // 送り元が分からないもの
    expect(trusted(null, 'https://w01y.kancolle-server.com/kcsapi/api_port/port'), isFalse);
    expect(trusted('', 'https://w01y.kancolle-server.com/kcsapi/api_port/port'), isFalse);
  });
}
