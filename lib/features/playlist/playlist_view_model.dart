import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/levels_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/playback_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/engines/filter_engine.dart';
import '../../domain/engines/playlist_name_generator.dart';
import '../../domain/engines/sort_engine.dart';
import '../../domain/engines/virtual_playlists.dart';
import '../../domain/models/filter_criteria.dart';
import '../../domain/models/like_level.dart';
import '../../domain/models/playlist_draft.dart';
import '../../domain/models/result.dart';
import '../../domain/models/sort_option.dart';
import '../../domain/models/track.dart';
import '../../shared/playback_error_message.dart';
import '../filters/filter_view_model.dart';

/// State of the playlist screen, for the main playlist (cached in the
/// database), the Liked page ([isLiked], main tracks with level 2–5), a
/// genre or artist virtual playlist ([genre], [artistId], FR-6) or a
/// permanent playlist ([playlistId], read from Spotify).
///
/// [tracks] is the visible list: the playlist after [shownLevels] (Liked
/// only, FR-7.2), [criteria] (FR-5.2) and [sort] (FR-5.4). A null [sort]
/// keeps the playlist's own order.
class PlaylistViewModel extends ChangeNotifier {
  PlaylistViewModel({
    required this._library,
    required this._levels,
    required this._playback,
    required this._playlists,
    required this._settings,
    this.playlistId,
    this.isLiked = false,
    this.genre,
    this.artistId,
  }) : assert(
          (playlistId != null ? 1 : 0) +
                  (isLiked ? 1 : 0) +
                  (genre != null ? 1 : 0) +
                  (artistId != null ? 1 : 0) <=
              1,
          'Only one kind of playlist',
        );

  /// Spotify id of a permanent playlist; null for the main playlist and
  /// the virtual playlists.
  final String? playlistId;

  /// The Liked page (FR-7): main tracks with level 2–5, each once.
  final bool isLiked;

  /// Genre virtual playlist (lower-case genre name, FR-6.1).
  final String? genre;

  /// Artist virtual playlist (Spotify artist id, FR-6.2).
  final String? artistId;

  /// Levels the Liked page can show/hide.
  static const likedLevels = {2, 3, 4, 5};

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
  Set<int> _shownLevels = likedLevels;

  late String _name = isLiked
      ? 'Liked'
      : isMain
          ? 'Main playlist'
          : genre != null
              ? VirtualPlaylists.genreName(genre!)
              : 'Playlist';
  String? _coverUrl;
  bool _loaded = false;
  bool _syncing = false;
  bool _starting = false;
  String? _errorMessage;

  /// Visible tracks (filtered and sorted).
  List<Track> get tracks => _tracks;

  /// Every track of the playlist (Liked: every liked track), before
  /// filters.
  int get totalCount => _baseTracks.length;

  FilterCriteria get criteria => _criteria;
  SortOption? get sort => _sort;

  bool get isMain =>
      playlistId == null && !isLiked && genre == null && artistId == null;

  /// Liked, genre and artist playlists exist only in the app (no Spotify
  /// playlist to play, nothing to add music to).
  bool get isVirtual => isLiked || genre != null || artistId != null;

  /// "Add music" is hidden in virtual playlists (FR-9.5).
  bool get canAddMusic => !isVirtual;

  /// Main and virtual playlists come from the database.
  bool get _fromDatabase => playlistId == null;

  /// Liked page: levels currently shown (all of 2–5 by default).
  Set<int> get shownLevels => _shownLevels;

  /// True when filters or a custom order change what is shown.
  bool get isCustomized => _criteria.isNotEmpty || _sort != null;

  /// Artist playlists use the artist's name once it is known.
  String get name =>
      artistId != null ? _artistNames[artistId] ?? 'Artist' : _name;

  String? get coverUrl => _coverUrl;

  /// Genre and artist playlists: up to 4 covers of their tracks for a
  /// mosaic (like their card); empty otherwise.
  List<String> get coverUrls {
    if (genre == null && artistId == null) return const [];
    final urls = <String>[];
    for (final track in _baseTracks) {
      final url = track.coverUrl;
      if (url != null && !urls.contains(url)) urls.add(url);
      if (urls.length == VirtualPlaylists.maxCovers) break;
    }
    return urls;
  }

  /// False until the first list arrived.
  bool get loaded => _loaded;
  bool get syncing => _syncing;

  /// True while playback is being prepared.
  bool get starting => _starting;
  String? get errorMessage => _errorMessage;

  Duration get totalDuration =>
      _tracks.fold(Duration.zero, (sum, track) => sum + track.duration);

  /// Like level of [track]; null when it is not in the main playlist
  /// (every main track has a level row after sync), so it cannot be rated.
  int? levelOf(Track track) => _levelsById[track.id];

  /// Sets the like level of [track] without playing it. The list, Liked
  /// and the shuffle update through the levels stream. Returns an error
  /// message, or null.
  Future<String?> setLevel(Track track, int level) async {
    if (levelOf(track) == null) return null;
    final result = await _levels.setLevel(track.id, LikeLevel(level));
    return switch (result) {
      Ok() => null,
      Error() => 'Could not save the level.',
    };
  }

