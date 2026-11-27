import 'track.dart';

/// One track found by the Spotify search (FR-12).
///
/// Immutable. Carries the artist names because the track may not be in
/// the local database yet.
class SearchResult {
  const SearchResult({
    required this.track,
    required this.artistNames,
    required this.inMain,
  });

  final Track track;

  /// Artist names, in the same order as [Track.artistIds].
  final List<String> artistNames;

  /// Whether the track is already in the main playlist.
  final bool inMain;

  SearchResult copyWith({
    Track? track,
    List<String>? artistNames,
    bool? inMain,
  }) {
    return SearchResult(
      track: track ?? this.track,
      artistNames: artistNames ?? this.artistNames,
      inMain: inMain ?? this.inMain,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult &&
          other.track == track &&
          _listEquals(other.artistNames, artistNames) &&
          other.inMain == inMain;

  @override
  int get hashCode => Object.hash(track, Object.hashAll(artistNames), inMain);

  @override
  String toString() => 'SearchResult(${track.id}, inMain: $inMain)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}