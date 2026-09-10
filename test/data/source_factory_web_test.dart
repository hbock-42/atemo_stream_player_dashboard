import 'package:atemo_stream_player_viewer/data/source_factory_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('demo mode selection', () {
    test('is off unless asked for', () {
      for (final url in [
        'http://streamplayer.local:8080/',
        'http://streamplayer.local:8080/?wall',
        'http://streamplayer.local:8080/?demonstration=1',
      ]) {
        expect(isDemo(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test('is on when asked for', () {
      for (final url in ['https://example.com/?demo', 'https://example.com/?demo=1&wall']) {
        expect(isDemo(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('can be switched off explicitly', () {
      expect(isDemo(Uri.parse('https://example.com/?demo=0')), isFalse);
      expect(isDemo(Uri.parse('https://example.com/?demo=false')), isFalse);
    });
  });
}
