import 'package:atemo_stream_player_viewer/discovery/mdns_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TXT parsing', () {
    test('reads the record a real Streamplayer publishes', () {
      // Captured from a device on the LAN, 2026-09-10.
      const record = 'id=38067793cb7c81ff4c11baa216b5de90\n'
          'cd=33D97A986F4FE80E8EAB058DC0A4E94C\n'
          'rm=\n'
          've=05\n'
          'md=Streamplayer\n'
          'ic=/setup/icon.png\n'
          'fn=The Kids 🕺\n'
          'ca=198660\n'
          'st=1\n'
          'bs=FA8FCA53AA29\n'
          'nf=1\n'
          'rs=Casting: Dor Fodida';

      final txt = MdnsDiscovery.parseTxt(record);

      expect(txt['md'], 'Streamplayer');
      expect(txt['fn'], 'The Kids 🕺', reason: 'names contain emoji');
      expect(txt['st'], '1', reason: 'an app is running');
      expect(txt['rs'], 'Casting: Dor Fodida',
          reason: 'now-playing text over plain mDNS — the OQ-1 fallback');
    });

    test('keeps = inside a value', () {
      // A status line is free text and may well contain one.
      expect(MdnsDiscovery.parseTxt('rs=Casting: a=b')['rs'], 'Casting: a=b');
    });

    test('skips malformed lines instead of throwing', () {
      final txt = MdnsDiscovery.parseTxt('good=yes\nnonsense\n=novalue\n\n  \nalso=fine');

      expect(txt, {'good': 'yes', 'also': 'fine'});
    });

    test('an empty value is kept, since rm= appears empty in practice', () {
      expect(MdnsDiscovery.parseTxt('rm=')['rm'], '');
    });

    test('an empty record yields an empty map', () {
      expect(MdnsDiscovery.parseTxt(''), isEmpty);
    });
  });

  group('instance matching', () {
    test('matches the real instance name', () {
      expect(
        kStreamplayerInstance.hasMatch(
            'Streamplayer-38067793cb7c81ff4c11baa216b5de90._googlecast._tcp.local'),
        isTrue,
      );
    });

    test('does not match other Cast devices on the network', () {
      for (final other in [
        'Chromecast-1234._googlecast._tcp.local',
        'Living Room speaker._googlecast._tcp.local',
        'Streamplayer-tooshort._googlecast._tcp.local',
      ]) {
        expect(kStreamplayerInstance.hasMatch(other), isFalse, reason: other);
      }
    });
  });
}
