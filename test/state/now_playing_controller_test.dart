import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:atemo_stream_player_viewer/state/now_playing_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_source.dart';

const playingState = Playing(
  title: 'Waltz for Debby',
  artist: 'Bill Evans Trio',
  castingApp: 'Spotify',
  volumeLevel: 0.4,
  capabilities: Capabilities(canPause: true, canSkipNext: true),
);

void main() {
  // The controller registers a WidgetsBindingObserver for lifecycle handling.
  TestWidgetsFlutterBinding.ensureInitialized();

  late ManualSource source;
  late NowPlayingController controller;

  Future<void> build({String? commandError}) async {
    source = ManualSource()..throwOnCommand = commandError;
    controller = NowPlayingController(
      createSource: () => source,
      revertAfter: const Duration(milliseconds: 120),
      errorVisibleFor: const Duration(milliseconds: 200),
    );
    await controller.start();
    source.push(playingState);
    await Future<void>.delayed(Duration.zero);
  }

  tearDown(() => controller.dispose());

  group('optimistic control', () {
    test('applies the intended state immediately', () async {
      await build();

      controller.pause();

      expect((controller.value as Playing).isPaused, isTrue,
          reason: 'the button must respond before the device confirms');
      expect(source.recorded.calls, ['pause']);
    });

    test('seek shows the target immediately and calls the source', () async {
      await build();
      controller.seek(const Duration(seconds: 30));

      expect((controller.value as Playing).position, const Duration(seconds: 30),
          reason: 'the bar should jump to where the finger let go, not wait for '
              'the device to confirm');
      expect(source.recorded.calls, contains('seek'));
    });

    test('reconciles when the device confirms', () async {
      await build();
      controller.pause();

      source.push(playingState.copyWith(isPaused: true));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect((controller.value as Playing).isPaused, isTrue,
          reason: 'a confirmed command must not be reverted');
    });

    test('reverts when nothing confirms it', () async {
      await build();
      controller.pause();
      expect((controller.value as Playing).isPaused, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect((controller.value as Playing).isPaused, isFalse,
          reason: 'a button must not keep lying about what the speaker is doing');
    });

    test('reverts immediately when the command is refused', () async {
      await build(commandError: 'the app currently casting does not support pausing');
      controller.pause();

      // No waiting for the timeout: a rejection is known at once.
      expect((controller.value as Playing).isPaused, isFalse);
      expect(controller.lastError, contains('does not support pausing'));
    });

    test('clears the error message after a while', () async {
      await build(commandError: 'nothing is playing');
      controller.next();
      expect(controller.lastError, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(controller.lastError, isNull);
    });
  });

  group('volume', () {
    test('shows the dragged position immediately', () async {
      await build();

      controller
        ..beginVolumeDrag()
        ..setVolume(0.9);

      expect((controller.value as Playing).volumeLevel, 0.9);
      expect(source.recorded.lastVolume, 0.9);
    });

    test('inbound updates do not move the slider mid-drag', () async {
      await build();
      controller
        ..beginVolumeDrag()
        ..setVolume(0.9);

      // The device is still reporting the old level while we drag.
      source.push(playingState.copyWith(volumeLevel: 0.4));
      await Future<void>.delayed(Duration.zero);

      expect((controller.value as Playing).volumeLevel, 0.9,
          reason: 'the slider must not fight the status stream');
    });

    test('adopts the device level again once the drag ends', () async {
      await build();
      controller
        ..beginVolumeDrag()
        ..setVolume(0.9)
        ..endVolumeDrag(0.9);

      source.push(playingState.copyWith(volumeLevel: 0.55));
      await Future<void>.delayed(Duration.zero);

      expect((controller.value as Playing).volumeLevel, 0.55);
    });

    test('always transmits the settled value', () async {
      await build();
      controller
        ..beginVolumeDrag()
        ..setVolume(0.71)
        ..endVolumeDrag(0.73);

      expect(source.recorded.lastVolume, 0.73);
    });
  });

  group('read-only sources', () {
    test('canControl is false when the source offers no control', () async {
      source = ManualSource(controllable: false);
      controller = NowPlayingController(createSource: () => source);
      await controller.start();

      expect(controller.canControl, isFalse);
    });

    test('commands on a read-only source are harmless', () async {
      source = ManualSource(controllable: false);
      controller = NowPlayingController(createSource: () => source);
      await controller.start();
      source.push(playingState);
      await Future<void>.delayed(Duration.zero);

      expect(controller.pause, returnsNormally);
    });
  });

  test('retry builds a fresh source', () async {
    // A real factory returns a new source each time, as retry exists precisely
    // to throw away the connection that failed.
    final built = <ManualSource>[];
    controller = NowPlayingController(
      createSource: () {
        final next = ManualSource();
        built.add(next);
        return next;
      },
    );
    await controller.start();
    built.last.push(Unreachable(reason: 'connection lost'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.value, isA<Unreachable>());

    await controller.retry();
    await Future<void>.delayed(Duration.zero);

    expect(built, hasLength(2), reason: 'the failed source must be discarded');
    expect(controller.value, isA<Connecting>());
  });
}
