import 'package:atemo_stream_player_viewer/discovery/system_mdns.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captured verbatim from the real device on 2026-09-10.
const browseOutput = '''
Browsing for _googlecast._tcp.local
DATE: ---Thu 10 Sep 2026---
18:50:53.853  ...STARTING...
Timestamp     A/R    Flags  if Domain               Service Type         Instance Name
18:50:53.853  Add        2  14 local.               _googlecast._tcp.    Streamplayer-38067793cb7c81ff4c11baa216b5de90
18:50:53.854  Add        2  14 local.               _googlecast._tcp.    Chromecast-abc123
''';

const resolveOutput = r'''
18:50:47.837  ...STARTING...
18:50:47.839  Streamplayer-38067793cb7c81ff4c11baa216b5de90._googlecast._tcp.local. can be reached at 38067793-cb7c-81ff-4c11-baa216b5de90.local.:8009 (interface 14)
 id=38067793cb7c81ff4c11baa216b5de90 cd=33D97A986F4FE80E8EAB058DC0A4E94C rm= ve=05 md=Streamplayer ic=/setup/icon.png fn=The\ Kids\ 🕺 ca=198660 st=1 bs=FA8FCA53AA29 nf=1 rs=Casting:\ Matières\ #1\ -\ Présentée\ par\ Guessaï
''';

const addressOutput = '''
Timestamp     A/R Flags if Hostname                               Address
18:52:01.123  Add     2 14 38067793-cb7c-81ff-4c11-baa216b5de90.local. 192.168.1.131
''';

void main() {
  group('browse', () {
    test('finds the Streamplayer and ignores other Cast devices', () {
      expect(SystemMdns.parseBrowse(browseOutput),
          ['Streamplayer-38067793cb7c81ff4c11baa216b5de90']);
    });

    test('empty output yields nothing', () {
      expect(SystemMdns.parseBrowse(''), isEmpty);
      expect(SystemMdns.parseBrowse('Browsing for _googlecast._tcp.local'), isEmpty);
    });
  });

  group('resolve', () {
    test('reads host and port', () {
      final resolved = SystemMdns.parseResolve(resolveOutput);

      expect(resolved.host, '38067793-cb7c-81ff-4c11-baa216b5de90.local');
      expect(resolved.port, 8009);
    });

    test('reads the TXT record, unescaping spaces', () {
      final txt = SystemMdns.parseResolve(resolveOutput).txt;

      expect(txt['md'], 'Streamplayer');
      expect(txt['st'], '1');
      expect(txt['fn'], 'The Kids 🕺');
      // The status line is one value containing spaces, accents and a #.
      expect(txt['rs'], 'Casting: Matières #1 - Présentée par Guessaï');
    });

    test('an empty value survives', () {
      expect(SystemMdns.parseResolve(resolveOutput).txt['rm'], '');
    });
  });

  group('escaped TXT parsing', () {
    test('a backslash-escaped space does not split the pair', () {
      expect(SystemMdns.parseEscapedTxt(r' a=one\ two b=three'),
          {'a': 'one two', 'b': 'three'});
    });

    test('an escaped backslash survives', () {
      expect(SystemMdns.parseEscapedTxt(r' a=back\\slash'), {'a': r'back\slash'});
    });

    test('a value containing = is kept whole', () {
      expect(SystemMdns.parseEscapedTxt(' a=x=y'), {'a': 'x=y'});
    });

    test('malformed pairs are skipped', () {
      expect(SystemMdns.parseEscapedTxt(' good=1 nonsense =novalue'), {'good': '1'});
    });
  });

  group('address', () {
    test('reads the IPv4 address', () {
      expect(SystemMdns.parseAddress(addressOutput), '192.168.1.131');
    });

    test('no Add line yields nothing', () {
      expect(SystemMdns.parseAddress('Timestamp A/R Flags if Hostname Address'), isNull);
    });
  });
}
