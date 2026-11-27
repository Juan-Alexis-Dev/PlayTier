import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/engines/virtual_playlists.dart';

/// One card of the Browse grid (a genre or an artist virtual playlist).
typedef BrowseItem = VirtualPlaylist;

/// State of the shared Browse screen (Genres and Artists tabs).
///
/// Shows the items of [_source] in the order they come (by track count),
/// filtered by the search query. The source is a stream, so the grid
/// updates after every sync or genre enrichment.
class BrowseViewModel extends ChangeNotifier {
  BrowseViewModel(this._source);

  final Stream<List<BrowseItem>> _source;
  StreamSubscription<List<BrowseItem>>? _sub;

  List<BrowseItem> _all = const [];
  List<BrowseItem> _items = const [];
  String _query = '';
  bool _loading = true;
  String? _errorMessage;

  /// Items matching [query], in source order.
  List<BrowseItem> get items => _items;

  /// Every item, ignoring the query.
  int get totalCount => _all.length;

  String get query => _query;
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  void init() {
    _sub = _source.listen(
      (items) {
        _all = items;
        _loading = false;
        _errorMessage = null;
        _applyQuery();
      },
      onError: (Object error) {
        debugPrint('Browse source failed: $error');
        _loading = false;
        _errorMessage = 'Could not load this page.';
        notifyListeners();
      },
    );
  }

  /// Filters by name, ignoring case and accents ("espanol" finds "español").
  void setQuery(String query) {
    if (query == _query) return;
    _query = query;
    _applyQuery();
  }

  void _applyQuery() {
    final needle = _fold(_query.trim());
    _items = needle.isEmpty
        ? _all
        : [
            for (final item in _all)
              if (_fold(item.name).contains(needle)) item,
          ];
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y',
};

/// Lower-case without accents, for search.
String _fold(String text) {
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}