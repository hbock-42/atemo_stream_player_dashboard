import 'package:atemo_stream_player_viewer/data/spotify_now_playing_mapper.dart';
import 'package:atemo_stream_player_viewer/data/spotify_web_api_source.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> track(String name) => {
      'device': {'name': 'The Kids', 'volume_percent': 50},
      'is_playing': true,
      'progress_ms': 1000,
      'item': {
        'name': name,
        'duration_ms': 200000,
        'artists': [
          {'name': 'Someone'},
        ],
        'album': {'name': 'An Album', 'images': <dynamic>[]},
      },
    };

void main() {
  test('polls and emits what Spotify reports', () async {
    final source = SpotifyWebApiSource(
      fetch: () async => SpotifyFetchResult(track('Teardrop')),
      mapper: const SpotifyNowPlayingMapper(deviceName: 'The Kids'),
      interval: const Duration(milliseconds: 20),
    );
    addTearDown(source.dispose);

    final states = <NowPlaying>[];
    source.stream.listen(states.add);
    await source.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(states.whereType<Playing>().any((p) => p.title == 'Teardrop'), isTrue);
  });

  test('picks up a track change on the next poll', () async {
    var current = track('First');
    final source = SpotifyWebApiSource(
      fetch: () async => SpotifyFetchResult(current),
      mapper: const SpotifyNowPlayingMapper(deviceName: 'The Kids'),
      interval: const Duration(milliseconds: 20),
    );
    addTearDown(source.dispose);
    await source.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect((source.current as Playing).title, 'First');

    current = track('Second');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect((source.current as Playing).title, 'Second');
  });

  test('a 204 is idle', () async {
    final source = SpotifyWebApiSource(
      fetch: () async => const SpotifyFetchResult(null),
      interval: const Duration(milliseconds: 20),
    );
    addTearDown(source.dispose);
    await source.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(source.current, isA<Idle>());
  });

  test('an unreachable API is Unreachable, not idle', () async {
    final source = SpotifyWebApiSource(
      fetch: () async => SpotifyFetchResult.unreachable,
      interval: const Duration(milliseconds: 20),
    );
    addTearDown(source.dispose);
    await source.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(source.current, isA<Unreachable>());
  });

  test('control is null for a read-only token, so the UI is view-only', () async {
    final source = SpotifyWebApiSource(fetch: () async => const SpotifyFetchResult(null));
    addTearDown(source.dispose);
    expect(source.control, isNull);
  });

  test('a slow fetch does not overlap the next poll', () async {
    var inFlight = 0;
    var maxConcurrent = 0;
    final source = SpotifyWebApiSource(
      fetch: () async {
        inFlight++;
        maxConcurrent = inFlight > maxConcurrent ? inFlight : maxConcurrent;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        inFlight--;
        return const SpotifyFetchResult(null);
      },
      interval: const Duration(milliseconds: 10),
    );
    addTearDown(source.dispose);
    await source.start();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(maxConcurrent, 1, reason: 'polls must not pile up on a slow API');
  });
}
