import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/library_repository.dart';
import '../../data/repositories/playback_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../domain/engines/playlist_name_generator.dart';
import '../../domain/models/playlist_draft.dart';
import '../../domain/models/result.dart';
import '../../domain/models/track.dart';
import '../../shared/playback_error_message.dart';

/// What the preview finished with, so the screen can close and report it.
enum PreviewOutcome { played, saved }

/// State of the preview screen (FR-8): name, removable tracks and the two
/// ways to finish, Temporary (plays through the playback playlist) or
/// Permanent (creates a real playlist in Spotify).
class PreviewViewModel extends ChangeNotifier {
  PreviewViewModel({
    required PlaylistDraft draft,
    required this._library,
    required this._playback,
    required this._playlists,
  })  : _name = draft.name,
        _tracks = List.of(draft.tracks);

  final LibraryRepository _library;
  final PlaybackRepository _playback;
  final PlaylistRepository _playlists;

  StreamSubscription<Map<String, String>>? _artistsSub;
  Map<String, String> _artistNames = const {};

  String _name;
  final List<Track> _tracks;
  bool _busy = false;
  String? _errorMessage;
  PreviewOutcome? _outcome;

  String get name => _name;
  List<Track> get tracks => List.unmodifiable(_tracks);
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;

  /// Set once playback started or the playlist was saved.
  PreviewOutcome? get outcome => _outcome;

  PlaylistDraft get draft =>
      PlaylistDraft(name: _name, tracks: List.unmodifiable(_tracks));

  bool get canFinish => !_busy && _tracks.isNotEmpty;

  /// Saving needs a name; the generator's fallback is used if it is blank.
  String get nameToSave =>
      _name.trim().isEmpty ? PlaylistNameGenerator.fallback : _name.trim();

  String artistsOf(Track track) => track.artistIds
      .map((id) => _artistNames[id])
      .whereType<String>()
      .join(', ');

  void init() {
    _artistsSub = _library.watchArtistNames().listen((names) {
      _artistNames = names;
      notifyListeners();
    });
  }

  void rename(String name) {
    _name = name;
    notifyListeners();
  }

  /// Removes the track at [index] and returns it (for "Undo").
  Track removeAt(int index) {
    final track = _tracks.removeAt(index);
    notifyListeners();
    return track;
  }

  /// Puts back a removed track at its old [index].
  void undoRemove(int index, Track track) {
    _tracks.insert(index.clamp(0, _tracks.length), track);
    notifyListeners();
  }

  /// Temporary: writes the list to the playback playlist and plays it.
  Future<void> playTemporary() => _finish(() async {
        final written = await _playlists
            .writePlaybackPlaylist([for (final t in _tracks) t.uri]);
        switch (written) {
          case Error():
            return 'Could not prepare the list in Spotify.';
          case Ok(:final value):
            final played = await _playback.playList(value, name: nameToSave);
            if (played case Error(:final error)) {
              return playbackErrorMessage(error);
            }
            _outcome = PreviewOutcome.played;
            return null;
        }
      });

  /// Permanent: creates a real, private playlist in Spotify.
  Future<void> savePermanent() => _finish(() async {
        final created = await _playlists.createPermanent(
          nameToSave,
          [for (final t in _tracks) t.uri],
        );
        if (created case Error()) {
          return 'Could not create the playlist in Spotify.';
        }
        _outcome = PreviewOutcome.saved;
        return null;
      });

  /// Runs [action], which returns an error message or null on success.
  Future<void> _finish(Future<String?> Function() action) async {
    if (!canFinish) return;
    _busy = true;
    _errorMessage = null;
    notifyListeners();

    _errorMessage = await action();

    _busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _artistsSub?.cancel();
    super.dispose();
  }
}