  /// Artist names of [track], joined with commas.
  String artistsOf(Track track) => track.artistIds
      .map((id) => _artistNames[id])
      .whereType<String>()
      .join(', ');

  /// Main: listens to the database and checks Spotify for changes.
  /// Permanent: reads the playlist from Spotify. Genres and levels always
  /// come from the database.
  Future<void> init() async {
    if (_fromDatabase) {
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
      ]);
    }
    _subscriptions.addAll([
      _library.watchArtistGenres().listen((genres) {
        _genresByArtist = genres;
        _refresh();
      }),
      _levels.watchLevels().listen((levels) {
        _levelsById = levels;
        _refresh();
      }),
    ]);
    if (isMain) await _loadInfo();
    await sync();
  }

  /// A view model for the filter sheet, starting from the current filters.
  FilterViewModel createFilterViewModel() => FilterViewModel(
        tracks: _baseTracks,
        genresByArtist: _genresByArtist,
        artistNames: _artistNames,
        levels: _levelsById,
        initial: _criteria,
      );

  /// The visible list as a draft for the preview screen, named after the
  /// active filters (FR-8.1).
  PlaylistDraft createDraft() {
    final name = PlaylistNameGenerator.generate(
      _criteria,
      artistNames: _artistNames,
      albumNames: {for (final t in _allTracks) t.albumId: t.albumName},
    );
    final fallback = isVirtual && name == PlaylistNameGenerator.fallback;
    return PlaylistDraft(name: fallback ? this.name : name, tracks: _tracks);
  }

  void setFilters(FilterCriteria criteria) {
    _criteria = criteria;
    _refresh();
  }

  void clearFilters() => setFilters(FilterCriteria.empty);

  /// Liked page: shows or hides the tracks of [level] (2–5). Only changes
  /// what is shown (FR-7.2).
  void toggleLevel(int level) {
    if (!likedLevels.contains(level)) return;
    final levels = {..._shownLevels};
    if (!levels.remove(level)) levels.add(level);
    _shownLevels = levels;
    _refresh();
  }

  /// Null goes back to the playlist's own order.
  void setSort(SortOption? sort) {
    _sort = sort;
    _refresh();
  }

  /// Main: syncs only if the playlist changed in Spotify; the database
  /// streams then update the list. Permanent: reads it again.
  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    _errorMessage = null;
    notifyListeners();

    if (_fromDatabase) {
      final result = await _library.syncIfChanged();
      if (result case Error()) {
        _errorMessage = 'Could not sync with Spotify. Showing saved data.';
      }
      if (isMain) await _loadInfo();
    } else {
      await _loadPermanent(playlistId!);
    }

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
      final result = await _playback.playList(
        contextUri,
        startIndex: startIndex,
        name: name,
      );
      if (result case Error(:final error)) {
        _errorMessage = playbackErrorMessage(error);
      }
    }

    _starting = false;
    notifyListeners();
  }

  /// Weighted shuffle of what is shown (FR-4.1): every visible track
  /// plays as many times as its like level. The sort order does not matter.
  Future<void> shuffle() async {
    if (_starting || _tracks.isEmpty) return;
    _starting = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _playback.playShuffled(_tracks, name: name);
    if (result case Error(:final error)) {
      _errorMessage = playbackErrorMessage(error);
    }

    _starting = false;
    notifyListeners();
  }

  /// Context URI to play, or null (with [_errorMessage] set) on failure.
  /// Virtual playlists have no Spotify playlist, so they always write the
  /// list.
  Future<String?> _contextToPlay() async {
    if (!isCustomized && !isVirtual) {
      final id = playlistId ?? await _settings.getMainPlaylistId();
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

  /// The playlist before any filter. Liked: main tracks with level 2–5.
  /// Genre: main tracks with an artist of that genre. Artist: main tracks
  /// of that artist, featured included.
  List<Track> get _baseTracks {
    final genre = this.genre;
    final artistId = this.artistId;
    if (isLiked) {
      return [
        for (final t in _allTracks)
          if ((_levelsById[t.id] ?? 1) >= 2) t,
      ];
    }
    if (genre != null) {
      return [
        for (final t in _allTracks)
          if (t.artistIds.any(
            (id) => _genresByArtist[id]?.contains(genre) ?? false,
          ))
            t,
      ];
    }
    if (artistId != null) {
      return [
        for (final t in _allTracks)
          if (t.artistIds.contains(artistId)) t,
      ];
    }
    return _allTracks;
  }

  void _refresh() {
    final base = isLiked
        ? [
            for (final t in _baseTracks)
              if (_shownLevels.contains(_levelsById[t.id])) t,
          ]
        : _baseTracks;
    final filtered = FilterEngine.apply(
      base,
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

  Future<void> _loadPermanent(String id) async {
    final result = await _playlists.getPlaylistContent(id);
    switch (result) {
      case Ok(:final value):
        _name = value.name;
        _coverUrl = value.coverUrl;
        _artistNames = value.artistNames;
        _allTracks = value.tracks;
        _refresh();
      case Error():
        _errorMessage = 'Could not load this playlist from Spotify.';
    }
    _loaded = true;
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