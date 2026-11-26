import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Open in Spotify" link for content that comes from Spotify (FR-12.2).
class SpotifyAttribution extends StatelessWidget {
  const SpotifyAttribution({super.key, required this.url});

  /// Spotify web link, e.g. `https://open.spotify.com/track/<id>`.
  final Uri url;

  /// Opens [url] in the Spotify app or the browser.
  static Future<void> open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => open(url),
      icon: const Icon(Icons.open_in_new, size: 18),
      label: const Text('Open in Spotify'),
    );
  }
}