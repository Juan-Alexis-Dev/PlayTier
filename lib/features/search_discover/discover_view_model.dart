import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/discover_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../domain/engines/playlist_name_generator.dart';
import '../../domain/engines/virtual_playlists.dart';
import '../../domain/models/discover_mode.dart';
import '../../domain/models/discover_parameter.dart';
import '../../domain/models/filter_criteria.dart';
import '../../domain/models/playlist_draft.dart';
import '../../domain/models/result.dart';

/// State of Discover (FR-10): which mode is running, the last error and
/// the own-parameter chips (FR-10.5). A successful run returns a
/// [PlaylistDraft] for the preview.
///
/// Call [init] once to load the artists and genres used as suggestions.
class DiscoverViewModel extends ChangeNotifier {
  DiscoverViewModel({required this._discover, required this._library});

  final DiscoverRepository _discover;
  final LibraryRepository _library;

  /// Modes implemented so far; cards of other modes show "Coming soon".
  static const readyModes = {
    DiscoverMode.fromArtists,
    DiscoverMode.fromGenres,
    DiscoverMode.youCouldLike,
    DiscoverMode.toTry,
    DiscoverMode.custom,
  };

  /// The four cards of the 2×2 grid, in order. [DiscoverMode.custom] has
  /// its own input above the cards.
  static const cardModes = [
    DiscoverMode.fromArtists,
    DiscoverMode.fromGenres,
    DiscoverMode.youCouldLike,
    DiscoverMode.toTry,
  ];

  /// Most chips at once (each one means several Last.fm calls).
  static const maxParameters = 5;

  /// Most suggestions shown under the input.
  static const maxSuggestions = 8;

  static const errorText =
      'Could not get suggestions. Check your connection and try again.';
  static const emptyText = 'No new tracks found. Try another option.';

  DiscoverMode? _running;
  String? _errorMessage;

  StreamSubscription<List<VirtualPlaylist>>? _artistsSub;
  StreamSubscription<List<VirtualPlaylist>>? _genresSub;
  List<DiscoverParameter> _artistOptions = const [];
  List<DiscoverParameter> _genreOptions = const [];
  final List<DiscoverParameter> _selected = [];

  /// False without a Last.fm API key.
  bool get isAvailable => _discover.isAvailable;

  /// The mode being loaded, or null.
  DiscoverMode? get running => _running;
  bool get busy => _running != null;

  /// Message of the last failed or empty run.
  String? get errorMessage => _errorMessage;

  /// Chosen own parameters, in the order they were added.
  List<DiscoverParameter> get selected => List.unmodifiable(_selected);

  bool get canAddParameter => _selected.length < maxParameters;

  bool isReady(DiscoverMode mode) => readyModes.contains(mode);

  /// Whether [mode] can run now (own parameters needs at least one chip).
  bool canRun(DiscoverMode mode) =>
      isAvailable &&
      isReady(mode) &&
      !busy &&
      (mode != DiscoverMode.custom || _selected.isNotEmpty);

  /// Listens to the library's artists and genres (most tracks first).
  void init() {
    _artistsSub = _library.watchArtistPlaylists().listen((artists) {
      _artistOptions = [
        for (final a in artists)
          DiscoverParameter.artist(id: a.id, label: a.name),
      ];
    });
    _genresSub = _library.watchGenrePlaylists().listen((genres) {
      _genreOptions = [
        for (final g in genres) DiscoverParameter.genre(g.id),
      ];
    });
  }

  /// Artists and genres whose name contains [query] (case-insensitive),
  /// not chosen yet. Names that start with it come first; then the order
  /// is artists, then genres, each by number of tracks.
  List<DiscoverParameter> suggestions(String query) {
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return const [];

    final starts = <DiscoverParameter>[];
    final contains = <DiscoverParameter>[];
    for (final option in [..._artistOptions, ..._genreOptions]) {
      if (_selected.contains(option)) continue;
      final label = option.label.toLowerCase();
      if (label.startsWith(text)) {
        starts.add(option);
      } else if (label.contains(text)) {
        contains.add(option);
      }
    }
    return [...starts, ...contains].take(maxSuggestions).toList();
  }

  void addParameter(DiscoverParameter parameter) {
    if (!canAddParameter || _selected.contains(parameter)) return;
    _selected.add(parameter);
    notifyListeners();
  }

  void removeParameter(DiscoverParameter parameter) {
    if (_selected.remove(parameter)) notifyListeners();
  }

  /// Provisional name from the chips, e.g. `Rock · Muse + Radiohead`.
  String get ownParametersName {
    final artists = [for (final p in _selected) if (p.isArtist) p];
    return PlaylistNameGenerator.generate(
      FilterCriteria(
        genres: {for (final p in _selected) if (!p.isArtist) p.id},
        artistIds: {for (final p in artists) p.id},
      ),
      artistNames: {for (final p in artists) p.id: p.label},
    );
  }

  /// Runs [mode]. Returns the draft to preview, or null when it failed,
  /// found nothing (see [errorMessage]) or cannot run now.
  Future<PlaylistDraft?> run(DiscoverMode mode) async {
    if (!canRun(mode)) return null;
    _running = mode;
    _errorMessage = null;
    notifyListeners();

    final result = await _load(mode);
    PlaylistDraft? draft;
    switch (result) {
      case Ok(:final value) when value.tracks.isNotEmpty:
        draft = mode == DiscoverMode.custom
            ? value.copyWith(name: ownParametersName)
            : value;
      case Ok():
        _errorMessage = emptyText;
      case Error(:final error):
        debugPrint('Discover $mode failed: $error');
        _errorMessage = errorText;
    }

    _running = null;
    notifyListeners();
    return draft;
  }

  Future<Result<PlaylistDraft>> _load(DiscoverMode mode) {
    return switch (mode) {
      DiscoverMode.fromArtists => _discover.newFromYourArtists(),
      DiscoverMode.fromGenres => _discover.newFromYourGenres(),
      DiscoverMode.youCouldLike => _discover.musicYouCouldLike(),
      DiscoverMode.toTry => _discover.musicToTry(),
      DiscoverMode.custom => _discover.fromOwnParameters(
          artists: [for (final p in _selected) if (p.isArtist) p.label],
          genres: [for (final p in _selected) if (!p.isArtist) p.id],
        ),
    };
  }

  @override
  void dispose() {
    _artistsSub?.cancel();
    _genresSub?.cancel();
    super.dispose();
  }
}