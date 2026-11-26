/// A device where Spotify is open and can play (FR-11.2), e.g. the PC
/// while the app runs on the phone.
class PlaybackDevice {
  const PlaybackDevice({
    required this.id,
    required this.name,
    required this.type,
    this.isActive = false,
  });

  /// Spotify Connect device id.
  final String id;
  final String name;

  /// `Computer`, `Smartphone`, `Speaker`… as Spotify reports it.
  final String type;

  /// The device currently playing.
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackDevice &&
          other.id == id &&
          other.name == name &&
          other.type == type &&
          other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, name, type, isActive);

  @override
  String toString() => 'PlaybackDevice($name, $type${isActive ? ', active' : ''})';
}