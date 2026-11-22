import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/levels_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/playlist_summary.dart';
import '../../domain/models/result.dart';

/// State of Home: Main and Liked cards, "Your playlists" grid.
///
/// Opening Home also syncs the main playlist if it changed (FR-2.2).
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required this._library,
    required this._levels,
    required this._playlists,
    required this._settings,
  });

  final LibraryRepository _library;
  final LevelsRepository _levels;
  final PlaylistRepository _playlists;
  final SettingsRepository _settings;

  StreamSubscription<int>? _trackCountSub;
  StreamSubscription<int>? _likedCountSub;

  String _mainName = 'Main playlist';
  String? _mainCoverUrl;
  int _trackCount = 0;
  int _likedCount = 0;
  List<PlaylistSummary> _playlistsList = const [];
  bool _syncing = false;
  bool _loadingPlaylists = false;
  String? _syncError;
  String? _playlistsError;

  String get mainName => _mainName;
  String? get mainCoverUrl => _mainCoverUrl;
  int get trackCount => _trackCount;
  int get likedCount => _likedCount;
  List<PlaylistSummary> get playlists => _playlistsList;
  bool get syncing => _syncing;
  bool get loadingPlaylists => _loadingPlaylists;
  String? get syncError => _syncError;
  String? get playlistsError => _playlistsError;

  Future<void> init() async {
    _trackCountSub = _library.watchTrackCount().listen((count) {
      _trackCount = count;
      notifyListeners();
    });
    _likedCountSub = _levels.watchLikedCount().listen((count) {
      _likedCount = count;
      notifyListeners();
    });
    await _loadMainInfo();
    await refresh();
  }

  /// Syncs the main playlist and reloads the grid.
  Future<void> refresh() async {
    await Future.wait([sync(), loadPlaylists()]);
  }

  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    _syncError = null;
    notifyListeners();

    final result = await _library.syncIfChanged();
    if (result case Error()) {
      _syncError = 'Could not sync with Spotify. Showing saved data.';
    }
    await _loadMainInfo();

    _syncing = false;
    notifyListeners();
  }

  Future<void> loadPlaylists() async {
    if (_loadingPlaylists) return;
    _loadingPlaylists = true;
    _playlistsError = null;
    notifyListeners();

    final result = await _playlists.getHomePlaylists(
      option: await _settings.getHomePlaylistsOption(),
      mainPlaylistId: await _settings.getMainPlaylistId(),
    );
    switch (result) {
      case Ok(:final value):
        _playlistsList = value;
      case Error():
        _playlistsError = 'Could not load your playlists.';
    }

    _loadingPlaylists = false;
    notifyListeners();
  }

  Future<void> _loadMainInfo() async {
    final info = await _library.getMainPlaylistInfo();
    _mainName = info.name ?? _mainName;
    _mainCoverUrl = info.coverUrl;
    notifyListeners();
  }

  @override
  void dispose() {
    _trackCountSub?.cancel();
    _likedCountSub?.cancel();
    super.dispose();
  }
}