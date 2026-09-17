import 'package:atemo_stream_player_viewer/data/spotify_now_playing_mapper.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape of a real /v1/me/player/currently-playing response, trimmed.
Map<String, dynamic> response({
  String device = 'The Kids',
  bool isPlaying = true,
  int volume = 66,
  Map<String, dynamic>? item = _defaultItem,
}) =>
    {
      'device': {'name': device, 'volume_percent': volume},
      'is_playing': isPlaying,
      'progress_ms': 42000,
      'item': item,
    };

const _defaultItem = {
  'name': 'Teardrop',
  'duration_ms': 330000,
  'artists': [
    {'name': 'Massive Attack'},
  ],
  'album': {
    'name': 'Mezzanine',
    'images': [
      {'url': 'https://i.scdn.co/image/abc.jpg'},
    ],
  },
};

void main() {
  const mapper = SpotifyNowPlayingMapper(deviceName: 'The Kids');

  test('maps a track playing on the speaker', () {
    final state = mapper.map(response()) as Playing;

    expect(state.title, 'Teardrop');
    expect(state.artist, 'Massive Attack');
    expect(state.album, 'Mezzanine');
    expect(state.artworkUrl, 'https://i.scdn.co/image/abc.jpg');
    expect(state.castingApp, 'Spotify');
    expect(state.isPaused, isFalse);
    expect(state.position, const Duration(seconds: 42));
    expect(state.duration, const Duration(seconds: 330));
    expect(state.volumeLevel, closeTo(0.66, 0.001));
  });

  test('joins multiple artists', () {
    final r = response(item: {
      ..._defaultItem,
      'artists': [
        {'name': 'A'},
        {'name': 'B'},
      ],
    });
    expect((mapper.map(r) as Playing).artist, 'A, B');
  });

  test('a paused track is paused, not idle', () {
    expect((mapper.map(response(isPlaying: false)) as Playing).isPaused, isTrue);
  });

  group('device filtering — the whole point of this source', () {
    test('a track on a different device is not shown as the speaker', () {
      // Someone playing Spotify on their phone must not appear as the office
      // system.
      expect(mapper.map(response(device: "Hugo's iPhone")), isA<Idle>());
    });

    test('a partial, case-insensitive name match counts', () {
      expect(mapper.map(response(device: 'the kids 🕺')), isA<Playing>());
    });

    test('with no device filter, anything playing counts', () {
      const anywhere = SpotifyNowPlayingMapper();
      expect(anywhere.map(response(device: 'whatever')), isA<Playing>());
    });
  });

  group('empty and error states', () {
    test('a 204 (null body) is idle', () {
      expect(mapper.map(null), isA<Idle>());
    });

    test('an unreachable API is Unreachable, distinct from idle', () {
      expect(mapper.map(null, reachable: false), isA<Unreachable>());
    });

    test('playing an ad (no item) is idle, not a blank track', () {
      expect(mapper.map(response(item: null)), isA<Idle>());
    });

    test('never throws on a malformed body', () {
      for (final bad in <Map<String, dynamic>>[
        {},
        {'item': 'nonsense'},
        {'device': 42, 'item': _defaultItem},
        {'is_playing': true, 'item': {'name': 123}},
      ]) {
        expect(() => SpotifyNowPlayingMapper().map(bad), returnsNormally);
      }
    });
  });
}
