import 'package:atemo_stream_player_viewer/domain/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiagnosticLog', () {
    test('keeps only the most recent lines', () {
      final log = DiagnosticLog(capacity: 3);
      for (var i = 0; i < 10; i++) {
        log.add('line $i');
      }

      expect(log.length, 3);
      expect(log.entries.map((e) => e.message), ['line 7', 'line 8', 'line 9']);
    });

    test('entries are oldest first and carry a timestamp', () {
      final log = DiagnosticLog()
        ..add('first', at: DateTime(2026, 1, 1, 9, 5, 3))
        ..add('second', at: DateTime(2026, 1, 1, 9, 5, 4));

      expect(log.entries.first.message, 'first');
      expect(log.entries.first.format(), '09:05:03  first');
    });

    test('the returned list cannot be mutated by a caller', () {
      final log = DiagnosticLog()..add('a');
      expect(
        () => log.entries.add(DiagnosticLogEntry(DateTime.now(), 'b')),
        throwsUnsupportedError,
      );
    });
  });

  group('SourceDiagnostics', () {
    final now = DateTime(2026, 3, 1, 12, 0, 30);

    test('silence is measured from the last inbound message', () {
      const never = SourceDiagnostics();
      expect(never.silenceFor(now), isNull);

      final quiet = SourceDiagnostics(lastMessageAt: now.subtract(const Duration(seconds: 12)));
      expect(quiet.silenceFor(now), const Duration(seconds: 12));
    });

    test('a clock that jumped backwards reads as zero, never negative', () {
      final future = SourceDiagnostics(lastMessageAt: now.add(const Duration(minutes: 5)));
      expect(future.silenceFor(now), Duration.zero);
    });

    test('withFacts appends without disturbing anything else', () {
      final base = SourceDiagnostics(
        mode: SourceMode.direct,
        link: LinkState.connected,
        endpoint: '192.168.1.42:8009',
        sessionId: 'transport-7',
        lastMessageAt: now,
        facts: const [DiagnosticFact('app', 'Spotify')],
      );

      final extended = base.withFacts([const DiagnosticFact('last refused command', 'nope')]);

      expect(extended.facts, [
        const DiagnosticFact('app', 'Spotify'),
        const DiagnosticFact('last refused command', 'nope'),
      ]);
      expect(extended.endpoint, '192.168.1.42:8009');
      expect(extended.sessionId, 'transport-7');
      expect(extended.mode, SourceMode.direct);
      expect(base.facts.length, 1, reason: 'the original is untouched');
    });

    test('the clipboard report carries every field a bug report needs', () {
      final diagnostics = SourceDiagnostics(
        mode: SourceMode.direct,
        link: LinkState.disconnected,
        endpoint: '192.168.1.42:8009',
        lastError: 'no response from the device',
        sessionId: 'transport-7',
        lastMessageAt: now.subtract(const Duration(seconds: 45)),
        facts: const [DiagnosticFact('app', 'Spotify')],
        log: [DiagnosticLogEntry(DateTime(2026, 3, 1, 11, 59, 0), 'connecting')],
      );

      final report = diagnostics.toReport(now);

      expect(report, contains('source mode: direct'));
      expect(report, contains('connection: disconnected'));
      expect(report, contains('address: 192.168.1.42:8009'));
      expect(report, contains('session: transport-7'));
      expect(report, contains('last message: 45s ago'));
      expect(report, contains('last error: no response from the device'));
      expect(report, contains('app: Spotify'));
      expect(report, contains('11:59:00  connecting'));
    });

    test('an empty report says so rather than showing blanks', () {
      final report = const SourceDiagnostics().toReport(now);

      expect(report, contains('source mode: unknown'));
      expect(report, contains('last message: never'));
      expect(report, contains('last error: none'));
      expect(report, contains('(empty)'));
    });
  });
}
