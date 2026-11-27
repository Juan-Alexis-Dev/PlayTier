import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/library_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/search_repository.dart';
import '../../domain/models/result.dart';
import '../../domain/models/search_result.dart';

/// State of the Spotify search (FR-9).
///
/// Typing searches after a short pause ([debounce]); submitting searches
/// at once.
///
/// Two modes:
/// - Search & Discover tab: "Add" puts a track in the main playlist
///   (FR-9.3).
/// - "Add music" of a permanent playlist ([targetPlaylistId]): "Add" puts
///   the track in that playlist **and** in the main playlist if missing
///   (FR-9.4).
class SearchViewModel extends ChangeNotifier {
  SearchViewModel({
    required this._search,
    required this._library,
    PlaylistRepository? playlists,
    this.targetPlaylistId,
    this.targetName,
    Set<String> targetTrackIds = const {},
    this.debounce = const Duration(milliseconds: 400),
  })  : assert(
          targetPlaylistId == null || playlists != null,
          'A target playlist needs the PlaylistRepository',
        ),
        _playlists = playlists,
        _inTarget = {...targetTrackIds};

  final SearchRepository _search;
  final LibraryRepository _library;
  final PlaylistRepository? _playlists;

  /// Spotify id of the playlist "Add music" adds to; null adds only to
  /// the main playlist.
  final String? targetPlaylistId;

  /// Name of the playlist being filled (shown in the hint and messages).
  final String? targetName;

  /// Pause after the last key before searching.
  final Duration debounce;

  /// Track ids already in the target playlist (plus the ones added here).
  final Set<String> _inTarget;

  Timer? _timer;

  /// Increases with every new search, so late answers of an older
  /// search are ignored.
  int _request = 0;
  bool _disposed = false;

  String _query = '';
  List<SearchResult> _results = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _searched = false;
  int _addedCount = 0;
  String? _errorMessage;
  final Set<String> _adding = {};

  String get query => _query;
  List<SearchResult> get results => _results;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;

  /// Whether the last page was full, so "Load more" may bring more.
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;

  /// Whether a search has finished for the current query.
  bool get hasSearched => _searched;

  /// Tracks added during this screen's life.
  int get addedCount => _addedCount;

  bool get hasTarget => targetPlaylistId != null;

  /// Whether [trackId] is being added right now.
  bool isAdding(String trackId) => _adding.contains(trackId);

  /// Whether "Add" has nothing left to do for [item]: it is already in
  /// the target playlist, or (without a target) in the main playlist.
  bool isDone(SearchResult item) =>
      hasTarget ? _inTarget.contains(item.track.id) : item.inMain;

  /// Updates the query and searches after [debounce]. A blank query
  /// clears the results.
  void setQuery(String query) {
    if (query == _query) return;
    _query = query;
    _timer?.cancel();
    if (query.trim().isEmpty) {
      _request++;
      _clearResults();
    } else {
      _timer = Timer(debounce, submit);
    }
    notifyListeners();
  }

  /// Searches the current query now (Enter key, retry).
  Future<void> submit() async {
    _timer?.cancel();
    final text = _query.trim();
    if (text.isEmpty) return;

    final request = ++_request;
    _loading = true;
    _loadingMore = false;
    _errorMessage = null;
    notifyListeners();

    final result = await _search.search(text);
    if (_disposed || request != _request) return;

    _loading = false;
    _searched = true;
    switch (result) {
      case Ok(:final value):
        _results = value;
        _hasMore = value.length == SearchRepository.pageSize;
      case Error(:final error):
        debugPrint('Search failed: $error');
        _results = const [];
        _hasMore = false;
        _errorMessage = 'Search failed. Check your connection and try again.';
    }
    notifyListeners();
  }

  /// Appends the next page of results.
  Future<void> loadMore() async {
    if (!_hasMore || _loading || _loadingMore) return;

    final request = _request;
    _loadingMore = true;
    notifyListeners();

    final result =
        await _search.search(_query.trim(), offset: _results.length);
    if (_disposed || request != _request) return;

    _loadingMore = false;
    switch (result) {
      case Ok(:final value):
        final known = {for (final r in _results) r.track.id};
        _results = [
          ..._results,
          for (final r in value)
            if (!known.contains(r.track.id)) r,
        ];
        _hasMore = value.length == SearchRepository.pageSize;
      case Error(:final error):
        // Keeps "Load more" so the user can retry.
        debugPrint('Search (more) failed: $error');
    }
    notifyListeners();
  }

  /// Adds [item]: to the target playlist first (if any), then to the main
  /// playlist if missing. Returns an error message, or null on success.
  Future<String?> add(SearchResult item) async {
    final id = item.track.id;
    if (isDone(item) || _adding.contains(id)) return null;

    _adding.add(id);
    notifyListeners();
    final message = await _add(item);
    if (_disposed) return message;

    _adding.remove(id);
    notifyListeners();
    return message;
  }

  Future<String?> _add(SearchResult item) async {
    final id = item.track.id;
    final uri = item.track.uri;

    final target = targetPlaylistId;
    if (target != null) {
      final result = await _playlists!.addTracks(target, [uri]);
      if (result case Error(:final error)) {
        debugPrint('Add to playlist failed: $error');
        return 'Could not add the track to this playlist. Try again.';
      }
      _inTarget.add(id);
      _addedCount++;
      if (item.inMain) return null;
    }

    final result = await _library.addToMain(uri);
    if (result case Error(:final error)) {
      debugPrint('Add to main failed: $error');
      return target != null
          ? 'Added to this playlist, but not to the main playlist.'
          : 'Could not add the track. Try again.';
    }
    if (target == null) _addedCount++;
    _results = [
      for (final r in _results) r.track.id == id ? r.copyWith(inMain: true) : r,
    ];
    return null;
  }

  void _clearResults() {
    _results = const [];
    _loading = false;
    _loadingMore = false;
    _hasMore = false;
    _searched = false;
    _errorMessage = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}