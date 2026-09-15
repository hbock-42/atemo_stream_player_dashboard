import 'package:atemo_stream_player_viewer/ui/theme/app_theme.dart';
import 'package:atemo_stream_player_viewer/ui/widgets/track_progress.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDuration', () {
    test('m:ss under an hour', () {
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(formatDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
      expect(formatDuration(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('h:mm:ss past an hour, for a long mix', () {
      expect(formatDuration(const Duration(hours: 3, minutes: 3, seconds: 52)),
          '3:03:52');
      expect(formatDuration(const Duration(hours: 1)), '1:00:00');
    });

    test('a negative value reads as zero, never garbage', () {
      expect(formatDuration(const Duration(seconds: -5)), '0:00');
    });
  });

  group('interpolation', () {
    Widget wrap(Widget child) => AppTheme(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: SizedBox(width: 300, child: child)),
          ),
        );

    testWidgets('advances while playing', (tester) async {
      await tester.pumpWidget(wrap(const TrackProgress(
        position: Duration(seconds: 10),
        duration: Duration(seconds: 100),
        isPaused: false,
      )));

      expect(find.text('0:10'), findsOneWidget);

      // The device sent nothing more, but the display ticks forward.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('0:13'), findsOneWidget);
      expect(find.text('1:40'), findsOneWidget, reason: 'total stays put');
    });

    testWidgets('does not advance while paused', (tester) async {
      await tester.pumpWidget(wrap(const TrackProgress(
        position: Duration(seconds: 42),
        duration: Duration(seconds: 100),
        isPaused: true,
      )));

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('0:42'), findsOneWidget);
    });

    testWidgets('a fresh report resets the baseline, so drift does not accumulate',
        (tester) async {
      await tester.pumpWidget(wrap(const TrackProgress(
        position: Duration(seconds: 10),
        duration: Duration(seconds: 100),
        isPaused: false,
      )));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('0:14'), findsOneWidget);

      // The device reports 20s (a seek, or just its next push).
      await tester.pumpWidget(wrap(const TrackProgress(
        position: Duration(seconds: 20),
        duration: Duration(seconds: 100),
        isPaused: false,
      )));
      await tester.pump();
      expect(find.text('0:20'), findsOneWidget);
    });

    testWidgets('never overshoots the end', (tester) async {
      await tester.pumpWidget(wrap(const TrackProgress(
        position: Duration(seconds: 98),
        duration: Duration(seconds: 100),
        isPaused: false,
      )));

      await tester.pump(const Duration(seconds: 10));
      expect(find.text('1:40'), findsNWidgets(2),
          reason: 'clamped to the duration, shown as both elapsed and total');
    });
  });
}
