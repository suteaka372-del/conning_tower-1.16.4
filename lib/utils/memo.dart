/// 入力が前回と同じ (==) なら前回の結果を返す。リストや Map は中身でなく同じものかで比べる
class Memo<R> {
  List<Object?>? _inputs;
  R? _value;

  R of(List<Object?> inputs, R Function() compute) {
    final last = _inputs;
    if (last != null && last.length == inputs.length) {
      var same = true;
      for (var i = 0; i < inputs.length && same; i++) {
        same = last[i] == inputs[i];
      }
      if (same) return _value as R;
    }
    final value = compute();
    _inputs = List.of(inputs);
    _value = value;
    return value;
  }

  void clear() {
    _inputs = null;
    _value = null;
  }
}

/// 文字列のキーで結果を覚えておく。[capacity] を超えたら長く使っていないものから捨てる
class MemoCache<V> {
  MemoCache([this.capacity = 256]);

  final int capacity;
  final _map = <String, V>{};

  int get length => _map.length;

  V get(String key, V Function() compute) {
    if (_map.containsKey(key)) {
      final hit = _map.remove(key) as V;
      _map[key] = hit;
      return hit;
    }
    final value = compute();
    _map[key] = value;
    if (_map.length > capacity) _map.remove(_map.keys.first);
    return value;
  }

  void clear() => _map.clear();
}
