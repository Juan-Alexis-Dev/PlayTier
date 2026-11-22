import 'spotify_device_dto.dart';

/// Player state from `GET /me/player`.
///
/// Track fields are null when nothing is playing or the item is not a
/// track (ads, episodes).
class SpotifyPlayerDto {
  const SpotifyPlayerDto({
    required this.isPlaying,
    required this.progressMs,
    required this.shuffleState,
    required this.repeatState,
    this.device,
    this.contextUri,
    this.trackUri,
    this.trackName,
    this.durationMs,
    this.artistNames = const [],
    this.albumName,
    this.coverUrl,
  });

  factory SpotifyPlayerDto.fromJson(Map<String, dynamic> json) {
    final device = json['device'] as Map<String, dynamic>?;
    final context = json['context'] as Map<String, dynamic>?;
    final item = json['item'] as Map<String, dynamic>?;
    final isTrack = item != null && item['type'] == 'track';
    final album = isTrack ? item['album'] as Map<String, dynamic>? : null;
    final images = album?['images'] as List<dynamic>? ?? const [];

    return SpotifyPlayerDto(
      isPlaying: json['is_playing'] as bool? ?? false,
      progressMs: json['progress_ms'] as int? ?? 0,
      shuffleState: json['shuffle_state'] as bool? ?? false,
      repeatState: json['repeat_state'] as String? ?? 'off',
      device: device == null ? null : SpotifyDeviceDto.fromJson(device),
      contextUri: context?['uri'] as String?,
      trackUri: isTrack ? item['uri'] as String? : null,
      trackName: isTrack ? item['name'] as String? : null,
      durationMs: isTrack ? item['duration_ms'] as int? : null,
      artistNames: isTrack
          ? [
              for (final a in item['artists'] as List<dynamic>? ?? const [])
                if (a is Map<String, dynamic>) a['name'] as String? ?? '',
            ]
          : const [],
      albumName: album?['name'] as String?,
      coverUrl: images.isNotEmpty && images.first is Map<String, dynamic>
          ? (images.first as Map<String, dynamic>)['url'] as String?
          : null,
    );
  }

  final bool isPlaying;
  final int progressMs;
  final bool shuffleState;

  /// `off`, `context` or `track`.
  final String repeatState;
  final SpotifyDeviceDto? device;
  final String? contextUri;
  final String? trackUri;
  final String? trackName;
  final int? durationMs;
  final List<String> artistNames;
  final String? albumName;
  final String? coverUrl;
}