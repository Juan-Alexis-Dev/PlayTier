// SPIKE v0.0b — Step 2: minimal lyrics screen with the current line
// highlighted from the player position.
//
// - Android (App Remote connected): position is PUSHED on events
//   (track change, play/pause, seek).
// - Desktop (or Android without App Remote): position is POLLED with
//   GET /me/player every second.
// In both cases a local timer advances the position between updates.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:spotify_sdk/spotify_sdk.dart';

const _lrclibUserAgent =
    'PlayTier/0.0 spike (https://github.com/Juan-Alexis-Dev/PlayTier)';

// ---------------------------------------------------------------------------
// Playback sources
// ---------------------------------------------------------------------------

/// What the player reported at a moment in time.
class PlaybackSnapshot {
  PlaybackSnapshot({
    required this.trackUri,
    required this.trackName,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.positionMs,
    required this.isPaused,
    required this.receivedAt,
  });

  final String trackUri;
  final String trackName;
  final String artist;
  final String album;
  final int durationMs;
  final int positionMs; // position when the snapshot was taken
  final bool isPaused;
  final DateTime receivedAt;

  /// Position now = reported position + time elapsed since then.
  int livePositionMs(DateTime now) {
    if (isPaused) return positionMs;
    final live = positionMs + now.difference(receivedAt).inMilliseconds;
    return live > durationMs ? durationMs : live;
  }
}

abstract class PlaybackSource {
  Stream<PlaybackSnapshot> get snapshots;
  String get label;
  void dispose();
}

/// Android: PlayerState events from spotify_sdk App Remote (push).
class AppRemotePlaybackSource implements PlaybackSource {
  AppRemotePlaybackSource(this._states);

  final Stream<PlayerState> _states;

  @override
  String get label => 'App Remote (push)';

  @override
  Stream<PlaybackSnapshot> get snapshots => _states
      .where((s) => s.track != null)
      .map((s) => PlaybackSnapshot(
            trackUri: s.track!.uri,
            trackName: s.track!.name,
            artist: s.track!.artist.name ?? '',
            album: s.track!.album.name ?? '',
            durationMs: s.track!.duration,
            positionMs: s.playbackPosition,
            isPaused: s.isPaused,
            receivedAt: DateTime.now(),
          ));

  @override
  void dispose() {}
}

/// Desktop: GET /me/player every [interval] (poll).
class PollingPlaybackSource implements PlaybackSource {
  PollingPlaybackSource(this._token,
      {this.interval = const Duration(seconds: 1)});

  final String _token;
  final Duration interval;
  final _controller = StreamController<PlaybackSnapshot>.broadcast();
  Timer? _timer;
  bool _busy = false;

  @override
  String get label => 'Web API polling (${interval.inMilliseconds} ms)';

  @override
  Stream<PlaybackSnapshot> get snapshots {
    _timer ??= Timer.periodic(interval, (_) => _poll());
    _poll();
    return _controller.stream;
  }

