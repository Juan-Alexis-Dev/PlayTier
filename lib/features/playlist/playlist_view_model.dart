import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/levels_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/playback_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/engines/filter_engine.dart';
import '../../domain/engines/sort_engine.dart';
import '../../domain/models/filter_criteria.dart';
import '../../domain/models/playback_exception.dart';
import '../../domain/models/result.dart';
import '../../domain/models/sort_option.dart';
import '../../domain/models/track.dart';
import '../filters/filter_view_model.dart';

/// State of the playlist screen. For now: the main playlist only.
///
/// [tracks] is the visible list: the playlist after [criteria] (FR-5.2)
/// and [sort] (FR-5.4). A null [sort] keeps the playlist's own order.
class PlaylistViewModel extends ChangeNotifier {
  PlaylistViewModel({
    required this._library,
    required this._levels,
    required this._playback,
    required this._playlists,
    required this._settings,
  });

  final LibraryRepository _library;
  final LevelsRepository _levels;
  final PlaybackRepository _playback;
  final PlaylistRepository _playlists;
  final SettingsRepository _settings;

  final _subscriptions = <StreamSubscription<Object?>>[];

  List<Track> _allTracks = const [];
  List<Track> _tracks = const [];
  Map<String, String> _artistNames = const {};
  Map<String, List<String>> _genresByArtist = const {};
  Map<String, int> _levelsById = const {};
  FilterCriteria _criteria = FilterCriteria.empty;
  SortOption? _sort;

  String _name = 'Main playlist';
  String? _coverUrl;
  bool _loaded = false;
  bool _syncing = false;
  bool _starting = false;
  String? _errorMessage;

  /// Visible tracks (filtered and sorted).
  List<Track> get tracks => _tracks;

  /// Every track of the playlist, before filters.
  int get totalCount => _allTracks.length;

  FilterCriteria get criteria => _criteria;
  SortOption? get sort => _sort;

  /// True when filters or a custom order change what is shown.
  bool get isCustomized => _criteria.isNotEmpty || _sort != null;

  String get name => _name;
  String? get coverUrl => _coverUrl;

  /// False until the database emitted the first list.
  bool get loaded => _loaded;
  bool get syncing => _syncing;

  /// True while playback is being prepared.
  bool get starting => _starting;
  String? get errorMessage => _errorMessage;

  Duration get totalDuration =>
      _tracks.fold(Duration.zero, (sum, track) => sum + track.duration);

  /// Artist names of [track], joined with commas.
  String artistsOf(Track track) => track.artistIds
      .map((id) => _artistNames[id])
      .whereType<String>()
      .join(', ');

  /// Listens to the database and checks Spotify for changes.
  Future<void> init() async {
    _subscriptions.addAll([
      _library.watchTracks().listen((tracks) {
        _allTracks = tracks;
        _loaded = true;
        _refresh();
      }),
      _library.watchArtistNames().listen((names) {
        _artistNames = names;
        _refresh();
      }),
      _library.watchArtistGenres().listen((genres) {
        _genresByArtist = genres;
        _refresh();
      }),
      _levels.watchLevels().listen((levels) {
        _levelsById = levels;
        _refresh();
      }),
    ]);
    await _loadInfo();
    await sync();
  }

  /// A view model for the filter sheet, starting from the current filters.
  FilterViewModel createFilterViewModel() => FilterViewModel(
        tracks: _allTracks,
        genresByArtist: _genresByArtist,
        artistNames: _artistNames,
        levels: _levelsById,
        initial: _criteria,
      );

  void setFilters(FilterCriteria criteria) {
    _criteria = criteria;
    _refresh();
  }

  void clearFilters() => setFilters(FilterCriteria.empty);

  /// Null goes back to the playlist's own order.
  void setSort(SortOption? sort) {
    _sort = sort;
    _refresh();
  }

  /// Syncs only if the playlist changed in Spotify; the database streams
  /// then update the list.
  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _library.syncIfChanged();
    if (result case Error()) {
      _errorMessage = 'Could not sync with Spotify. Showing saved data.';
    }
    await _loadInfo();

    _syncing = false;
    notifyListeners();
  }

  /// Plays what is shown, in order, from [startIndex].
  ///
  /// Without filters or custom order it plays the main playlist itself;
  /// otherwise the visible list is written to the playback playlist and
  /// played from there (temporary, FR-5.5).
  Future<void> play({int startIndex = 0}) async {
    if (_starting || _tracks.isEmpty) return;
    _starting = true;
    _errorMessage = null;
    notifyListeners();

    final contextUri = await _contextToPlay();
    if (contextUri != null) {
      final result =
          await _playback.playList(contextUri, startIndex: startIndex);
      if (result case Error(:final error)) {
        _errorMessage = _playbackMessage(error);
      }
    }

    _starting = false;
    notifyListeners();
  }

  /// Context URI to play, or null (with [_errorMessage] set) on failure.
  Future<String?> _contextToPlay() async {
    if (!isCustomized) {
      final id = await _settings.getMainPlaylistId();
      return id == null ? null : 'spotify:playlist:$id';
    }
    final result = await _playlists
        .writePlaybackPlaylist([for (final t in _tracks) t.uri]);
    switch (result) {
      case Ok(:final value):
        return value;
      case Error():
        _errorMessage = 'Could not prepare the list in Spotify.';
        return null;
    }
  }

  void _refresh() {
    final filtered = FilterEngine.apply(
      _allTracks,
      _criteria,
      genresByArtist: _genresByArtist,
      levels: _levelsById,
    );
    final sort = _sort;
    _tracks = sort == null
        ? filtered
        : SortEngine.sort(
            filtered,
            sort,
            artistNames: _artistNames,
            levels: _levelsById,
          );
    notifyListeners();
  }

  String _playbackMessage(Exception error) {
    if (error is! PlaybackException) return 'Could not start playback.';
    return switch (error.kind) {
      PlaybackErrorKind.noDevice =>
        'No active Spotify device. Open Spotify and try again.',
      PlaybackErrorKind.spotifyAppUnavailable =>
        'Could not connect to the Spotify app. Open it and try again.',
      PlaybackErrorKind.rejected =>
        'Spotify rejected the request. A Premium account is required.',
    };
  }

  Future<void> _loadInfo() async {
    final info = await _library.getMainPlaylistInfo();
    _name = info.name ?? _name;
    _coverUrl = info.coverUrl;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}