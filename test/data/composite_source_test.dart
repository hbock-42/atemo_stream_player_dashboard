import 'package:atemo_stream_player_viewer/data/composite_source.dart';
import 'package:atemo_stream_player_viewer/domain/now_playing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_source.dart';

const rich = Playing(
  title: 'Waltz for Debby',
  artist: 'Bill Evans Trio',
  album: 'Waltz for Debby',
  castingApp: 'Spotify',
  capabilities: Capabilities(canPause: true),
);

const poor = Playing(title: 'Waltz for Debby', capabilities: Capabilities.none);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late ManualSource primary;
  late List<ManualSource> floors;
  late CompositeSource composite;

  setUp(() async {
    primary = ManualSource();
    floors = [];
    composite = CompositeSource(
      primary: primary,
      buildFloor: () {
        final f = ManualSource(controllable: false);
        floors.add(f);
        return f;
      },
    );
    await composite.start();
  });

  tearDown(() => composite.dispose());

  test('the primary leads while it has something to show', () async {
    primary.push(rich);
    await settle();

    expect(composite.current, rich);
    expect(composite.primaryLeads, isTrue);
    expect(composite.control, isNotNull);
    expect(floors, isEmpty, reason: 'the floor is not even built while the primary is up');
  });

  test('the floor takes over when the primary is unreachable', () async {
    primary.push(rich);
    await settle();
    primary.push(Unreachable(reason: 'could not reach the Streamplayer'));
    await settle();

    expect(floors, hasLength(1));
    floors.single.push(poor);
    await settle();

    expect(composite.current, poor);
    expect(composite.primaryLeads, isFalse);
    expect(composite.control, isNull,
        reason: 'the status line cannot control anything, whatever the primary could');
  });

  test('the primary takes back over, and the floor is torn down', () async {
    primary.push(Unreachable(reason: 'gone'));
    await settle();
    floors.single.push(poor);
    await settle();
    expect(composite.current, poor);

    primary.push(rich);
    await settle();

    expect(composite.current, rich);
    expect(composite.primaryLeads, isTrue);
    expect(composite.control, isNotNull);
  });

  test('a second outage gets a fresh floor', () async {
    // A disposed source cannot be restarted, so reuse would silently show
    // nothing the second time.
    primary.push(Unreachable(reason: 'gone'));
    await settle();
    primary.push(rich);
    await settle();
    primary.push(Unreachable(reason: 'gone again'));
    await settle();

    expect(floors, hasLength(2));
    floors.last.push(poor);
    await settle();
    expect(composite.current, poor);
  });

  test('a reconnect behind a live screen does not blank it', () async {
    primary.push(rich);
    await settle();

    primary.push(const Connecting());
    await settle();

    expect(composite.current, rich, reason: 'Connecting keeps what is there');
  });

  test('when both are out, the floor\'s unreachable is what shows', () async {
    primary.push(Unreachable(reason: 'socket refused'));
    await settle();
    floors.single.push(Unreachable(reason: 'the Streamplayer is not advertising'));
    await settle();

    // The floor can still see the device when the socket cannot, so its
    // verdict is the honest one.
    expect((composite.current as Unreachable).reason,
        'the Streamplayer is not advertising');
  });

  test('a stale floor update after recovery is ignored', () async {
    primary.push(Unreachable(reason: 'gone'));
    await settle();
    final floor = floors.single;
    primary.push(rich);
    await settle();

    floor.push(poor); // late, after it was torn down
    await settle();

    expect(composite.current, rich);
  });

  test('diagnostics say which source is on screen', () async {
    primary.push(Unreachable(reason: 'socket refused'));
    await settle();

    final showing = composite.diagnostics.facts.firstWhere((f) => f.label == 'showing');
    expect(showing.value, 'mDNS status line');
  });
}
