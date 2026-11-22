/// Field used to sort a list of tracks (FR-5.4).
enum SortField {
  dateAdded,
  title,
  artist,
  album,
  duration,
  likeLevel,
}

/// Sort direction.
enum SortDirection {
  ascending,
  descending,
}

/// How a list of tracks is sorted: a [SortField] plus a [SortDirection].
///
/// Immutable. The logic itself lives in `SortEngine`.
class SortOption {
  const SortOption(this.field, this.direction);

  /// Default order: newest added first, like Spotify.
  static const SortOption defaultOption =
      SortOption(SortField.dateAdded, SortDirection.descending);

  final SortField field;
  final SortDirection direction;

  bool get isAscending => direction == SortDirection.ascending;

  /// Same field, opposite direction (for the "tap again to reverse" menu).
  SortOption get reversed => SortOption(
        field,
        isAscending ? SortDirection.descending : SortDirection.ascending,
      );

  SortOption copyWith({SortField? field, SortDirection? direction}) {
    return SortOption(field ?? this.field, direction ?? this.direction);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SortOption &&
          other.field == field &&
          other.direction == direction;

  @override
  int get hashCode => Object.hash(field, direction);

  @override
  String toString() => 'SortOption(${field.name}, ${direction.name})';
}