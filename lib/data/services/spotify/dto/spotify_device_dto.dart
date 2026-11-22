/// Device from `GET /me/player/devices` or inside `GET /me/player`.
class SpotifyDeviceDto {
  const SpotifyDeviceDto({
    required this.id,
    required this.name,
    required this.type,
    required this.isActive,
    required this.isRestricted,
  });

  factory SpotifyDeviceDto.fromJson(Map<String, dynamic> json) {
    return SpotifyDeviceDto(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? false,
      isRestricted: json['is_restricted'] as bool? ?? false,
    );
  }

  /// Null for some restricted devices.
  final String? id;
  final String name;

  /// `Computer`, `Smartphone`, `Speaker`…
  final String type;
  final bool isActive;

  /// Restricted devices do not accept Web API commands.
  final bool isRestricted;
}