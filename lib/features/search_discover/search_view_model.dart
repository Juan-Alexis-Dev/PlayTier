import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/library_repository.dart';
import '../../data/repositories/search_repository.dart';
import '../../domain/models/result.dart';
import '../../domain/models/search_result.dart';

/// State of the Spotify search in the Search & Discover tab (FR-9).
///
/// Typing searches after a short pause ([debounce]); submitting searches
/// at once. "Add" puts a track at the end of the main playlist (FR-9.3).
class SearchViewModel extends ChangeNotifier {
  SearchViewModel({
    required this._search,
    required this._library,
    this.debounce = const Duration(milliseconds: 400),
  });

  final SearchRepository _search;
  final LibraryRepository _library;

  /// Pause after the last key before searching.
  final Duration debounce;

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

  /// Whether [trackId] is being added right now.
  bool isAdding(String trackId) => _adding.contains(trackId);

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

  /// Adds [item] to the main playlist. Returns false if it failed.
  Future<bool> add(SearchResult item) async {
    final id = item.track.id;
    if (item.inMain || _adding.contains(id)) return true;

    _adding.add(id);
    notifyListeners();

    final result = await _library.addToMain(item.track.uri);
    if (_disposed) return result is Ok;

    _adding.remove(id);
    final ok = result is Ok;
    if (ok) {
      _results = [
        for (final r in _results)
          r.track.id == id ? r.copyWith(inMain: true) : r,
      ];
    } else {
      debugPrint('Add to main failed: ${(result as Error).error}');
    }
    notifyListeners();
    return ok;
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