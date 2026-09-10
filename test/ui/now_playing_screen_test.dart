import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:atemo_stream_player_viewer/state/now_playing_controller.dart';
import 'package:atemo_stream_player_viewer/ui/screens/now_playing_screen.dart';
import 'package:atemo_stream_player_viewer/ui/theme/app_theme.dart';
import 'package:atemo_stream_player_viewer/ui/widgets/app_artwork.dart';
import 'package:atemo_stream_player_viewer/ui/widgets/app_button.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_source.dart';

const fullTrack = Playing(
  title: 'Waltz for Debby',
  artist: 'Bill Evans Trio',
  album: 'Waltz for Debby',
  castingApp: 'Spotify',
  volumeLevel: 0.4,
  capabilities: Capabilities(canPause: true, canSkipNext: true),
  deviceName: 'Streamplayer',
);

void main() {
  late ManualSource source;
  late NowPlayingController controller;

  Future<void> show(WidgetTester tester, NowPlaying state,
      {bool controllable = true, Size size = const Size(390, 844)}) async {
    source = ManualSource(controllable: controllable);
    controller = NowPlayingController(createSource: () => source);
    await controller.start();
    source.push(state);

    await tester.pumpWidget(
      AppTheme(
        child: DefaultTextStyle(
          style: AppTypography.dark.body,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(size: size),
              child: NowPlayingScreen(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  tearDown(() => controller.dispose());

  testWidgets('shows the track, artist, album and casting app', (tester) async {
    await show(tester, fullTrack);

    expect(find.text('Waltz for Debby'), findsNWidgets(2)); // title and album
    expect(find.text('Bill Evans Trio'), findsOneWidget);
    expect(find.text('SPOTIFY'), findsOneWidget);
  });

  testWidgets('idle and unreachable do not look the same', (tester) async {
    await show(tester, const Idle(deviceName: 'Streamplayer', volumeLevel: 0.4));
    expect(find.text('Nothing playing'), findsOneWidget);
    expect(find.textContaining('connected and idle'), findsOneWidget);
    expect(find.textContaining("Can't reach"), findsNothing);
    controller.dispose();

    await show(tester, Unreachable(reason: 'Streamplayer not found on the network'));
    expect(find.textContaining("Can't reach the speaker"), findsOneWidget);
    expect(find.text('Streamplayer not found on the network'), findsOneWidget);
    expect(find.text('Try now'), findsOneWidget);
    expect(find.text('Nothing playing'), findsNothing);
  });

  testWidgets('idle keeps a working volume control', (tester) async {
    // Device volume is addressed to the receiver, so it works with no app.
    await show(tester, const Idle(deviceName: 'Streamplayer', volumeLevel: 0.4));

    expect(find.text('40'), findsOneWidget);
  });

  testWidgets('a track with no metadata still renders', (tester) async {
    await show(tester, const Playing(castingApp: 'Tidal'));

    expect(find.text('Unknown track'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view-only hides the controls rather than disabling them',
      (tester) async {
    await show(tester, fullTrack, controllable: false);

    expect(find.text('View only'), findsOneWidget);
  });

  testWidgets('a brief connecting flicker is suppressed', (tester) async {
    await show(tester, fullTrack);
    expect(find.text('Waltz for Debby'), findsNWidgets(2));

    // A reconnect that resolves quickly must not flash a spinner over a live
    // screen.
    source.push(const Connecting());
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Looking for'), findsNothing);

    source.push(fullTrack);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Waltz for Debby'), findsNWidgets(2));
  });

  testWidgets('a sustained connecting state does show', (tester) async {
    await show(tester, fullTrack);

    source.push(const Connecting());
    // The guard's timer is only created during this first frame, so the grace
    // period is counted from the frame after the state change.
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.textContaining('Looking for'), findsOneWidget);
  });

  /// WEB-03 — the browser window is whatever size the office happens to have.
  testWidgets('lays out from a 360px phone up to a desktop window',
      (tester) async {
    for (final size in const [
      Size(360, 640), // the narrowest phone we support
      Size(390, 844),
      Size(768, 1024), // tablet
      Size(1440, 900), // desktop browser, maximised
    ]) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await show(tester, fullTrack, size: size);

      expect(tester.takeException(), isNull, reason: 'no overflow at $size');
      expect(find.text('Waltz for Debby'), findsNWidgets(2));
      // Every control stays inside the viewport rather than running off the
      // edge at 360px or floating off-centre on a wide window.
      for (final button in find.byType(AppIconButton).evaluate()) {
        final rect = tester.getRect(find.byWidget(button.widget));
        expect(rect.left, greaterThanOrEqualTo(0.0));
        expect(rect.right, lessThanOrEqualTo(size.width));
      }
      final artwork = tester.getRect(find.byType(AppArtwork));
      expect(artwork.width, lessThanOrEqualTo(size.width));
    }
  });
}
