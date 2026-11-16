# PlayTier

> 🚧 **Work in progress** — currently in the planning / setup phase.

PlayTier is a cross-platform companion app for Spotify (Android, Linux, Windows) built with Flutter.
It is made for people who keep **all their music in a single playlist** and want to filter, group and shuffle it quickly — without manually maintaining dozens of playlists.

## Planned features

- **Virtual playlists** by genre and artist, generated automatically from your main playlist.
- **Multi-filter** (genre, artist, album, year, like level…) with a preview before creating a playlist.
- **Like levels (1–5)** — songs you like more appear more often in shuffle.
- **Weighted shuffle** that never repeats a song back-to-back.
- **Discover** new music from your artists, your genres or outside your usual taste.
- **Custom dark themes** with importable color palettes.

## Tech stack

| Area | Choice |
|---|---|
| Framework | Flutter (Android, Linux, Windows) |
| Architecture | MVVM + Repositories + pure-Dart domain |
| State management | Provider |
| Local storage | drift (SQLite) |
| Data sources | Spotify Web API, Spotify App Remote SDK, Last.fm, MusicBrainz, LRCLIB |

## Documentation

- [Requirements](docs/requirements.md)
- [Architecture](docs/architecture.md)
- [Roadmap](docs/roadmap.md)

## Requirements to run

- A **Spotify Premium** account.
- The official Spotify app installed and running on the device that plays music.
- Your own Spotify Developer app (Client ID) and a Last.fm API key.

## Setup

1. Clone the repository.
2. Copy `config.example.json` to `config.json` and fill in your keys.
3. Run:
   ```bash
   flutter pub get
   flutter run --dart-define-from-file=config.json
   ```

Detailed setup instructions will be added as development progresses.

## Disclaimer

PlayTier is an independent personal project and is **not affiliated with, endorsed by or sponsored by Spotify**. Spotify content, metadata and artwork belong to Spotify and their respective owners.

## License

[MIT](LICENSE)
