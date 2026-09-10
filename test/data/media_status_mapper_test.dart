import 'package:atemo_stream_player_viewer/cast/cast_snapshot.dart';
import 'package:atemo_stream_player_viewer/data/media_status_mapper.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:flutter_test/flutter_test.dart';

const mapper = MediaStatusMapper();

CastSnapshot snapshotWith(Map<String, dynamic>? mediaStatus) => CastSnapshot(
      appId: 'CC32E753',
      appDisplayName: 'Spotify',
      transportId: 'transport-1',
      mediaSessionId: 1,
      volumeLevel: 0.4,
      supportedMediaCommands: 1 | 2 | 64 | 128,
      mediaStatus: mediaStatus,
      deviceName: 'Streamplayer',
    );

void main() {
  group('a well-formed status', () {
    test('maps every field', () {
      final result = mapper.map(snapshotWith({
        'playerState': 'PLAYING',
        'currentTime': 42.5,
        'media': {
          'duration': 396.0,
          'metadata': {
            'title': 'Waltz for Debby',
            'artist': 'Bill Evans Trio',
            'albumName': 'Waltz for Debby',
            'images': [
              {'url': 'http://192.168.1.50:8008/art.jpg'},
            ],
          },
        },
      })) as Playing;

      expect(result.title, 'Waltz for Debby');
      expect(result.artist, 'Bill Evans Trio');
      expect(result.album, 'Waltz for Debby');
      expect(result.artworkUrl, 'http://192.168.1.50:8008/art.jpg');
      expect(result.castingApp, 'Spotify');
      expect(result.isPaused, isFalse);
      expect(result.position, const Duration(milliseconds: 42500));
      expect(result.duration, const Duration(milliseconds: 396000));
      expect(result.volumeLevel, 0.4);
      expect(result.capabilities.canPause, isTrue);
      expect(result.capabilities.canSkipNext, isTrue);
    });

    test('falls back to albumArtist when artist is absent', () {
      final result = mapper.map(snapshotWith({
        'playerState': 'PLAYING',
        'media': {
          'metadata': {'title': 'A Track', 'albumArtist': 'The Band'},
        },
      })) as Playing;

      expect(result.artist, 'The Band');
    });

    test('treats BUFFERING as playing, not paused', () {
      final result = mapper.map(snapshotWith({'playerState': 'BUFFERING'})) as Playing;
      expect(result.isPaused, isFalse);
    });

    test('maps PAUSED to paused', () {
      final result = mapper.map(snapshotWith({'playerState': 'PAUSED'})) as Playing;
      expect(result.isPaused, isTrue);
    });
  });

  group('idle', () {
    test('no application means idle, and volume survives', () {
      final result = mapper.map(const CastSnapshot(volumeLevel: 0.4, deviceName: 'S'))
          as Idle;
      expect(result.volumeLevel, 0.4);
      expect(result.deviceName, 'S');
    });

    test('playerState IDLE means idle', () {
      expect(mapper.map(snapshotWith({'playerState': 'IDLE'})), isA<Idle>());
    });

    test('an app with no media status yet is idle, not a blank card', () {
      expect(mapper.map(snapshotWith(null)), isA<Idle>());
    });
  });

  group('malformed payloads never throw', () {
    final hostile = <String, Map<String, dynamic>>{
      'empty': <String, dynamic>{},
      'null metadata': {'playerState': 'PLAYING', 'media': null},
      'metadata is a string': {'playerState': 'PLAYING', 'media': 'nonsense'},
      'images is not a list': {
        'playerState': 'PLAYING',
        'media': {
          'metadata': {'images': 'http://example.com/a.jpg'},
        },
      },
      'images is empty': {
        'playerState': 'PLAYING',
        'media': {
          'metadata': {'images': <dynamic>[]},
        },
      },
      'image entries lack urls': {
        'playerState': 'PLAYING',
        'media': {
          'metadata': {
            'images': [
              {'height': 500},
            ],
          },
        },
      },
      'title is a number': {
        'playerState': 'PLAYING',
        'media': {
          'metadata': {'title': 42},
        },
      },
      'title is blank': {
        'playerState': 'PLAYING',
        'media': {
          'metadata': {'title': '   '},
        },
      },
      'durations are strings': {
        'playerState': 'PLAYING',
        'currentTime': '12.5',
        'media': {'duration': '300'},
      },
      'durations are nonsense': {
        'playerState': 'PLAYING',
        'currentTime': double.nan,
        'media': {'duration': -5},
      },
      'playerState missing': {
        'media': {
          'metadata': {'title': 'Untitled'},
        },
      },
      'playerState lowercase': {'playerState': 'playing'},
    };

    hostile.forEach((name, status) {
      test(name, () {
        expect(() => mapper.map(snapshotWith(status)), returnsNormally);
      });
    });

    test('a numeric title degrades to absent rather than to "42"', () {
      final result = mapper.map(snapshotWith({
        'playerState': 'PLAYING',
        'media': {
          'metadata': {'title': 42, 'artist': 'Someone'},
        },
      })) as Playing;

      expect(result.title, isNull);
      expect(result.artist, 'Someone');
      expect(result.hasMetadata, isTrue);
    });

    test('string durations are parsed rather than dropped', () {
      final result = mapper.map(snapshotWith({
        'playerState': 'PLAYING',
        'currentTime': '12.5',
        'media': {'duration': '300'},
      })) as Playing;

      expect(result.position, const Duration(milliseconds: 12500));
      expect(result.duration, const Duration(seconds: 300));
    });

    test('NaN and negative durations become null, not garbage', () {
      final result = mapper.map(snapshotWith({
        'playerState': 'PLAYING',
        'currentTime': double.nan,
        'media': {'duration': -5},
      })) as Playing;

      expect(result.position, isNull);
      expect(result.duration, isNull);
    });
  });

  group('capabilities', () {
    test('decodes the bitmask', () {
      const caps = MediaStatusMapper.capabilitiesFrom;
      expect(caps(0).canPause, isFalse);
      expect(caps(1).canPause, isTrue);
      expect(caps(2).canSeek, isTrue);
      expect(caps(64).canSkipNext, isTrue);
      expect(caps(128).canSkipPrevious, isTrue);
      expect(caps(1 | 128).canSkipNext, isFalse);
    });

    test('an app supporting nothing yields no capabilities', () {
      final result = mapper.map(const CastSnapshot(
        transportId: 't',
        mediaSessionId: 1,
        supportedMediaCommands: 0,
        mediaStatus: {'playerState': 'PLAYING'},
      )) as Playing;

      expect(result.capabilities, Capabilities.none);
    });
  });
}
