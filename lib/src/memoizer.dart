import 'dart:async';

import 'package:async/async.dart';

/// A memoizer cache used for memoizing functions run by index,
/// backed by an [AsyncMemoizer]
///
/// This allows multiple memoizations to occur for a given funct
class CacheableMap<T> {
  final Duration? _duration;
  final Map<String, AsyncCache<T>> memoizations = {};

  CacheableMap([this._duration]);

  /// Performs `runOnce` on the memoizer for the given computation
  Future<T> fetch(String id, Future<T> Function() computation) {
    if (!memoizations.containsKey(id)) {
      memoizations[id] = _duration == null
          ? AsyncCache<T>.ephemeral()
          : AsyncCache<T>(_duration);
    }

    return memoizations[id]!.fetch(computation);
  }

  void invalidate(String id) {
    return memoizations[id]?.invalidate();
  }
}
