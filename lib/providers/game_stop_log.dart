import 'package:conning_tower/main.dart';
import 'package:conning_tower/models/perf_monitor.dart';

/// アプリ全体で使う「ゲーム画面が止まった」記録
final GameStopLog gameStopLog = GameStopLog(
  load: () => localStorage.getString('KC_GAME_STOPS'),
  save: (json) => localStorage.setString('KC_GAME_STOPS', json),
);
