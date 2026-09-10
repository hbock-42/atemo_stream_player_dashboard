/// POL-01 — the tablet on the wall.
library;

import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:atemo_stream_player_viewer/state/now_playing_controller.dart';
import 'package:atemo_stream_player_viewer/ui/screens/now_playing_screen.dart';
import 'package:atemo_stream_player_viewer/ui/theme/app_theme.dart';
import 'package:atemo_stream_player_viewer/ui/widgets/app_artwork.dart';
import 'package:atemo_stream_player_viewer/ui/widgets/app_button.dart';
import 'package:atemo_stream_player_viewer/ui/widgets/display_mode.dart';
import 'package:atemo_stream_player_viewer/ui/widgets/volume_bar.dart';
import 'package:atemo_stream_player_viewer/ui/widgets/wall_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_browser.dart';
import '../support/manual_source.dart';

const track = Playing(
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
  NowPlayingController? controller;
  late FakeBrowser browser;

  /// The wall display is judged at real tablet sizes, so the test view is
  /// resized rather than the widget being boxed inside an 800x600 default —
  /// a box smaller than its child lays out at a negative offset and every
  /// geometric assertion below would be measuring the wrong thing.
  void useScreen(WidgetTester tester, Size size) {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> showWall(
    WidgetTester tester,
    NowPlaying state, {
    Size size = const Size(1280, 800),
  }) async {
    useScreen(tester, size);
    browser = FakeBrowser();
    source = ManualSource();
    final built = controller = NowPlayingController(createSource: () => source);
    await built.start();
    source.push(state);

    await tester.pumpWidget(
      AppTheme(
        child: DefaultTextStyle(
          style: AppTypography.dark.body,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(size: size),
              child: WallView(controller: built, browser: browser),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  tearDown(() {
    controller?.dispose();
    controller = null;
  });

  testWidgets('shows the track large, with no controls at all', (tester) async {
    await showWall(tester, track);

    expect(find.text('Waltz for Debby'), findsOneWidget);
    expect(find.text('Bill Evans Trio'), findsOneWidget);
    expect(find.text('SPOTIFY'), findsOneWidget);

    // Chrome is not hidden, it is absent: nothing on this screen is tappable.
    expect(find.byType(AppIconButton), findsNothing);
    expect(find.byType(AppTextButton), findsNothing);
    expect(find.byType(VolumeBar), findsNothing);
  });

  testWidgets('type is sized for reading across a room', (tester) async {
    await showWall(tester, track);

    final title = tester.widget<Text>(find.text('Waltz for Debby'));
    // The phone scale tops out at 34; a wall must be well past it.
    expect(title.style!.fontSize, greaterThan(50));
  });

  testWidgets('dims when idle so it is not a nightlight', (tester) async {
    await showWall(tester, const Idle(deviceName: 'Streamplayer'));
    await tester.pump(const Duration(seconds: 2));

    final dim = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(dim.opacity, lessThan(0.5));
    expect(find.text('Nothing playing'), findsOneWidget);
  });

  testWidgets('is at full brightness while playing', (tester) async {
    await showWall(tester, track);

    final dim = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(dim.opacity, 1.0);
  });

  testWidgets('an unreachable relay says so rather than lying', (tester) async {
    await showWall(tester, Unreachable(reason: 'cannot reach the relay'));

    expect(find.textContaining("Can't reach the speaker"), findsOneWidget);
    expect(find.text('cannot reach the relay'), findsOneWidget);
  });

  testWidgets('sits side by side in landscape and stacks in portrait',
      (tester) async {
    await showWall(tester, track, size: const Size(1280, 800));
    var artwork = tester.getRect(find.byType(AppArtwork));
    var title = tester.getRect(find.text('Waltz for Debby'));
    expect(title.left, greaterThanOrEqualTo(artwork.right),
        reason: 'landscape puts the text beside the artwork');
    expect(artwork.width, greaterThan(300), reason: 'visible across a room');
    controller?.dispose();
    controller = null;

    await showWall(tester, track, size: const Size(800, 1280));
    artwork = tester.getRect(find.byType(AppArtwork));
    title = tester.getRect(find.text('Waltz for Debby'));
    expect(title.top, greaterThanOrEqualTo(artwork.bottom),
        reason: 'portrait stacks the text under the artwork');
  });

  testWidgets('takes the screen wake lock while mounted and gives it back',
      (tester) async {
    await showWall(tester, track);
    expect(browser.keepAwake, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(browser.keepAwake, isFalse);
    // The bridge was injected, so it is the caller's to dispose.
    expect(browser.disposed, isFalse);
  });

  testWidgets('survives days of state changes without accumulating timers',
      (tester) async {
    await showWall(tester, track);

    for (var i = 0; i < 200; i++) {
      source.push(
        i.isEven
            ? const Idle(deviceName: 'Streamplayer')
            : Playing(title: 'Track $i', capabilities: const Capabilities()),
      );
      await tester.pump(const Duration(seconds: 30));
    }

    // pumpWidget's tearDown asserts no timers are left pending; this is the
    // "runs for days" acceptance criterion, mechanised.
    expect(find.text('Track 199'), findsOneWidget);
    expect(browser.keepAwakeCalls, 1, reason: 'the wake lock is taken once');
  });

  test('the ?wall query parameter selects the wall display', () {
    expect(displayModeFromUri(Uri.parse('http://relay:8080/')), DisplayMode.normal);
    expect(displayModeFromUri(Uri.parse('http://relay:8080/?wall')), DisplayMode.wall);
    expect(
      displayModeFromUri(Uri.parse('http://relay:8080/?wall=1')),
      DisplayMode.wall,
    );
    expect(
      displayModeFromUri(Uri.parse('http://relay:8080/?wall=0')),
      DisplayMode.normal,
    );
    expect(
      displayModeFromUri(Uri.parse('http://relay:8080/?wall=false')),
      DisplayMode.normal,
    );
    // Native: Uri.base is a file: path, so the flag can never be set there.
    expect(displayModeFromUri(Uri.parse('file:///app/')), DisplayMode.normal);
  });

  testWidgets('the screen renders the wall display when asked for it', (tester) async {
    source = ManualSource();
    final built = controller = NowPlayingController(createSource: () => source);
    await built.start();
    source.push(track);

    await tester.pumpWidget(
      AppTheme(
        child: DefaultTextStyle(
          style: AppTypography.dark.body,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(1280, 800)),
              child: NowPlayingScreen(
                controller: built,
                mode: DisplayMode.wall,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(WallView), findsOneWidget);
    expect(find.byType(AppIconButton), findsNothing);
  });
}
