/// Like level of a track, from 1 (default) to 5 (FR-3).
///
/// The level is how many times the track appears in one weighted shuffle
/// round. Levels 2–5 count as "liked" (Liked page). Immutable.
class LikeLevel {
  /// Creates a level. Throws a [RangeError] if [value] is not 1–5.
  LikeLevel(int value)
      : this._(RangeError.checkValueInInterval(value, min, max, 'value'));

  const LikeLevel._(this.value);

  static const int min = 1;
  static const int max = 5;

  /// Level of every track that was never rated.
  static const LikeLevel defaultLevel = LikeLevel._(min);

  final int value;

  /// Whether the track shows on the Liked page (level 2–5).
  bool get isLiked => value >= 2;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LikeLevel && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'LikeLevel($value)';
}