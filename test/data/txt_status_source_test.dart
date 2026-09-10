import 'package:atemo_stream_player_viewer/data/txt_status_source.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The record captured from the real device on 2026-09-10, which is also what
/// the office Android phones are reading.
const realRecord = {
  'id': '38067793cb7c81ff4c11baa216b5de90',
  'md': 'Streamplayer',
  'fn': 'The Kids 🕺',
  'st': '1',
  'rs': 'Casting: Dor Fodida',
  'ca': '198660',
};

void main() {
  group('mapping the real record', () {
    test('reports the track and the device name', () {
      final state = TxtStatusSource.fromTxt(realRecord) as Playing;

      expect(state.title, 'Dor Fodida',
          reason: 'the "Casting:" prefix is the receiver\'s, not the track');
      expect(state.deviceName, 'The Kids 🕺');
    });

    test('offers no capabilities, because it cannot control anything', () {
      final state = TxtStatusSource.fromTxt(realRecord) as Playing;

      expect(state.capabilities, Capabilities.none);
      expect(state.capabilities.canPause, isFalse);
    });
  });

  group('idle', () {
    test('st=0 is idle even when a status line is present', () {
      final state = TxtStatusSource.fromTxt(
          {...realRecord, 'st': '0'}) as Idle;
      expect(state.deviceName, 'The Kids 🕺');
    });

    test('an idle status line is not shown as a track', () {
      for (final line in ['Ready to cast', 'ready to play', 'Idle', 'Backdrop']) {
        expect(TxtStatusSource.fromTxt({...realRecord, 'rs': line}), isA<Idle>(),
            reason: '"$line" is the receiver saying nothing is playing');
      }
    });

    test('an empty status line is idle', () {
      expect(TxtStatusSource.fromTxt({...realRecord, 'rs': ''}), isA<Idle>());
      expect(TxtStatusSource.fromTxt({'st': '1'}), isA<Idle>());
    });
  });

  group('status lines we have not seen', () {
    test('an unprefixed line is taken as the track', () {
      final state =
          TxtStatusSource.fromTxt({...realRecord, 'rs': 'Blue in Green'}) as Playing;
      expect(state.title, 'Blue in Green');
    });

    test('other prefixes are stripped too', () {
      for (final line in ['Playing: A Track', 'Now playing: A Track']) {
        final state = TxtStatusSource.fromTxt({...realRecord, 'rs': line}) as Playing;
        expect(state.title, 'A Track', reason: line);
      }
    });

    test('a track containing a colon survives', () {
      final state = TxtStatusSource.fromTxt(
          {...realRecord, 'rs': 'Casting: Symphony No. 5: Allegro'}) as Playing;
      expect(state.title, 'Symphony No. 5: Allegro');
    });

    test('a bare prefix with nothing after it is idle', () {
      expect(TxtStatusSource.fromTxt({...realRecord, 'rs': 'Casting:'}), isA<Idle>());
    });
  });

  test('an empty record is not a track', () {
    expect(TxtStatusSource.fromTxt(const {}), isA<Idle>());
  });
}
