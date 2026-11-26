import 'dart:math';

import '../models/like_level.dart';
import '../models/track.dart';

/// Builds one weighted shuffle round (FR-4). Pure Dart, no I/O.
///
/// Rules:
/// - Each track appears as many times as its like level (FR-4.2).
///   Tracks missing from `levels` are level 1; values are clamped to 1–5.
/// - Copies of the same track always have at least one other track between
///   them, and are spread as evenly as possible over the round (FR-4.3).
/// - If that is impossible (e.g. a very short list), the extra copies of
///   the track with the most copies are dropped until it fits (FR-4.4).
/// - Duplicate tracks in the input (same id) are used once.
/// - Pass a seeded [Random] for repeatable results in tests.
abstract final class WeightedShuffle {
  static List<Track> generate(
    List<Track> tracks, {
    Map<String, int> levels = const {},
    Random? random,
  }) {
    final rng = random ?? Random();
    final unique = {for (final t in tracks) t.id: t}.values.toList();
    if (unique.isEmpty) return const [];

    final copies = [
      for (final t in unique)
        (levels[t.id] ?? LikeLevel.min).clamp(LikeLevel.min, LikeLevel.max),
    ];
    _dropImpossibleCopies(copies);

    final total = copies.fold(0, (sum, c) => sum + c);
    final slots = [
      for (var i = 0; i < unique.length; i++)
        _Slot(unique[i], copies[i], total, rng),
    ];

    final round = <Track>[];
    _Slot? last;
    var remaining = total;
    while (remaining > 0) {
      final next = _pickNext(slots, last, remaining);
      round.add(next.track);
      next.left--;
      remaining--;
      last = next;
    }
    return round;
  }

  /// Copies can be separated only if the largest count is at most the sum
  /// of all others plus one. At most one track can break that rule.
  static void _dropImpossibleCopies(List<int> copies) {
    var total = copies.fold(0, (sum, c) => sum + c);
    var maxIndex = 0;
    for (var i = 1; i < copies.length; i++) {
      if (copies[i] > copies[maxIndex]) maxIndex = i;
    }
    while (copies[maxIndex] > total - copies[maxIndex] + 1) {
      copies[maxIndex]--;
      total--;
    }
  }

  /// Picks the next track, never the same as [last].
  ///
  /// A track whose remaining copies only just fit (one other track between
  /// each) must go now, or the round could not be finished. Otherwise the
  /// track whose next copy is most overdue wins, which spreads copies out.
  static _Slot _pickNext(List<_Slot> slots, _Slot? last, int remaining) {
    _Slot? best;
    for (final slot in slots) {
      if (slot.left == 0 || identical(slot, last)) continue;
      if (slot.left == remaining - slot.left + 1) return slot;
      if (best == null || slot.isBefore(best)) best = slot;
    }
    return best!;
  }
}

/// Mutable bookkeeping for one track while a round is being built.
class _Slot {
  _Slot(this.track, this.copies, int total, Random rng)
      : left = copies,
        _gap = total / copies,
        _offset = rng.nextDouble(),
        _tieBreak = rng.nextDouble();

  final Track track;
  final int copies;
  int left;

  /// Ideal distance between copies: the round length divided by copies.
  final double _gap;

  /// Random start inside the first gap, so every round is different.
  final double _offset;
  final double _tieBreak;

  /// Ideal position of the next copy in the round.
  double get _due => (copies - left + _offset) * _gap;

  bool isBefore(_Slot other) {
    if (_due != other._due) return _due < other._due;
    return _tieBreak < other._tieBreak;
  }
}