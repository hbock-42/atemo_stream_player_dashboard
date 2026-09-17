/// A [NowPlayingSource] that reads what is playing from the Spotify Web API.
///
/// The only way to see a Spotify Connect track, which is invisible to Cast on
/// this device (OQ-1). Runs on the relay, server-side: the OAuth credentials
/// never reach a browser (ADR-0005).
///
/// The Web API has no push, so this polls. It is deliberately built around two
/// injected functions — one that fetches the current track, one that yields a
/// token — so the whole thing is testable without a network or a Spotify app,
/// and so the OAuth mechanism can be swapped without touching the source.
library;

import 'dart:async';

import '../domain/diagnostics.dart';
import '../domain/now_playing_source.dart';
import 'source_base.dart';
import 'spotify_now_playing_mapper.dart';

/// The result of one currently-playing fetch.
///
/// [body] is the parsed JSON (null for a 204 — nothing playing). [reachable]
/// is false when the request itself failed.
class SpotifyFetchResult {
  const SpotifyFetchResult(this.body, {this.reachable = true, this.retryAfter});

  final Map<String, dynamic>? body;
  final bool reachable;

  /// Set from a 429 Retry-After, so the caller can back off as Spotify asks.
  final Duration? retryAfter;

  static const unreachable = SpotifyFetchResult(null, reachable: false);
}

typedef SpotifyFetcher = Future<SpotifyFetchResult> Function();

class SpotifyWebApiSource with ReplayLatestSource implements NowPlayingSource {
  SpotifyWebApiSource({
    required this.fetch,
    this.mapper = const SpotifyNowPlayingMapper(),
    this.interval = const Duration(seconds: 5),
    this.control,
  });

  final SpotifyFetcher fetch;
  final SpotifyNowPlayingMapper mapper;
  final Duration interval;

  /// Null unless the granted scopes allow modifying playback. The UI renders
  /// view-only when null, which is correct for a read-only token.
  @override
  final PlaybackControl? control;

  Timer? _timer;
  bool _disposed = false;
  bool _inFlight = false;

  @override
  SourceMode get mode => SourceMode.unknown;

  @override
  SourceDiagnostics get diagnostics =>
      super.diagnostics.copyWith(endpoint: 'Spotify Web API');

  @override
  Future<void> start() async {
    await _poll();
    _schedule(interval);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (_disposed) return;
    _timer = Timer(delay, () async {
      await _poll();
      _schedule(interval);
    });
  }

  Future<void> _poll() async {
    if (_disposed || _inFlight) return;
    _inFlight = true;
    try {
      final result = await fetch();
      if (_disposed) return;
      if (!result.reachable) {
        emit(mapper.map(null, reachable: false));
      } else {
        emit(mapper.map(result.body));
      }
      // Respect a rate-limit by pushing the next poll out.
      final retry = result.retryAfter;
      if (retry != null && retry > interval) _schedule(retry);
    } finally {
      _inFlight = false;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await closeController();
  }
}
