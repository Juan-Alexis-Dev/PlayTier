import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/models/result.dart';
import '../services/local/secure_storage_service.dart';
import '../services/spotify/dto/spotify_tokens.dart';
import '../services/spotify/spotify_auth_exception.dart';
import '../services/spotify/spotify_auth_service.dart';

/// Session state: login, logout and valid access tokens.
///
/// Call [init] once at startup. The router listens to [isLoggedIn].
class AuthRepository {
  AuthRepository({
    required this._authService,
    required this._storage,
  });

  final SpotifyAuthService _authService;
  final SecureStorageService _storage;

  static const _tokensKey = 'spotify_tokens';

  final _isLoggedIn = ValueNotifier<bool>(false);
  SpotifyTokens? _tokens;

  /// Shared future so parallel 401s trigger only one refresh.
  Future<String?>? _refreshing;

  ValueListenable<bool> get isLoggedIn => _isLoggedIn;

  /// Loads saved tokens.
  Future<void> init() async {
    final raw = await _storage.read(_tokensKey);
    if (raw != null) {
      try {
        _tokens = SpotifyTokens.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        await _storage.delete(_tokensKey); // Corrupted entry.
      }
    }
    _isLoggedIn.value = _tokens != null;
  }

  Future<Result<void>> login() async {
    try {
      await _save(await _authService.login());
      return const Result<void>.ok(null);
    } on Exception catch (e) {
      return Result<void>.error(e);
    }
  }

  Future<void> logout() async {
    _tokens = null;
    await _storage.delete(_tokensKey);
    _isLoggedIn.value = false;
  }

  /// Valid access token (refreshed if about to expire), or null if logged out.
  Future<String?> getAccessToken() async {
    final tokens = _tokens;
    if (tokens == null) return null;
    if (!tokens.isExpired()) return tokens.accessToken;
    return refreshAccessToken();
  }

  /// Forces a refresh (used after a `401`). Returns null if it failed.
  Future<String?> refreshAccessToken() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  void dispose() => _isLoggedIn.dispose();

  Future<String?> _refresh() async {
    final tokens = _tokens;
    if (tokens == null) return null;
    try {
      final next = await _authService.refresh(tokens.refreshToken);
      await _save(next);
      return next.accessToken;
    } on SpotifyAuthException catch (e) {
      // Revoked/expired refresh token → the user must log in again.
      if (e.isInvalidGrant) await logout();
      return null;
    } on Exception {
      return null; // Network error: keep the session, try later.
    }
  }

  Future<void> _save(SpotifyTokens tokens) async {
    _tokens = tokens;
    await _storage.write(_tokensKey, jsonEncode(tokens.toJson()));
    _isLoggedIn.value = true;
  }
}