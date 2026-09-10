import 'dart:typed_data';

import 'package:atemo_stream_player_viewer/cast/cast_channel.dart';
import 'package:atemo_stream_player_viewer/cast/cast_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cast_device.dart';

CastMessage message(String payload) => CastMessage(
      sourceId: 'receiver-0',
      destinationId: 'sender-0',
      namespace: 'urn:x-cast:com.google.cast.receiver',
      payloadUtf8: payload,
    );

void main() {
  group('CastChannel framing', () {
    late ScriptedTransport transport;
    late CastChannel channel;

    setUp(() {
      transport = ScriptedTransport();
      channel = CastChannel.fromTransport(transport);
    });

    tearDown(() => channel.close());

    test('emits two frames arriving in a single read', () async {
      final received = <CastMessage>[];
      channel.messages.listen(received.add);

      transport.deliver([
        ...frame(message('{"type":"ONE"}')),
        ...frame(message('{"type":"TWO"}')),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(received.map((m) => m.type), ['ONE', 'TWO']);
    });

    test('reassembles one frame split across three reads', () async {
      final received = <CastMessage>[];
      channel.messages.listen(received.add);

      final bytes = frame(message('{"type":"SPLIT"}'));
      // Split mid-length-prefix, then mid-payload: both are real cases.
      transport.deliver(bytes.sublist(0, 2));
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);

      transport.deliver(bytes.sublist(2, 9));
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);

      transport.deliver(bytes.sublist(9));
      await Future<void>.delayed(Duration.zero);

      expect(received.single.type, 'SPLIT');
    });

    test('holds a partial trailing frame until the rest arrives', () async {
      final received = <CastMessage>[];
      channel.messages.listen(received.add);

      final first = frame(message('{"type":"WHOLE"}'));
      final second = frame(message('{"type":"LATER"}'));

      transport.deliver([...first, ...second.sublist(0, 5)]);
      await Future<void>.delayed(Duration.zero);
      expect(received.map((m) => m.type), ['WHOLE']);

      transport.deliver(second.sublist(5));
      await Future<void>.delayed(Duration.zero);
      expect(received.map((m) => m.type), ['WHOLE', 'LATER']);
    });

    test('writes a length-prefixed frame', () {
      channel.send(message('{"type":"OUT"}'));

      final written = transport.written.single;
      final length = ByteData.view(written.buffer, written.offsetInBytes, 4)
          .getUint32(0, Endian.big);
      expect(length, written.length - 4);
      expect(
        CastMessage.decode(Uint8List.sublistView(written, 4)).type,
        'OUT',
      );
    });

    test('surfaces a corrupt frame as a stream error', () async {
      final errors = <Object>[];
      channel.messages.listen((_) {}, onError: errors.add);

      // A length prefix promising four bytes of garbage that is not a valid
      // message: there is no way to resynchronise, so this ends the connection.
      transport.deliver([0, 0, 0, 4, 0xFF, 0xFF, 0xFF, 0xFF]);
      await Future<void>.delayed(Duration.zero);

      expect(errors.single, isA<CastMessageFormatException>());
    });
  });
}