  Future<void> _poll() async {
    if (_busy) return; // never stack requests
    _busy = true;
    try {
      final sentAt = DateTime.now();
      final res = await http.get(
        Uri.https('api.spotify.com', '/v1/me/player'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final receivedAt = DateTime.now();
      if (res.statusCode != 200) return; // 204 = nothing playing
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final item = body['item'] as Map<String, dynamic>?;
      if (item == null) return;
      // progress_ms was measured roughly in the middle of the request:
      // add half the round-trip time.
      final halfRtt = receivedAt.difference(sentAt).inMilliseconds ~/ 2;
      final isPlaying = body['is_playing'] == true;
      _controller.add(PlaybackSnapshot(
        trackUri: item['uri'] as String? ?? '',
        trackName: item['name'] as String? ?? '',
        artist: ((item['artists'] as List?)?.firstOrNull as Map?)?['name']
                as String? ??
            '',
        album: (item['album'] as Map?)?['name'] as String? ?? '',
        durationMs: item['duration_ms'] as int? ?? 0,
        positionMs:
            (body['progress_ms'] as int? ?? 0) + (isPlaying ? halfRtt : 0),
        isPaused: !isPlaying,
        receivedAt: receivedAt,
      ));
    } catch (e) {
      debugPrint('Polling error: $e');
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}

// ---------------------------------------------------------------------------
// LRC parsing + LRCLIB
// ---------------------------------------------------------------------------

class LyricLine {
  const LyricLine(this.timeMs, this.text);
  final int timeMs;
  final String text;
}

final _timeTag = RegExp(r'\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]');

/// Parses LRC text. Supports several time tags per line
/// ("[00:12.00][01:30.00] text") and ignores metadata tags ("[ar:...]").
List<LyricLine> parseLrc(String lrc) {
  final lines = <LyricLine>[];
  for (final raw in const LineSplitter().convert(lrc)) {
    final tags = _timeTag.allMatches(raw).toList();
    if (tags.isEmpty) continue;
    final text = raw.substring(tags.last.end).trim();
    for (final m in tags) {
      final minutes = int.parse(m.group(1)!);
      final seconds = int.parse(m.group(2)!);
      final fraction = m.group(3) ?? '0';
      // "5" → 500 ms, "50" → 500 ms, "500" → 500 ms
      final ms = int.parse(fraction.padRight(3, '0'));
      lines.add(LyricLine((minutes * 60 + seconds) * 1000 + ms, text));
    }
  }
  lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  return lines;
}

/// Index of the line being sung at [positionMs] (-1 before the first line).
int currentLineIndex(List<LyricLine> lines, int positionMs) {
  var low = 0, high = lines.length - 1, result = -1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    if (lines[mid].timeMs <= positionMs) {
      result = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return result;
}

/// Synced lyrics from LRCLIB, or null if there are none.
Future<String?> fetchSyncedLyrics(PlaybackSnapshot s) async {
  final headers = {'User-Agent': _lrclibUserAgent};
  final seconds = (s.durationMs / 1000).round();

  final exact = await http.get(
    Uri.https('lrclib.net', '/api/get', {
      'track_name': s.trackName,
      'artist_name': s.artist,
      'album_name': s.album,
      'duration': '$seconds',
    }),
    headers: headers,
  );
  if (exact.statusCode == 200) {
    final body = jsonDecode(utf8.decode(exact.bodyBytes)) as Map;
    final synced = body['syncedLyrics'] as String?;
    if (synced != null && synced.isNotEmpty) return synced;
  }

  final search = await http.get(
    Uri.https('lrclib.net', '/api/search', {
      'track_name': s.trackName,
      'artist_name': s.artist,
    }),
    headers: headers,
  );
  if (search.statusCode != 200) return null;
  final results = jsonDecode(utf8.decode(search.bodyBytes)) as List;
  for (final r in results.whereType<Map>()) {
    final diff = ((r['duration'] as num? ?? 0) - seconds).abs();
    final synced = r['syncedLyrics'] as String?;
    if (diff <= 2 && synced != null && synced.isNotEmpty) return synced;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class LyricsSpikeScreen extends StatefulWidget {
  const LyricsSpikeScreen({super.key, required this.source});

  final PlaybackSource source;

  @override
  State<LyricsSpikeScreen> createState() => _LyricsSpikeScreenState();
}

class _LyricsSpikeScreenState extends State<LyricsSpikeScreen> {
  StreamSubscription<PlaybackSnapshot>? _sub;
  Timer? _ticker;
  PlaybackSnapshot? _snapshot;
  String? _loadedUri;
  List<LyricLine> _lines = [];
  String _message = 'Waiting for the player...';
  int _current = -1;
  final List<GlobalKey> _lineKeys = [];

  @override
  void initState() {
    super.initState();
    _sub = widget.source.snapshots.listen(_onSnapshot);
    // Advance the highlight between player updates (10 times per second).
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    widget.source.dispose();
    super.dispose();
  }

  void _onSnapshot(PlaybackSnapshot s) {
    _snapshot = s;
    if (s.trackUri != _loadedUri) _loadLyrics(s);
  }

  Future<void> _loadLyrics(PlaybackSnapshot s) async {
    _loadedUri = s.trackUri;
    setState(() {
      _lines = [];
      _current = -1;
      _message = 'Loading lyrics for "${s.trackName}"...';
    });
    try {
      final lrc = await fetchSyncedLyrics(s);
      if (!mounted || _loadedUri != s.trackUri) return; // track changed
      final lines = lrc == null ? <LyricLine>[] : parseLrc(lrc);
      _lineKeys
        ..clear()
        ..addAll(List.generate(lines.length, (_) => GlobalKey()));
      setState(() {
        _lines = lines;
        _message = lines.isEmpty ? 'No synced lyrics for this track' : '';
      });
    } catch (e) {
      setState(() => _message = 'Lyrics error: $e');
    }
  }

  void _tick() {
    final s = _snapshot;
    if (s == null || !mounted) return;
    final index = currentLineIndex(_lines, s.livePositionMs(DateTime.now()));
    if (index != _current) {
      _current = index;
      _scrollToCurrent();
    }
    setState(() {}); // refresh the position label
  }

  /// Keeps the current line in the middle of the screen.
  void _scrollToCurrent() {
    if (_current < 0 || _current >= _lineKeys.length) return;
    final context = _lineKeys[_current].currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _snapshot;
    final scheme = Theme.of(context).colorScheme;
    final position = s?.livePositionMs(DateTime.now()) ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Lyrics spike')),
      body: Column(
        children: [
          ListTile(
            title: Text(s?.trackName ?? '—'),
            subtitle: Text(
              '${s?.artist ?? ''}\n'
              '${_fmt(position)} / ${_fmt(s?.durationMs ?? 0)}'
              '${s?.isPaused ?? false ? '  (paused)' : ''}'
              '  ·  line ${_current + 1}/${_lines.length}'
              '  ·  ${widget.source.label}',
            ),
            isThreeLine: true,
          ),
          const Divider(height: 1),
          Expanded(
            child: _lines.isEmpty
                ? Center(child: Text(_message, textAlign: TextAlign.center))
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < _lines.length; i++)
                          Padding(
                            key: _lineKeys[i],
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontSize: i == _current ? 24 : 18,
                                fontWeight: i == _current
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: i == _current
                                    ? scheme.primary
                                    : scheme.onSurface.withValues(
                                        alpha: i < _current ? 0.35 : 0.6),
                              ),
                              child: Text(
                                _lines[i].text.isEmpty ? '♪' : _lines[i].text,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _fmt(int ms) {
    final total = ms ~/ 1000;
    final tenths = (ms % 1000) ~/ 100;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}.$tenths';
  }
}