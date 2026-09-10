/// ADR-0006 is enforced here, so it is tested here.
///
/// The rule: everyone on the office Wi-Fi may view and control; nobody outside
/// may do either. No PIN. That makes these checks the whole of the security
/// model, rather than a defence-in-depth extra.
library;

import 'dart:io';

import 'package:streamplayer_relay/access.dart';
import 'package:test/test.dart';

void main() {
  group('private address detection (layer 2)', () {
    const allowed = [
      '10.0.0.5',
      '10.255.255.254',
      '192.168.1.50',
      '172.16.0.1',
      '172.31.255.254',
      '169.254.10.1',
      '127.0.0.1',
    ];
    const refused = [
      '8.8.8.8',
      '1.1.1.1',
      '172.15.0.1', // just below the private range
      '172.32.0.1', // just above it
      '192.169.1.1',
      '11.0.0.1',
      '203.0.113.7',
    ];

    for (final address in allowed) {
      test('$address is private', () {
        expect(AccessPolicy.isPrivateAddress(InternetAddress(address)), isTrue);
      });
    }

    for (final address in refused) {
      test('$address is public', () {
        expect(AccessPolicy.isPrivateAddress(InternetAddress(address)), isFalse,
            reason: 'a public peer must never be granted control');
      });
    }

    test('IPv6 unique-local and link-local are private', () {
      expect(AccessPolicy.isPrivateAddress(InternetAddress('fd00::1')), isTrue);
      expect(AccessPolicy.isPrivateAddress(InternetAddress('fe80::1')), isTrue);
      expect(AccessPolicy.isPrivateAddress(InternetAddress('::1')), isTrue);
    });

    test('a public IPv6 address is refused', () {
      expect(
        AccessPolicy.isPrivateAddress(InternetAddress('2001:4860:4860::8888')),
        isFalse,
      );
    });
  });

  group('end to end over a real socket', () {
    late HttpServer server;
    late AccessPolicy policy;
    final decisions = <AccessDecision>[];

    setUp(() async {
      policy = const AccessPolicy(allowedHosts: {'streamplayer.local'});
      decisions.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final decision = policy.evaluate(request);
        decisions.add(decision);
        request.response.statusCode =
            decision.allowed ? HttpStatus.ok : HttpStatus.forbidden;
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Future<int> get_({Map<String, String> headers = const {}}) async {
      final client = HttpClient();
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/'));
      headers.forEach(request.headers.set);
      final response = await request.close();
      await response.drain<void>();
      client.close();
      return response.statusCode;
    }

    test('a loopback client with a matching Host is allowed to control', () async {
      expect(await get_(), HttpStatus.ok);
      expect(decisions.single.canControl, isTrue);
    });

    test('a request with no Origin is allowed — the native app sends none', () async {
      expect(await get_(headers: {'host': 'streamplayer.local'}), HttpStatus.ok);
    });

    test('a cross-origin request is refused (DNS rebinding)', () async {
      // The attack: a page on evil.example re-resolves its own name to the
      // relay's private address, so the request genuinely comes from a LAN
      // peer. Only the Origin gives it away.
      final status = await get_(headers: {'origin': 'http://evil.example'});

      expect(status, HttpStatus.forbidden);
      expect(decisions.single.reason, contains('Host or Origin'));
    });

    test('an unrecognised Host is refused', () async {
      expect(await get_(headers: {'host': 'attacker.example'}), HttpStatus.forbidden);
    });

    test('an allowlisted hostname as Origin is accepted', () async {
      final status = await get_(headers: {
        'host': 'streamplayer.local',
        'origin': 'http://streamplayer.local',
      });
      expect(status, HttpStatus.ok);
    });

    test('a private-IP Origin is accepted', () async {
      final status = await get_(headers: {
        'host': '192.168.1.20:8080',
        'origin': 'http://192.168.1.20:8080',
      });
      expect(status, HttpStatus.ok);
    });

    test('X-Forwarded-For cannot fake a private peer', () async {
      // Trusting that header would let anyone behind a proxy claim to be local.
      final status = await get_(headers: {
        'host': 'attacker.example',
        'x-forwarded-for': '192.168.1.5',
      });
      expect(status, HttpStatus.forbidden);
    });
  });
}
