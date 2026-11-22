import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/library_repository.dart';
import '../../data/repositories/playback_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/playback_exception.dart';
import '../../domain/models/result.dart';
import '../../domain/models/track.dart';

/// State of the playlist screen. For now: the main playlist only.
class PlaylistViewModel extends ChangeNotifier {
  PlaylistViewModel({
    required this._library,
    required this._playback,
    required this._settings,
  });

  final LibraryRepository _library;
  final PlaybackRepository _playback;
  final SettingsRepository _settings;

  StreamSubscription<List<Track>>? _tracksSub;
  StreamSubscription<Map<String, String>>? _artistsSub;

  List<Track> _tracks = const [];
  Map<String, String> _artistNames = const {};
  String _name = 'Main playlist';
  String? _coverUrl;
  bool _loaded = false;
  bool _syncing = false;
  String? _errorMessage;

  List<Track> get tracks => _tracks;
  String get name => _name;
  String? get coverUrl => _coverUrl;

  /// False until the database emitted the first list.
  bool get loaded => _loaded;
  bool get syncing => _syncing;
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
    _tracksSub = _library.watchTracks().listen((tracks) {
      _tracks = tracks;
      _loaded = true;
      notifyListeners();
    });
    _artistsSub = _library.watchArtistNames().listen((names) {
      _artistNames = names;
      notifyListeners();
    });
    await _loadInfo();
    await sync();
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

  /// Plays the main playlist in Spotify, in order, from [startIndex].
  Future<void> play({int startIndex = 0}) async {
    final id = await _settings.getMainPlaylistId();
    if (id == null) return;
    _errorMessage = null;
    notifyListeners();

    final result = await _playback.playList(
      'spotify:playlist:$id',
      startIndex: startIndex,
    );
    if (result case Error(:final error)) {
      _errorMessage = _playbackMessage(error);
      notifyListeners();
    }
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
    _tracksSub?.cancel();
    _artistsSub?.cancel();
    super.dispose();
  }
}