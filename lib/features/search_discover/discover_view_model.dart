import 'package:flutter/foundation.dart';

import '../../data/repositories/discover_repository.dart';
import '../../domain/models/discover_mode.dart';
import '../../domain/models/playlist_draft.dart';
import '../../domain/models/result.dart';

/// State of the Discover cards (FR-10): which mode is running and the
/// last error. A successful run returns a [PlaylistDraft] for the preview.
class DiscoverViewModel extends ChangeNotifier {
  DiscoverViewModel({required this._discover});

  final DiscoverRepository _discover;

  /// Modes implemented so far; the other cards show "Coming soon".
  static const readyModes = {
    DiscoverMode.fromArtists,
    DiscoverMode.fromGenres,
  };

  /// The four cards of the 2×2 grid, in order.
  static const cardModes = [
    DiscoverMode.fromArtists,
    DiscoverMode.fromGenres,
    DiscoverMode.youCouldLike,
    DiscoverMode.toTry,
  ];

  static const errorText =
      'Could not get suggestions. Check your connection and try again.';
  static const emptyText = 'No new tracks found. Try another option.';

  DiscoverMode? _running;
  String? _errorMessage;

  /// False without a Last.fm API key.
  bool get isAvailable => _discover.isAvailable;

  /// The mode being loaded, or null.
  DiscoverMode? get running => _running;
  bool get busy => _running != null;

  /// Message of the last failed or empty run.
  String? get errorMessage => _errorMessage;

  bool isReady(DiscoverMode mode) => readyModes.contains(mode);

  /// Whether the card of [mode] can be tapped now.
  bool canRun(DiscoverMode mode) => isAvailable && isReady(mode) && !busy;

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
        draft = value;
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
      _ => Future.value(Result.error(Exception('$mode is not ready'))),
    };
  }
}