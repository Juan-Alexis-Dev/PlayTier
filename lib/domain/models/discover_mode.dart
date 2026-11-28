/// The Discover options of the Search & Discover tab (FR-10).
///
/// Each mode has the title and description shown on its card; the title
/// is also the provisional name of the playlist it creates.
enum DiscoverMode {
  /// FR-10.1
  fromArtists(
    'New music from your artists',
    "Popular tracks of your artists that you don't have yet.",
  ),

  /// FR-10.2
  fromGenres(
    'New music from your genres',
    'Tracks from the genres you listen to the most.',
  ),

  /// FR-10.3
  youCouldLike(
    'Music you could like',
    'Similar artists and tracks, inside your taste.',
  ),

  /// FR-10.4
  toTry(
    'Music to try',
    'Popular music outside your usual genres.',
  ),

  /// FR-10.5: modes 1/2 with artists or genres picked by the user.
  custom(
    'Own parameters',
    'Pick artists or genres to discover from.',
  );

  const DiscoverMode(this.title, this.description);

  final String title;
  final String description;
}