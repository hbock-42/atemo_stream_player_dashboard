import 'package:atemo_stream_player_viewer/domain/diagnostics.dart';
import 'package:atemo_stream_player_viewer/ui/screens/diagnostics_gate.dart';
import 'package:atemo_stream_player_viewer/ui/screens/diagnostics_screen.dart';
import 'package:atemo_stream_player_viewer/ui/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

SourceDiagnostics sample({DateTime? lastMessageAt}) => SourceDiagnostics(
      mode: SourceMode.direct,
      link: LinkState.connected,
      endpoint: '192.168.1.42:8009 (Streamplayer)',
      lastError: 'no response from the device',
      sessionId: 'transport-7',
      lastMessageAt: lastMessageAt ?? DateTime.now(),
      facts: const [DiagnosticFact('app', 'Spotify')],
      log: [DiagnosticLogEntry(DateTime(2026, 3, 1, 11, 59), 'connecting')],
    );

void main() {
  Widget wrap(Widget child) => AppTheme(
        child: DefaultTextStyle(
          style: AppTypography.dark.body,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(390, 844)),
              child: child,
            ),
          ),
        ),
      );

  testWidgets('shows every fact a bug report needs', (tester) async {
    await tester.pumpWidget(wrap(DiagnosticsScreen(
      read: () => sample(lastMessageAt: DateTime.now().subtract(const Duration(seconds: 3))),
      onClose: () {},
    )));

    expect(find.text('direct'), findsOneWidget);
    expect(find.text('connected'), findsOneWidget);
    expect(find.text('192.168.1.42:8009 (Streamplayer)'), findsOneWidget);
    expect(find.text('transport-7'), findsOneWidget);
    expect(find.text('3s ago'), findsOneWidget);
    expect(find.text('no response from the device'), findsOneWidget);
    expect(find.text('Spotify'), findsOneWidget);
    expect(find.text('11:59:00  connecting'), findsOneWidget);
  });

  testWidgets('re-reads the source while nothing pushes an update',
      (tester) async {
    // The interesting number here changes when nothing happens, so the screen
    // has to pull rather than wait to be told.
    var age = 0;
    await tester.pumpWidget(wrap(DiagnosticsScreen(
      read: () =>
          sample(lastMessageAt: DateTime.now().subtract(Duration(seconds: age))),
      onClose: () {},
      refreshInterval: const Duration(milliseconds: 100),
    )));

    expect(find.text('0s ago'), findsOneWidget);
    age = 12;
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('12s ago'), findsOneWidget);
  });

  testWidgets('an empty log says so', (tester) async {
    await tester.pumpWidget(wrap(DiagnosticsScreen(
      read: () => const SourceDiagnostics(),
      onClose: () {},
    )));

    expect(find.text('nothing logged yet'), findsOneWidget);
    expect(find.text('never'), findsOneWidget);
    expect(find.text('not discovered'), findsOneWidget);
  });

  testWidgets('copies the whole report to the clipboard', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(wrap(DiagnosticsScreen(read: sample, onClose: () {})));

    await tester.tap(find.text('Copy report'));
    await tester.pump();

    expect(copied, hasLength(1));
    expect(copied.single, contains('source mode: direct'));
    expect(copied.single, contains('11:59:00  connecting'));
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('close calls back', (tester) async {
    var closed = false;
    await tester.pumpWidget(wrap(DiagnosticsScreen(
      read: sample,
      onClose: () => closed = true,
    )));

    await tester.tap(find.text('Close'));
    await tester.pump();

    expect(closed, isTrue);
  });

  group('hidden entry point', () {
    testWidgets('a long press in the corner opens diagnostics, a tap does not',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(DiagnosticsGate(
        read: sample,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const Center(child: Text('now playing', textDirection: TextDirection.ltr)),
        ),
      )));

      // A tap in the hot zone still belongs to the screen underneath.
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(taps, 1);
      expect(find.text('DIAGNOSTICS'), findsNothing);

      await tester.longPressAt(const Offset(20, 20));
      await tester.pump();
      expect(find.text('DIAGNOSTICS'), findsOneWidget);
      expect(find.text('now playing'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pump();
      expect(find.text('now playing'), findsOneWidget);
    });

    testWidgets('a long press elsewhere on the screen does nothing',
        (tester) async {
      await tester.pumpWidget(wrap(DiagnosticsGate(
        read: sample,
        child: const Center(child: Text('now playing', textDirection: TextDirection.ltr)),
      )));

      await tester.longPressAt(const Offset(300, 500));
      await tester.pump();

      expect(find.text('DIAGNOSTICS'), findsNothing);
    });
  });
}
